# Wake-Word-Aufnahmen und Messung (WP42)

Sprachaufnahmen bleiben lokal in `~/wendelin-fixtures/wake/` und kommen nie ins Repo.

## 1. Aufnehmen (20 bis 30 Clips, ca. 15 Minuten)

Mit dem Handy (Sprachmemo) oder Voice Memos am Mac, je Clip ein Satz, 1 bis 2 s Pause davor und danach.
Dateien als `01.m4a` ... in einen Ordner `~/wendelin-fixtures/wake/raw/` legen.

| Nr. | Was sprechen | Abstand / Umgebung |
|---|---|---|
| 01-08 | „Wendelin“ (allein) | 0,5 m, ruhig |
| 09-12 | „Hey Wendelin“ | 1 m, ruhig |
| 13-16 | „Wendelin, wie wird das Wetter morgen?“ | 1 m, ruhig |
| 17-20 | „Wendelin“ | 3 m, ruhig |
| 21-24 | „Wendelin“ | 1 m, Radio/Fernseher im Hintergrund |
| 25-28 | „Wendelin, stell einen Timer auf zehn Minuten“ | 2 m, Küchenlärm |
| 29-30 | „Wendelin“ leise/flüsternd und schnell | 1 m |

Dateien mit „allein“ bekommen das Suffix `_solo` (z. B. `01_solo.m4a`), damit die Latenz gemessen werden kann.
Zusätzlich 10 Minuten normales Sprechen ohne das Wort (Negativsatz), z. B. Vorlesen: `neg/01.m4a`.

## 2. Umwandeln (macOS, 16 kHz mono)

```sh
cd ~/wendelin-fixtures/wake
mkdir -p pos neg
for f in raw/*.m4a; do afconvert -f WAVE -d LEI16@16000 -c 1 "$f" "pos/$(basename "${f%.m4a}").wav"; done
# Negativ analog aus neg-raw/ nach neg/
```

## 3. Messen

Einmalig (außerhalb des Repos):

```sh
python3 -m venv ~/wendelin-models/kws/venv
~/wendelin-models/kws/venv/bin/pip install sherpa-onnx numpy soundfile sentencepiece
# Modelle: github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models
#   sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20, sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01
```

```sh
~/wendelin-models/kws/venv/bin/python tool/kws_measure.py \
  --model-dir <Modellordner> --pos ~/wendelin-fixtures/wake/pos --neg ~/wendelin-fixtures/wake/neg \
  --chunk 16 --cond clean,noise,reverb --thr 0.02,0.1 --boost 3,8 \
  --kw "V EH1 N D IH0 L IY1 N" --kw "V EH1 N D AH0 L IH1 N"
```

BPE-Modell (gigaspeech): zusätzlich `--bpe` und `--kw VENDELINE` (Wort statt Phoneme).
Die Ausgabe ist eine Markdown-Tabelle: Trefferquote, Falschauslösungen je Stunde, Latenz (nur `_solo`-Dateien), Echtzeitfaktor.
Synthetische Positive/Negative: `say -v Anna -o x.wav --data-format=LEI16@16000 "Wendelin"`.
