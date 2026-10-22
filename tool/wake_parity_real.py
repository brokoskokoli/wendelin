#!/usr/bin/env python3
"""WP129 „Paritaet echt“: App-Strom gegen Messskript auf den echten Pruef-Aufnahmen.

Eingang: die Rohdaten des Tests app/test/platform/wake_classifier_real_parity_test.dart
(Ordner WENDELIN_PARITY_OUT: <src>.ends.i32, <src>.scores.f32, <src>.hits.json) und der Cache der
Messung (v8_measure.py, s1/v8a-<sha8>/<src>.npz). Nichts davon liegt im Repo; ausgegeben werden nur Zahlen.
Schreibt nichts, aendert tool/train_wake_word/ nicht.

  nice -n 10 ~/wendelin-models/kws/wp58/venv/bin/python -I tool/wake_parity_real.py <ausgabeordner> [--cache <s1-ordner>]
"""
import argparse, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "train_wake_word")); sys.path.insert(0, HERE)
import numpy as np
import real_split as R
import words_measure as W
import v8_measure as V

SR = 16000
DEV = ["huawei", "handy2"]
THR = [0.98, 0.995]
FLOOR = 0.5          # Cluster: zusammenhaengende Fenster ab diesem Wert (Spitze je Ereignis)
MATCH = 0.4          # s: Cluster gelten als dasselbe Ereignis, wenn sie sich auf +-MATCH s ueberlappen


def load_app(d, src):
    e = np.fromfile(f"{d}/{src}.ends.i32", dtype="int32")
    s = np.fromfile(f"{d}/{src}.scores.f32", dtype="float32")
    info = json.load(open(f"{d}/{src}.hits.json"))
    sk = info.get("skip", 0)
    for h in info["hits"]: h["end"] += sk                  # Zeit im Original (Test liess sk Samples weg)
    return ((e + sk) / SR).astype("float64"), s.astype("float64"), info


def load_ref(cache, src):
    z = np.load(f"{cache}/{src}.npz")
    k = src
    return z[f"{k}|t"].astype("float64"), z[f"{k}|s"].astype("float64")


def clusters(t, v, floor=FLOOR):
    """[(t_start, t_end, peak, t_peak)] aus zusammenhaengenden Fenstern >= floor (Luecke <= 1 Fenster)."""
    idx = np.where(v >= floor)[0]
    out, i = [], 0
    while i < len(idx):
        j = i
        while j + 1 < len(idx) and idx[j + 1] - idx[j] <= 2: j += 1
        seg = idx[i:j + 1]; p = seg[np.argmax(v[seg])]
        out.append((t[seg[0]], t[seg[-1]], float(v[p]), float(t[p]))); i = j + 1
    return out


def match(cs, ca):
    """Paare (script, app) mit ueberlappenden Clustern; Rest einzeln."""
    used, pairs, only_s = set(), [], []
    for s in cs:
        best = None
        for k, a in enumerate(ca):
            if k in used: continue
            if a[0] <= s[1] + MATCH and s[0] <= a[1] + MATCH:
                if best is None or abs(a[3] - s[3]) < abs(ca[best][3] - s[3]): best = k
        if best is None: only_s.append(s)
        else: used.add(best); pairs.append((s, ca[best]))
    return pairs, only_s, [a for k, a in enumerate(ca) if k not in used]


def pct(x, q): return float(np.percentile(x, q)) if len(x) else float("nan")


