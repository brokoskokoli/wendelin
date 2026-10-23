#!/usr/bin/env python3
"""WP129 Spitzenwert-Halten und verlorene Rufe auf den echten Pruef-Aufnahmen.

Eingang: Ausgabeordner <ordner>/p<skip>/d<N>/ des Tests app/test/platform/wake_classifier_real_parity_test.dart
(WENDELIN_PARITY_DROPS=1,2,99,1goff,…, je Rasterphase WENDELIN_PARITY_SKIP) und der Cache der Messung. Gibt nur Zahlen aus,
schreibt nichts, Aufnahmen liegen nie im Repo.

  nice -n 10 ~/wendelin-models/kws/wp58/venv/bin/python -I tool/wake_hold_real.py <ordner> [--lost N [--phase SKIP]]
Ohne --lost: Tabelle je Gerät und N (Mittel und Spanne ueber die Phasen). Mit --lost: je Label, das im Skript >= 0,98
erreicht, in der App-Engine (dropsToEnd N, Phase SKIP) aber keinen Treffer hat, die Belege fuer die Ursache.
"""
import argparse, glob, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "train_wake_word")); sys.path.insert(0, HERE)
import numpy as np
import soundfile as sf
import words_measure as W
import v8_measure as V
import wake_parity_real as P

SR = 16000
DEV = ["huawei", "handy2"]
WORDS = {"Wendelin", "Hey Wendelin"}
AUDIO = os.path.expanduser("~/wendelin-models/kws/wp121/work")
LO, HI = 0.98, 0.999


def engine_hits(d, src):
    _, _, info = P.load_app(d, src)
    return [(h["end"] / SR, h["score"] or 0.0, h["direct"]) for h in info["hits"]]


def first_in_cluster(t, v, t_hit, floor=LO):
    """Zeit des ersten Fensters >= floor in der Folge direkt vor dem Treffer (Luecke <= 1 Fenster)."""
    i = int(np.searchsorted(t, t_hit - 1e-6))
    i = min(i, len(t) - 1)
    j = i
    while j > 0 and (v[j - 1] >= floor or (j > 1 and v[j - 2] >= floor)) and t[i] - t[j - 1] < 1.0: j -= 1
    while j < i and v[j] < floor: j += 1
    return float(t[j])


def per_label(cache, dirp, dev, labels, ref):
    ts, vs = ref
    ta, va, _ = P.load_app(dirp, f"pos_{dev}")
    hits = engine_hits(dirp, f"pos_{dev}")
    rows = []
    for lb in labels:
        lo, hi = W.label_window(lb["start"], lb["end"], lb["status"])
        m = (ts >= lo) & (ts <= hi); ma = (ta >= lo) & (ta <= hi)
        sp = float(vs[m].max()) if m.any() else 0.0
        ap = float(va[ma].max()) if ma.any() else 0.0
        hs = [h for h in hits if lo <= h[0] <= hi]
        best = max(hs, key=lambda h: h[1]) if hs else None
        rows.append(dict(lb=lb, lo=lo, hi=hi, script=sp, raw=ap, hits=hs, best=best, ta=ta, va=va))
    return rows


