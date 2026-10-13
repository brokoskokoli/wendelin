#!/bin/sh
# Misst die Spracherkennung lokal auf macOS (sherpa-onnx-Desktop-Bindings):
# Wortfehlerrate von Whisper base/small und Kalibrierung von Silero VAD auf
# den Fixtures in app/test/fixtures/stt.
#
#   tool/stt_measure.sh <modell-verzeichnis>
#
# Das Verzeichnis enthält je Katalog-Id einen Ordner mit den Modelldateien
# (whisper-base/, whisper-small/, silero-vad/), z. B. aus der App kopiert
# oder mit den URLs aus SpeechModelCatalog geladen. Modelle nie einchecken.
# Ergebnis: Markdown-Tabellen auf stdout (für docs/notes/stt-wer-<datum>.md).
set -eu
models="${1:?Modell-Verzeichnis fehlt}"
cd "$(dirname "$0")/../app"
echo "## Wortfehlerrate"
echo
dart run tool/stt_wer.dart --models "$models"
echo
echo "## Silero VAD"
echo
dart run tool/vad_calibrate.dart --vad "$models/silero-vad/silero_vad.onnx"
