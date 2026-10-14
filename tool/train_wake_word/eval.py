#!/usr/bin/env python3
"""Misst ein Wendelin-Modell (ONNX) auf Positiv-/Negativ-Ordnern wie tool/kws_measure.py (WP58).

  python eval.py --model m.onnx --models <oww-modelle> --pos <wav-ordner> --neg <wav-ordner> \
      [--neg-max-h 0.5] [--cond clean,noise,reverb,both] [--thr 0.3,0.5,0.7,0.9]

Ausgabe: Markdown-Tabelle Bedingung x Schwelle -> Trefferquote, Falschausloesungen/h
(Ereignisse mit 2 s Sperrzeit), Echtzeitfaktor (Mel + Embedding + Klassifikator, 1 Thread).
Die Bedingungen (Rauschen 10 dB SNR, Hall RT60 0,5 s) kommen aus tool/kws_measure.py.
"""
import argparse, glob, importlib.util, os, sys, time
import numpy as np
import onnxruntime as ort
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("kws_measure", os.path.join(HERE, "..", "kws_measure.py"))
km = importlib.util.module_from_spec(spec); spec.loader.exec_module(km)


def scores(af, sess, x):
    """Modellausgabe je Fenster (Schritt 80 ms)."""
    emb = embed(af, [x])[0]
    nf = len(emb)
    if nf < WIN:
        return np.zeros(0, "float32")
    W = np.stack([emb[j:j + WIN] for j in range(nf - WIN + 1)]).astype("float32")
    return sess.run(None, {"input": W})[0][:, 0]


def events(s, thr, refr=25):
    ev, last = 0, -10 ** 9
    for j in np.where(s >= thr)[0]:
        if j - last >= refr:
            ev += 1
        last = j
    return ev


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--model", required=True); a.add_argument("--models", required=True)
    a.add_argument("--pos", required=True); a.add_argument("--neg", required=True)
    a.add_argument("--neg-max-h", type=float, default=0.5)
    a.add_argument("--cond", default="clean,noise,reverb,both")
    a.add_argument("--thr", default="0.3,0.5,0.7,0.9"); a.add_argument("--seed", type=int, default=1)
    a.add_argument("--save-scores")
    a = a.parse_args()
    rng = np.random.default_rng(a.seed)
    af = make_features(a.models, 1)
    so = ort.SessionOptions(); so.intra_op_num_threads = 1
    sess = ort.InferenceSession(a.model, so, providers=["CPUExecutionProvider"])
    pos = sorted(glob.glob(os.path.join(a.pos, "*.wav"))); neg = sorted(glob.glob(os.path.join(a.neg, "*.wav")))
    px = [km.load(p) for p in pos]
    nx = []
    for p in neg:
        nx.append(km.load(p))
        if a.neg_max_h and sum(map(len, nx)) / SR / 3600 >= a.neg_max_h:
            break
    pad = lambda x: np.concatenate([np.zeros(SR, "float32"), x, np.zeros(SR, "float32")])
    thrs = [float(t) for t in a.thr.split(",")]
    print(f"Positiv {len(px)} Clips, Negativ {len(nx)} Clips\n")
    print("| Bedingung | Schwelle | Trefferquote | FA/h | RTF |\n|---|---|---|---|---|")
    for cond in a.cond.split(","):
        P = [km.condition(x, cond, rng) for x in px]
        N = [km.condition(x, cond, rng) for x in nx]
        nh = sum(map(len, N)) / SR / 3600
        t0 = time.process_time()
        ps = [scores(af, sess, pad(x)) for x in P]
        ns = [scores(af, sess, pad(x)) for x in N]
        rtf = (time.process_time() - t0) / ((sum(map(len, P)) + sum(map(len, N)) + 2 * SR * (len(P) + len(N))) / SR)
        if a.save_scores:
            np.savez(f"{a.save_scores}_{cond}.npz", pos=np.array([s.max() if len(s) else 0 for s in ps]),
                     neg=np.array(ns, dtype=object), nh=nh)
        for th in thrs:
            hit = sum(bool(len(s) and s.max() >= th) for s in ps)
            fa = sum(events(s, th) for s in ns)
            print(f"| {cond} | {th} | {hit}/{len(P)} = {100*hit/len(P):.0f} % | {fa/nh:.1f} ({fa}) | {rtf:.3f} |", flush=True)
    print(f"\nNegativ-Audio je Bedingung: {nh:.2f} h")


if __name__ == "__main__":
    main()
