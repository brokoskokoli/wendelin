# WP111 – Vergleich alternativer Wake Words (Spike, Messung)

**Zuordnung:** M6, „Vergleich alternativer Wake Words“. Baut auf WP106 auf (`docs/notes/wake-word-station-spike.md`, K80). Entscheidungen Maintainer 2026-10-20: „Hey Wendelin“ testen, andere Erkennungsprogramme auch, Porcupine weglassen; Start mit dem synthetischen Teil, echte Aufnahmen folgen.

Ergebnis ist eine Notiz `docs/notes/wake-word-compare.md` mit Zahlen und Empfehlung. Kein App-Code.

## Inhalt

### 1. Wörter
- „Hey Wendelin“ als eigenes Wake Word gegen „Wendelin“, gleiche Pipeline wie WP106 (Stufe 1 → Parakeet-Hotword → optional CAM++).
- Für „Hey Wendelin“ ein eigenes Stufe-1-Modell trainieren bzw. die vorhandenen Modelle (mit „Hey Wendelin“ trainiert) auf das Wortpaar auswerten; Hotword-Liste der Stufe 2 passend („Hey Wendelin“, „Wendelin“).
- Verwechsler erweitern: „Hey Wendel“, „Hey Berlin“, „hey, wenn der …“, dazu die Liste aus WP106.

### 2. Erkennungsprogramme (nur offene)
- Unser Zwei-Stufen-Aufbau (v7/v9, Vorlagen, persönliches Feintuning) als Bezug.
- **microWakeWord** richtig trainiert (nicht das 2-h-Kurztraining aus WP106): Trainingsdauer und Datenmenge nach Doku des Projekts, für beide Wörter.
- **sherpa-onnx Keyword Spotting** mit frei eingegebenem Wort ohne Training (Konzept: Standard-Engine), für beide Wörter.
- Porcupine entfällt (Entscheidung Maintainer).

### 3. Messung
- **Teil A synthetisch (sofort):** Piper-Stimmen, Rauschen/Hall wie WP106, synthetischer Fernseher, Negativsprache ≥ 1,5 h. Kennzahlen: Treffer %, Kandidaten/h Stufe 1, FA/h und Verwechsler/h nach allen Stufen, Latenz/RTF/RAM am Mac.
- **Teil B echte Aufnahmen (sobald vorhanden):** `~/wendelin-fixtures/wake/hey/` (Anleitung dort; zwei Handys, Paare „Hey Wendelin“/„Wendelin“, Negativ ≥ 1,5 h). Fehlen die Aufnahmen am Ende von Teil A, meldet die Sitzung das und schließt mit Teil A ab.
- Gleiche Regeln wie WP106: Labels nie aus dem gemessenen Erkenner, Wilson-Intervalle angeben, Station und Mobil getrennt.

## Umsetzungshinweise
- Skripte unter `tool/train_wake_word/` erweitern (nicht duplizieren). Modelle unter `~/wendelin-fixtures/models` (`WENDELIN_MODELS`), Trainingsdaten unter `~/wendelin-models/kws/wp111/`. Nichts davon ins Repo.
- Aufnahmen und Transkripte bleiben lokal; in der Notiz nur Zahlen und Zeitstempel.
- Platte ist knapp (~18 GB frei): große Zwischenstände nach Gebrauch per `trash` entfernen, venvs wiederverwenden. Training belegt viel RAM: kein lokales Gate parallel zum Training.

## Abnahmekriterien
- [ ] Notiz mit Tabelle je Wort × Programm × Gerät (synthetisch, bei Aufnahmen auch echt) und Empfehlung: Wort, Programm, Schwellen für Handy und Station.
- [ ] Aussage, ob „Hey Wendelin“ die Zielwerte (≥ 80 % Treffer, ≤ 2 FA/h) erreicht oder wie weit es fehlt.
- [ ] Skripte reproduzierbar (Kommandos in der Notiz), `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Läuft neben WP99 (App/Kotlin). Berührt nur `tool/train_wake_word/`, `tool/kws_measure.py`, `docs/notes/`. Kein Emulator nötig.