def hits_labels(ev, labels, word_set):
    own = [lb for lb in labels if lb["word"] in word_set]
    n = h = 0
    for lb in own:
        lo, hi = W.label_window(lb["start"], lb["end"], lb["status"])
        n += 1; h += any(lo <= t <= hi for t in ev)
    return h, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out"); ap.add_argument("--cache", default=None)
    ap.add_argument("--phases", nargs="*", default=[], help="weitere Ausgabeordner des Tests mit WENDELIN_PARITY_SKIP (Rasterphase)")
    a = ap.parse_args()
    cache = a.cache or f"{V.RES}/s1/v8a-bfeb939d"
    labels = V.filter_labels(W.read_labels())
    hr = {s: V.hours(s) for s in W.NEG_SRC if s.startswith("neg_")}
    allpair = []
    print("Cluster-Spitzen (Floor %.2f) je Quelle: Paare, nur Skript, nur App (jeweils mit Spitze >= 0,9)" % FLOOR)
    for src in [f"pos_{d}" for d in DEV] + [f"neg_{d}" for d in DEV]:
        ts, vs = load_ref(cache, src); ta, va, info = load_app(a.out, src)
        cs, ca = clusters(ts, vs), clusters(ta, va)
        pairs, os_, oa = match(cs, ca)
        big = [(s, p) for s, p in pairs if max(s[2], p[2]) >= 0.9]
        d = np.array([p[2] - s[2] for s, p in big])
        allpair += [(src, s, p) for s, p in big]
        print(f"{src}: Cluster Skript {len(cs)}, App {len(ca)}, Paare {len(pairs)}, Paare>=0,9 {len(big)}; "
              f"nur Skript>=0,9 {sum(c[2] >= .9 for c in os_)}, nur App>=0,9 {sum(c[2] >= .9 for c in oa)}; "
              f"Fenster Skript {len(ts)} App {len(ta)}; Block {info['frame']} Samples")
        if len(d):
            print(f"   Abw. App-Skript (>=0,9): mittel {d.mean():+.5f}, max |.| {np.abs(d).max():.5f}, p95 |.| {pct(np.abs(d), 95):.5f}, n={len(d)}")
    d = np.array([p[2] - s[2] for _, s, p in allpair])
    if len(d):
        print(f"GESAMT Paare mit Spitze >= 0,9: n={len(d)}, max |.| {np.abs(d).max():.5f}, p95 |.| {pct(np.abs(d), 95):.5f}, "
              f"p50 |.| {pct(np.abs(d), 50):.5f}")
    print("\nTreffer (Wendelin + Hey Wendelin, Stufe 1, Label-Fenster) und FA/h (Stufe 1) je Geraet")
    for dev in DEV:
        L = [lb for lb in labels if lb["dev"] == dev]
        ts, vs = load_ref(cache, f"pos_{dev}"); ta, va, ip = load_app(a.out, f"pos_{dev}")
        tns, vns = load_ref(cache, f"neg_{dev}"); tna, vna, ineg = load_app(a.out, f"neg_{dev}")
        h = hr[f"neg_{dev}"]
        for thr in THR:
            evs, eva = W.score_events(ts, vs, thr), W.score_events(ta, va, thr)
            ens, ena = W.score_events(tns, vns, thr), W.score_events(tna, vna, thr)
            eng_p = [x["end"] / SR for x in ip["hits"] if (x["score"] or 0) >= thr]
            eng_n = [x["end"] / SR for x in ineg["hits"] if (x["score"] or 0) >= thr]
            row = []
            for nm, p, n_ in (("Skript", evs, ens), ("App roh", eva, ena), ("App-Engine", eng_p, eng_n)):
                hh, nn = hits_labels(p, L, W.WORDS_ALL if hasattr(W, "WORDS_ALL") else {"Wendelin", "Hey Wendelin"})
                row.append(f"{nm}: {hh}/{nn} Treffer, FA {len(n_)} = {len(n_) / h:.2f}/h")
            print(f"{dev} @{thr}: " + " | ".join(row))
    if a.phases:
        print("\nPhasenstreuung App (Raster gegen die Sprache verschoben): Treffer Stufe 1 / FA je Geraet und Schwelle, App roh | App-Engine")
        for dev in DEV:
            L = [lb for lb in labels if lb["dev"] == dev]
            for thr in THR:
                cells = []
                for d in [a.out] + a.phases:
                    ta, va, ip = load_app(d, f"pos_{dev}"); tna, vna, ineg = load_app(d, f"neg_{dev}")
                    sk = ip.get("skip", 0)
                    hh, nn = hits_labels(W.score_events(ta, va, thr), L, {"Wendelin", "Hey Wendelin"})
                    he, _ = hits_labels([x["end"] / SR for x in ip["hits"] if (x["score"] or 0) >= thr], L, {"Wendelin", "Hey Wendelin"})
                    fa = len(W.score_events(tna, vna, thr)); fe = sum((x["score"] or 0) >= thr for x in ineg["hits"])
                    cells.append(f"skip {sk}: {hh}/{nn} FA {fa} | {he}/{nn} FA {fe}")
                print(f"{dev} @{thr}: " + "; ".join(cells))
    print("\nGrenzkreuzer (Spitze des Clusters auf einer Seite >= Schwelle, auf der anderen darunter)")
    for src in [f"pos_{d}" for d in DEV] + [f"neg_{d}" for d in DEV]:
        ts, vs = load_ref(cache, src); ta, va, _ = load_app(a.out, src)
        pairs, os_, oa = match(clusters(ts, vs), clusters(ta, va))
        for thr in THR:
            cross = [(s, p) for s, p in pairs if (s[2] >= thr) != (p[2] >= thr)]
            cross_o = [c for c in os_ if c[2] >= thr] + [c for c in oa if c[2] >= thr]
            print(f"{src} @{thr}: gekreuzt {len(cross)}" + "".join(f" [Skript {s[2]:.4f}/App {p[2]:.4f} bei {s[3]:.1f}s]" for s, p in cross)
                  + f"; ohne Gegenstueck {len(cross_o)}")


if __name__ == "__main__":
    main()
