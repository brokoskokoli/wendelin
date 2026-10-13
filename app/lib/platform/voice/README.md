# Sprach-Plattform (WP17)

Plattform-Implementierungen der Ports aus `wendelin_voice`. Verdrahtet in
`lib/di/voice_providers.dart`, Oberfläche in `lib/ui/settings/voice_screen.dart`
und `lib/ui/onboarding/voice_download_step.dart`.

| Datei | Port / Aufgabe | Technik |
|---|---|---|
| `record_audio_input.dart` | `AudioInput` (16 kHz, mono, PCM16) | `record` (Android `AudioRecord`, Quelle `VOICE_RECOGNITION`) |
| `silero_vad.dart` | `VoiceActivityDetector` | sherpa-onnx Silero VAD (FFI); Wahrscheinlichkeit binär, siehe Doc-Kommentar |
| `whisper_stt.dart`, `whisper_sherpa.dart` | `SpeechToText` | Whisper base/small (int8) über sherpa-onnx in einem Hintergrund-Isolat; Stille-Sperre, Halluzinations-Filter, heuristische Konfidenz |
| `system_tts.dart` | `TextToSpeech` (System) | `flutter_tts`; nur Offline-Stimmen, `isAvailable` = TTS-Engine installiert |
| `sherpa_tts.dart`, `audio_playback.dart` | `TextToSpeech` (Fallback, K7) | Piper/VITS über sherpa-onnx im Isolat, Wiedergabe mit `audioplayers` |
| `file_model_store.dart` | `ModelStore` | Dateisystem, `<id>/<datei>.part` + atomares Umbenennen |
| `model_installer.dart` | Download-Ablauf | Speicherplatzprüfung, `ModelDownloader`, sicheres Entpacken, Archiv erst danach löschen |
| `tar_bz2.dart` | `.tar.bz2` entpacken | bzip2 mit Größenlimit, eigener Tar-Leser: nur relative Pfade ohne `..`, keine Links/Geräte, temporäres Verzeichnis + Umbenennen |
| `disk_space.dart` | freier Speicher | libc `statvfs` per FFI (64-bit Android, macOS); sonst unbekannt |
| `pcm.dart`, `wer.dart` | Hilfen | PCM/WAV, Wortfehlerrate für `tool/stt_wer.dart` |

**Berechtigungen:** `RECORD_AUDIO`, erst beim ersten Sprechen bzw. in
Einstellungen → Sprache nach einer Erklärung (`ensureMicrophoneAccess`).
`<queries>` für `TTS_SERVICE`, damit Android 11+ die TTS-Engines zeigt.

**Ohne Google-Dienste (K7):** `sherpa_onnx`, `record`, `flutter_tts`,
`audioplayers`, `archive` bringen keine GMS-Abhängigkeit mit. Fehlt eine
System-Sprachausgabe, spricht Wendelin mit der Offline-Stimme.

**Modelle** kommen nie ins APK: Download beim Onboarding oder in den
Einstellungen nach `<App-Support>/models`. Ein beschädigtes Modell würde
sherpa-onnx mit einem nativen `exit` beenden; Schutz ist die
SHA-256-Prüfung jedes Downloads.

**Messen:** `tool/stt_wer.dart` (WER) und `tool/vad_calibrate.dart`
(Schwelle, Mindestsprechdauer), Fixtures aus `tool/make_stt_fixtures.sh`.
Desktop-FFI-Tests: `WENDELIN_MODELS=<dir> flutter test test/platform/voice/sherpa_ffi_test.dart`.
