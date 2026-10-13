#!/usr/bin/env bash
# Laufzeit von Whisper auf dem eigenen Telefon messen (WP19).
#
#   tool/whisper_timing.sh --clear   # logcat leeren, dann in Wendelin sprechen
#   tool/whisper_timing.sh           # Auswertung der seither erkannten Sätze
#
# Wendelin schreibt nach jeder Erkennung eine Zeile ohne Inhalt ins Log
# (auch in Release-Builds):
#   Whisper-Zeit whisper-small de: Audio 4200 ms, Rechenzeit 1650 ms, RTF 0.39
# „Audio“ ist die Länge der Aufnahme (mit 300 ms Vorlauf und 800 ms
# Endstille), „Rechenzeit“ die Zeit von der Übergabe an Whisper bis zum Text.
# Zeilen mit „Erkenner:“ stammen von der System-Spracherkennung (andere Apps).
#
# Das Skript liest nur logcat, es ändert nichts auf dem Gerät; echte Geräte
# sind deshalb erlaubt. Gerät: DEVICE bzw. ANDROID_SERIAL, sonst das einzige
# verbundene. Anleitung: docs/testing/m2-device.md, Abschnitt Laufzeit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tool/android_device.sh
. "$ROOT/tool/android_device.sh"

if [ "${1:-}" = "--clear" ]; then
  adb logcat -c
  echo "logcat geleert. Jetzt in Wendelin sprechen (Modell und Sprache in"
  echo "Einstellungen → Sprache), danach: tool/whisper_timing.sh"
  exit 0
fi

lines="$(adb logcat -d -s flutter:I | grep -E 'Whisper-Zeit ' || true)"
if [ -z "$lines" ]; then
  echo "Keine Messwerte im Log. Erst tool/whisper_timing.sh --clear, dann sprechen." >&2
  exit 1
fi

echo "$lines" | awk '
  {
    at = index($0, "Whisper-Zeit ")
    src = (substr($0, at - 10, 10) == "Erkenner: ") ? "Erkenner" : "App"
    # whisper-small de: Audio 4200 ms, Rechenzeit 1650 ms, RTF 0.39
    split(substr($0, at + 13), f, " ")
    model = f[1]; lang = f[2]; sub(/:$/, "", lang)
    audio = f[4]; compute = f[7]
    key = src " " model " " lang
    n[key]++; a[key] += audio; c[key] += compute
    if (compute > mx[key]) mx[key] = compute
  }
  END {
    printf "%-9s %-14s %-5s %5s %10s %13s %10s %6s\n", "Quelle", "Modell", "Spr.", "Sätze", "Ø Audio", "Ø Rechenzeit", "max", "RTF"
    for (k in n) {
      split(k, p, " ")
      printf "%-9s %-14s %-5s %5d %7d ms %10d ms %7d ms %6.2f\n", p[1], p[2], p[3], n[k], a[k] / n[k], c[k] / n[k], mx[k], c[k] / a[k]
    }
  }'
