#!/usr/bin/env bash
# Prüfungen für den Release-Workflow (.github/workflows/release.yml, WP131).
# Gibt nie Werte von Secrets aus, nur Namen und öffentliche Fingerabdrücke.
#
#   tool/release_check.sh secrets                 # alle Release-Secrets gesetzt und nicht leer?
#   tool/release_check.sh version <tag> [pubspec] # Tag-Basisversion == pubspec-Version?
#   tool/release_check.sh prerelease <tag>        # Ausgabe true/false (Tag mit „-“)
#   tool/release_check.sh on-main <tag> <sha> [ref]  # echtes Release (Tag ohne „-“): Commit muss Vorfahre von ref (origin/main) sein
#   tool/release_check.sh cert-match <apk> <keystore>  # APK-Zertifikat == Zertifikat des Keystores?
#   tool/release_check.sh --self-test
#
# Umgebung: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS,
# ANDROID_KEY_PASSWORD (ANDROID_KEY_ALIAS ist eine Repo-Variable, die übrigen Secrets; cert-match); APKSIGNER, KEYTOOL (Pfad, auch für Attrappen).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS=(ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD)

fail() { echo "::error::$*" >&2; echo "FEHLER: $*" >&2; exit 1; }

cmd_secrets() {
  local missing=() n
  for n in "${SECRETS[@]}"; do
    [ -n "${!n:-}" ] || missing+=("$n")
  done
  [ ${#missing[@]} -eq 0 ] || fail "Release-Secrets/-Variable fehlen oder sind leer: ${missing[*]} (ANDROID_KEY_ALIAS ist eine Repo-Variable, Anleitung: docs/RELEASE.md)"
  echo "ok: alle ${#SECRETS[@]} Release-Werte (drei Secrets, Variable ANDROID_KEY_ALIAS) sind gesetzt"
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

cmd_on_main() {
  local tag="${1:-}" sha="${2:-}" ref="${3:-origin/main}"
  [ -n "$tag" ] && [ -n "$sha" ] || fail "on-main: Tag und Commit angeben"
  if [ "$(cmd_prerelease "$tag")" = true ]; then
    echo "ok: Vorabversion $tag darf von einem Branch kommen (Probe)"; return 0
  fi
  git merge-base --is-ancestor "$sha" "$ref" 2>/dev/null ||
    fail "Commit $sha liegt nicht auf $ref. Ein echtes Release (Tag ohne „-“) nur von gemergtem main; für Proben einen Tag mit „-“ (z. B. $tag-rc.1) verwenden."
  echo "ok: Commit $sha liegt auf $ref"
}

norm() { tr -d ': \r' | tr 'A-F' 'a-f'; }

cmd_cert_match() {
  local apk="${1:?apk}" ks="${2:?keystore}" signer keytool apk_fp ks_fp
  signer="${APKSIGNER:-}"
  if [ -z "$signer" ]; then
    # Nur stabile Build-Tools (Verzeichnisname ohne „-rc“ o. Ä.), die höchste Version.
    local sdk bt
    sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
    for bt in $(ls "$sdk/build-tools" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V); do
      [ -x "$sdk/build-tools/$bt/apksigner" ] && signer="$sdk/build-tools/$bt/apksigner"
    done
  fi
  [ -x "$signer" ] || fail "apksigner nicht gefunden"
  echo "apksigner: $signer (Version $("$signer" --version 2>&1 | head -1))"
  keytool="${KEYTOOL:-keytool}"
  local out rc=0
  out="$("$signer" verify --print-certs "$apk" 2>&1)" || rc=$?
  if [ $rc -ne 0 ]; then
    printf '%s\n' "$out" >&2
    fail "apksigner verify fehlgeschlagen (Exit $rc)"
  fi
  # Jede Zeile „… certificate SHA-256 digest: <64 hex>“, unabhängig vom Präfix (Signer #n, Signer (minSdkVersion=…),
  # V1/V2/V3/V3.1 Signer …, build-tools 37: „V2 Signer: …“). Die Menge muss genau ein Zertifikat enthalten.
  local fps
  fps="$(printf '%s\n' "$out" | sed -nE 's/.*certificate SHA-256 digest: *([0-9A-Fa-f]{64})([^0-9A-Fa-f].*)?$/\1/p' | norm | sort -u)"
  if [ -z "$fps" ]; then
    echo "apksigner-Ausgabe (Zertifikate sind öffentlich):" >&2; printf '%s\n' "$out" >&2
    fail "Kein Signer-Zertifikat in der APK gefunden"
  fi
  if [ "$(printf '%s\n' "$fps" | wc -l | tr -d ' ')" -ne 1 ]; then
    printf '%s\n' "$out" >&2
    fail "APK enthält mehrere Signer mit verschiedenen Zertifikaten"
  fi
  apk_fp="$fps"
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
  # on-main: echtes Release nur von main, Vorabversion von jedem Branch
  ( export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
    cd "$d" && git init -q r && cd r && git commit -q --allow-empty -m a && git branch -M main &&
    git commit -q --allow-empty -m b && git checkout -q -b wp/x && git commit -q --allow-empty -m c ) >/dev/null 2>&1
  local onmain offmain
  onmain="$(git -C "$d/r" rev-parse main)"; offmain="$(git -C "$d/r" rev-parse wp/x)"
  expect_ok "Release-Tag, Commit auf main" bash -c "cd '$d/r' && '$ROOT/tool/release_check.sh' on-main v1.0.0 $onmain main"
  expect_fail "Release-Tag, Commit nur auf Branch" bash -c "cd '$d/r' && '$ROOT/tool/release_check.sh' on-main v1.0.0 $offmain main"
  expect_ok "Vorabversion vom Branch" bash -c "cd '$d/r' && '$ROOT/tool/release_check.sh' on-main v1.0.0-rc.1 $offmain main"
  # cert-match mit Attrappen
  touch "$d/x.apk" "$d/x.jks"
  printf '#!/usr/bin/env bash\necho "Signer #1 certificate SHA-256 digest: a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13"\n' >"$d/apksigner"
  printf '#!/usr/bin/env bash\necho "Certificate fingerprints:"; echo "	 SHA256: $(cat "$(dirname "$0")/fp")"\n' >"$d/keytool"
  chmod +x "$d/apksigner" "$d/keytool"
  export APKSIGNER="$d/apksigner" KEYTOOL="$d/keytool" ANDROID_KEY_ALIAS=a ANDROID_KEYSTORE_PASSWORD=p
  echo "A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13" >"$d/fp"
  expect_ok "Zertifikat gleich" cmd_cert_match "$d/x.apk" "$d/x.jks"
  echo "11:22:33:44:11:22:33:44:11:22:33:44:11:22:33:44:11:22:33:44:11:22:33:44:11:22:33:44:11:22:33:44" >"$d/fp"
  expect_fail "Zertifikat verschieden (z. B. Debug-Schlüssel)" cmd_cert_match "$d/x.apk" "$d/x.jks"
  # Format „Signer (minSdkVersion=…)“ und mehrere Signer
  echo "A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13" >"$d/fp"; printf '#!/usr/bin/env bash\necho "	 SHA256: $(cat "$(dirname "$0")/fp")"\n' >"$d/keytool"
  printf '#!/usr/bin/env bash\necho "Signer (minSdkVersion=24, maxSdkVersion=34) certificate SHA-256 digest: A9E95A13A9E95A13A9E95A13A9E95A13A9E95A13A9E95A13A9E95A13A9E95A13"\n' >"$d/apksigner"
  expect_ok "Signer-Format mit minSdkVersion" cmd_cert_match "$d/x.apk" "$d/x.jks"
  printf '#!/usr/bin/env bash\necho "Signer #1 certificate SHA-256 digest: a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13"\necho "Signer #2 certificate SHA-256 digest: a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13"\n' >"$d/apksigner"
  expect_ok "mehrere Signer, gleiches Zertifikat" cmd_cert_match "$d/x.apk" "$d/x.jks"
  printf '#!/usr/bin/env bash\necho "Signer #1 certificate SHA-256 digest: a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13"\necho "Signer #2 certificate SHA-256 digest: 1122334411223344112233441122334411223344112233441122334411223344"\n' >"$d/apksigner"
  expect_fail "mehrere Signer, verschiedene Zertifikate" cmd_cert_match "$d/x.apk" "$d/x.jks"
  # Echtes Format von build-tools 37.0.0 („V2 Signer: …“) sowie Mischungen mehrerer Schemata
  fa="a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13"; fb="1122334411223344112233441122334411223344112233441122334411223344"
  mk_signer() { { echo '#!/usr/bin/env bash'; for l in "$@"; do printf 'echo "%s"\n' "$l"; done; } >"$d/apksigner"; }
  mk_signer "V2 Signer: certificate DN: CN=Test" "V2 Signer: certificate SHA-256 digest: $fa" "V2 Signer: certificate SHA-1 digest: 0123456789abcdef0123456789abcdef01234567"
  expect_ok "build-tools-37-Format V2 Signer" cmd_cert_match "$d/x.apk" "$d/x.jks"
  mk_signer "V2 Signer: certificate SHA-256 digest: $fa" "V3 Signer: certificate SHA-256 digest: $fa"
  expect_ok "V2 und V3, gleicher Fingerabdruck" cmd_cert_match "$d/x.apk" "$d/x.jks"
  mk_signer "V2 Signer: certificate SHA-256 digest: $fa" "V3 Signer: certificate SHA-256 digest: $fb"
  expect_fail "V2 und V3, verschiedene Fingerabdrücke" cmd_cert_match "$d/x.apk" "$d/x.jks"
  mk_signer "V2 Signer: certificate DN: CN=Test" "V2 Signer: certificate SHA-1 digest: 0123456789abcdef0123456789abcdef01234567"
  # Keystore-Fingerabdruck absichtlich gleich dem (falschen) Wert, damit nur das Parsing den Fehler fangen kann
  cp "$d/fp" "$d/fp.orig"; echo "0123456789abcdef0123456789abcdef01234567" >"$d/fp"
  expect_fail "nur SHA-1/DN, kein SHA-256-Fingerabdruck" cmd_cert_match "$d/x.apk" "$d/x.jks"
  mk_signer "V2 Signer: certificate SHA-256 digest: ${fa#?}"; echo "${fa#?}" >"$d/fp"
  expect_fail "abgeschnittener Fingerabdruck (63 Hex)" cmd_cert_match "$d/x.apk" "$d/x.jks"
  cp "$d/fp.orig" "$d/fp"
  printf '#!/usr/bin/env bash\n[ \"${1:-}\" = verify ] && echo \"Verified using v2 scheme: true\"\nexit 0\n' >"$d/apksigner"
  expect_fail "Ausgabe ohne Zertifikatszeile" cmd_cert_match "$d/x.apk" "$d/x.jks"
  local err
  err="$( ( cmd_cert_match "$d/x.apk" "$d/x.jks" ) 2>&1 || true)"
  case "$err" in *"Verified using v2 scheme"*) ;; *) echo "FEHLER Selbsttest: apksigner-Ausgabe fehlt im Log" >&2; rc=1 ;; esac
  # Build-Tools-Auswahl: stabile Version vor -rc, apksigner-Version im Log
  mkdir -p "$d/sdk/build-tools/35.0.0" "$d/sdk/build-tools/9.0.0" "$d/sdk/build-tools/37.0.0-rc1"
  for v in 35.0.0 9.0.0 37.0.0-rc1; do
    printf '#!/usr/bin/env bash\n[ "${1:-}" = --version ] && { echo %s; exit 0; }\necho "Signer #1 certificate SHA-256 digest: a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13"\n' "$v" >"$d/sdk/build-tools/$v/apksigner"
    chmod +x "$d/sdk/build-tools/$v/apksigner"
  done
  err="$( ( unset APKSIGNER; ANDROID_SDK_ROOT="$d/sdk" cmd_cert_match "$d/x.apk" "$d/x.jks" ) 2>&1 || true)"
  case "$err" in *"build-tools/35.0.0/apksigner (Version 35.0.0)"*) ;; *) echo "FEHLER Selbsttest: falsche apksigner-Auswahl: $err" >&2; rc=1 ;; esac
  echo "A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13:A9:E9:5A:13" >"$d/fp"; printf '#!/usr/bin/env bash\necho "Signer #1 certificate SHA-256 digest: a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13a9e95a13"\n' >"$d/apksigner"
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
  on-main) shift; cmd_on_main "$@" ;;
  cert-match) shift; cmd_cert_match "$@" ;;
  --self-test) self_test ;;
  *) sed -n 2,12p "$0" >&2; exit 2 ;;
esac
