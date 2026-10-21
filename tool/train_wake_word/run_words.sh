#!/bin/zsh
# WP121 Etappe 3: je ein openWakeWord-Modell fuer "Hey Octavia" (oct) und "Kobalos" (kob), gleiche Pipeline und Parameter wie v7
# (WP58, run.sh): Piper-Positive (ca. 13,7k wie pos+pos2 bei v7), Verwechsler, gleiche Negativ-/FLEURS-Daten (verlinkt),
# Features --n-pos 20000 --n-neg 7000, 5000 Schritte. Alles unter $K/wp121, nichts im Repo.
# Aufruf aus dem Repo-Root: nice -n 10 tool/train_wake_word/run_words.sh [oct|kob ...]   (NJ = Prozesse, Standard 2)
K=${K:-$HOME/wendelin-models/kws}
T=$(cd "$(dirname "$0")" && pwd)
PY=$K/wp58/venv/bin/python
NJ=${NJ:-2}
words=(oct kob); [ $# -gt 0 ] && words=("$@")
for w in $words; do
  G=$K/wp121/gen_$w; W=$K/wp121/work_$w; mkdir -p $G/real $W $K/wp121/models
  [ -e $G/neg ] || ln -s $K/wp58/gen/neg $G/neg
  [ -e $G/real/dev ] || ln -s $K/wp58/gen/real/dev $G/real/dev
  if [ ! -f $G/gen.done ]; then
    for s in $(seq 1 $NJ); do
      $PY -I $T/gen_samples.py --kind $w --out $G/pos --n $((14000 / NJ)) --seed $((s + 50)) --voices $K/wp58/dl &
    done; wait
    $PY -I $T/gen_samples.py --kind conf_$w --out $G/conf --n 3100 --seed 61 --voices $K/wp58/dl
    touch $G/gen.done
  fi
  [ -f $W/feat_val.npz ] || $PY -I $T/train.py features --gen $G --real $G/real/dev --models $K/wp58/dl/oww --work $W \
    --pos-dirs pos --conf-dirs conf --neg-dirs neg --n-pos 20000 --n-neg 7000 --ncpu $NJ
  [ -f $K/wp121/models/$w.onnx ] || $PY -I $T/train.py train --work $W --out $K/wp121/models/$w.onnx --threads $NJ --steps 5000
done
echo ALLDONE
