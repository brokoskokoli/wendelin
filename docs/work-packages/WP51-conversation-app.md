# WP51 – Gesprächsmodus und Barge-in in der App (`app/lib/voice/`, Overlay, Audioquelle)

Abhängig von: WP45 (Pipeline), WP50 (KWS-Engine in der App), WP42 (AEC-Ergebnis). Andockpunkte: `VoiceController` (`app/lib/voice/voice_controller.dart`), `app/lib/platform/voice/record_audio_input.dart` (heute `AndroidAudioSource.voiceRecognition`), `app/lib/di/voice_providers.dart`, Overlay `app/lib/ui/overlay/`, Zuhör-Leiste/Mikrofon-Zustände (WP31, K18 b), Einstellungen Sprache. Legt ADR 0015 an.

## Inhalt
- Gesprächsmodus aktivieren (`VoicePipelineConfig.conversationMode`) für Sprach-Anfragen im Hauptbildschirm und im Overlay. Anzeige des Folgefensters in der Zuhör-Leiste (Restzeit, „Ich höre noch zu …“, gesprochen wird nichts). Einstellung „Weiter zuhören nach der Antwort“ (Standard nach Antwort des Maintainers).
- Barge-in: `KwsBargeInDetector implements BargeInDetector` mit der Wake-Word-Engine (Schlüsselwörter `wake`, `stop`, strengere Schwelle). Während der Sprachausgabe läuft die Aufnahme mit `VOICE_COMMUNICATION` und `AcousticEchoCanceler` (wenn verfügbar, über einen kleinen Kotlin-Kanal oder die `record`-Option), danach wieder `VOICE_RECOGNITION`. Die TTS-Ausgabe läuft je nach WP42 über `USAGE_ASSISTANT` oder `USAGE_VOICE_COMMUNICATION`. Ohne AEC gilt nur „Stopp“ mit noch strengerer Schwelle.
- Einstellung Barge-in: aus / Schlüsselwörter (Standard) / beliebige Sprache (experimentell, nur wenn AEC verfügbar).
- Lebenszyklus: ADR 0007 §12 gilt weiter (kein Zuhören im Hintergrund außer dem Wake-Word-Dienst). Das Folgefenster endet bei `paused`/`hidden`.

## Abnahmekriterien
- [ ] Provider-/Widget-Tests mit Fakes: Folgefrage im Fenster ohne Tipp. Fenster abgelaufen → Mikrofon aus. Barge-in-Signal stoppt TTS und hört zu bzw. beendet.
- [ ] Wechsel der Audioquelle nur während der Sprachausgabe (Test mit Fake-Audio, das die Quelle protokolliert). AEC wird angelegt und freigegeben (Kanal-Test).
- [ ] Emulator (`Wendelin_AOSP_35`): eingespeiste Folge „Frage 1“ → Antwort → „Frage 2“ innerhalb von 5 s ergibt zwei Anfragen im selben Gespräch. Mit „Stopp“ während der Ausgabe stoppt sie (WAV mit Stopp während des Sprechens).
- [ ] WER mit `VOICE_COMMUNICATION` gegen `VOICE_RECOGNITION` auf dem Emulator gemessen (`tool/stt_measure.sh`). Whisper bekommt keine schlechtere Quelle für die eigentliche Anfrage.
- [ ] Golden der Zuhör-Leiste im Folgefenster. Gate grün, ADR 0015 angelegt.

## Prüfliste für den Maintainer (echtes Telefon)
- [ ] Laut gestellte Sprachausgabe, „Stopp“ sagen → Ausgabe endet. 10×, Selbstauslösungen ohne Sprechen zählen (Ziel 0).
- [ ] „Wendelin“ während der Ausgabe → Ausgabe endet, neue Frage wird verstanden.
- [ ] Gesprächsmodus: drei Folgefragen ohne Tipp. „Danke“ beendet.
- [ ] Mit Bluetooth-Kopfhörer: Barge-in und Folgefenster funktionieren, Audio bleibt auf dem Kopfhörer.
