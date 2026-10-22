# WP121 – Wake Words mit echten Aufnahmen vergleichen (fair)

**Zuordnung:** M6, Folge zu WP111 (`docs/notes/wake-word-compare.md`, K83). Aufnahmen Maintainer 2026-10-21 nach `~/wendelin-fixtures/wake/words/ANLEITUNG.md`. Wörter: „Wendelin“, „Hey Wendelin“, „Alexa“, „Hey Octavia“, „Kobalos“.

## Daten
- `~/wendelin-fixtures/wake/words/raw/all_huawei.m4a` (13 min, **alle Blöcke 1–6 in einer Datei**, Ansagen im Ton, jedes Wort 5× je Block in fester Reihenfolge laut Anleitung), `raw-neg/neg_huawei.m4a` (37 min). Nur ein Handy (Huawei P20 Pro), Rolle Station/Mobil offen (`notizen.txt`).
- Aufnahmen und Transkripte bleiben lokal; in der Notiz nur Zahlen. Labels nie aus dem gemessenen Erkenner: Schneiden über Ansagen + Reihenfolge, Abweichungen von Hand (Liste in `~/wendelin-fixtures/wake/words/labels/`), Unsicherheiten an Maintainer per AskUserQuestion.

## Fairer Vergleich (Kritik an WP111 aufgreifen)
- Je Wort eigene Kalibrierung; Vergleich der Trefferquote bei **gleicher Fehlalarmrate** (z. B. 1 und 2 FA/h auf der Negativ-Aufnahme), dazu DET-Kurve.
- „Alexa“-Probe reparieren (WP111: 8 %, Verdacht Modell/Token); „Kobalos“ 0 % prüfen (Token/Abgleich). Erst wenn die Kontrollen plausibel sind, Wörter vergleichen.
- Programme wie WP111 (Zwei-Stufen-Aufbau, sherpa-KWS ohne Training, vorhandene microWakeWord-Modelle); kein neues Training ohne Rückfrage (Platte: trainierte Modelle bleiben, Features wurden entfernt).
- 37 min Negativ sind kurz: Wilson-/Poisson-Intervalle angeben, synthetische Negativsprache aus WP111 ergänzend und getrennt ausweisen.

## Abnahmekriterien
- [ ] Labelliste mit Zählung je Wort × Block (Maintainer bestätigt Auffälligkeiten).
- [ ] Notiz-Abschnitt „Teil B echte Aufnahmen“ in `docs/notes/wake-word-compare.md`: Tabelle Wort × Programm × Block, Treffer bei gleicher FA/h, Intervalle, Empfehlung; Kontrollen (Alexa, Kobalos) erklärt.
- [ ] Skripte reproduzierbar (Kommandos in der Notiz); `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Läuft neben WP120 (App-Code). WP121 berührt nur `tool/train_wake_word/`, `tool/kws_measure.py`, `docs/notes/`. Kein Emulator. Platte knapp halten (`trash`), keine schweren Läufe parallel zum lokalen Gate.
