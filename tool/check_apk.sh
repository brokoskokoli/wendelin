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
#     (M2: RECORD_AUDIO für Push-to-talk, Assistent und Spracherkennung)
#   - exportierte Komponenten nur aus der Liste: MainActivity,
#     OAuthRedirectActivity (OAuth-Rückleitung, WP27), die
#     Assistenten-Services nur mit BIND_VOICE_INTERACTION, der
#     RecognitionService ab Werk deaktiviert (enabled="false", ADR 0006),
#     ProfileInstallReceiver nur mit DUMP; alles andere nicht exportiert
#   - Gradle-Abhängigkeiten (releaseRuntimeClasspath) ohne GMS/Firebase;
#     ist der Baum nicht lesbar, ist das ein Fehler – überspringen nur mit
#     CHECK_APK_SKIP_GRADLE=1 (mit Warnung). Eine nicht aufgelöste
#     Abhängigkeit (FAILED) ist ein Fehler.
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
    <activity android:name="app.wendelin.MainActivity" android:exported="true" />
    <activity android:name="app.wendelin.AssistantActivity" android:exported="false" />
    <service android:name="app.wendelin.WendelinVoiceInteractionService"
        android:permission="android.permission.BIND_VOICE_INTERACTION"
        android:exported="true" />
    <service android:name="app.wendelin.WendelinVoiceSessionService"
        android:permission="android.permission.BIND_VOICE_INTERACTION"
        android:exported="true" />
    <service android:name="app.wendelin.WendelinRecognitionService"
        android:enabled="false" android:exported="true" />
    <receiver android:name="androidx.profileinstaller.ProfileInstallReceiver"
        android:permission="android.permission.DUMP" android:exported="true" />
  </application>
