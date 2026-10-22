# WP103 – Bessere Sprache einbauen: größere Modelle, ständig geladen, Rauschunterdrückung, Hinweis-Begriffe (`wendelin_voice`, `app/`)

**Zuordnung:** M5. Nach WP102 (Inhalt der Modell-Liste nach dessen Empfehlung).

Bezug: Wunsch Maintainer 2026-10-19 (K64); Ergebnis WP102 in `docs/notes/voice-quality-spike.md` (K66).

**Stand nach WP102 (K66, Wahl Maintainer offen, bis dahin gilt):** STT „groß“ = Parakeet TDT 0.6B v3 int8 mit Hotwords (bpe_vocab aus der .nemo), fr optional Canary-180m-flash; Whisper bleibt Standard (small). TTS wählbar Thorsten high (fp32) und Kokoro (en/fr). **Teil 4 (Rauschunterdrückung) entfällt.** Hinweis-Begriffe nur für Parakeet/Transducer. Lizenzhinweise (CC-BY-4.0) in der App. Modell-Liste so bauen, dass Maintainers Wahl nur Katalogeinträge ändert.

## Inhalt
1. **Größere STT-Modelle wählbar** nach WP102 (z. B. Parakeet, Whisper turbo), mit Größe, RAM-Bedarf und Hinweis in der Auswahl; Download wie bisher, nicht im APK.
2. **Bessere Stimmen wählbar** nach WP102 (z. B. Piper high, Kokoro für en/fr), mit Hörprobe in den Einstellungen.
3. **Modell im Speicher halten:** Einstellung, damit STT- und TTS-Modell nicht bei jeder Äußerung neu geladen werden; im Stationsmodus (WP99) standardmäßig an. Speicher freigeben bei Speicherdruck (`onTrimMemory`).
4. **Rauschunterdrückung** (GTCRN über sherpa-onnx) vor der Erkennung, abschaltbar.
5. **Eigene Begriffe als Hinweis:** Kontaktnamen, HA-Räume/-Entitäten, Listen- und Agentennamen gehen lokal als Hinweis an die Erkennung (Whisper-Prompt bzw. Hotwords, soweit das Modell es kann); nichts verlässt das Gerät.

## Umsetzung
- STT/TTS bleiben hinter den Ports `SpeechToText`/`TextToSpeech`; neue Engine als eigener Adapter.
- Debug-Ansicht zeigt Latenz, Echtzeitfaktor und RAM je Äußerung (für den Gerätetest).
- Parallel: berührt `app/lib/voice/*` und die Spracheinstellungen; nicht gleichzeitig mit Paketen am Voice-Controller (WP81b, WP93).

## Abnahmekriterien
- [ ] Tests: Modellwahl und Download je Engine, Speicher-halten an/aus und Freigabe bei Speicherdruck, Rauschunterdrückung an/aus, Hinweis-Begriffe enthalten keine Inhalte außer Namen (Mutationsbeleg).
- [ ] E2E (Emulator): großes Modell laden, Erkennung einer Testaufnahme, Stimme wechseln.
- [ ] Prüfpunkte für den Gerätetest (Latenz, Akku, Wärme) ergänzt. Gate grün.
