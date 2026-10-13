# WP45 – Gesprächsmodus und Barge-in in der Pipeline (`packages/wendelin_voice/lib/src/pipeline/`)

Abhängig von: – (sofort startbar). Andockpunkte: `VoicePipeline` und `VoicePipelineConfig.conversationMode`/`followUpWindow` (`packages/wendelin_voice/lib/src/pipeline/voice_pipeline.dart`, dort schon vorbereitet), `Endpointer`, `SpeechQueue` (`src/tts/speech_queue.dart`), `VoiceEvent`/`VoiceState` (`src/pipeline/voice_events.dart`), Stopp-Erkennung in `src/text/voice_texts.dart` (K11 d). Bezug: K14 h, K11 c/d, Konzept „Gesprächsmodus“ und „Barge-in“.

## Inhalt
- **Gesprächsmodus**: Nach dem Ende der Sprachausgabe wird `followUpWindow` (5 s) lang weiter zugehört. Spricht der Nutzer, beginnt eine neue Anfrage im selben Gespräch (kein Wake Word). Endebedingungen mit Grundcode: Stille im Fenster, „Stopp“/Abbruchphrase (vorhandene Regel), Abschlussphrase („Danke“, „Das war’s“, „Merci“, „Thanks“, nur wenn die Äußerung ausschließlich daraus besteht), Tipp, `cancel()`, offene Bestätigungskarte (dann übernimmt die Ja/Nein-Logik), Höchstzahl an Folgerunden (Vorschlag 5) und Fehler. Der Modus gilt nur für Sprach-Anfragen.
- **Barge-in**: neuer Port `BargeInDetector` (Strom von `BargeInSignal` mit Art `keyword(stop|wake)` bzw. `speech`). Während `VoiceState.speaking` stoppt ein Signal die `SpeechQueue` sofort. Bei `keyword(stop)` endet die Anfrage. Bei `keyword(wake)` bzw. `speech` beginnt das Zuhören für eine neue Äußerung, mit Pre-Roll aus dem Signal, falls vorhanden. Die Pipeline weiß nichts von AEC und Audioquelle, das ist Sache der App (WP51).
- Neue Zustände bzw. Ereignisse für die UI: `followUpListening` (Fenster läuft, mit Restzeit) und `VoiceEvent.bargeIn`. Diagnose `conv-exit reason=…`, `barge-in kind=…` ohne Inhalte.
- Konfiguration: `conversationMode`, `followUpWindow`, `maxFollowUps`, `bargeIn` (`off|keywords|speech`).

## Abnahmekriterien
- [ ] Tabellentest der Endebedingungen (Stille, Stopp, Danke, Tipp, Bestätigungskarte, Höchstzahl, Fehler) mit Fake-Uhr. Jede endet mit genau einem Grundcode.
- [ ] Folgefrage innerhalb des Fensters landet als neue Anfrage im selben Gespräch. Nach dem Fenster wird nicht mehr zugehört (`FakeAudioInput.isRunning == false`).
- [ ] Barge-in: Signal während der Ausgabe stoppt die Queue in ≤ 1 Frame (Test mit `FakeTextToSpeech`). Ein Stopp-Signal beendet die Anfrage, ein Wake-Signal hört neu zu. Signale außerhalb von `speaking` werden ignoriert.
- [ ] Bestehende Pipeline-Tests unverändert grün (Modus aus = altes Verhalten).
- [ ] Contract/Fake für `BargeInDetector` in `fakes.dart`/`testing.dart`.
- [ ] Gate grün.