</manifest>'
  run() {
    APKANALYZER="$dir/apkanalyzer" CHECK_APK_SKIP_GRADLE=1 \
      "$ROOT/tool/check_apk.sh" "$dir/x.apk" >"$dir/out.txt" 2>&1
  }
  expect() { # name, erwarteter Exit (0/1), [erwartete Fehlermeldung]
    local got=0
    run || got=$?
    if [ "$got" != "$2" ] || { [ -n "${3:-}" ] && ! grep -qF "$3" "$dir/out.txt"; }; then
      echo "Selbsttest FEHLER: $1 (Exit $got, erwartet $2)" >&2
      sed 's/^/    /' "$dir/out.txt" >&2
      status=1
    else
      echo "ok: $1"
    fi
  }
  printf 'P d 1 2 3 app.wendelin\nP d 1 2 3 io.flutter\n' >"$dir/dex.txt"
  echo "$good_manifest" >"$dir/manifest.xml"
  printf 'android.permission.INTERNET\nandroid.permission.READ_CALENDAR\nandroid.permission.RECORD_AUDIO\n' >"$dir/perms.txt"
  expect "sauberes APK (mit RECORD_AUDIO und Assistenten-Diensten)" 0

  printf 'P d 1 2 3 com.google.android.gms.common\n' >>"$dir/dex.txt"
  expect "GMS-Klasse erkannt" 1 "GMS-/Firebase-Klassen im APK"
  printf 'P d 1 2 3 app.wendelin\n' >"$dir/dex.txt"

  echo "$good_manifest" | sed 's/allowBackup="false"/allowBackup="true"/' >"$dir/manifest.xml"
  expect "allowBackup=true erkannt" 1 '<application> hat nicht android:allowBackup="false"'

  # allowBackup="false" nur an einem anderen Element zählt nicht.
  echo "$good_manifest" | sed 's/ android:allowBackup="false"//' |
    sed 's#<activity android:name="app.wendelin.AssistantActivity"#<activity android:allowBackup="false" android:name="app.wendelin.AssistantActivity"#' >"$dir/manifest.xml"
  expect "allowBackup nur außerhalb von <application>" 1 '<application> hat nicht android:allowBackup="false"'
  echo "$good_manifest" >"$dir/manifest.xml"

  echo "$good_manifest" | sed 's#android:exported="false" />#android:exported="true" />#' >"$dir/manifest.xml"
  expect "exportierte AssistantActivity erkannt" 1 "AssistantActivity unerwartet exportiert"
  # Nur beim ersten Service (VoiceInteractionService) die Berechtigung weglassen.
  echo "$good_manifest" | awk '!done && /BIND_VOICE_INTERACTION/ { sub(/android:permission="android.permission.BIND_VOICE_INTERACTION"/, ""); done = 1 } { print }' >"$dir/manifest.xml"
  expect "Assistenten-Service ohne BIND_VOICE_INTERACTION erkannt" 1 "WendelinVoiceInteractionService ohne"
  echo "$good_manifest" | sed 's/android:enabled="false"/android:enabled="true"/' >"$dir/manifest.xml"
  expect "RecognitionService ab Werk aktiv erkannt" 1 "WendelinRecognitionService nicht ab Werk deaktiviert"
  echo "$good_manifest" | sed 's# android:permission="android.permission.DUMP"##' >"$dir/manifest.xml"
  expect "ProfileInstallReceiver ohne DUMP erkannt" 1 "ProfileInstallReceiver ohne android.permission.DUMP"
  echo "$good_manifest" | sed 's#<activity android:name="app.wendelin.AssistantActivity" android:exported="false" />#&\n    <provider android:name="app.wendelin.Leak" android:exported="true" />#' >"$dir/manifest.xml"
  expect "fremde exportierte Komponente erkannt" 1 "app.wendelin.Leak unerwartet exportiert"
  echo "$good_manifest" >"$dir/manifest.xml"

  printf 'android.permission.ACCESS_FINE_LOCATION\n' >>"$dir/perms.txt"
  expect "unerwartete Berechtigung erkannt" 1 "ACCESS_FINE_LOCATION"
  printf 'android.permission.INTERNET\n' >"$dir/perms.txt"

  # Gradle-Schritt mit einem Baum aus einer Datei.
  run() {
    APKANALYZER="$dir/apkanalyzer" CHECK_APK_GRADLE_DEPS="$dir/deps.txt" \
      "$ROOT/tool/check_apk.sh" "$dir/x.apk" >"$dir/out.txt" 2>&1
  }
  printf '+--- androidx.browser:browser:1.8.0\n|    \\--- androidx.core:core:1.13.1\n' >"$dir/deps.txt"
  expect "Gradle-Baum sauber" 0 "ok: Gradle-Abhängigkeiten ohne GMS/Firebase"
  printf '+--- androidx.browser:browser:1.8.0 FAILED\n' >"$dir/deps.txt"
  expect "nicht aufgelöste Abhängigkeit (FAILED) erkannt" 1 "nicht aufgelöst"
  printf '+--- com.google.android.gms:play-services-base:18.0.0\n' >"$dir/deps.txt"
  expect "GMS im Gradle-Baum erkannt" 1 "GMS/Firebase im Gradle-Abhängigkeitsbaum"
  : >"$dir/deps.txt"
  expect "leerer Gradle-Baum erkannt" 1 "nicht lesbar"
  run() {
    APKANALYZER="$dir/apkanalyzer" CHECK_APK_SKIP_GRADLE=1 \
      "$ROOT/tool/check_apk.sh" "$dir/x.apk" >"$dir/out.txt" 2>&1
  }
  expect "Überspringen warnt" 0 "WARNUNG: Gradle-Abhängigkeiten NICHT geprüft"
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

# Exportierte Komponenten (eine Zeile je Start-Tag).
components="$("$APKANALYZER" manifest print "$APK" | tr '\n' ' ' |
  grep -oE '<(activity|activity-alias|service|receiver|provider)[[:space:]][^>]*>' |
  sed -E 's/[[:space:]]+/ /g' || true)"