def summarize(rows):
    n = len(rows)
    direct = sum(1 for r in rows if any(h[2] for h in r["hits"]))
    d995 = sum(1 for r in rows if any(h[1] >= HI for h in r["hits"]))
    band = sum(1 for r in rows if r["hits"] and not any(h[2] for h in r["hits"]))
    lost = sum(1 for r in rows if r["script"] >= LO and not r["hits"])
    lost_raw = sum(1 for r in rows if r["raw"] >= LO and not r["hits"])
    reach = sum(1 for r in rows if r["script"] >= LO)
    lat = []
    for r in rows:
        if r["best"]:
            t0 = first_in_cluster(r["ta"], r["va"], r["best"][0])
            lat.append((r["best"][0] - t0) * 1000)
    return n, d995, direct, band, lost, lost_raw, reach, lat


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("root"); ap.add_argument("--lost"); ap.add_argument("--phase", type=int, default=0)
    a = ap.parse_args()
    cache = f"{V.RES}/s1/v8a-bfeb939d"
    labels = [lb for lb in V.filter_labels(W.read_labels()) if lb["word"] in WORDS]
    hrs = {s: V.hours(s) for s in W.NEG_SRC if s.startswith("neg_")}
    phases = sorted(int(os.path.basename(p)[1:]) for p in glob.glob(f"{a.root}/p[0-9]*"))
    ns = sorted((os.path.basename(p)[1:] for p in glob.glob(f"{a.root}/p{phases[0]}/d*")), key=lambda x: (int(re.match(r'\d+', x)[0]), x))
    if a.lost is not None:
        return lost(a, cache, labels)
    print(f"Phasen (skip): {phases}; N: {ns}; Schwellen: Band {LO}..{HI}")
    print("Je Geraet und N: Direkt-Treffer (Engine-Flag, Band bis 0,999) | Band-Treffer | verloren (Skript>=0,98, kein Treffer) | FA direkt/Band (je 0,61 h) | Zusatzlatenz ms")
    for dev in DEV:
        L = [lb for lb in labels if lb["dev"] == dev]; ref = P.load_ref(cache, f"pos_{dev}")
        for n in ns:
            S, F, LAT, SL = [], [], [], []
            for ph in phases:
                d = f"{a.root}/p{ph}/d{n}"
                rows = per_label(cache, d, dev, L, ref)
                S.append(summarize(rows)); LAT += summarize(rows)[7]
                doff = f"{a.root}/p{ph}/d{n}goff"
                if n.isdigit() and os.path.isdir(doff):
                    ro = per_label(cache, doff, dev, L, ref)
                    SL.append(sum(1 for x, y in zip(rows, ro) if y["hits"] and not x["hits"]))
                nh = engine_hits(d, f"neg_{dev}")
                F.append((sum(h[2] for h in nh), sum(1 for h in nh if not h[2])))
            f = lambda i: f"{np.mean([s[i] for s in S]):.1f} ({min(s[i] for s in S)}-{max(s[i] for s in S)})"
            fa = lambda i: f"{np.mean([x[i] for x in F]):.1f} ({min(x[i] for x in F)}-{max(x[i] for x in F)})"
            print(f"{dev} N={n:<7} n={S[0][0]} Skript>=0,98: {S[0][6]} | direkt {f(1)} | Band {f(3)} | verloren {f(4)} (App roh>=0,98 ohne Treffer {f(5)}) "
                  f"| durch Stille-Sperre verloren {SL if SL else '-'} | FA direkt {fa(0)}, Band {fa(1)} | Latenz {np.mean(LAT):.0f} ms (max {np.max(LAT):.0f}, n={len(LAT)})")


def rms_blocks(path, ts0):
    x, sr = sf.read(path, dtype="int16", always_2d=False); assert sr == SR
    n = len(x) // 320
    b = x[:n * 320].astype("float64").reshape(n, 320)
    return np.sqrt((b ** 2).mean(axis=1))


def lost(a, cache, labels):
    """Labels, die im Skript >= 0,98 erreichen, in der Engine (N, Katalog-Sperre) aber keinen Treffer haben; je Fall die Ursache:
    gleiche Engine ohne Stille-Sperre (d<N>goff) trifft = Stille-Sperre; sonst Raster/Halten/Sperre (1,5 s)."""
    ph = a.phase; d = f"{a.root}/p{ph}/d{a.lost}"; doff = f"{a.root}/p{ph}/d{a.lost}goff"
    for dev in DEV:
        L = [lb for lb in labels if lb["dev"] == dev]; ref = P.load_ref(cache, f"pos_{dev}")
        rows = per_label(cache, d, dev, L, ref)
        roff = per_label(cache, doff, dev, L, ref) if os.path.isdir(doff) else None
        rms = rms_blocks(f"{AUDIO}/all_{dev}.wav", 0)
        for i, r in enumerate(rows):
            if not (r["script"] >= LO and not r["hits"]): continue
            lb = r["lb"]
            off_hit = roff is not None and bool(roff[i]["hits"])
            a0, b0 = int(lb["start"] * SR / 320), int(lb["end"] * SR / 320) + 1
            pk = rms[a0:b0].max() if b0 > a0 else 0
            cause = "Stille-Sperre (ohne Sperre trifft die Engine)" if off_hit else "nicht die Stille-Sperre (Raster, Halten oder Sperre von 1,5 s)"
            print(f"{dev} {lb['word']} bei {lb['start']:.1f}-{lb['end']:.1f}s: Skript {r['script']:.4f}, App roh {r['raw']:.4f}, Spitzenpegel im Label {pk:.0f} RMS -> {cause}")


if __name__ == "__main__":
    main()
