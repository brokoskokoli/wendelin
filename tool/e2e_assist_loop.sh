#!/usr/bin/env bash
# Schleife zum Befund B10 (WP30): Öffnet der Assistent nach Overlay-Nutzung,
# Schließen und App-Nutzung jedes Mal das Overlay?
#
#   DEVICE=emulator-5554 tool/e2e_assist_loop.sh [durchläufe=30] [pause_s=10]
#
# Je Durchlauf: KEYCODE_ASSIST (wie der lange Druck auf die Power-Taste;
# `cmd voiceinteraction show` verlangt ACCESS_VOICE_INTERACTION_SERVICE, das
# die Shell auf dem AOSP-Image nicht hat) → warten, bis die AssistantActivity oben ist → Zurück →
# App (MainActivity) in den Vordergrund → Home → Pause (Standard 10 s, der
# Gerätetest nennt 2 min: pause_s=120). Gezählt werden `wm_create_activity`
# der AssistantActivity im Event-Log gegen die Zahl der Aufrufe; dazu die
# Zeilen `Wendelin/voice` der Session (ohne Inhalte).
#
# Voraussetzung: Die App ist installiert (Debug- oder Release-APK). Das
# Skript setzt die Assistenten-Rolle und entzieht sie am Ende wieder. Läuft
# nur auf Emulatoren (Seriennummer emulator-*, ro.kernel.qemu=1).
set -euo pipefail

PKG=app.wendelin
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tool/android_device.sh
. "$ROOT/tool/android_device.sh"

RUNS="${1:-30}"
PAUSE="${2:-10}"

if ! is_emulator; then
  echo "Abbruch: $DEVICE ist kein Emulator. Die Schleife läuft nur auf Emulatoren." >&2
  exit 1
fi
if ! adb shell pm list packages "$PKG" | tr -d '\r' | grep -q "^package:$PKG\$"; then
  echo "Abbruch: $PKG ist nicht installiert" >&2
  exit 1
fi

had_role=""
if adb shell cmd role get-role-holders android.app.role.ASSISTANT | grep -q "$PKG"; then
  had_role=1
else
  adb shell cmd role add-role-holder --user 0 android.app.role.ASSISTANT "$PKG"
  sleep 3
fi
cleanup() {
  if [ -z "$had_role" ]; then
    adb shell cmd role remove-role-holder --user 0 android.app.role.ASSISTANT "$PKG" || true
  fi
}
trap cleanup EXIT

top() { adb shell dumpsys activity activities 2>/dev/null | grep -E 'topResumedActivity|mResumedActivity' || true; }
wait_for() { # <regex> <sekunden>; 0 wenn erschienen
  local end=$((SECONDS + $2))
  while [ $SECONDS -lt $end ]; do
    top | grep -qE "$1" && return 0
    sleep 0.3
  done
  return 1
}
wait_gone() { # <regex> <sekunden>
  local end=$((SECONDS + $2))
  while [ $SECONDS -lt $end ]; do
    adb shell dumpsys activity activities | grep -qE "$1" || return 0
    sleep 0.3
  done
  return 1
}

adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
adb logcat -G 16M >/dev/null 2>&1 || true
adb logcat -c
adb logcat -b events -c || true

shown=0
missing=0
for i in $(seq 1 "$RUNS"); do
  adb shell input keyevent KEYCODE_ASSIST
  shown=$((shown + 1))
  if wait_for 'AssistantActivity' 10; then
    status=ok
  else
    status=FEHLT
    missing=$((missing + 1))
  fi
  sleep 2
  adb shell input keyevent KEYCODE_BACK
  wait_gone 'app.wendelin/.AssistantActivity' 10 || true
  adb shell am start -n "$PKG/.MainActivity" >/dev/null
  wait_for 'MainActivity' 15 || true
  sleep 2
  adb shell input keyevent KEYCODE_HOME
  echo "Durchlauf $i/$RUNS: Overlay $status"
  [ "$i" -lt "$RUNS" ] && sleep "$PAUSE"
done

created="$(adb logcat -d -b events | grep -c 'wm_create_activity.*app.wendelin/.AssistantActivity' || true)"
arrived="$(adb logcat -d | grep -c 'Wendelin/voice.*session-finish reason=arrived' || true)"
echo "Ergebnis B10: ${shown} Aufrufe, ${created}× AssistantActivity erzeugt," \
  "${arrived}× Session nach Ankunft beendet, ${missing}× nicht oben"
echo "Session-Zeilen (Wendelin/voice, ohne Inhalte):"
adb logcat -d | grep 'Wendelin/voice' | grep -E 'session-|assistant-start|overlay-' |
  awk '{ $1=""; $2=""; print }' | sort | uniq -c | sort -rn | head -20
[ "$created" -ge "$shown" ] && [ "$missing" = 0 ]
