# WP102 – Spike: bessere Spracherkennung und Sprachausgabe messen (`app/`, `tool/`, Notiz)

**Zuordnung:** M5.

Bezug: Wunsch Maintainer 2026-10-19 (K64): größere Modelle wählbar, 2–3 GB RAM sind in Ordnung; erst messen, dann einbauen. Konzept „Sprach-Pipeline“ (STT/TTS), „Tests“ (Wortfehlerrate je Modellgröße).

## Inhalt
1. **Kandidaten STT** (sherpa-onnx, offline): heutiger Stand Whisper base/small int8; dazu Parakeet TDT 0.6B v3 (int8), Whisper large-v3-turbo und medium (int8), ggf. Canary-180m-flash. Aktuelle Verfügbarkeit und Lizenz zuerst prüfen (Release-Seite sherpa-onnx, Hugging Face).
2. **Kandidaten TTS:** heutige Piper low/medium; Piper high (de Thorsten high u. a.), Kokoro multi-lang (en/fr), weitere aktuelle offline-Stimmen mit Deutsch, falls vorhanden.
3. **Messung je Modell:** Wortfehlerrate de/fr/en auf synthetischen bzw. öffentlichen Aufnahmen (keine privaten Aufnahmen im Repo), Latenz bis Text (kurz/lang), Echtzeitfaktor, RAM-Spitze, Ladezeit, Download-Größe; mit und ohne Rauschunterdrückung (GTCRN); mit und ohne Hinweis-Begriffe (Whisper-Prompt bzw. Hotwords, wo das Modell es kann). TTS: Echtzeitfaktor, RAM, Zeit bis erstes Audio, Hörproben (WAV außerhalb des Repos für Stefan).
4. **Ergebnis:** Notiz `docs/notes/voice-quality-spike.md` mit Tabelle und Empfehlung (Standard, „groß“, je Sprache), Hörproben-Ordner für Stefan; Messskript wiederverwendbar unter `tool/`.

## Umsetzung
- Messung auf dem Mac (Desktop-Build von sherpa-onnx) plus Stichprobe auf dem Emulator (x86_64, nur Größenordnung); echte Handy-Zahlen misst Stefan per Debug-Ansicht im Folgepaket.
- Kein Einbau in die App-Auswahl (das ist WP103). Keine Cloud-Dienste.
- Parallel: läuft unabhängig; berührt nur `tool/` und `docs/notes/`.

## Abnahmekriterien
- [ ] Tabelle mit allen Kandidaten und Werten, Quelle/Version/Lizenz je Modell.
- [ ] Hörproben je Stimme (gleicher Text de/fr/en) für Stefan abgelegt.
- [ ] Empfehlung für WP103 mit Begründung; Gate grün.
