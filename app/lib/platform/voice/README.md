# Sprach-Plattform (WP17)

Plattform-Implementierungen der Ports aus `wendelin_voice`. Verdrahtet in
`lib/di/voice_providers.dart`, Oberfläche in `lib/ui/settings/voice_screen.dart`
und `lib/ui/onboarding/voice_download_step.dart`.

| Datei | Port / Aufgabe | Technik |
|---|---|---|
| `record_audio_input.dart` | `AudioInput` (16 kHz, mono, PCM16) | `record` (Android `AudioRecord`, Quelle `VOICE_RECOGNITION`) |
| `silero_vad.dart` | `VoiceActivityDetector` | sherpa-onnx Silero VAD (FFI); Wahrscheinlichkeit binär, siehe Doc-Kommentar |
| `whisper_stt.dart`, `whisper_sherpa.dart` | `SpeechToText` | Whisper base/small (int8) über sherpa-onnx in einem Hintergrund-Isolat; Stille-Sperre, Halluzinations-Filter, heuristische Konfidenz |
| `system_tts.dart` | `TextToSpeech` (System) | `flutter_tts`; setzt immer ausdrücklich eine Offline-Stimme, `isAvailable` = Engine mit Offline-Stimme installiert |
| `sherpa_tts.dart`, `audio_playback.dart` | `TextToSpeech` (Fallback, K7) | Piper/VITS über sherpa-onnx im Isolat, Wiedergabe mit `audioplayers` |
| `file_model_store.dart` | `ModelStore` | Dateisystem, `<id>/<datei>.part` + atomares Umbenennen |
| `model_installer.dart` | Download-Ablauf | Speicherplatzprüfung, `ModelDownloader`, sicheres Entpacken, Archiv erst danach löschen |
| `tar_bz2.dart` | `.tar.bz2` entpacken | bzip2 mit Größenlimit, eigener Tar-Leser: nur relative Pfade ohne `..`, keine Links/Geräte, temporäres Verzeichnis + Umbenennen; Schreibfehler verwerfen das Archiv |
| `whisper_share.dart`, `whisper_registry.dart` | Whisper zwischen Engines teilen (ADR 0008) | Das Whisper-Isolat der App beantwortet auch Anfragen der Erkenner-Engine; Port prozessweit im `IsolateNameServer` |
| `isolate_exit.dart` | Isolate beenden | auf `onExit` warten, `kill` nur nach 5 s |
| `disk_space.dart` | freier Speicher | libc `statvfs` per FFI (64-bit Android, macOS); sonst unbekannt |
| `pcm.dart`, `wer.dart` | Hilfen | PCM/WAV, Wortfehlerrate für `tool/stt_wer.dart` |
| `wav_audio_input.dart` | `AudioInput` aus einer WAV (nur Gerätetests, WP19) | spielt die Aufnahme in Echtzeit, danach Stille; das Overlay bekommt ihn in Debug-Builds über `lib/debug/device_test_overrides.dart` |

**Berechtigungen:** `RECORD_AUDIO`, erst beim ersten Sprechen (sobald die
Modelle da sind) bzw. in Einstellungen → Sprache nach einer Erklärung
(`ensureMicrophoneAccess`).
`<queries>` für `TTS_SERVICE`, damit Android 11+ die TTS-Engines zeigt.

**Ohne Google-Dienste (K7):** `sherpa_onnx`, `record`, `flutter_tts`,
`audioplayers`, `archive` bringen keine GMS-Abhängigkeit mit. Fehlt eine
System-Sprachausgabe, spricht Wendelin mit der Offline-Stimme.

**Speicherbedarf beim Entpacken:** Archiv und entpacktes Tar liegen ganz im
Arbeitsspeicher (im Hintergrund-Isolat): bei einer Piper-Stimme 21 MB +
37 MB, also rund 60 MB Spitze. Auf dem Datenträger prüft `ModelInstaller`
vorher Download + 3 × Archiv + 50 MB Puffer.

**Modelle** kommen nie ins APK: Download beim Onboarding oder in den
Einstellungen nach `<App-Support>/models`. Ein beschädigtes Modell würde
sherpa-onnx mit einem nativen `exit` beenden; Schutz sind die
SHA-256-Prüfung jedes Downloads und die Größenprüfung vor jedem Laden.

**Pflicht für den Betreiber der Pipeline (WP18):** Bei App im Hintergrund
`VoicePipeline.cancel()` aufrufen (ADR 0007 §12), damit das Mikrofon
freigegeben wird.

**Laufzeit:** Jede Whisper-Erkennung meldet ihre Dauer ohne Inhalt (`WhisperTiming`, logcat „Whisper-Zeit …“, beim System-Erkenner „Erkenner: Whisper-Zeit …“). `tool/whisper_timing.sh` wertet das auf dem Telefon aus, Emulator-Werte in `docs/notes/m2-e2e-2026-10-13.md`.

**Messen:** `tool/stt_wer.dart` (WER) und `tool/vad_calibrate.dart`
(Schwelle, Mindestsprechdauer), Fixtures aus `tool/make_stt_fixtures.sh`.
Desktop-FFI-Tests: `WENDELIN_MODELS=<dir> flutter test test/platform/voice/sherpa_ffi_test.dart`.
