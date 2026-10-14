#!/usr/bin/env bash
# Gerätetests (WP11) auf einem Android-Emulator ohne Google Play (K7).
#
#   tool/e2e_android.sh [integration_test/<datei>.dart …]
#
# Erwartet ein laufendes Gerät (adb) – z. B. das AVD Wendelin_AOSP_35:
#   ~/Library/Android/sdk/emulator/emulator -avd Wendelin_AOSP_35 \
#     -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect &
#
# Das Skript
#   1. legt einen lokalen Kalender an, falls das Gerät keinen hat
#      (Content-Provider als Sync-Adapter, Kontotyp LOCAL),
#   2. erteilt die Kalender-Berechtigung, sobald `flutter test` die App
#      installiert hat (`pm grant` im Hintergrund – die Tests warten darauf),
#   3. tippt im Speichern-Dialog der Android-Dateiauswahl auf „Speichern“
#      (SAF-Test), da sich der System-Picker nicht aus Flutter bedienen lässt,
#   4. führt die Tests aus und prüft danach, dass kein Testtermin übrig ist.
#
# Umgebungsvariablen: ANDROID_SDK_ROOT (Standard ~/Library/Android/sdk),
# DEVICE bzw. ANDROID_SERIAL (ohne beides muss genau ein Gerät verbunden
# sein, sonst Abbruch). Läuft nur auf Emulatoren (Seriennummer emulator-*,
# ro.kernel.qemu=1); ein echtes Gerät nur mit E2E_ALLOW_DEVICE=1.
# Achtung, auf einem echten Gerät: Das Skript legt Testtermine im Kalender
# an, schreibt /sdcard/Download/wendelin-e2e-*.md und mit WENDELIN_MODELS
# /sdcard/Documents/WendelinE2E (wird danach gelöscht), setzt und entzieht
# die Assistenten-Rolle und löscht mit WENDELIN_LIVE oder WENDELIN_MODELS
# alle Wendelin-Daten (`pm clear app.wendelin`: Verläufe, Einstellungen,
# Keys, Modelle).
#
# Sprache und Assistent (M2, WP19): mit WENDELIN_MODELS=<dir> (darin
# whisper-base/, whisper-small/, silero-vad/ wie in tool/e2e_recognizer.sh)
# laufen auch voice_note_e2e_test.dart und overlay_e2e_test.dart. Das Skript
#   5. erteilt RECORD_AUDIO und kopiert per `run-as` die Modelle nach
#      files/models/ und die WAVs aus app/test/fixtures/stt/ nach
#      files/e2e/stt/ (einmal je Installation, Marke files/e2e/ready),
#   6. legt den Test-Vault /sdcard/Documents/WendelinE2E an und wählt ihn in
#      der Ordnerauswahl (Documents → WendelinE2E → „Use this folder“ →
#      „Allow“),
#   7. erledigt Aufträge der Tests aus files/e2e/host-request: `assist`
#      (Bildschirm an, Assistenten-Rolle per `cmd role add-role-holder`,
#      KEYCODE_ASSIST öffnet das Overlay), `back` (Overlay schließen, warten
#      bis die AssistantActivity weg ist), `meminfo` (`dumpsys meminfo` nach
#      files/e2e/meminfo.txt), `unrole` (Rolle entziehen, prüfen,
#      dass WendelinRecognitionService wieder aus ist),
#   8. räumt danach auf: Rolle entzogen, Test-Vault gelöscht, App-Daten
#      gelöscht (`pm clear`, auch die Modell-Kopien).
#
# Sprach-Robustheit (WP30): WENDELIN_REPEAT=<n> wiederholt die Runden von
# voice_robustness_e2e_test.dart (je Runde D3 ohne und nach Overlay-Nutzung),
# E2E_VOICE_LOG=<datei> sammelt danach alle `Wendelin/voice`-Zeilen.
#
# Tests mit eigenem Skript (WP29): app_presence_e2e_test.dart
# (tool/e2e_app_presence.sh: Attrappen-APKs), mcp_e2e_test.dart und
# oauth_redirect_e2e_test.dart (tool/e2e_mcp.sh: Test-Server auf dem Rechner,
# `am start`-Rückleitungen) brauchen Vorbereitung, die dieses Skript nicht
# leistet. Im Sammellauf (ohne Argumente) werden sie nicht rot, sondern als
# „übersprungen – Skript X“ gemeldet; mit E2E_SCRIPTS=1 ruft das Skript
# sie danach selbst auf (dasselbe Gerät). Nennt man sie ausdrücklich als
# Argument, laufen sie ebenfalls über ihr Skript.
#
# Live (integration_test/live_e2e_test.dart, kostet ein paar Cent):
#   WENDELIN_LIVE=1 mit ANTHROPIC_API_KEY in der Umgebung. Der Key geht per
#   `adb shell run-as` über stdin in die privaten App-Daten (nicht auf die
#   Platte des Rechners, nicht in den Build), der Test löscht die Datei
#   sofort; nach dem Lauf werden die App-Daten gelöscht (`pm clear`).
set -euo pipefail

