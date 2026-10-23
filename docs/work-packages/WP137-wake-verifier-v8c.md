# WP137 – Wake Word: v8c mit echten Aufnahmen, wortspezifischer Prüfer statt Parakeet, Aufnahme-Anleitung

**Zuordnung:** K110, Ergebnis WP133. Entscheidungen Maintainer 2026-10-23: v8c (hidden 256) auch mit den echten Aufnahmen trainieren und vergleichen (der Vergleich in WP133 mischte „mit/ohne echte Aufnahmen“ und „schmal/breit“); Prüfer als Folgepaket umsetzen, Ergebnis interessiert ihn; mehr echte Sprecher sammeln.

## Teil 1 – v8c-real
- `run_v8.sh` mit `TAG=c HIDDEN=256`, echte Positive wie v8a (Huawei B1–3, Trainings-Split K101), sonst gleiche Daten/Seed wie v8a. Danach 1–2 weitere Seeds für v8a **und** v8c (Streuung, WP133: Verwechsler streuen stark).
- Messung wie WP133 auf dem Prüf-Split (Huawei B4–6, handy2): Stufe 1 bei fester Schwelle und mit Band 0,98–0,999 + hw2, Verwechsler, FA/h, App-Parität (Spitzenwert-Halten).
- Ergebnis: Empfehlung v8a oder v8c für WP129 (nur der Katalogeintrag ändert sich).

## Teil 2 – Wortspezifischer Prüfer (Stufe 2 neu)
Ziel: Stufe 2 für Treffer im Band (0,98–0,999) ohne allgemeine Spracherkennung – kleiner, schneller, kein Ausfall bei leisen Rufen.
- **A Prüf-Klassifikator:** kleines Netz (1D-Faltung oder GRU, ≤ ~300 k Parameter, < 1,5 MB ONNX) auf den openWakeWord-Embeddings, die Stufe 1 ohnehin berechnet, aber über ein längeres Fenster (~2,0 s statt ~1,3 s) und mit Lautstärke-Normalisierung des Ausschnitts. Training gezielt auf schwierige Fälle: Positive (echt Trainings-Split + synthetisch), **harte Negative** = Verwechsler (conf_v8) und Stellen, an denen v8a/v8c auf Negativ-Daten ≥ 0,98 anschlägt (Hard-Negative-Mining auf neg/syn/FLEURS/MLS), gewichtet auf das Band.
- **B Vorlagen-Vergleich zentriert:** Kosinus auf zentrierten Embeddings gegen die eingelernten Vorlagen (ohne Stille-Polster, wie WP134), offline nachgebaut; persönlich, braucht kein Training.
- **C Kombination:** Stufe-1-Wert + A (+ B) per logistischer Fusion, kalibriert per Kreuzauswahl über die Prüf-Blöcke.
- Vergleich gegen hw2 am selben Arbeitspunkt (2 FA/h): Treffer, Verwechsler, FA/h, **leise Rufe** getrennt, Rechenzeit je Prüfung und Speicher. Keine Prüf-Aufnahme im Training (Datenleck-Prüfung wie `assert_syn_only`).
- Ergebnis: Empfehlung, ob A/B/C hw2 ersetzt. Einbau in die App ist ein eigenes Paket nach Go des Maintainers.

## Teil 3 – Aufnahme-Anleitung für weitere Sprecher
- Anleitung außerhalb des Repos (`~/wendelin-fixtures/wake/ANLEITUNG-sprecher.md`): je Sprecher ~30 Rufe „Wendelin“ und ~30 „Hey Wendelin“, Abstände 0,5/1/3 m, normal und leise, ruhiger Raum und mit Hintergrund; Dateiablage je Sprecher-Kürzel; Einverständnis-Hinweis (Stimme fließt in ein öffentliches Modell, Aufnahmen bleiben lokal); Aufteilung je Sprecher in Training/Prüfung, mindestens ein Sprecher nur zur Prüfung. `real_split.py` so erweitern, dass weitere Sprecher dazukommen können (Test).

## Abnahmekriterien
- [ ] Teil 1 und 2: Skripte unter `tool/train_wake_word/` mit Python-Tests, Notiz in `docs/notes/wake-word-compare.md` (nur Zahlen, Intervalle, Zweifel), klare Empfehlungen.
- [ ] Teil 3: Anleitung liegt vor, Split-Erweiterung getestet.
- [ ] Kritisch geprüft (Plausibilität, Datenleck, feste Schwelle statt nur Kreuzauswahl); Gate `--changed`, CI grün, Review FREIGABE. Kein Emulator.

## Parallel-Hinweise
- Nur `tool/train_wake_word/`, `docs/notes/`. Training mit `nohup`, `nice -n 10`, Threads begrenzt, vorher `memory_pressure` ≥ 30 %.
