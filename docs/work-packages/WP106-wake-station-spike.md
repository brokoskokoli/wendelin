# WP106 – Spike: Wake-Word-Erkennung für den Stationsmodus (Messung)

**Zuordnung:** M6 (Vorarbeit Stationsmodus), läuft als reine Messung neben M5. Freigabe Maintainer 2026-10-19 („als Spike jetzt“).

Bezug: Frage Maintainer 2026-10-19: Kann ein anderes Modell das Wake Word vor allem im Stationsmodus besser erkennen – weniger Fehlauslöser **und** weniger Überhörte? Grundlage: `docs/notes/wake-word-model-2026-10-14.md`, `docs/notes/wake-word-two-stage-2026-10-14.md`, `docs/notes/voice-quality-spike.md` (WP102: Parakeet mit Hotword „Wendelin“ 6/6 sauber, 5/6 Rauschen; Whisper small 4/6, 3/6), K29/K31/K34/K35, Stationsmodus (WP99–WP101).

## Inhalt (nur Messung, kein App-Code)
1. **Messaufbau** wie WP58/WP44 (`tool/train_wake_word/eval.py`, `tool/kws_measure.py`): Treffer in %, Fehlauslöser je Stunde (FA/h), Latenz, RTF; Bedingungen sauber/Rauschen/Hall/beides, zusätzlich „Station“ = Abstand 2–3 m mit Fernsehton.
2. **Varianten der Zweitstufe:** Whisper small (heute) gegen Parakeet v3 mit Hotword „Wendelin“ (Boost-Stufen), gegen Parakeet ohne Hotword; besonders messen, ob der Hotword-Boost Fehlauslöser erhöht.
3. **Erste Stufe:** Modell v7 (heute) gegen v7 nachtrainiert mit mehr Sprechervielfalt/echter deutscher Negativ-Sprache und gegen microWakeWord (Apache-2.0, wenn in vertretbarem Aufwand trainierbar); persönliche Vorlagen (K31) als Vergleich.
4. **Dritte Stufe Sprecherprüfung:** mit dem Speaker-ID-Modell aus WP92a (sobald verfügbar, sonst dasselbe sherpa-onnx-Modell direkt): wie viele Fehlauslöser durch Fernseher/fremde Stimmen fallen weg, wie viele echte Treffer gehen verloren.
5. **Schwellen je Modus:** Empfehlung für Handy und Station getrennt.
6. **Daten:** synthetisch (Piper/macOS-Stimmen, Rauschen, Hall, Fernsehton aus frei lizenzierten Quellen) sofort; Maintainers echte Aufnahmen aus `~/wendelin-fixtures/wake/station/` (Anleitung dort), sobald vorhanden – nur lokal, nie im Repo, keine Ausschnitte in Notizen.

## Ergebnis
- Notiz `docs/notes/wake-word-station-spike.md` mit Tabellen und Empfehlung (welche Kombination, erwartete Treffer/FA/h, RAM/Akku-Abschätzung, Aufwand Einbau) als Grundlage für ein Einbaupaket.
- Skripte unter `tool/train_wake_word/` (ohne Daten); große Daten/Modelle unter `~/wendelin-models/kws/`.

## Abnahmekriterien
- [ ] Tabelle Treffer/FA/h für mindestens: heute (v7+Whisper small), v7+Parakeet±Hotword, +Sprecherprüfung; je synthetisch und – falls bis dahin vorhanden – mit echten Aufnahmen.
- [ ] Klare Empfehlung mit Begründung; Lizenzen aller Modelle/Daten genannt. Gate grün.