PKG=app.wendelin
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tool/android_device.sh
. "$ROOT/tool/android_device.sh"

# Nur Emulatoren: Das Skript schreibt in den Kalender, tippt in der
# Dateiauswahl und löscht App-Daten. Ein echtes Gerät nur mit
# E2E_ALLOW_DEVICE=1.
if ! is_emulator; then
  if [ "${E2E_ALLOW_DEVICE:-}" != "1" ]; then
    echo "Abbruch: $DEVICE ist kein Emulator (Gerätetests schreiben in" \
      "Kalender und Dateien). Freigabe nur mit E2E_ALLOW_DEVICE=1." >&2
    exit 1
  fi
  echo "Warnung: E2E_ALLOW_DEVICE=1 – Tests laufen auf dem echten Gerät $DEVICE." \
    "Sie legen Testtermine an, schreiben /sdcard/Download/wendelin-e2e-*.md" \
    "und /sdcard/Documents/WendelinE2E (Test-Vault, wird gelöscht), ändern die" \
    "Assistenten-Rolle und löschen mit WENDELIN_LIVE/WENDELIN_MODELS alle" \
    "Wendelin-Daten (pm clear app.wendelin)." >&2
fi

if [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" != "1" ]; then
  echo "Gerät $DEVICE ist noch nicht hochgefahren" >&2
  exit 1
fi
if adb shell pm list packages | grep -q 'com.google.android.gms'; then
  echo "Warnung: Gerät hat Google Play Services (K7 verlangt AOSP ohne GMS)" >&2
fi

# 1. Lokaler Kalender
if ! adb shell content query --uri content://com.android.calendar/calendars \
  --projection _id | grep -q '_id='; then
  echo "Lege lokalen Kalender „Wendelin Test“ an"
  adb shell 'content insert --uri "content://com.android.calendar/calendars?caller_is_syncadapter=true&account_name=Wendelin%20Test&account_type=LOCAL" --bind account_name:s:"Wendelin Test" --bind account_type:s:LOCAL --bind name:s:wendelin_test --bind calendar_displayName:s:"Wendelin Test" --bind calendar_access_level:i:700 --bind ownerAccount:s:"Wendelin Test" --bind visible:i:1 --bind sync_events:i:1 --bind calendar_timezone:s:Europe/Berlin --bind calendar_color:i:-16776961'
fi

# 5. Sprache (optional): Modelle und WAVs prüfen
MODELS="${WENDELIN_MODELS:-}"
VAULT_DIR=/sdcard/Documents/WendelinE2E
if [ -n "$MODELS" ]; then
  for f in whisper-base/base-encoder.int8.onnx whisper-base/base-decoder.int8.onnx \
    whisper-base/base-tokens.txt whisper-small/small-encoder.int8.onnx \
    whisper-small/small-decoder.int8.onnx whisper-small/small-tokens.txt \
    silero-vad/silero_vad.onnx; do
    [ -f "$MODELS/$f" ] || { echo "Modell fehlt: $MODELS/$f" >&2; exit 1; }
  done
  adb shell mkdir -p "$VAULT_DIR"
fi

# 2. + 3. Helfer im Hintergrund
installed() { adb shell pm list packages "$PKG" | tr -d '\r' | grep -q "^package:$PKG\$"; }
in_app() { adb shell run-as "$PKG" "$@"; }
TMP=/data/local/tmp/wendelin-e2e
copy_in() { # <quelle auf dem Rechner> <ziel relativ zu files/>
  adb push "$1" "$TMP/x" >/dev/null 2>&1
  adb shell "cat $TMP/x | run-as $PKG sh -c 'cat > files/$2'"
  adb shell rm -f "$TMP/x"
}
prepare_voice() {
  in_app test -f files/e2e/ready 2>/dev/null && return 0
  echo "Kopiere Modelle und WAVs in die App-Daten …"
  adb shell mkdir -p "$TMP"
  in_app mkdir -p files/models/whisper-base files/models/whisper-small \
    files/models/silero-vad files/e2e/stt
  local id f
  for id in whisper-base whisper-small silero-vad; do
    for f in "$MODELS/$id"/*; do copy_in "$f" "models/$id/$(basename "$f")"; done
  done
  for f in "$ROOT"/app/test/fixtures/stt/*.wav; do
    copy_in "$f" "e2e/stt/$(basename "$f")"
  done
  in_app touch files/e2e/ready
  echo "Modelle und WAVs bereit"
}
# Text-Treffer im aktuellen uiautomator-Abzug antippen.
ui_dump() {
  adb shell uiautomator dump /sdcard/wendelin_ui.xml >/dev/null 2>&1 || true
  adb shell cat /sdcard/wendelin_ui.xml 2>/dev/null | tr '>' '\n'
}
tap_text() { # <abzug> <text-regex>
  local bounds n
  bounds="$(echo "$1" | grep -E "text=\"($2)\"" |
    grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1 || true)"
  [ -n "$bounds" ] || return 1
  read -r -a n <<<"$(echo "$bounds" | tr -c '0-9' ' ')"
  adb shell input tap $(((n[0] + n[2]) / 2)) $(((n[1] + n[3]) / 2))
}
resumed() { adb shell dumpsys activity activities 2>/dev/null | grep -E 'topResumedActivity|mResumedActivity'; }
LOCK_PIN=4711
host_request() {
  local action
  action="$(in_app cat files/e2e/host-request 2>/dev/null | tr -d '\r' || true)"
  [ -n "$action" ] || return 0
  in_app rm -f files/e2e/host-request
  case "$action" in
    assist)
      adb shell input keyevent KEYCODE_WAKEUP
      adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
      if ! adb shell cmd role get-role-holders android.app.role.ASSISTANT | grep -q "$PKG"; then
        adb shell cmd role add-role-holder --user 0 android.app.role.ASSISTANT "$PKG"
        sleep 2
      fi
      adb shell input keyevent KEYCODE_ASSIST
      for _ in $(seq 1 40); do resumed | grep -q AssistantActivity && break; sleep 0.5; done
      ;;
    assist-locked)
      # WP53: gesperrtes Gerät (PIN nur auf dem Emulator), Bildschirm aus und
      # an (Sperrbildschirm), dann KEYCODE_ASSIST. Entfernt wird die PIN von
      # `unlock` und beim Aufräumen.
      is_emulator || { echo "Sperre nur auf dem Emulator" >&2; exit 1; }
      adb shell locksettings set-pin "$LOCK_PIN" >/dev/null
      adb shell input keyevent KEYCODE_SLEEP
      sleep 2
      adb shell input keyevent KEYCODE_WAKEUP
      sleep 2
      if ! adb shell cmd role get-role-holders android.app.role.ASSISTANT | grep -q "$PKG"; then
        adb shell cmd role add-role-holder --user 0 android.app.role.ASSISTANT "$PKG"
        sleep 2
      fi
      adb shell input keyevent KEYCODE_ASSIST
      for _ in $(seq 1 40); do resumed | grep -q AssistantActivity && break; sleep 0.5; done
      ;;
    unlock)
      adb shell locksettings clear --old "$LOCK_PIN" >/dev/null 2>&1 || true
      adb shell input keyevent KEYCODE_WAKEUP
      adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
      ;;
    back)
      adb shell input keyevent KEYCODE_BACK
      for _ in $(seq 1 40); do
        adb shell dumpsys activity activities | grep -q 'app.wendelin/.AssistantActivity' || break
        sleep 0.5
      done
      ;;
    meminfo)
      # Speicher der App (B14, WP30): TOTAL PSS/RSS und Native Heap.
      adb shell dumpsys meminfo "$PKG" | tr -d '\r' |
        grep -E 'TOTAL PSS|TOTAL RSS|TOTAL SWAP|Native Heap:|^ *TOTAL ' |
        adb shell run-as "$PKG" sh -c "'cat > files/e2e/meminfo.txt'"
      ;;
    unrole)
      adb shell cmd role remove-role-holder --user 0 android.app.role.ASSISTANT "$PKG"
      sleep 3
      # Nur der Abschnitt enabledComponents (bis zur nächsten Überschrift).
      if adb shell dumpsys package "$PKG" | tr -d '\r' |
        awk '/enabledComponents:/ {on = 1; next} on && /^ *[A-Za-z]+:$/ {on = 0} on' |
        grep -q WendelinRecognitionService; then
        in_app sh -c "'echo aktiv > files/e2e/recognizer-state'"
      else
        in_app sh -c "'echo aus > files/e2e/recognizer-state'"
      fi
      ;;
  esac
  in_app touch "files/e2e/host-done-$action"
}
LIVE="${WENDELIN_LIVE:-}"
if [ -n "$LIVE" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "WENDELIN_LIVE gesetzt, aber ANTHROPIC_API_KEY fehlt" >&2
  exit 1
fi
helper() {
  local granted="" pushed="" voiced=""
  while true; do
    if [ -z "$granted" ] && installed; then
      if adb shell pm grant "$PKG" android.permission.READ_CALENDAR 2>/dev/null &&
        adb shell pm grant "$PKG" android.permission.WRITE_CALENDAR 2>/dev/null; then
        granted=1
      fi
    fi
    if [ -n "$LIVE" ] && [ -n "$granted" ] && [ -z "$pushed" ]; then
      if printf '%s' "$ANTHROPIC_API_KEY" | adb shell run-as "$PKG" \
        sh -c "'mkdir -p files && cat > files/live_anthropic.key'" 2>/dev/null; then
        pushed=1
      fi
    fi
    if [ -n "$granted" ] && ! installed; then
      granted="" # neu installiert: erneut erteilen
      voiced=""
    fi
    if [ -n "$MODELS" ] && [ -n "$granted" ] && [ -z "$voiced" ]; then
      adb shell pm grant "$PKG" android.permission.RECORD_AUDIO 2>/dev/null &&
        prepare_voice && voiced=1
    fi
    # Dateiauswahl im Vordergrund: „Speichern“ (Liste) bzw. den Test-Vault
    # (Ordnerauswahl) antippen.
    if resumed | grep -q documentsui; then
      local ui
      ui="$(ui_dump)"
      tap_text "$ui" 'ALLOW|Zulassen|ZULASSEN|SAVE|Speichern|SPEICHERN' ||
        { echo "$ui" | grep -q 'text="Files in WendelinE2E"' &&
          tap_text "$ui" 'USE THIS FOLDER|DIESEN ORDNER VERWENDEN'; } ||
        tap_text "$ui" 'WendelinE2E' || tap_text "$ui" 'Documents' || true
    fi
    if [ -n "$voiced" ]; then host_request; fi
    sleep 1
  done
}
helper &
HELPER=$!
cleanup() {
  kill "$HELPER" 2>/dev/null || true
  # Sperre aus WP53 sicher entfernen (nur Emulator).
  if is_emulator; then
    adb shell locksettings clear --old "$LOCK_PIN" >/dev/null 2>&1 || true
  fi
  if [ -n "$LIVE" ]; then
    adb shell run-as "$PKG" rm -f files/live_anthropic.key 2>/dev/null || true
  fi
  # Testdateien der Dateiauswahl und den uiautomator-Abzug entfernen.
  adb shell 'rm -f /sdcard/Download/wendelin-e2e-*.md /sdcard/wendelin_ui.xml' 2>/dev/null || true
  if [ -n "$MODELS" ]; then
    adb shell cmd role remove-role-holder --user 0 android.app.role.ASSISTANT "$PKG" 2>/dev/null || true
    adb shell rm -rf "$VAULT_DIR" "$TMP" 2>/dev/null || true
    if installed; then adb shell pm clear "$PKG" >/dev/null || true; fi
  fi
}
trap cleanup EXIT

# 4. Tests
cd "$ROOT/app"
COLLECT=0
if [ $# -eq 0 ]; then
  COLLECT=1
  set -- integration_test/*_test.dart
fi
# Tests mit eigenem Skript herausnehmen (siehe Kopf).
script_for() { # <test.dart> -> Skript oder leer
  case "$(basename "$1")" in
    app_presence_e2e_test.dart) echo tool/e2e_app_presence.sh ;;
    mcp_e2e_test.dart | oauth_redirect_e2e_test.dart) echo tool/e2e_mcp.sh ;;
  esac
}
SCRIPTS=()
KEEP=()
for f in "$@"; do
  s="$(script_for "$f")"
  if [ -z "$s" ]; then
    KEEP+=("$f")
  else
    case " ${SCRIPTS[*]-} " in *" $s "*) ;; *) SCRIPTS+=("$s") ;; esac
  fi
done
set -- ${KEEP[@]+"${KEEP[@]}"}
status=0
DEFINES=()
if [ -n "$LIVE" ]; then DEFINES+=(--dart-define=WENDELIN_LIVE=true); fi
if [ -n "$MODELS" ]; then DEFINES+=(--dart-define=WENDELIN_VOICE_E2E=true); fi
# Wiederholungen der Sprach-Robustheit (WP30, voice_robustness_e2e_test.dart).
if [ -n "${WENDELIN_REPEAT:-}" ]; then
  DEFINES+=(--dart-define=WENDELIN_REPEAT="$WENDELIN_REPEAT")
fi

# Tests, die eine zweite Engine der App starten (Overlay), definieren deren
# Dart-Einstieg selbst (`@pragma('vm:entry-point')`): Die Engine sucht ihn in
# der Root-Bibliothek, und die ist nur bei `flutter build -t <test>` die
# Testdatei (bei `flutter test` ein generierter Listener). Sie laufen deshalb
# über Android-Instrumentierung (androidTest/…/FlutterE2eTest.kt).
PLAIN=()
INSTRUMENTED=()
for f in "$@"; do
  if [ -f "$f" ] && grep -q "pragma('vm:entry-point')" "$f"; then
    INSTRUMENTED+=("$f")
  else
    PLAIN+=("$f")
  fi
done
run_instrumented() { # <test.dart>
  echo "Instrumentiert: $1"
  (cd android && ./gradlew -q app:assembleDebugAndroidTest >/dev/null)
  flutter build apk --debug -t "$1" ${DEFINES[@]+"${DEFINES[@]}"} >/dev/null
  adb install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null
  adb install -r build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk >/dev/null
  adb logcat -c
  adb logcat -G 16M >/dev/null 2>&1 || true
  local out
  out="$(adb shell am instrument -w -r -e class "$PKG.FlutterE2eTest" \
    "$PKG.test/androidx.test.runner.AndroidJUnitRunner" | tr -d '\r')"
  # Ausgaben der Dart-Tests (Messwerte, Fehler) aus logcat.
  adb logcat -d -s flutter | grep -E 'M2-|WP30-|TOTAL|Native Heap|EXCEPTION|Expected|Actual|Notiz|fail' | cut -c 33- || true
  # Diagnosezeilen ohne Inhalte (WP30) aller Engines und der Session.
  if [ -n "${E2E_VOICE_LOG:-}" ]; then
    adb logcat -d | grep 'Wendelin/voice' >"$E2E_VOICE_LOG" || true
  fi
  echo "$out" | grep -E 'INSTRUMENTATION_STATUS: (test|stack)=|^OK|FAILURES|Tests run|INSTRUMENTATION_FAILED' | head -20 || true
  adb uninstall "$PKG.test" >/dev/null 2>&1 || true
  echo "$out" | grep -q '^OK (' || return 1
}
if [ ${#PLAIN[@]} -gt 0 ]; then
  flutter test "${PLAIN[@]}" ${DEFINES[@]+"${DEFINES[@]}"} -d "$DEVICE" || status=$?
fi
for f in ${INSTRUMENTED[@]+"${INSTRUMENTED[@]}"}; do
  run_instrumented "$f" || status=1
done
if [ -n "$LIVE" ] && installed; then
  adb shell pm clear "$PKG" >/dev/null || true
fi

if [ ${#SCRIPTS[@]} -gt 0 ]; then
  # Der Hintergrund-Helfer (Berechtigungen, Modelle, Dateiauswahl) würde die
  # Skripte stören (run-as auf eine gerade deinstallierte App).
  kill "$HELPER" 2>/dev/null || true
  if [ "$COLLECT" = 1 ] && [ "${E2E_SCRIPTS:-}" != "1" ]; then
    for s in "${SCRIPTS[@]}"; do
      echo "übersprungen – Skript $s (eigene Vorbereitung; E2E_SCRIPTS=1 ruft es auf)"
    done
  else
    for s in "${SCRIPTS[@]}"; do
      echo "Skript $s"
      DEVICE="$DEVICE" bash "$ROOT/$s" || status=1
    done
  fi
fi

left="$(adb shell "content query --uri content://com.android.calendar/events --projection _id --where \"title='Tauchen' AND deleted=0\"" | grep -c '_id=' || true)"
if [ "$left" != "0" ]; then
  echo "Fehler: $left Testtermin(e) „Tauchen“ im Gerätekalender übrig" >&2
  status=1
fi
exit $status
