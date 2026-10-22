#!/usr/bin/env bash
# Prüfungen für den Release-Workflow (.github/workflows/release.yml, WP131).
# Gibt nie Werte von Secrets aus, nur Namen und öffentliche Fingerabdrücke.
#
#   tool/release_check.sh secrets                 # alle Release-Secrets gesetzt und nicht leer?
#   tool/release_check.sh version <tag> [pubspec] # Tag-Basisversion == pubspec-Version?
#   tool/release_check.sh prerelease <tag>        # Ausgabe true/false (Tag mit „-“)
#   tool/release_check.sh cert-match <apk> <keystore>  # APK-Zertifikat == Zertifikat des Keystores?
#   tool/release_check.sh --self-test
#
# Umgebung: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS,
# ANDROID_KEY_PASSWORD (secrets, cert-match); APKSIGNER, KEYTOOL (Pfad, auch für Attrappen).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS=(ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD)

fail() { echo "::error::$*" >&2; echo "FEHLER: $*" >&2; exit 1; }

cmd_secrets() {
  local missing=() n
  for n in "${SECRETS[@]}"; do
    [ -n "${!n:-}" ] || missing+=("$n")
  done
  [ ${#missing[@]} -eq 0 ] || fail "Release-Secrets fehlen oder sind leer: ${missing[*]} (Anleitung: docs/RELEASE.md)"
  echo "ok: alle ${#SECRETS[@]} Release-Secrets sind gesetzt"
}

cmd_prerelease() {
  case "${1:-}" in *-*) echo true ;; *) echo false ;; esac
}

cmd_version() {
  local tag="${1:-}" pubspec="${2:-$ROOT/app/pubspec.yaml}" base pub
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || fail "Tag '$tag' passt nicht zu vX.Y.Z[-suffix]"
  base="${tag#v}"; base="${base%%-*}"
  pub="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$pubspec" | head -1)"
  [ -n "$pub" ] || fail "Keine version: in $pubspec gefunden"
  [ "$base" = "$pub" ] || fail "Tag-Basisversion $base ist nicht die pubspec-Version $pub"
  echo "ok: Tag $tag entspricht pubspec-Version $pub"
}

norm() { tr -d ': \r' | tr 'A-F' 'a-f'; }

cmd_cert_match() {
  local apk="${1:?apk}" ks="${2:?keystore}" signer keytool apk_fp ks_fp
  signer="${APKSIGNER:-}"
  if [ -z "$signer" ]; then
    signer="$(ls -d "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
  fi
  [ -x "$signer" ] || fail "apksigner nicht gefunden"
  keytool="${KEYTOOL:-keytool}"
  local out
  out="$("$signer" verify --print-certs "$apk")" || fail "apksigner verify fehlgeschlagen"
  apk_fp="$(printf '%s\n' "$out" | sed -nE 's/^Signer #1 certificate SHA-256 digest: *//p' | head -1 | norm)"
  [ -n "$apk_fp" ] || fail "Kein Signer-Zertifikat in der APK gefunden"
  ks_fp="$("$keytool" -list -v -keystore "$ks" -alias "$ANDROID_KEY_ALIAS" -storepass:env ANDROID_KEYSTORE_PASSWORD 2>/dev/null \
    | sed -nE 's/^[[:space:]]*SHA-?256: *//p' | head -1 | norm)" || true
  [ -n "$ks_fp" ] || fail "Fingerabdruck aus dem Keystore nicht lesbar (Alias oder Passwort falsch?)"
  [ "$apk_fp" = "$ks_fp" ] || fail "APK ist nicht mit dem Release-Schlüssel signiert (Fingerabdruck weicht ab)"
  # Öffentlicher Wert (Zertifikat), darf ins Log.
  echo "ok: APK ist mit dem Release-Schlüssel signiert"
  echo "SHA-256 (Zertifikat): $(printf '%s' "$apk_fp" | tr 'a-f' 'A-F' | sed -E 's/(..)/\1:/g; s/:$//')"
}

