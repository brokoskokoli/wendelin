#!/usr/bin/env bash
# Sammelt die Diagnose-Zeilen nach einem Fehlversuch der Power-Taste (WP56).
# Anleitung für den Maintainer, nicht für Agenten: Handy per USB, Entwickleroptionen an.
#
#   tool/diag_assistant_idle.sh <Serial>    # Serial aus `adb devices`, Pflicht
#
# Achtung: `adb logcat -c` leert den Gerätelog (Puffer des Handys), nicht nur eine Kopie.
#
# Ablauf: 1. adb logcat -c (macht das Skript), 2. Power-Taste lang drücken (Fehlversuch),
# 3. Enter. Ausgabe: Wendelin/voice-Zeilen (ohne Inhalte), Prozessstand und Standby-Bucket.
# Fehlt `session-new`, hat Android die Sitzung nie an Wendelin übergeben (Dienst nicht
# gebunden, Herstellersperre). Fehlt `overlay-create`, ist die Activity nicht gestartet.
set -euo pipefail
ADB="${ADB:-adb}"
if [ -z "${1:-}" ]; then
  echo "Usage: tool/diag_assistant_idle.sh <Serial>   (Serial aus 'adb devices'; leert den Gerätelog per logcat -c)" >&2
  exit 1
fi
SERIAL="$1"
a() { "$ADB" -s "$SERIAL" "$@"; }
a logcat -c
echo "Jetzt die Power-Taste lang drücken, dann hier Enter."
read -r _
echo "--- Wendelin/voice"
a logcat -d | grep -E "Wendelin/voice|VoiceInteraction" | cut -c1-200 || true
echo "--- Activity-Start / Hintergrundstart (BAL)"
a logcat -d | grep -E "ActivityTaskManager.*app\.wendelin|BackgroundActivityStart|BAL" | cut -c1-200 || true
echo "--- Prozess beendet/gestartet"
a logcat -d | grep -E "ActivityManager.*(Killing|Start proc).*app\.wendelin" | cut -c1-200 || true
echo "--- Hersteller-Freezer (HyperOS)"
a logcat -d | grep -E "Greeze|ProcessManager" | cut -c1-200 || true
echo "--- Prozess"
a shell pidof app.wendelin || echo "kein Prozess"
echo "--- Standby-Bucket"
a shell am get-standby-bucket app.wendelin || true
echo "--- Dienst gebunden?"
a shell dumpsys voiceinteraction | grep -E "mComponent|mBound" || true
