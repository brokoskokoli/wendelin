#!/bin/zsh
# WP111: Piper-Trainingsclips (bare = Wendelin, hey = Hey Wendelin, conf2 = Verwechsler fuer Hey Wendelin)
# Aufruf aus dem Repo-Root: tool/train_wake_word/run_gen.sh   (K = Modellordner ausserhalb des Repos)
K=${K:-$HOME/wendelin-models/kws}
R=${R:-$(cd "$(dirname "$0")" && pwd)/gen_samples.py}
mkdir -p $K/wp111/gen && cd $K/wp111/gen || exit 1
g() { nice -n 10 $K/wp58/venv/bin/python -I $R --kind $1 --out $1 --n $2 --seed $3 --voices $K/wp58/dl --wide; }
for kind in bare hey; do
  for s in 31 32 33 34; do g $kind 4500 $s & done; wait
done
for s in 41 42; do g conf2 2500 $s & done; wait
echo ALLDONE
