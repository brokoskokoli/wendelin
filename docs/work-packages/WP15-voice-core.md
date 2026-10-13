# WP15 – Sprach-Kern (`packages/wendelin_voice`, reines Dart)

Abhängig von: wendelin_core (UserInput, CancelToken, Clock), wendelin_agent (SentenceChunker). Konzept-Bezug: „Sprach-Pipeline“ (Stufen 1–5), „Gesprächsmodus“ (nur Vorbereitung, aktiv ab M4), K7.

Neues Paket im Workspace; `tool/check_deps.dart` um `wendelin_voice -> core, agent` erweitern.

## Inhalt
- **Interfaces** (Plattform liefert Implementierungen in WP17):
  - `TriggerSource` (Stream von `TriggerEvent { source: pushToTalk|assistant|wakeWord|widget, at }`)
  - `AudioInput` (Stream<Int16List>-Frames 16 kHz Mono, start/stop)
  - `VoiceActivityDetector` (Frame → Sprachwahrscheinlichkeit bzw. speech/silence)
  - `SpeechToText` (`Future<Transcript> transcribe(Int16List pcm, {String? language})`, `Transcript { text, language, confidence }`), `SpeechToTextEngineInfo` (Name, Sprachen, Modell)
  - `TextToSpeech` (`speak(String, {voice, rate})`, `stop()`, Stream von Zuständen, `isAvailable`)
- **Endpointing** (reine Logik, tabellengetestet): Pre-Roll-Puffer 300 ms, Ende nach 800 ms Stille, maximal 30 s, Mindestsprechdauer (z. B. 250 ms, sonst „nichts verstanden“), alles konfigurierbar.
- **VoicePipeline** (Zustandsautomat): idle → listening → transcribing → thinking → speaking → idle; Abbruch jederzeit (Antippen, Abbruchwort „Stopp“ im Transkript); liefert `UserInput(source: voice, sttConfidence, language)` an einen `AgentRun`-Adapter; konsumiert `AgentEvent`s; TTS satzweise über `SentenceChunker`, `AgentTextReset` verwirft gepufferte, noch nicht gesprochene Sätze; ProviderBlocks/Thinking nie sprechen.
- **Sprechtext kürzen**: Antworten für TTS kürzen (z. B. max. 3 Sätze / 400 Zeichen, Markdown/URLs/Code entfernen, Listen zusammenfassen „und 4 weitere“); langer Rest nur auf dem Bildschirm.
- **TTS-Auswahl** (K7): `TtsSelector` wählt System-TTS, wenn verfügbar, sonst sherpa-Stimme; Einstellung überschreibt.
- **Modellkatalog + Download**: `SpeechModelCatalog` (Whisper `base`/`small` multilingual, Silero VAD, sherpa-TTS-Stimmen de/fr/en) mit URL, Größe, SHA-256; `ModelDownloader` über `http.Client` mit Fortschritt, Fortsetzen (Range), Prüfsumme, atomarem Umbenennen, Abbruch; Speicherort über Port (`ModelStore`). Keine Modelle im APK.
- **Gesprächsmodus-Vorbereitung**: Konfiguration „nach Antwort 5 s weiter zuhören“ im Automaten vorgesehen, standardmäßig aus (aktiv ab M4).

## Tests
- Endpointing-Tabellen (Stille/Sprache-Muster → Schnittpunkte), Pipeline-Szenarien mit Fakes (Fake-Audio, Fake-VAD, Fake-STT, Fake-TTS, FakeLlmProvider-basierter Agent), Abbruch in jedem Zustand, Reset-Verhalten, Kürzungstabellen (de/fr/en), Downloader mit MockClient (Fortsetzen, falsche Prüfsumme, Abbruch).
- Fakes + Contract-Suites wie üblich (`fakes.dart`, `testing.dart`).

## Abnahmekriterien
- [ ] Alle Interfaces dokumentiert, Fakes + Contract-Suites für STT, TTS, VAD, AudioInput.
- [ ] Pipeline-Szenarien inkl. Abbruch/Reset grün; keine Thinking/ProviderBlock-Inhalte in TTS.
- [ ] Downloader prüft SHA-256 und setzt fort.
- [ ] Gate grün, Abdeckung ≥ 85 %.
