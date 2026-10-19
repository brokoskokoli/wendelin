#!/usr/bin/env bash
# Prüft ein Android-APK auf K7 (keine Google Play Services) und das
# Manifest (kein Backup, nur die erwarteten Berechtigungen).
#
#   tool/check_apk.sh [pfad/zum.apk]   # Standard: Release-APK, wird gebaut
#   tool/check_apk.sh --manifest [xml…] # Allowlist gegen das Quell-Manifest, ohne APK-Build
#   tool/check_apk.sh --self-test      # prüft das Skript mit Attrappen
#
# Prüfungen:
#   - keine Klassen aus com.google.android.gms, com.google.firebase,
#     com.google.android.play, com.android.vending (apkanalyzer dex packages)
#   - <application> mit android:allowBackup="false" und
#     android:dataExtractionRules; keine Berechtigungen außer der Liste
#     (M2: RECORD_AUDIO für Push-to-talk, Assistent und Spracherkennung;
#     M4: POST_NOTIFICATIONS für die Warnung bei fehlgeschlagener TEE-Prüfung;
#     WP86: ACCESS_FINE/COARSE_LOCATION für den Standort, nie Hintergrund)
#   - exportierte Komponenten nur aus der Liste: MainActivity,
#     OAuthRedirectActivity (OAuth-Rückleitung, WP27), die
#     Assistenten-Services nur mit BIND_VOICE_INTERACTION, der
#     RecognitionService ab Werk deaktiviert (enabled="false", ADR 0006),
#     ProfileInstallReceiver nur mit DUMP, MediaListenerService (WP90,
#     NotificationListenerService) nur mit
#     BIND_NOTIFICATION_LISTENER_SERVICE; alles andere nicht exportiert
#   - Gradle-Abhängigkeiten (releaseRuntimeClasspath) ohne GMS/Firebase;
#     ist der Baum nicht lesbar, ist das ein Fehler – überspringen nur mit
#     CHECK_APK_SKIP_GRADLE=1 (mit Warnung). Eine nicht aufgelöste
#     Abhängigkeit (FAILED) ist ein Fehler.
#
# Umgebung: ANDROID_SDK_ROOT, APKANALYZER (Pfad, z. B. für Attrappen).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

attr() { { echo "$1" | grep -oE "android:$2=\"[^\"]*\"" || true; } | head -1 | sed -E 's/.*="(.*)"/\1/'; }

# Begründung WP85: READ_CONTACTS (Kontakt nach Name finden), SEND_SMS (SMS erst nach bestätigter
# Vorschau senden), CALL_PHONE (Anruf nach Bestätigung starten, sonst Wählbildschirm);
# alle drei werden erst beim Aktivieren der Integration „Kontakte & Telefon“ abgefragt.
# Begründung WP86: ACCESS_FINE_LOCATION/ACCESS_COARSE_LOCATION (Standort für Wetter und Karten,
# nur beim Aktivieren der Integration „Standort“ abgefragt).
ALLOWED='^(android\.permission\.FOREGROUND_SERVICE|android\.permission\.FOREGROUND_SERVICE_MICROPHONE|android\.permission\.WAKE_LOCK|android\.permission\.INTERNET|android\.permission\.ACCESS_NETWORK_STATE|android\.permission\.CHANGE_WIFI_MULTICAST_STATE|android\.permission\.POST_NOTIFICATIONS|android\.permission\.READ_CALENDAR|android\.permission\.WRITE_CALENDAR|android\.permission\.READ_CONTACTS|android\.permission\.SEND_SMS|android\.permission\.CALL_PHONE|android\.permission\.RECORD_AUDIO|android\.permission\.ACCESS_FINE_LOCATION|android\.permission\.ACCESS_COARSE_LOCATION|android\.permission\.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS|com\.android\.alarm\.permission\.SET_ALARM|app\.wendelin\.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION)$'
# Erlaubte exportierte Komponenten; Argumente: Name, android:permission, android:enabled.
# Gibt den Befund aus (leer = erlaubt).
export_problem() {
  local name="$1" perm="$2" enabled="$3" problem=""
  case "$name" in
    app.wendelin.MainActivity) ;;
    # OAuth-Rückleitung der MCP-Server (WP27): nimmt nur die Adresse an, state prüft die App.
    app.wendelin.OAuthRedirectActivity) ;;
    app.wendelin.WendelinVoiceInteractionService | app.wendelin.WendelinVoiceSessionService)
      [ "$perm" = "android.permission.BIND_VOICE_INTERACTION" ] ||
        problem="ohne android.permission.BIND_VOICE_INTERACTION" ;;
    app.wendelin.WendelinRecognitionService)
      [ "$enabled" = "false" ] ||
        problem="nicht ab Werk deaktiviert (android:enabled=\"false\")" ;;
    # Anker des Benachrichtigungszugriffs (WP90): das System bindet ihn, ohne
    # die Berechtigung könnte jede App den Dienst binden.
    app.wendelin.MediaListenerService)
      [ "$perm" = "android.permission.BIND_NOTIFICATION_LISTENER_SERVICE" ] ||
        problem="ohne android.permission.BIND_NOTIFICATION_LISTENER_SERVICE" ;;
    androidx.profileinstaller.ProfileInstallReceiver)
      [ "$perm" = "android.permission.DUMP" ] || problem="ohne android.permission.DUMP" ;;
    *) problem="unerwartet exportiert" ;;
  esac
  echo "$problem"
}

