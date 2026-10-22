#!/usr/bin/env python3
"""WP129 Spitzenwert-Halten und verlorene Rufe auf den echten Pruef-Aufnahmen.

Eingang: Ausgabeordner <ordner>/p<skip>/d<N>/ des Tests app/test/platform/wake_classifier_real_parity_test.dart
(WENDELIN_PARITY_DROPS=1,2,99, je Rasterphase WENDELIN_PARITY_SKIP) und der Cache der Messung. Gibt nur Zahlen aus,
schreibt nichts, Aufnahmen liegen nie im Repo.

  nice -n 10 ~/wendelin-models/kws/wp58/venv/bin/python -I tool/wake_hold_real.py <ordner> [--lost N [--phase SKIP]]
Ohne --lost: Tabelle je Gerät und N (Mittel und Spanne ueber die Phasen). Mit --lost: je Label, das im Skript >= 0,98
erreicht, in der App-Engine (dropsToEnd N, Phase SKIP) aber keinen Treffer hat, die Belege fuer die Ursache.
"""
import argparse, glob, os, sys
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
    ns = sorted((os.path.basename(p)[1:] for p in glob.glob(f"{a.root}/p{phases[0]}/d*")), key=lambda x: (int(x.split('g')[0]), x))
    if a.lost is not None:
        return lost(a, cache, labels)
    print(f"Phasen (skip): {phases}; N: {ns}; Schwellen: Band {LO}..{HI}")
    print("Je Geraet und N: Direkt-Treffer (Engine-Flag, Band bis 0,999) | Band-Treffer | verloren (Skript>=0,98, kein Treffer) | FA direkt/Band (je 0,61 h) | Zusatzlatenz ms")
    for dev in DEV:
        L = [lb for lb in labels if lb["dev"] == dev]; ref = P.load_ref(cache, f"pos_{dev}")
        for n in ns:
            S, F, LAT = [], [], []
            for ph in phases:
                d = f"{a.root}/p{ph}/d{n}"
                rows = per_label(cache, d, dev, L, ref)
                S.append(summarize(rows)); LAT += summarize(rows)[7]
                nh = engine_hits(d, f"neg_{dev}")
                F.append((sum(h[2] for h in nh), sum(1 for h in nh if not h[2])))
            f = lambda i: f"{np.mean([s[i] for s in S]):.1f} ({min(s[i] for s in S)}-{max(s[i] for s in S)})"
            fa = lambda i: f"{np.mean([x[i] for x in F]):.1f} ({min(x[i] for x in F)}-{max(x[i] for x in F)})"
            print(f"{dev} N={n:<7} n={S[0][0]} Skript>=0,98: {S[0][6]} | direkt {f(1)} | Band {f(3)} | verloren {f(4)} (App roh>=0,98 ohne Treffer {f(5)}) "
                  f"| FA direkt {fa(0)}, Band {fa(1)} | Latenz {np.mean(LAT):.0f} ms (max {np.max(LAT):.0f}, n={len(LAT)})")


def rms_blocks(path, ts0):
    x, sr = sf.read(path, dtype="int16", always_2d=False); assert sr == SR
    n = len(x) // 320
    b = x[:n * 320].astype("float64").reshape(n, 320)
    return np.sqrt((b ** 2).mean(axis=1))


def gate_trace(rms):
    """Nachbildung von SpeechGate (minRms 150, ratio 4, memory 800 ms = 40 Bloecke): (peak, floor) je Block."""
    peak = np.zeros(len(rms)); fl = np.zeros(len(rms)); f = -1.0
    for i, r in enumerate(rms):
        f = r if f < 0 else f + (r - f) * (0.2 if r < f else 0.002)
        fl[i] = f; peak[i] = rms[max(0, i - 39):i + 1].max()
    return peak, fl


def lost(a, cache, labels):
    ph = a.phase; d = f"{a.root}/p{ph}/d{a.lost}"
    for dev in DEV:
        L = [lb for lb in labels if lb["dev"] == dev]; ref = P.load_ref(cache, f"pos_{dev}")
        rows = per_label(cache, d, dev, L, ref)
        rms = rms_blocks(f"{AUDIO}/all_{dev}.wav", 0)  # Phase: Test lässt skip Samples weg, Zeiten sind Original (load_app addiert skip)
        peak, fl = gate_trace(rms[ph // 320:])
        sk = ph / SR
        hits = engine_hits(d, f"pos_{dev}")
        for r in rows:
            if not (r["script"] >= LO and not r["hits"]): continue
            lb = r["lb"]; ta, va = r["ta"], r["va"]
            ma = (ta >= r["lo"]) & (ta <= r["hi"]); idx = np.where(ma & (va >= LO))[0]
            print(f"{dev} {lb['word']} bei {lb['start']:.1f}-{lb['end']:.1f}s ({lb['status']}): Skript-Spitze {r['script']:.4f}, App roh-Spitze {r['raw']:.4f}, Fenster >=0,98 der App: {len(idx)}")
            ctx = [(h[0], h[1]) for h in hits if r["lo"] - 2 <= h[0] <= r["hi"] + 0.5]
            print(f"    Engine-Treffer im Umfeld (-2 s .. +0,5 s): {[(round(t,2), round(s,4)) for t, s in ctx]}")
            act = []
            for i in idx:
                k = min(max(int(round((ta[i] - sk) * SR / 320)) - 1, 0), len(peak) - 1)
                act.append(peak[k] >= max(150, 4 * fl[k]))
            lock = [h for h in ctx if h[0] > r["lo"] - 1.5 and h[0] < ta[idx[0]] if len(idx)] if len(idx) else []
            if not len(idx): cause = "Raster/Phase: App roh nie >= 0,98 (Skript-Spitze nur im Skript-Raster)"
            elif lock: cause = "Sperre (Treffer %s innerhalb 1,5 s davor)" % [round(h[0], 2) for h in lock]
            elif not any(act): cause = "Pegel-Gate: in keinem Fenster >= 0,98 aktiv"
            else: cause = "Halten/Gate: Gate nur in %d von %d Fenstern aktiv, Entscheidung fiel auf ein geschlossenes" % (sum(act), len(act))
            print(f"    URSACHE: {cause}")
            for i in idx[:4]:
                k = int(round((ta[i] - sk) * SR / 320)) - 1
                k = min(max(k, 0), len(peak) - 1)
                print(f"    Fenster {ta[i]:.2f}s Score {va[i]:.4f}: Gate-Spitze {peak[k]:.0f} RMS, Rauschboden {fl[k]:.0f}, Schwelle max(150, 4*Boden)={max(150, 4*fl[k]):.0f} -> {'aktiv' if peak[k] >= max(150, 4*fl[k]) else 'ZU'}")


if __name__ == "__main__":
    main()
