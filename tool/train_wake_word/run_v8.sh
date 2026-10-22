#!/bin/bash
# WP130: reproduzierbarer Lauf fuer das Wake-Word-Modell v8 (openWakeWord, deckt „Wendelin“ und „Hey Wendelin“).
# Alles unter $W (Standard ~/wendelin-models/kws/wp130), nichts im Repo. Idempotent: jede Phase/jeder Teil traegt einen
# .done-Marker; ein erneuter Aufruf ueberspringt Erledigtes. Venv und v7-Daten kommen aus dem WP58-Ordner.
# Nutzung (aus dem Repo-Root):  tool/train_wake_word/run_v8.sh [gen | features | train | alle]
# Variablen: NJ = parallele Erzeuger (2), THREADS = Rechenkerne in features/train (NJ), TAG = Modellname (a),
#   STEPS (5000), SEED (1), HIDDEN (128), N_POS/N_CONF/N_NEG/N_CV (Mengen), PROBE=1 (Mini-Probe in $W/probe, ohne Marker),
#   FIX = Ordner der Wortaufnahmen mit labels/ und raw/ (nur Huawei-Block 1 bis 3, siehe real_split.py).
# Reproduktionsbedingung: NJ (Standard 2). Die Erzeuger nutzen die Seeds sb+1..sb+NJ mit n/NJ (abgerundet) Clips; anderes NJ = andere Daten.
# Downloads sind per SHA-256 gepinnt (run_v8.sha256, Pruefung verify_dl); Stimmen kommen von resolve/main, Tatoeba ist die Live-Datei.
# Aller Rechenaufwand laeuft mit nice -n 5.
set -euo pipefail
K0=${K0:-$HOME/wendelin-models/kws}
W=${W:-$K0/wp130}
B=$K0/wp58
PY=$B/venv/bin/python
T=$(cd "$(dirname "$0")" && pwd)
FIX=${FIX:-$HOME/wendelin-fixtures/wake/words}
NJ=${NJ:-2}; THREADS=${THREADS:-$NJ}; TAG=${TAG:-a}; STEPS=${STEPS:-5000}; SEED=${SEED:-1}; HIDDEN=${HIDDEN:-128}
N_POS=${N_POS:-34000}; N_CONF=${N_CONF:-10000}; N_NEG=${N_NEG:-13000}; N_CV=${N_CV:-4000}
PROBE=${PROBE:-0}
step=${1:-alle}
N="nice -n 5"
HF=https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE
CV=https://huggingface.co/datasets/fsicoli/common_voice_17_0/resolve/main/audio/de/train/de_train_0.tar   # CC0
G=$W/gen; [ "$PROBE" = 1 ] && G=$W/probe/gen
D=$W/dl; WK=$W/work; [ "$PROBE" = 1 ] && WK=$W/probe/work
mkdir -p "$D" "$G/.done" "$WK" "$W/out"

fetch() {      # fetch <url> <ziel>: fortsetzbar, erst .part, dann umbenennen
  [ -s "$2" ] && return 0
  curl -fL --retry 3 -C - -o "$2.part" "$1" && mv "$2.part" "$2"
}
marker() { [ -f "$G/.done/$1" ]; }
ok() { [ "$PROBE" = 1 ] || touch "$G/.done/$1"; }