# Quell-Manifest (ohne APK-Build): Berechtigungen gegen ALLOWED, exportierte Komponenten
# gegen export_problem. Namen ".X" gelten als app.wendelin.X. Läuft im Gate (check_manifest),
# sobald sich ein AndroidManifest.xml ändert.
check_manifest() {
  local file="$1" fail=0 tags tag name perm problem
  [ -f "$file" ] || { echo "Manifest nicht gefunden: $file" >&2; return 1; }
  local flat
  flat="$(tr '\n' ' ' <"$file" | sed -E 's/<!--([^-]|-[^-])*-->//g; s/[[:space:]]+/ /g')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if ! echo "$p" | grep -qE "$ALLOWED"; then
      echo "FEHLER: Berechtigung $p nicht in der Allowlist von tool/check_apk.sh (ALLOWED, K7/K-Eintrag, Begründung ergänzen)" >&2
      fail=1
    fi
  done <<<"$(echo "$flat" | grep -oE '<uses-permission(-sdk-23)? [^>]*>' | grep -oE 'android:name="[^"]*"' | sed -E 's/.*="(.*)"/\1/' | sort -u)"
  tags="$(echo "$flat" | grep -oE '<(activity|activity-alias|service|receiver|provider) [^>]*>' || true)"
  while IFS= read -r tag; do
    [ -n "$tag" ] || continue
    [ "$(attr "$tag" exported)" = "true" ] || continue
    name="$(attr "$tag" name)"
    case "$name" in .*) name="app.wendelin$name" ;; esac
    perm="$(attr "$tag" permission)"
    problem="$(export_problem "$name" "$perm" "$(attr "$tag" enabled)")"
    if [ -n "$problem" ]; then
      echo "FEHLER: Komponente $name $problem (Allowlist in tool/check_apk.sh)" >&2
      fail=1
    fi
  done <<<"$tags"
  [ $fail = 0 ] && echo "ok: Manifest $file entspricht der Allowlist"
  return $fail
}

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
    <service android:name="app.wendelin.WakeWordService"
        android:foregroundServiceType="microphone" android:exported="false" />
    <service android:name="app.wendelin.WendelinRecognitionService"
        android:enabled="false" android:exported="true" />
    <receiver android:name="androidx.profileinstaller.ProfileInstallReceiver"
        android:permission="android.permission.DUMP" android:exported="true" />
    <service android:name="app.wendelin.MediaListenerService"
        android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
        android:exported="true" />
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
  echo "$good_manifest" | sed 's/android:foregroundServiceType="microphone"/android:foregroundServiceType="location"/' >"$dir/manifest.xml"
  expect "WakeWordService mit falschem Dienst-Typ erkannt" 1 "WakeWordService nicht vom Typ microphone"
  echo "$good_manifest" | sed 's/android:foregroundServiceType="microphone" android:exported="false"/android:foregroundServiceType="microphone" android:exported="true"/' >"$dir/manifest.xml"
  expect "exportierter WakeWordService erkannt" 1 "WakeWordService darf nicht exportiert sein"
  echo "$good_manifest" | grep -v WakeWordService | grep -v 'foregroundServiceType="microphone" android:exported' >"$dir/manifest.xml"
  expect "fehlender WakeWordService erkannt" 1 "WakeWordService fehlt im Manifest"
  echo "$good_manifest" | sed 's/android:enabled="false"/android:enabled="true"/' >"$dir/manifest.xml"
  expect "RecognitionService ab Werk aktiv erkannt" 1 "WendelinRecognitionService nicht ab Werk deaktiviert"
  echo "$good_manifest" | sed 's# android:permission="android.permission.DUMP"##' >"$dir/manifest.xml"
  expect "ProfileInstallReceiver ohne DUMP erkannt" 1 "ProfileInstallReceiver ohne android.permission.DUMP"
  echo "$good_manifest" | sed 's# android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"##' >"$dir/manifest.xml"
  expect "MediaListenerService ohne BIND_NOTIFICATION_LISTENER_SERVICE erkannt" 1 "MediaListenerService ohne android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
  echo "$good_manifest" | sed 's#<activity android:name="app.wendelin.AssistantActivity" android:exported="false" />#&\n    <provider android:name="app.wendelin.Leak" android:exported="true" />#' >"$dir/manifest.xml"
  expect "fremde exportierte Komponente erkannt" 1 "app.wendelin.Leak unerwartet exportiert"
  echo "$good_manifest" >"$dir/manifest.xml"

  printf 'android.permission.ACCESS_BACKGROUND_LOCATION\n' >>"$dir/perms.txt"
  expect "unerwartete Berechtigung erkannt" 1 "ACCESS_BACKGROUND_LOCATION"
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

  # Quell-Manifest (--manifest, ohne APK): neue Berechtigung bzw. Komponente ist rot.
  src='<manifest xmlns:android="x">
    <!-- <uses-permission android:name="android.permission.CAMERA"/> auskommentiert -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:allowBackup="false">
      <service android:name=".WendelinVoiceSessionService"
          android:permission="android.permission.BIND_VOICE_INTERACTION" android:exported="true" />
      <activity android:name=".AssistantActivity" android:exported="false" />
    </application>
  </manifest>'
  mexpect() { # name, erwarteter Exit, [Meldung]
    local got=0
    "$ROOT/tool/check_apk.sh" --manifest "$dir/src.xml" >"$dir/out.txt" 2>&1 || got=$?
    if [ "$got" != "$1" ] || { [ -n "${3:-}" ] && ! grep -qF "$3" "$dir/out.txt"; }; then
      echo "Selbsttest FEHLER: $2 (Exit $got, erwartet $1)" >&2
      sed 's/^/    /' "$dir/out.txt" >&2
      status=1
    else
      echo "ok: $2"
    fi
  }
  echo "$src" >"$dir/src.xml"
  mexpect 0 "Quell-Manifest sauber (Kommentar zählt nicht)"
  echo "$src" | sed 's#<application#<uses-permission android:name="android.permission.CAMERA"/>\n<application#' >"$dir/src.xml"
  mexpect 1 "neue Berechtigung ohne Allowlist-Eintrag rot" "Berechtigung android.permission.CAMERA"
  echo "$src" | sed 's#<activity#<provider android:name=".Leak" android:exported="true" />\n<activity#' >"$dir/src.xml"
  mexpect 1 "neue exportierte Komponente rot" "app.wendelin.Leak unerwartet exportiert"
  echo "$src" | sed 's# android:permission="android.permission.BIND_VOICE_INTERACTION"##' >"$dir/src.xml"
  mexpect 1 "exportierter Assistenten-Dienst ohne Berechtigung rot" "ohne android.permission.BIND_VOICE_INTERACTION"
  return $status
}

