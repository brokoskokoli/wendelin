# WP141 – Wake Word: nach dem ersten Treffer bis 0,8 s weiter beobachten

**Zuordnung:** K110 (Band-Regel). Wunsch des Maintainers 2026-10-23 nach der Analyse in WP137: Rufe, die erst kurz nach dem ersten Fenster ≥ 0,98 ihren Spitzenwert erreichen, sollen direkt angenommen werden, statt über Stufe 2 zu laufen.

## Ist-Stand
- `CandidateWakeEngine` (`packages/wendelin_voice/lib/src/wake/candidate_wake_engine.dart:13`, `:80`, `:178`) hält nach dem ersten Fenster über der Schwelle, bis die Werte fallen (`dropsToEnd`, im Katalog 2: `wake_classifier_catalog.dart:108-111`), höchstens `holdWindows` (5) Fenster lang, und entscheidet dann mit dem Spitzenwert.
- Die Messung bildet diese Regel in `tool/train_wake_word/stage2_cut.py` (`app_events`) nach.

## Analyse (WP137, s1-Kurven von 13 Modellen, Wahl auf Huawei B1–3, Prüf-Split bestätigt)
- Vom ersten Fenster ≥ 0,98 bis zum Maximum: 95 % nach 0,44–0,64 s, Maximum ≤ 0,80 s.
- Mit 0,8 s Beobachtung kommen je Split 3–9 Rufe mehr direkt durch (≥ 0,999, ohne Stufe 2). Zusätzliche falsche Direktannahmen: echte Negative 0, syn/fleurs 0–5, Verwechsler je nach Modell +1,5 bis +8. Ab 0,5 s ist der Gewinn ausgereizt.
- Nachteil: Bei Rufen unter 0,999 beginnt Stufe 2 bis zu 0,8 s später.

## Inhalt
- Nach dem ersten Fenster ≥ Bandunterkante bis zu W = 0,8 s (10 Fenster bei 80 ms) weiter beobachten, auch über einen Abfall hinweg. Erreicht ein Fenster ≥ 0,999, sofort annehmen (ohne Stufe 2). Sonst nach W mit dem Spitzenwert und dem Ausschnitt um den Spitzenwert an Stufe 2. W als Konstante je Modell im Katalog (Standard 0,8 s), Tests mit Grenzfällen (Spitze bei 0,79 bzw. 0,81 s, Doppelgipfel, Abfall und Wiederanstieg).
- Messung und App gleich: `stage2_cut.app_events` und `stage2_analysis` (Abschnitt 6) nutzen dieselbe Regel; ein Paritätstest (Python gegen Dart auf denselben Fensterfolgen) belegt das.
- Latenz loggen: `wake-decision hold_ms=… peak=… path=direct|stage2`.

## Abnahmekriterien
- [ ] Engine und Nachbildung nach derselben Regel, Paritätstest grün, Tests mit Mutationsbeleg.
- [ ] Auf dem Prüf-Split mit dem App-Bezug nachgerechnet (Treffer, Direktannahmen, Verwechsler, FA vorher/nachher), plausibel geprüft; beachten: Huawei- und handy2-Prüfblöcke sind dieselbe Sitzung auf zwei Geräten (nicht unabhängig).
- [ ] Gate `--changed`, CI grün, Review FREIGABE, E2E (Wake-Kandidat mit spätem Spitzenwert) grün, Gerätetest-Block.

## Parallel-Hinweise
- WP137 rechnet noch (nur `tool/train_wake_word/`, `docs/notes/`). `stage2_cut.py` gehört zu beiden: WP141 ändert dort nur `app_events`, mit WP137 abstimmen (WP137 nicht nach main mergen, bevor WP141 abgestimmt ist).
