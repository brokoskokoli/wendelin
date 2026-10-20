#!/bin/zsh
# WP111: microWakeWord fuer „Wendelin“ und „Hey Wendelin“ (Merkmale, dann beide Trainings parallel)
# Voraussetzung: run_gen.sh gelaufen, venv $K/wp111/mww-venv (Python 3.11, TF 2.18) und microWakeWord-Quellen in $K/wp106/mww-src
K=${K:-$HOME/wendelin-models/kws}
R=${R:-$(cd "$(dirname "$0")" && pwd)/mww_train.py}
export PYTHONPATH=$K/wp106/mww-src
PY=$K/wp111/mww-venv/bin/python
STEPS=${STEPS:-40000}
mkdir -p $K/wp111 && cd $K/wp111 || exit 1
nice -n 10 $PY $R prep --word wendelin || exit 1
nice -n 10 $PY $R feats --word wendelin --pos-rep 2 --conf-rep 2 > feats_wendelin.log 2>&1 || exit 1
nice -n 10 $PY $R feats --word hey --pos-rep 2 --conf-rep 2 > feats_hey.log 2>&1 || exit 1
echo FEATS_DONE
nice -n 10 $PY $R train --word wendelin --name w_main --steps $STEPS --threads 4 > train_wendelin.log 2>&1 &
nice -n 10 $PY $R train --word hey --name h_main --steps $STEPS --threads 4 > train_hey.log 2>&1 &
wait
echo ALLDONE