# ---------- Phase gen ----------
download() {
  [ -f "$D/dl.done" ] && return 0
  mkdir -p "$D/oww" "$D/tatoeba"
  [ -e "$D/oww/melspectrogram.onnx" ] || cp "$B/dl/oww/"*.onnx "$D/oww/"      # Apache-2.0
  # Stimmen: Ordner v-<name>/m.onnx(+.json), Lizenzen siehe docs/notes/wake-word-v8-licenses.md (pavoque/NC ausgeschlossen)
  for v in thorsten-low:thorsten/low/de_DE-thorsten-low thorsten-medium:thorsten/medium/de_DE-thorsten-medium \
           thorsten-high:thorsten/high/de_DE-thorsten-high emo:thorsten_emotional/medium/de_DE-thorsten_emotional-medium \
           kerstin:kerstin/low/de_DE-kerstin-low mls:mls/medium/de_DE-mls-medium eva:eva_k/x_low/de_DE-eva_k-x_low \
           ramona:ramona/low/de_DE-ramona-low karlsson:karlsson/low/de_DE-karlsson-low; do
    n=${v%%:*}; p=${v#*:}; mkdir -p "$D/v-$n"
    fetch "$HF/$p.onnx" "$D/v-$n/m.onnx"; fetch "$HF/$p.onnx.json" "$D/v-$n/m.onnx.json"
  done
  fetch https://downloads.tatoeba.org/exports/per_language/deu/deu_sentences.tsv.bz2 "$D/tatoeba/deu.tsv.bz2"   # CC-BY 2.0 FR
  touch "$D/dl.done"
}

verify_dl() {      # SHA-256 aller geladenen Dateien gegen run_v8.sha256 (gepinnt); Abweichung = Abbruch
  ( cd "$D" && grep -v '^#' "$T/run_v8.sha256" | shasum -a 256 -c --quiet ) || { echo "SHA-256 der Downloads weicht von run_v8.sha256 ab" >&2; exit 1; }
}

link() { [ -e "$2" ] || ln -s "$1" "$2"; }     # v7-Daten wiederverwenden

synth_kind() {   # synth_kind <kind> <ordner> <n> <seedbasis> [weitere Argumente]
  local kind=$1 out=$2 n=$3 sb=$4; shift 4
  marker "$out" && return 0
  local pids=() p
  for s in $(seq 1 "$NJ"); do
    $N $PY -I "$T/gen_samples.py" --kind "$kind" --out "$G/$out" --n $((n / NJ)) --seed $((sb + s)) --voices "$D" "$@" &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || { echo "gen_samples ($kind) fehlgeschlagen" >&2; exit 1; }; done    # kein .done bei Fehler
  ok "$out"
}

gen() {
  download
  verify_dl
  mkdir -p "$G/real"
  link "$B/gen/pos" "$G/pos"; link "$B/gen/pos2" "$G/pos2"; link "$B/gen/conf2" "$G/conf2"; link "$B/gen/neg" "$G/neg"
  link "$B/gen/real/train" "$G/real/train"; link "$B/gen/real/dev" "$G/real/dev"     # FLEURS de_de (CC-BY 4.0)
  synth_kind pos_v8 pos_v8 "$N_POS" 100
  synth_kind conf_v8 conf_v8 "$N_CONF" 200
  synth_kind neg_v8 neg_v8 "$N_NEG" 300 --text "$D/tatoeba/deu.tsv.bz2"
  if ! marker cv; then      # Common Voice de (CC0, ohne Login ueber die HF-Spiegelung), jeder dritte Clip des ersten Train-Shards
    mkdir -p "$D/cv"
    if [ "$PROBE" = 1 ]; then
      [ -s "$D/cv/probe.tar" ] || curl -fL -r 0-40000000 -o "$D/cv/probe.tar" "$CV"; src=$D/cv/probe.tar
    else
      fetch "$CV" "$D/cv/de_train_0.tar"; src=$D/cv/de_train_0.tar
    shasum -a 256 "$src" | tee "$D/cv/de_train_0.tar.sha256"      # noch nicht gepinnt: nur loggen
    fi
    local trunc=(); [ "$PROBE" = 1 ] && trunc=(--allow-truncated)      # nur die Probe darf ein abgeschnittenes Archiv lesen
    $N $PY -I "$T/cv_extract.py" --tar "$src" --out "$G/cv" --every 3 --max "$N_CV" ${trunc[@]+"${trunc[@]}"}
    ok cv
  fi
  if ! marker real_pos; then    # echte Positive: nur Huawei Block 1 bis 3 (real_split.py)
    $N $PY -I "$T/real_split.py" cut --fix "$FIX" --work "$WK" --out "$WK/real_pos"
    ok real_pos
  fi
  echo "gen fertig: $(ls "$G/pos_v8" | wc -l) pos_v8, $(ls "$G/conf_v8" | wc -l) conf_v8, $(ls "$G/neg_v8" | wc -l) neg_v8, $(ls "$G/cv" | wc -l) cv, $(ls "$WK/real_pos" | wc -l) real_pos"
}

# ---------- Phase features ----------
features() {
  [ -f "$WK/features.done" ] && return 0
  $N $PY -I "$T/train.py" features --gen "$G" --models "$D/oww" --work "$WK" \
    --real "$G/real/train" --real-val "$G/real/dev" --real-rep 3 \
    --real-pos "$WK/real_pos" --real-pos-rep 100 \
    --pos-dirs pos,pos2,pos_v8 --conf-dirs conf2,conf_v8 --neg-dirs neg,neg_v8,cv \
    --n-pos 30000 --n-neg 14000 --ncpu "$THREADS" --seed "$SEED"
  touch "$WK/features.done"
}

# ---------- Phase train ----------
train() {
  local out=$W/out/wendelin_wp130_$TAG.onnx
  [ -f "$out.done" ] && return 0
  $N $PY -I "$T/train.py" train --work "$WK" --out "$out" --threads "$THREADS" --steps "$STEPS" --seed "$SEED" --hidden "$HIDDEN"
  shasum -a 256 "$out" | tee "$out.sha256"
  touch "$out.done"
}

case $step in
  gen) gen ;;
  features) features ;;
  train) train ;;
  alle) gen; features; train ;;
  *) echo "Phase: gen | features | train | alle" >&2; exit 2 ;;
esac
echo "$step fertig"
