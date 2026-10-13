#!/usr/bin/env bash
# Prüft ein Android-APK auf K7 (keine Google Play Services) und das
# Manifest (kein Backup, nur die erwarteten Berechtigungen).
#
#   tool/check_apk.sh [pfad/zum.apk]   # Standard: Release-APK, wird gebaut
#   tool/check_apk.sh --self-test      # prüft das Skript mit Attrappen
#
# Prüfungen:
#   - keine Klassen aus com.google.android.gms, com.google.firebase,
#     com.google.android.play, com.android.vending (apkanalyzer dex packages)
#   - <application> mit android:allowBackup="false" und
#     android:dataExtractionRules; keine Berechtigungen außer der Liste
#   - Gradle-Abhängigkeiten (releaseRuntimeClasspath) ohne GMS/Firebase;
#     ist der Baum nicht lesbar, ist das ein Fehler – überspringen nur mit
#     CHECK_APK_SKIP_GRADLE=1
#
# Umgebung: ANDROID_SDK_ROOT, APKANALYZER (Pfad, z. B. für Attrappen).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

self_test() {
  local dir out status=0
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' RETURN
  touch "$dir/x.apk"
  # Attrappe: Verhalten über Dateien im selben Verzeichnis.
  cat >"$dir/apkanalyzer" <<'STUB'
#!/usr/bin/env bash
d="$(dirname "$0")"
case "$1 $2" in
  "dex packages") cat "$d/dex.txt" ;;
  "manifest print") cat "$d/manifest.xml" ;;
  "manifest permissions") cat "$d/perms.txt" ;;
esac
STUB
  chmod +x "$dir/apkanalyzer"
  good_manifest='<manifest>
  <application
      android:label="Wendelin"
      android:allowBackup="false"
      android:dataExtractionRules="@xml/data_extraction_rules">
    <activity android:name=".MainActivity" />
  </application>
</manifest>'
  run() {
    APKANALYZER="$dir/apkanalyzer" CHECK_APK_SKIP_GRADLE=1 \
      "$ROOT/tool/check_apk.sh" "$dir/x.apk" >/dev/null 2>&1
  }
  expect() { # name, erwarteter Exit (0/1)
    local got=0
    run || got=$?
    if [ "$got" != "$2" ]; then
      echo "Selbsttest FEHLER: $1 (Exit $got, erwartet $2)" >&2
      status=1
    else
      echo "ok: $1"
    fi
  }
  printf 'P d 1 2 3 app.wendelin\nP d 1 2 3 io.flutter\n' >"$dir/dex.txt"
  echo "$good_manifest" >"$dir/manifest.xml"
  printf 'android.permission.INTERNET\nandroid.permission.READ_CALENDAR\n' >"$dir/perms.txt"
  expect "sauberes APK" 0

  printf 'P d 1 2 3 com.google.android.gms.common\n' >>"$dir/dex.txt"
  expect "GMS-Klasse erkannt" 1
  printf 'P d 1 2 3 app.wendelin\n' >"$dir/dex.txt"

  echo "$good_manifest" | sed 's/allowBackup="false"/allowBackup="true"/' >"$dir/manifest.xml"
  expect "allowBackup=true erkannt" 1

  # allowBackup="false" nur an einem anderen Element zählt nicht.
  echo "$good_manifest" | sed 's/ android:allowBackup="false"//' |
    sed 's#<activity android:name=".MainActivity" />#<activity android:allowBackup="false" />#' >"$dir/manifest.xml"
  expect "allowBackup nur außerhalb von <application>" 1
  echo "$good_manifest" >"$dir/manifest.xml"

  printf 'android.permission.ACCESS_FINE_LOCATION\n' >>"$dir/perms.txt"
  expect "unerwartete Berechtigung erkannt" 1
  return $status
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
APKANALYZER="${APKANALYZER:-$(ls -d "$SDK"/cmdline-tools/*/bin/apkanalyzer 2>/dev/null | head -1)}"
[ -x "$APKANALYZER" ] || { echo "apkanalyzer fehlt (Android cmdline-tools)" >&2; exit 1; }
APK="${1:-}"
if [ -z "$APK" ]; then
  (cd "$ROOT/app" && flutter build apk --release >/dev/null)
  APK="$ROOT/app/build/app/outputs/flutter-apk/app-release.apk"
