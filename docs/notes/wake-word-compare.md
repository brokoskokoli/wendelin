# Wake Words im Vergleich (WP111): Messung

Stand: Gerüst (Teil A, synthetisch). Die Ergebnisse stehen unter „Ergebnisse“ als Platzhalter, bis die Messläufe fertig sind. Nur Zahlen, keine Transkripte und keine Aufnahmen.

## Ziel
Frage: Ist „Hey Wendelin“ als Wake Word besser als „Wendelin“, und welches offene Erkennungsprogramm trägt es? Zielwerte: Treffer >= 80 %, <= 2 Fehlalarme je Stunde (FA/h) nach allen Stufen. Bezug ist WP106 (`docs/notes/wake-word-station-spike.md`). Porcupine entfällt (Entscheidung Stefan 2026-10-20).

## Aufbau
Zwei Wörter (`wendelin`, `hey`) x vier Stufe-1-Regeln, danach Stufe 2 (Parakeet ohne/mit Hotwords) auf identischem Audio (Rausch-Parameter je Clip per Seed, Paare „Wendelin“/„Hey Wendelin“ gleich).

Stufe-1-Regeln (`--rules`):
- `T<thr>`: Vorlagen (Kosinus gegen 15 Einlernclips je Stimme).
- `M<thr>`: openWakeWord v7 (mit Mix trainiert, deckt „Hey“ mit ab).
- `W<thr>`: microWakeWord, je Wort eigenes Modell (`--mww wendelin=..,hey=..`).
- `K<g|z><boost>/<thr>`: sherpa-onnx Keyword Spotting ohne Training, Wort frei eingegeben; `g` = gigaspeech (BPE), `z` = zh-en (Phoneme).

Stufe 2: Parakeet mit `parakeet-bs` (ohne Hotword), `parakeet-hw2`, `parakeet-hw3` (Hotword-Boost). Regel je Wort: `matches_wake_word` (App-Spiegel) bzw. `matches_hey_wake_word` (Hey-Wort direkt vor Wendelin-Treffer, `tool/kws_measure.py`). Stufe 3 (CAM++) ist in `--compare` nicht enthalten.

Kennzahlen: Treffer % (Wilson-95-%), Kandidaten/h Stufe 1, FA/h nach Stufe 2 (Poisson-Obergrenze), Verwechsler als Quote, „andere Phrase löst aus“ (für `wendelin`: Hey-Clips, Treffer erwartet; für `hey`: nacktes „Wendelin“, soll nicht auslösen), Latenz/RTF/RAM am Mac.

## Regeln der Messung
- Labels nie aus dem gemessenen Erkenner. Negativclips mit „Wendel…“ im Ausschluss: Treffer von Parakeet ODER Whisper small, dazu Textvorlagen (t018, t021) und `b6-*`.
- Positive Paare müssen dieselben Dateinamen haben (`check_pairs`), sonst Abbruch.
- Negativsprache >= 1,5 h (Log „Negativ: .. h“, sonst Warnung).
- Wilson-Intervalle bei Treffern, Poisson-Obergrenzen bei FA/h; Station und Mobil getrennt (Bedingungen `clean`, `both`, `station`).

## Datenquellen
- Testsprache: macOS-Systemstimmen (9 Stimmen, `gen_say_test.py`) statt Piper, unabhängig von den Trainingsstimmen und vergleichbar mit WP106. Abweichung vom Paketwortlaut (Piper).
- Fernseher: FLEURS test (862 Clips, ca. 6 h), nicht im Training von v7/mww.
- Hintergrund und Hall: synthetisch (wp106 `bg`/`rirs`), kein FSD50K/FMA.
- Negativsprache synthetisch (Systemstimmen), Verwechsler 306 Clips, Einlernclips `enroll_hey` 135.

## microWakeWord-Training
- Positive: ca. 14k Piper-Clips Wendelin (10,3k bare + 40 % hey) bzw. ca. 9,4k hey; Verwechsler 10,2k, Sprache 10,8k, 2x Augmentierung.
- Schritte 40000 + 20000 je Wort (`run_mww.sh`, `STEPS=40000`), beide Trainings parallel unter `nice`.
- Logs: `~/wendelin-models/kws/wp111/mww/` (Arbeitsordner), `train_wendelin.log`, `train_hey.log`, `feats_*.log`, `run_mww.log` unter `~/wendelin-models/kws/wp111/`.
- Modelle: `mww/trained_{w,h}_main/tflite_stream_state_internal_quant/stream_state_internal_quant.tflite`.

## Ergebnisse
TABELLE

## Empfehlung
EMPFEHLUNG

## Kommandos (alle aus dem Repo-Root, Venv wp58)
Daten und Training (Skripte unter `tool/train_wake_word/`): `gen_samples.py --kind bare|hey|conf2`, `gen_say_test.py`, `mww_train.py prep|feats|train --word wendelin|hey`.

Messung ohne mww (läuft mit `K=~/wendelin-models/kws`):
```
nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/station_measure.py --compare --cond clean,both,station --words wendelin,hey --rules T0.93,M0.3,M0.5,Kz2/0.15,Kz4/0.05,Kg4/0.05 --variants parakeet-bs,parakeet-hw2,parakeet-hw3 --neg-min 7 --neg-long-max 16 --tv-max-h 1.0 --fleurs $K/wp111/work/fleurs/test --out $K/wp111/results/nomww
```
Messung microWakeWord:
```
nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/station_measure.py --compare --cond clean,both,station --words wendelin,hey --rules W0.5,W0.8,W0.9 --mww wendelin=$K/wp111/mww/trained_w_main/tflite_stream_state_internal_quant/stream_state_internal_quant.tflite,hey=$K/wp111/mww/trained_h_main/tflite_stream_state_internal_quant/stream_state_internal_quant.tflite --variants parakeet-bs,parakeet-hw2,parakeet-hw3 --neg-min 7 --neg-long-max 16 --tv-max-h 1.0 --fleurs $K/wp111/work/fleurs/test --out $K/wp111/results/mww
```
Ausgabe je Lauf: `compare_table.md`, `compare_table.csv`, `compare_meta.json` im `--out`-Ordner. Selbsttests der Helfer: `$K/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_measure.py'`.

## Lizenzen (alles lokal, nichts im Repo)
Wie WP106: Parakeet TDT 0.6B v3 CC-BY-4.0; Whisper MIT; CAM++ Apache-2.0; microWakeWord Apache-2.0; openWakeWord-Code und speech_embedding Apache-2.0; sherpa-onnx und seine KWS-Modelle (gigaspeech, zh-en) Apache-2.0 (zh-en vor Nutzung im Produkt gegenprüfen); FLEURS CC-BY 4.0; macOS-Systemstimmen Apple-Lizenzvereinbarung (nur lokale Messung, Audios nicht weitergeben); Piper-Stimmen CC0 (Trainingsdaten).

## Abweichungen
- Testsprache Systemstimmen statt Piper (siehe Datenquellen).
- Hintergrund/Hall synthetisch, kein FSD50K/FMA; Trainingsumfang des mww-Modells über dem Start-Beispiel des Projekts, aber kleiner als eine Vollproduktion.
- Persönliches Feintuning wurde nicht neu gemessen; CAM++-Stufe 3 nicht in `--compare`.
- Teil B (echte Aufnahmen unter `~/wendelin-fixtures/wake/hey/`) fehlt: Ordner bei Start leer.
- Die Python-Selbsttests laufen nicht im Gate und nicht über `tool/t.sh` (nur Dart/Flutter), sondern per `unittest` wie oben.
