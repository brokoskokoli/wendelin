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
# DEVICE (Standard: erstes Gerät). Läuft nur auf Emulatoren (Seriennummer
# emulator-*, ro.kernel.qemu=1); ein echtes Gerät nur mit E2E_ALLOW_DEVICE=1.
#
# Live (integration_test/live_e2e_test.dart, kostet ein paar Cent):
#   WENDELIN_LIVE=1 mit ANTHROPIC_API_KEY in der Umgebung. Der Key geht per
#   `adb shell run-as` über stdin in die privaten App-Daten (nicht auf die
#   Platte des Rechners, nicht in den Build), der Test löscht die Datei
#   sofort; nach dem Lauf werden die App-Daten gelöscht (`pm clear`).
set -euo pipefail

SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
ADB="$SDK/platform-tools/adb"
PKG=app.wendelin
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${DEVICE:-$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')}"
[ -n "$DEVICE" ] || { echo "Kein Android-Gerät verbunden" >&2; exit 1; }
adb() { "$ADB" -s "$DEVICE" "$@"; }

# Nur Emulatoren: Das Skript schreibt in den Kalender, tippt in der
# Dateiauswahl und löscht App-Daten. Ein echtes Gerät nur mit
# E2E_ALLOW_DEVICE=1.
is_emulator() {
  case "$DEVICE" in emulator-*) ;; *) return 1 ;; esac
  [ "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = "1" ]
}
if ! is_emulator; then
  if [ "${E2E_ALLOW_DEVICE:-}" != "1" ]; then
    echo "Abbruch: $DEVICE ist kein Emulator (Gerätetests schreiben in" \
      "Kalender und Dateien). Freigabe nur mit E2E_ALLOW_DEVICE=1." >&2
    exit 1
  fi
  echo "Warnung: E2E_ALLOW_DEVICE=1 – Tests laufen auf dem echten Gerät $DEVICE" >&2
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

# 2. + 3. Helfer im Hintergrund
installed() { adb shell pm list packages "$PKG" | tr -d '\r' | grep -q "^package:$PKG\$"; }
LIVE="${WENDELIN_LIVE:-}"
if [ -n "$LIVE" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "WENDELIN_LIVE gesetzt, aber ANTHROPIC_API_KEY fehlt" >&2
  exit 1
fi
helper() {
  local granted="" pushed=""
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
    fi
    # Dateiauswahl im Vordergrund: „Speichern“ antippen.
    if adb shell dumpsys activity activities 2>/dev/null |
      grep -E 'topResumedActivity|mResumedActivity' | grep -q documentsui; then
      adb shell uiautomator dump /sdcard/wendelin_ui.xml >/dev/null 2>&1 || true
      local bounds
      bounds="$(adb shell cat /sdcard/wendelin_ui.xml 2>/dev/null |
        tr '>' '\n' | grep -iE 'text="(SAVE|Speichern)"' |
        grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1 || true)"
      if [ -n "$bounds" ]; then
        local n
        read -r -a n <<<"$(echo "$bounds" | tr -c '0-9' ' ')"
        adb shell input tap $(((n[0] + n[2]) / 2)) $(((n[1] + n[3]) / 2))
      fi
    fi
    sleep 1
  done
}
helper &
HELPER=$!
cleanup() {
  kill "$HELPER" 2>/dev/null || true
  if [ -n "$LIVE" ]; then
    adb shell run-as "$PKG" rm -f files/live_anthropic.key 2>/dev/null || true
  fi
  # Testdateien der Dateiauswahl und den uiautomator-Abzug entfernen.
  adb shell 'rm -f /sdcard/Download/wendelin-e2e-*.md /sdcard/wendelin_ui.xml' 2>/dev/null || true
}
trap cleanup EXIT

# 4. Tests
cd "$ROOT/app"
if [ $# -eq 0 ]; then set -- integration_test; fi
status=0
DEFINES=()
if [ -n "$LIVE" ]; then DEFINES=(--dart-define=WENDELIN_LIVE=true); fi
flutter test "$@" ${DEFINES[@]+"${DEFINES[@]}"} -d "$DEVICE" || status=$?
if [ -n "$LIVE" ] && installed; then
  adb shell pm clear "$PKG" >/dev/null || true
fi

left="$(adb shell "content query --uri content://com.android.calendar/events --projection _id --where \"title='Tauchen' AND deleted=0\"" | grep -c '_id=' || true)"
if [ "$left" != "0" ]; then
  echo "Fehler: $left Testtermin(e) „Tauchen“ im Gerätekalender übrig" >&2
  status=1
fi
exit $status