fi
[ -f "$APK" ] || { echo "APK nicht gefunden: $APK" >&2; exit 1; }

fail=0
FORBIDDEN='^(com\.google\.android\.gms|com\.google\.firebase|com\.google\.android\.play|com\.android\.vending)(\.|$)'

packages="$("$APKANALYZER" dex packages --defined-only "$APK" | awk '{print $NF}')"
if [ -z "$packages" ]; then
  echo "FEHLER: apkanalyzer lieferte keine Pakete" >&2
  fail=1
elif hits="$(echo "$packages" | grep -E "$FORBIDDEN")"; then
  echo "FEHLER: GMS-/Firebase-Klassen im APK:" >&2
  echo "$hits" | sort -u | head -20 >&2
  fail=1
else
  echo "ok: keine GMS-/Firebase-Klassen ($(echo "$packages" | wc -l | tr -d ' ') Pakete/Klassen geprüft)"
fi

# Nur das Start-Tag von <application> (über mehrere Zeilen).
application="$("$APKANALYZER" manifest print "$APK" | tr '\n' ' ' |
  grep -oE '<application[[:space:]][^>]*>' | head -1 || true)"
if [ -z "$application" ]; then
  echo 'FEHLER: kein <application>-Element im Manifest' >&2
  fail=1
else
  if echo "$application" | grep -q 'android:allowBackup="false"'; then
    echo 'ok: <application android:allowBackup="false">'
  else
    echo 'FEHLER: <application> hat nicht android:allowBackup="false"' >&2
    fail=1
  fi
  if echo "$application" | grep -q 'android:dataExtractionRules='; then
    echo 'ok: dataExtractionRules gesetzt'
  else
    echo 'FEHLER: android:dataExtractionRules fehlt an <application>' >&2
    fail=1
  fi
fi

ALLOWED='^(android\.permission\.INTERNET|android\.permission\.READ_CALENDAR|android\.permission\.WRITE_CALENDAR|com\.android\.alarm\.permission\.SET_ALARM|app\.wendelin\.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION)$'
perms="$("$APKANALYZER" manifest permissions "$APK")"
if extra="$(echo "$perms" | grep -vE "$ALLOWED")"; then
  echo "FEHLER: unerwartete Berechtigungen:" >&2
  echo "$extra" >&2
  fail=1
else
  echo "ok: Berechtigungen $(echo "$perms" | tr '\n' ' ')"
fi

if [ "${CHECK_APK_SKIP_GRADLE:-}" = "1" ]; then
  echo "Hinweis: Gradle-Abhängigkeiten übersprungen (CHECK_APK_SKIP_GRADLE=1)"
elif ! deps="$(cd "$ROOT/app/android" && ./gradlew -q :app:dependencies --configuration releaseRuntimeClasspath 2>&1)" || [ -z "$deps" ]; then
  echo "FEHLER: Gradle-Abhängigkeitsbaum nicht lesbar (CHECK_APK_SKIP_GRADLE=1 überspringt):" >&2
  echo "$deps" | tail -5 >&2
  fail=1
elif echo "$deps" | grep -qE 'com\.google\.android\.gms|com\.google\.firebase'; then
  echo "FEHLER: GMS/Firebase im Gradle-Abhängigkeitsbaum:" >&2
  echo "$deps" | grep -E 'com\.google\.android\.gms|com\.google\.firebase' | head >&2
  fail=1
else
  echo "ok: Gradle-Abhängigkeiten ohne GMS/Firebase"
fi

exit $fail