if [ "${1:-}" = "--manifest" ]; then
  shift
  [ $# -gt 0 ] || set -- "$ROOT"/app/android/app/src/*/AndroidManifest.xml
  rc=0
  for f in "$@"; do check_manifest "$f" || rc=1; done
  exit $rc
fi
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
exported_ok=1
while IFS= read -r tag; do
  [ -n "$tag" ] || continue
  [ "$(attr "$tag" exported)" = "true" ] || continue
  name="$(attr "$tag" name)"
  perm="$(attr "$tag" permission)"
  problem="$(export_problem "$name" "$perm" "$(attr "$tag" enabled)")"
  if [ -n "$problem" ]; then
    echo "FEHLER: Komponente $name $problem" >&2
    exported_ok=0
    fail=1
  fi
done <<<"$(echo "$components" | sed 's/> </>\n</g')"
# Wake-Word-Dienst (WP50, ADR 0013): Typ microphone, nicht exportiert.
wake_tag="$(echo "$components" | sed 's/> </>\n</g' | grep -F 'app.wendelin.WakeWordService' | head -1 || true)"
if [ -z "$wake_tag" ]; then
  echo "FEHLER: WakeWordService fehlt im Manifest" >&2
  fail=1
else
  case "$(attr "$wake_tag" foregroundServiceType)" in
    microphone | 0x80 | 128) echo 'ok: WakeWordService vom Typ microphone' ;;
    *) echo "FEHLER: WakeWordService nicht vom Typ microphone" >&2; fail=1 ;;
  esac
  if [ "$(attr "$wake_tag" exported)" = "true" ]; then
    echo "FEHLER: WakeWordService darf nicht exportiert sein" >&2
    fail=1
  fi
fi
if echo "$components" | grep -qi 'BOOT_COMPLETED'; then
  echo "FEHLER: Boot-Empfänger im Manifest (WP50: kein BOOT_COMPLETED)" >&2
  fail=1
fi
if [ -z "$components" ]; then
  echo "FEHLER: keine Komponenten im Manifest gefunden" >&2
  fail=1
elif [ "$exported_ok" = 1 ]; then
  echo "ok: exportierte Komponenten wie erwartet"
fi

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
