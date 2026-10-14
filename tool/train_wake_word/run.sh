#!/bin/bash
# Reproduzierbarer Lauf fuer das Wake-Word-Modell „Wendelin“ (WP58). Alles unter $K, nichts im Repo.
# Nutzung: tool/train_wake_word/run.sh [schritt]   (download | gen | features | train | eval | alle)
# Hardware: hoechstens die Haelfte der Kerne (NCPU, Standard 5).
set -euo pipefail
K=${K:-$HOME/wendelin-models/kws/wp58}
NCPU=${NCPU:-5}
T=$(cd "$(dirname "$0")" && pwd)
PY=$K/venv/bin/python
OWW=https://github.com/dscripka/openWakeWord/releases/download/v0.5.1
HF=https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE
EVAL_POS=${EVAL_POS:-$HOME/wendelin-models/kws/data/pos}   # Systemstimmen (macOS say), siehe WP42
EVAL_NEG=${EVAL_NEG:-$HOME/wendelin-models/kws/data/neg}
step=${1:-alle}
mkdir -p "$K"; cd "$K"

download() {   # je Download ein eigener Ordner
  mkdir -p dl/oww dl/v-thorsten dl/v-kerstin dl/v-mls dl/tatoeba dl/fleurs-dev gen/real
  curl -fLo dl/oww/melspectrogram.onnx $OWW/melspectrogram.onnx          # Apache-2.0
  curl -fLo dl/oww/embedding_model.onnx $OWW/embedding_model.onnx        # Apache-2.0 (Google speech_embedding)
  curl -fLo dl/v-thorsten/m.onnx $HF/thorsten/medium/de_DE-thorsten-medium.onnx      # CC0
  curl -fLo dl/v-thorsten/m.onnx.json $HF/thorsten/medium/de_DE-thorsten-medium.onnx.json
  curl -fLo dl/v-kerstin/m.onnx $HF/kerstin/low/de_DE-kerstin-low.onnx                # CC0
  curl -fLo dl/v-kerstin/m.onnx.json $HF/kerstin/low/de_DE-kerstin-low.onnx.json
  curl -fLo dl/v-mls/m.onnx $HF/mls/medium/de_DE-mls-medium.onnx                      # CC-BY 4.0
  curl -fLo dl/v-mls/m.onnx.json $HF/mls/medium/de_DE-mls-medium.onnx.json
  curl -fLo dl/tatoeba/deu.tsv.bz2 https://downloads.tatoeba.org/exports/per_language/deu/deu_sentences.tsv.bz2   # CC-BY 2.0 FR (nur Text)
  curl -fLo dl/fleurs-dev/dev.tar.gz https://huggingface.co/datasets/google/fleurs/resolve/main/data/de_de/audio/dev.tar.gz   # CC-BY 4.0
  tar -xzf dl/fleurs-dev/dev.tar.gz -C gen/real
}

gen() {   # parallel, je Prozess ein Seed; Single-Thread-ORT
  for s in 1 2 3 4 5; do
    ( $PY -I $T/gen_samples.py --kind pos  --out gen/pos2  --n 2500 --seed $((s+5))  --voices dl
      $PY -I $T/gen_samples.py --kind conf --out gen/conf2 --n 800  --seed $((s+10)) --voices dl
      $PY -I $T/gen_samples.py --kind neg  --out gen/neg   --n 3500 --seed $((s+20)) --voices dl --text dl/tatoeba/deu.tsv.bz2 ) &
  done; wait
}

run() { [ "$step" = "$1" ] || [ "$step" = alle ]; }
run download && download
run gen && gen
run features && $PY $T/train.py features --gen gen --real gen/real/dev --models dl/oww --work work \
  --n-pos 20000 --n-neg 7000 --ncpu $NCPU
run train && $PY $T/train.py train --work work --out out/wendelin.onnx --threads $NCPU --steps 5000
run eval && $PY $T/eval.py --model out/wendelin.onnx --models dl/oww --pos "$EVAL_POS" --neg "$EVAL_NEG" \
  --neg-max-h 2 --thr 0.2,0.4,0.5,0.6,0.7,0.8,0.9,0.95,0.98
true
