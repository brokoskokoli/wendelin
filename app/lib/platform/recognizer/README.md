# System-Spracherkennung (WP20)

Wendelin als `RecognitionService` für andere Apps: Whisper und Silero VAD
lokal, Endpointing wie die Sprach-Pipeline. Entscheidung und Begründung:
`docs/adr/0008-system-recognizer.md`.

| Datei | Aufgabe |
|---|---|
| `recognizer_host.dart` | Kanal `app.wendelin/recognizer`: je Anfrage eine `RecognitionSession` (wendelin_voice), Ereignisse zurück an Kotlin; `ChannelAudioInput` nimmt die Audio-Blöcke des Dienstes an |
| `device_recognizer_engines.dart` | Modelle der Erkenner-Engine: Whisper der App mitnutzen oder selbst laden (30 s nach der letzten Anfrage freigeben), Silero je Anfrage; `runRecognizerEngine` (Einstieg `recognizerMain` in `main.dart`) |
| `../../voice/recognizer_config.dart` | Spiegelt die Spracheinstellungen an den Dienst; Einstellung „Als Spracherkennung für andere Apps anbieten“ |

**Kotlin** (`android/app/src/main/kotlin/app/wendelin/`):
`WendelinRecognitionService` (Bindung, Berechtigung, Callbacks,
Fehlercodes), `RecognizerEngine` (Headless-Flutter-Engine),
`RecognizerAudio` (Mikrofon mit Attribution des Aufrufers, WAV-Testquelle
nur in debuggable Builds), `RecognizerSwitch` (aktiv nur mit
Assistenten-Rolle und Einstellung; gespiegelte Einstellungen).

**Berechtigungen:** `RECORD_AUDIO` (vorhanden). Der Aufrufer braucht sie
ebenfalls (prüft Android).

**Datenschutz:** Audio bleibt im Speicher, wird nicht gespeichert, nicht
geloggt und nicht an Clients weitergegeben (`onBufferReceived` wird nicht
gesendet). Im Log stehen nur Fehlercodes und die Textlänge.

**Emulator-Test:** `WENDELIN_MODELS=<dir> tool/e2e_recognizer.sh`
(Instrumentationstest `RecognitionServiceTest`).