self_test() {
  local d rc=0; d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
  expect_fail() { local what="$1"; shift; if ( "$@" ) >/dev/null 2>&1; then echo "FEHLER Selbsttest: $what sollte scheitern" >&2; rc=1; fi; }
  expect_ok() { local what="$1"; shift; if ! ( "$@" ) >/dev/null 2>&1; then echo "FEHLER Selbsttest: $what sollte gelingen" >&2; rc=1; fi; }
  sec_ok() { ANDROID_KEYSTORE_BASE64=a ANDROID_KEYSTORE_PASSWORD=b ANDROID_KEY_ALIAS=c ANDROID_KEY_PASSWORD=d cmd_secrets; }
  sec_one_empty() { ANDROID_KEYSTORE_BASE64=a ANDROID_KEYSTORE_PASSWORD= ANDROID_KEY_ALIAS=c ANDROID_KEY_PASSWORD=d cmd_secrets; }
  sec_none() { env -u ANDROID_KEYSTORE_BASE64 -u ANDROID_KEYSTORE_PASSWORD -u ANDROID_KEY_ALIAS -u ANDROID_KEY_PASSWORD bash "$0" secrets; }
  expect_ok "alle Secrets" sec_ok
  expect_fail "leeres Secret" sec_one_empty
  expect_fail "keine Secrets" sec_none
  # Die Meldung nennt Namen, nie Werte.
  local msg
  msg="$(ANDROID_KEYSTORE_BASE64=geheim1 ANDROID_KEYSTORE_PASSWORD= ANDROID_KEY_ALIAS=c ANDROID_KEY_PASSWORD=d bash "$0" secrets 2>&1 || true)"
  case "$msg" in *geheim1*) echo "FEHLER Selbsttest: Secret-Wert im Log" >&2; rc=1 ;; esac
  case "$msg" in *ANDROID_KEYSTORE_PASSWORD*) ;; *) echo "FEHLER Selbsttest: fehlender Name nicht genannt" >&2; rc=1 ;; esac
  printf 'name: x\nversion: 1.2.3+4\n' >"$d/pubspec.yaml"
  expect_ok "Tag = pubspec" cmd_version v1.2.3 "$d/pubspec.yaml"
  expect_ok "Prerelease-Tag" cmd_version v1.2.3-rc.1 "$d/pubspec.yaml"
  expect_fail "Tag ≠ pubspec" cmd_version v1.2.4 "$d/pubspec.yaml"
  expect_fail "Tag ohne v" cmd_version 1.2.3 "$d/pubspec.yaml"
  expect_fail "Tag mit Müll" cmd_version v1.2 "$d/pubspec.yaml"
  [ "$(cmd_prerelease v1.2.3-test)" = true ] || { echo "FEHLER Selbsttest: prerelease" >&2; rc=1; }
  [ "$(cmd_prerelease v1.2.3)" = false ] || { echo "FEHLER Selbsttest: prerelease stabil" >&2; rc=1; }
  # cert-match mit Attrappen
  touch "$d/x.apk" "$d/x.jks"
  printf '#!/usr/bin/env bash\necho "Signer #1 certificate SHA-256 digest: aabbcc"\n' >"$d/apksigner"
  printf '#!/usr/bin/env bash\necho "Certificate fingerprints:"; echo "	 SHA256: $(cat "$(dirname "$0")/fp")"\n' >"$d/keytool"
  chmod +x "$d/apksigner" "$d/keytool"
  export APKSIGNER="$d/apksigner" KEYTOOL="$d/keytool" ANDROID_KEY_ALIAS=a ANDROID_KEYSTORE_PASSWORD=p
  echo "AA:BB:CC" >"$d/fp"
  expect_ok "Zertifikat gleich" cmd_cert_match "$d/x.apk" "$d/x.jks"
  echo "AA:BB:DD" >"$d/fp"
  expect_fail "Zertifikat verschieden (z. B. Debug-Schlüssel)" cmd_cert_match "$d/x.apk" "$d/x.jks"
  : >"$d/fp"; printf '#!/usr/bin/env bash\nexit 1\n' >"$d/keytool"
  expect_fail "Keystore nicht lesbar" cmd_cert_match "$d/x.apk" "$d/x.jks"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$d/apksigner"
  expect_fail "apksigner verify scheitert" cmd_cert_match "$d/x.apk" "$d/x.jks"
  [ $rc = 0 ] && echo "ok: release_check Selbsttest"
  return $rc
}

case "${1:-}" in
  secrets) cmd_secrets ;;
  version) shift; cmd_version "$@" ;;
  prerelease) shift; cmd_prerelease "$@" ;;
  cert-match) shift; cmd_cert_match "$@" ;;
  --self-test) self_test ;;
  *) sed -n 2,12p "$0" >&2; exit 2 ;;
esac
