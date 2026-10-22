# WP130 – Wake-Word-Modell v8: mehr deutsche Stimmen, Varianten, harte Negative

**Zuordnung:** Folge K80/K98 (WP121). Entscheidungen Maintainer 2026-10-22: erst Deutsch; viele Stimmen, länger/kürzer gesprochen; seine Aufnahmen dürfen ins Training (Modell wird veröffentlicht – nur Gewichte, keine Aufnahmen), Training nachts bzw. bei Abwesenheit (Volllast), Vorbereitung vorher mit wenig Last.

## Inhalt
1. **Positiv synthetisch (de):** alle lizenzklaren deutschen Piper-Stimmen (thorsten, kerstin, MLS 236 Sprecher, M-AILABS eva_k/ramona/karlsson – Lizenz laut WP117 BSD-artig mit Namensnennung, nochmals belegen), macOS-Stimmen wie v7. Variation: Sprechtempo (length_scale ca. 0,75–1,5), noise_scale/noise_w, Tonhöhe, Kontexte („Wendelin“ allein, am Satzanfang, „Wendelin, …“-Befehle), Hall/Rauschen/Fernseher wie v7.
2. **Positiv echt:** Aufnahmen des Maintainers, **nur Trainings-Split**: Huawei Blöcke 1–3. **Prüf-Split, nie im Training:** Huawei Blöcke 4–6 und das gesamte zweite Handy (Labels aus WP121). Split im Skript fest verdrahtet, Test dafür.
3. **Negativ:** Common Voice de (CC0, mehrere Stunden, Sprecher-disjunkt zur Prüfung), FLEURS, Tatoeba-TTS, harte Verwechsler (Wendel, Berlin, Wendeltreppe, „wenn der Lin…“, Wendelstein, „Hey Wendel“, …) synthetisch in vielen Stimmen.
4. **Training** mit der v7-Pipeline (`tool/train_wake_word/`), ggf. 2–3 Varianten (Datenmix, Epochen). Phase A (Vorbereitung, `nice`, wenig Last) sofort; **Phase B (Training) erst nach Freigabe des Orchestrators** (Maintainer abwesend/nachts).
5. **Messung** mit `words_measure.py` auf dem Prüf-Split: v8 vs. v7 bei gleicher FA/h (2/h, Kreuzauswahl, Wilson), dazu synthetische Verwechsler/h. Ergebnis in `docs/notes/wake-word-compare.md` (Abschnitt v8), nur Zahlen.
6. Ausgabe: bestes Modell als ONNX lokal (`~/wendelin-models/kws/wp130/`), SHA-256; Veröffentlichung übernimmt der Orchestrator (Release-Asset, Katalog via WP129). Lizenz-/Namensnennungsliste für die App.

## Abnahmekriterien
- [ ] Split-Test (keine Prüf-Aufnahme im Training), Lizenzliste vollständig.
- [ ] Tabelle v8 vs. v7 auf echtem Prüf-Split (Huawei 4–6, handy2) mit Wilson-Intervallen; klare Empfehlung (v8 übernehmen ja/nein).
- [ ] Skripte reproduzierbar, Python-Selbsttests grün, `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE.
- [ ] Platte: Zwischenstände nach Gebrauch per `trash`, freier Platz > 15 GB halten.

## Parallel-Hinweise
- Läuft neben App-Paketen (WP128/WP129); berührt nur `tool/train_wake_word/`, `tool/kws_measure.py`, `docs/notes/`. Kein Emulator. Kein lokales Gate parallel zum Training.
