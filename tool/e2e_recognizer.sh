#!/usr/bin/env bash
# Emulator-Test der System-Spracherkennung (WP20, ADR 0008).
#
#   WENDELIN_MODELS=<dir> tool/e2e_recognizer.sh
#
# Erwartet ein laufendes Gerät (adb), z. B. das AVD Wendelin_AOSP_35:
#   ~/Library/Android/sdk/emulator/emulator -avd Wendelin_AOSP_35 \
#     -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect &
#
# Das Skript
#   1. baut die Debug-App und das Test-APK (Instrumentationstest
#      app/android/app/src/androidTest/…/RecognitionServiceTest.kt, die
#      STT-Fixtures liegen nur im Test-APK),
#   2. installiert beide neu, die App OHNE Mikrofon-Berechtigung (der erste
#      Test prüft diesen Fehlerpfad und erteilt sie dann),
#   3. kopiert Whisper base und Silero VAD aus $WENDELIN_MODELS
#      (<dir>/whisper-base/*, <dir>/silero-vad/silero_vad.onnx) per run-as in
#      die App-Daten (files/models/<id>/),
#   4. führt den Test aus: SpeechRecognizer → WendelinRecognitionService mit
#      WAV statt Mikrofon (nur in debuggable Builds möglich),
#   5. deinstalliert danach App und Test-APK und löscht die Modell-Kopie in
#      /data/local/tmp.
#
# Nur Emulatoren (Seriennummer emulator-*, ro.kernel.qemu=1): der Test setzt
# die Assistenten-Rolle und deinstalliert die App.
set -euo pipefail

PKG=app.wendelin
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS="${WENDELIN_MODELS:?WENDELIN_MODELS=<Verzeichnis mit whisper-base/ und silero-vad/> setzen}"
# DEVICE bzw. ANDROID_SERIAL; ohne beides genau ein Gerät, sonst Abbruch.
# shellcheck source=tool/android_device.sh
. "$ROOT/tool/android_device.sh"

is_emulator || { echo "Abbruch: $DEVICE ist kein Emulator" >&2; exit 1; }
[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ] ||
  { echo "Gerät $DEVICE ist noch nicht hochgefahren" >&2; exit 1; }
for f in whisper-base/base-encoder.int8.onnx whisper-base/base-decoder.int8.onnx \
  whisper-base/base-tokens.txt silero-vad/silero_vad.onnx; do
  [ -f "$MODELS/$f" ] || { echo "Modell fehlt: $MODELS/$f" >&2; exit 1; }
done

# 1. Bauen
(cd "$ROOT/app" && flutter build apk --debug)
(cd "$ROOT/app/android" && ./gradlew -q app:assembleDebugAndroidTest)
APK="$ROOT/app/build/app/outputs/flutter-apk/app-debug.apk"
TEST_APK="$ROOT/app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk"

TMP=/data/local/tmp/wendelin-models
cleanup() {
  adb uninstall "$PKG.test" >/dev/null 2>&1 || true
  adb uninstall "$PKG" >/dev/null 2>&1 || true
  adb shell rm -rf "$TMP" || true
}
trap cleanup EXIT

# 2. Installieren (ohne -g: keine Laufzeit-Berechtigungen)
adb uninstall "$PKG.test" >/dev/null 2>&1 || true
adb uninstall "$PKG" >/dev/null 2>&1 || true
adb install "$APK"
adb install "$TEST_APK"

# 3. Modelle in die App-Daten
copy_model() { # <id> <datei…>
  local id="$1"
  shift
  adb shell mkdir -p "$TMP/$id"
  adb shell run-as "$PKG" mkdir -p "files/models/$id"
  for f in "$@"; do
    adb push "$MODELS/$id/$f" "$TMP/$id/$f" >/dev/null
    adb shell "cat $TMP/$id/$f | run-as $PKG sh -c 'cat > files/models/$id/$f'"
  done
}
copy_model whisper-base base-encoder.int8.onnx base-decoder.int8.onnx base-tokens.txt
copy_model silero-vad silero_vad.onnx
adb shell rm -rf "$TMP"

# 4. Test
OUT="$(adb shell am instrument -w -r -e class "$PKG.RecognitionServiceTest" \
  "$PKG.test/androidx.test.runner.AndroidJUnitRunner" | tr -d '\r')"
echo "$OUT" | grep -E 'INSTRUMENTATION_STATUS: (test|stack)=|^OK|FAILURES|Tests run|INSTRUMENTATION_FAILED' || true
echo "$OUT" | grep -q '^OK (' || { echo "$OUT" | tail -40; echo "Erkenner-Test fehlgeschlagen" >&2; exit 1; }
echo "Erkenner-Test bestanden"
