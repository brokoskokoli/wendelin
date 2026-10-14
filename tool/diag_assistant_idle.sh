#!/usr/bin/env bash
# Sammelt die Diagnose-Zeilen nach einem Fehlversuch der Power-Taste (WP56).
# Anleitung für den Maintainer, nicht für Agenten: Handy per USB, Entwickleroptionen an.
#
#   tool/diag_assistant_idle.sh [Serial]    # Serial nur bei mehreren Geräten
#
# Ablauf: 1. adb logcat -c (macht das Skript), 2. Power-Taste lang drücken (Fehlversuch),
# 3. Enter. Ausgabe: Wendelin/voice-Zeilen (ohne Inhalte), Prozessstand und Standby-Bucket.
# Fehlt `session-new`, hat Android die Sitzung nie an Wendelin übergeben (Dienst nicht
# gebunden, Herstellersperre). Fehlt `overlay-create`, ist die Activity nicht gestartet.
set -euo pipefail
ADB="${ADB:-adb}"
S=()
[ -n "${1:-}" ] && S=(-s "$1")
a() { "$ADB" "${S[@]}" "$@"; }
a logcat -c
echo "Jetzt die Power-Taste lang drücken, dann hier Enter."
read -r _
echo "--- Wendelin/voice"
a logcat -d | grep -E "Wendelin/voice|VoiceInteraction" | cut -c1-200 || true
echo "--- Prozess"
a shell pidof app.wendelin || echo "kein Prozess"
echo "--- Standby-Bucket"
a shell am get-standby-bucket app.wendelin || true
echo "--- Dienst gebunden?"
a shell dumpsys voiceinteraction | grep -E "mComponent|mBound" || true