attr() { { echo "$1" | grep -oE "android:$2=\"[^\"]*\"" || true; } | head -1 | sed -E 's/.*="(.*)"/\1/'; }
exported_ok=1
while IFS= read -r tag; do
  [ -n "$tag" ] || continue
  [ "$(attr "$tag" exported)" = "true" ] || continue
  name="$(attr "$tag" name)"
  perm="$(attr "$tag" permission)"
  problem=""
  case "$name" in
    app.wendelin.MainActivity) ;;
    # OAuth-Rückleitung der MCP-Server (WP27): nimmt nur die Adresse an, state prüft die App.
    app.wendelin.OAuthRedirectActivity) ;;
    app.wendelin.WendelinVoiceInteractionService | app.wendelin.WendelinVoiceSessionService)
      [ "$perm" = "android.permission.BIND_VOICE_INTERACTION" ] ||
        problem="ohne android.permission.BIND_VOICE_INTERACTION" ;;
    app.wendelin.WendelinRecognitionService)
      [ "$(attr "$tag" enabled)" = "false" ] ||
        problem="nicht ab Werk deaktiviert (android:enabled=\"false\")" ;;
    androidx.profileinstaller.ProfileInstallReceiver)
      [ "$perm" = "android.permission.DUMP" ] || problem="ohne android.permission.DUMP" ;;
    *) problem="unerwartet exportiert" ;;
  esac
  if [ -n "$problem" ]; then
    echo "FEHLER: Komponente $name $problem" >&2
    exported_ok=0
    fail=1
  fi
done <<<"$(echo "$components" | sed 's/> </>\n</g')"
if [ -z "$components" ]; then
  echo "FEHLER: keine Komponenten im Manifest gefunden" >&2
  fail=1
elif [ "$exported_ok" = 1 ]; then
  echo "ok: exportierte Komponenten wie erwartet"
fi

ALLOWED='^(android\.permission\.INTERNET|android\.permission\.ACCESS_NETWORK_STATE|android\.permission\.READ_CALENDAR|android\.permission\.WRITE_CALENDAR|android\.permission\.RECORD_AUDIO|com\.android\.alarm\.permission\.SET_ALARM|app\.wendelin\.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION)$'
perms="$("$APKANALYZER" manifest permissions "$APK")"
if extra="$(echo "$perms" | grep -vE "$ALLOWED")"; then
  echo "FEHLER: unerwartete Berechtigungen:" >&2
  echo "$extra" >&2
  fail=1
else
  echo "ok: Berechtigungen $(echo "$perms" | tr '\n' ' ')"
fi

# Abhängigkeitsbaum; CHECK_APK_GRADLE_DEPS=<datei> liefert ihn aus einer Datei
# (Selbsttest).
gradle_deps() {
  if [ -n "${CHECK_APK_GRADLE_DEPS:-}" ]; then
    cat "$CHECK_APK_GRADLE_DEPS"
  else
    (cd "$ROOT/app/android" && ./gradlew -q :app:dependencies --configuration releaseRuntimeClasspath 2>&1)
  fi
}

if [ "${CHECK_APK_SKIP_GRADLE:-}" = "1" ]; then
  echo "WARNUNG: Gradle-Abhängigkeiten NICHT geprüft (CHECK_APK_SKIP_GRADLE=1)" >&2
elif ! deps="$(gradle_deps)" || [ -z "$deps" ]; then
  echo "FEHLER: Gradle-Abhängigkeitsbaum nicht lesbar (CHECK_APK_SKIP_GRADLE=1 überspringt):" >&2
  echo "$deps" | tail -5 >&2
  fail=1
elif echo "$deps" | grep -qE '(^|[[:space:]])FAILED$|[[:space:]]FAILED[[:space:]]'; then
  # Eine nicht auflösbare Abhängigkeit verdeckt ihren eigenen Baum.
  echo "FEHLER: Gradle-Abhängigkeiten nicht aufgelöst:" >&2
  echo "$deps" | grep -E 'FAILED' | head >&2
  fail=1
elif echo "$deps" | grep -qE 'com\.google\.android\.gms|com\.google\.firebase'; then
  echo "FEHLER: GMS/Firebase im Gradle-Abhängigkeitsbaum:" >&2
  echo "$deps" | grep -E 'com\.google\.android\.gms|com\.google\.firebase' | head >&2
  fail=1
else
  echo "ok: Gradle-Abhängigkeiten ohne GMS/Firebase"
fi

exit $fail
