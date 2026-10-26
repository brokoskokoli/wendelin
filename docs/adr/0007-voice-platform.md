# ADR 0007 – Sprach-Plattform Android (`app/lib/platform/voice/`)

Status: angenommen (umgesetzt, nachgezogen 2026-10-25) · 2026-10-13

## Kontext
WP17 setzt die Ports aus `wendelin_voice` (WP15) auf dem Gerät um: Mikrofon, Silero VAD, Whisper, System-TTS mit Offline-Fallback (K7), Modell-Download. Konzept und WP15 lassen offen, mit welchen Plugins, auf welchem Isolat und wie Archive, Speicherplatz und Einstellungen behandelt werden.

## Entscheidungen

### 1. Plugins
`sherpa_onnx` (FFI, VAD/Whisper/Piper), `record` (PCM-Stream, `AudioRecord`), `flutter_tts` (System-TTS), `audioplayers` (Wiedergabe der Offline-Stimme aus dem Speicher), `archive` (nur bzip2). Alle ohne Google Play Services; geprüft mit `tool/check_deps.dart` und einer dex-Suche im APK. Kein eigener Kotlin-Code, damit WP18 (Assistent, Overlay) die Android-Seite allein besitzt.

### 2. Whisper und Piper in Hintergrund-Isolaten
Eine Transkription dauert auf dem Telefon Sekunden und blockiert als FFI-Aufruf. Whisper und die Offline-Stimme laufen deshalb je in einem langlebigen Isolat (Modell bleibt geladen, Aufträge nacheinander). Silero VAD läuft auf dem aufrufenden Isolat (ein Fenster < 1 ms).

### 3. VAD-Wahrscheinlichkeit binär
Die C-API von sherpa-onnx liefert keine Wahrscheinlichkeit pro Fenster, nur „Sprache offen“. `speechProbability` ist deshalb 0 oder 1; die einstellbare Schwelle geht direkt an Silero. Silero bekommt eine minimale Mindestsprechdauer (ein Fenster) und 100 ms Nachlauf, Mindestsprechdauer und Endstille entscheidet der `Endpointer`.

### 4. Whisper-Ausgabe absichern
Stille (RMS < −54 dBFS) geht nicht ins Modell; Geräusch-Annotationen (`[Music]`, `(Lachen)`) und bekannte Untertitel-Halluzinationen werden entfernt. Die Konfidenz ist heuristisch (Textrate, Wiederholungen, Sprache außerhalb de/fr/en), weil sherpa-onnx für Whisper keine Token-Wahrscheinlichkeiten liefert.

### 5. Standardsprache = App-Sprache
Die Einstellung „Gesprochene Sprache“ steht anfangs auf „Wie die App“ (feste Sprache aus dem Onboarding). Automatische Erkennung bleibt wählbar. Grund: Auf den Fixtures halbiert die feste Sprache die WER für Deutsch (Whisper small 21 % → 9 %), und kurze Antworten („Ja“) werden automatisch oft als Englisch erkannt (`docs/notes/stt-wer-2026-10-13.md`).

### 6. Modelle, Archive, Speicherplatz
`FileModelStore` unter `<App-Support>/models/<id>/`, Teil-Downloads als `.part`. `ModelInstaller` prüft vorher den freien Platz (libc `statvfs` per FFI, Download + 3 × Archiv + 50 MB), lädt mit `ModelDownloader`, entpackt `.tar.bz2` mit eigenem Tar-Leser (nur Dateien/Ordner, relative Pfade ohne `..`, bzip2 mit Größenlimit) in ein temporäres Verzeichnis und benennt es um; erst danach wird das Archiv gelöscht. Ein angefangener Download wird beim Öffnen des Onboarding-Schritts fortgesetzt und ist in den Einstellungen als „Fortsetzen“ sichtbar.

### 7. Einstellungen als eigener Schlüssel
`voice.settings` (JSON) mit eigenem `AsyncNotifier` in `lib/di/voice_settings_providers.dart` (Modell `VoiceSettings` in `wendelin_voice`) statt eines Felds in `StartupSettings`: Die Werte werden erst gebraucht, wenn gesprochen wird, und die Datei bleibt getrennt von den Einstellungen anderer Pakete. Ungültige Werte fallen einzeln auf den Standard zurück.

### 8. Mikrofon nur nach Erklärung
`RecordAudioInput.start` fragt nie selbst; ohne Berechtigung kommt `VoiceException(permissionDenied)`. Die App ruft vorher `ensureMicrophoneAccess` (Erklärung, dann Android-Dialog), beim ersten Sprechen (WP18) oder in Einstellungen → Sprache.

### 9. Nur Offline-Systemstimmen
`SystemTextToSpeech.voices` blendet Stimmen mit `network_required` aus, damit Antworttext ohne ausdrückliche Wahl eines Cloud-Dienstes das Gerät nicht verlässt. Das gilt auch ohne gewählte Stimme: `speak` setzt immer ausdrücklich eine Offline-Stimme der Antwortsprache per `setVoice` (nie den Engine-Standard, der eine Netzstimme sein kann). Gibt es keine, wirft `speak` `VoiceException(unavailable)`, und die System-TTS meldet sich ohne Offline-Stimme als nicht verfügbar bzw. für diese Sprache unpassend, sodass `TtsSelector` die sherpa-Stimme nimmt.

### 10. Modelldateien vor dem Laden prüfen
Ein abgeschnittenes Modell würde sherpa-onnx (nativer `exit`) mitsamt App beenden. `ModelInstaller.isInstalled` und `IsolateWhisperBackend.start` prüfen deshalb vor jedem Laden die Dateigröße gegen `ModelFile.sizeBytes`; eine falsche Größe gilt als `modelMissing`, die Datei wird beim nächsten Laden verworfen und neu heruntergeladen.

### 11. Isolate sauber beenden
`dispose` der Whisper- und TTS-Isolate schickt den Stopp-Auftrag, wartet auf das `onExit` des Isolats (das vorher die nativen Modelle freigibt) und tötet es nur nach einer Frist (5 s) als Sicherheitsnetz (`WorkerIsolate`).

### 12. Pflicht für WP18: Stopp bei App im Hintergrund
Die Bausteine halten das Mikrofon nicht selbst an. Wer die `VoicePipeline` betreibt (WP18: Hauptbildschirm, Overlay, Assistent), muss bei `AppLifecycleState.paused`/`hidden` (bzw. Ende der Assistenten-Sitzung) `VoicePipeline.cancel()` aufrufen, damit `AudioInput.stop()` das Mikrofon freigibt und keine Aufnahme im Hintergrund weiterläuft (Konzept: kein Dauerzuhören außer Wake Word im Foreground Service, M4). Die laufende Sprachausgabe endet dabei ebenfalls. Nach `resumed` wird nicht automatisch weiter zugehört.

## Folgen
- Ein beschädigtes Modell gleicher Größe beendet den Prozess (nativer `exit` in sherpa-onnx); Schutz sind SHA-256 beim Download und die Größenprüfung vor dem Laden. Ein Test mit kaputtem Inhalt ist nicht möglich.
- Die Pipeline mit Agent und Auslösern baut WP18 aus `voiceComponentsProvider`.
- Laufzeiten: Auf dem Emulator gemessen (WP19, `docs/notes/m2-e2e-2026-10-13.md`), auf dem Telefon misst der Maintainer mit `tool/whisper_timing.sh` (`docs/testing/m2-device.md`). `WhisperSpeechToText` meldet dazu jede Laufzeit ohne Inhalt (`WhisperTiming`, Log „Whisper-Zeit …“). Echte Aufnahmen fehlen weiter.
