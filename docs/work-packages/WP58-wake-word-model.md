# WP58 – Eigenes Wake-Word-Modell „Wendelin“ (openWakeWord, Plan B aus WP42)

Abhängig von: WP42 (Messskript `tool/kws_measure.py`, Notiz `docs/notes/wake-word-spike-2026-10-14.md`). Blockiert: WP44 (Wake-Word-Kern nutzt das Modell).

## Inhalt
- Training eines openWakeWord-Modells für „Wendelin“ (auch „Hey Wendelin“) mit synthetischen deutschen Positivbeispielen (Piper-Stimmen de, mehrere Sprecher, Tempo/Tonhöhe variiert, Raumhall/Rauschen gemischt) und Negativbeispielen (deutsche Sprache ohne das Wort, ähnliche Wörter „Wendel“, „Wendeltreppe“, „Vanille“, „Berlin“, Geräusche). Lizenzen aller Stimmen/Datensätze notieren (öffentliches Repo; Gewichte des fertigen Modells dürfen ins Repo, wenn Lizenzen es erlauben, sonst Download wie Whisper).
- Training lokal auf dem Mac (CPU/MPS) oder per Skript, das reproduzierbar ist (`tool/train_wake_word/`, venv außerhalb des Repos, Daten unter `~/wendelin-models/kws/`).
- Messung mit `tool/kws_measure.py` gegen dieselben Sätze wie WP42 (synthetisch) und, sobald vorhanden, die Aufnahmen des Maintainers aus `~/wendelin-fixtures/wake/` (nie ins Repo).
- Laufzeit-Einbindung bewerten: openWakeWord-Modelle sind ONNX (Melspektrogramm + Embedding + Klassifikator) → Ausführung über das vorhandene onnxruntime (sherpa-onnx) in der schlanken Engine aus WP42-Empfehlung; CPU/RTF messen.

## Abnahmekriterien
- [ ] Trefferquote ≥ 80 % (ruhig, 1 m) und Falschauslösungen ≤ 2/h auf dem Negativsatz (synthetisch); mit Rauschen/Hall dokumentiert.
- [ ] Schwellenwert und Empfindlichkeitsstufen (niedrig/mittel/hoch) aus der ROC-Kurve festgelegt.
- [ ] Reproduzierbares Trainingsskript, Lizenzliste, Modellgröße, RTF auf dem Mac.
- [ ] Wenn die Aufnahmen des Maintainers vorliegen: Messung damit; sonst als offen melden.
