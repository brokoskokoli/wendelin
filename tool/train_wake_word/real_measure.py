#!/usr/bin/env python3
"""WP106 Teil 1b: Wake Word im Stationsmodus mit ECHTEN Aufnahmen (Messung, kein App-Code).

Aufruf (ein Kommando; Daten bleiben lokal, nie ins Repo):
  K=~/wendelin-models/kws; nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/real_measure.py [--out $K/wp106/results/real]
Eingaben: ~/wendelin-fixtures/wake/station/{pos,neg}/{station,mobile}/*.wav (16 kHz mono, zwei Handys gleichzeitig).
Schritte: (1) Geraete per Kreuzkorrelation (Energiehuellen) ausrichten, (2) Positiv-Datei per Energie-VAD in Aeusserungen
schneiden, Bedingungen nur dort zuordnen, wo die Segmentzahl zur ANLEITUNG-Tabelle passt (BLOCKS, geprueft ueber Segmentzahl),
(3) Negativ-Datei mit whisper-medium (unabhaengig) nach "Wendelin"/Verwechslern absuchen (nur Zeitstempel),
(4) Einlernen: Segmente 1-5 (Clips 01-05) = Vorlagen + CAM++-Profil je Geraet, Test nur auf den uebrigen,
(5) Stufe 1 (Vorlage/Modell v7), Stufe 2 (Whisper small, Parakeet ohne/Hotword 1/2/3), Stufe 3 (CAM++), je Geraet.
Treffer % je Geraet/Bedingung, FA/h aus der Negativ-Datei (echte Wendelin-Aeusserungen und Verwechsler laut whisper-medium
auf dem Ereignis-Segment getrennt ausgewiesen). Labels kommen aus Reihenfolge/Segmentzahl, nie aus dem gemessenen Erkenner.
Zwischendaten nur unter ~/wendelin-models/kws/wp106/work.
"""
import argparse, csv, json, os, re, sys, time
import numpy as np
import soundfile as sf
from scipy.ndimage import minimum_filter1d, uniform_filter1d
from scipy.signal import fftconvolve

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import common as C                      # noqa: E402
import kws_measure as K                 # noqa: E402
import station_measure as S             # noqa: E402

SR = C.SR
DIR = os.path.expanduser("~/wendelin-fixtures/wake/station")
FR = 320                                 # VAD-Rahmen (20 ms)
FPS = SR // FR
CTX = 0.9                                # Kontext um ein Positiv-Segment (s), kleiner als die Mindestluecke
# Zuordnung nach Segmentindex (1-basiert) bei erwarteter Gesamtzahl EXPECT_SEGS (sonst Abbruch):
SURE = {"satz2m": [16, 17, 20, 21], "kueche": [32, 33, 34, 35], "schnell": [46, 47]}      # Clips 11-14, 19-22, 29-30
REST = {"rest3m": range(6, 16), "restTV": range(22, 32), "restLeise": range(36, 46)}     # unsicher: mehr Segmente als Clips
ENROLL = [1, 2, 3, 4, 5]
EXPECT_CLIPS = {"rest3m": 5, "restTV": 4, "restLeise": 6}   # laut ANLEITUNG (06-10, 15-18, 23-28)
NEG_REFR = 38                            # Sperrzeit Negativ-Ereignisse (Fenster a 80 ms, ~3 s); Positiv 19 (~1,5 s)
EXPECT_SEGS = 47
WENDELIN = re.compile(r"w[eiu]nd[eao]l[iyu]n|wendeline|vendelin|gwendolin")
CONFUSER = re.compile(r"wendel|windel|berlin|vanill|linie|wendolin|gwendol|wenn die")


def load(p):
    x, sr = sf.read(p, dtype="float32")
    assert sr == SR
    return x if x.ndim == 1 else x.mean(axis=1)


def env(x, f=160):
    n = len(x) // f
    e = np.sqrt((x[:n * f].reshape(n, f) ** 2).mean(1)); return e - e.mean()


def lag_samples(a, b):
    """a_abs = b_abs + lag. Ueber Energiehuellen (10 ms)."""
    ea, eb = env(a), env(b)
    c = fftconvolve(ea, eb[::-1])
    k = int(np.argmax(c)); q = c[k] / np.sqrt((ea ** 2).sum() * (eb ** 2).sum() + 1e-12)
    return (k - (len(eb) - 1)) * 160, float(q)


def level_db(x):
    n = len(x) // FR
    e = 20 * np.log10(np.sqrt((x[:n * FR].reshape(n, FR) ** 2).mean(1)) + 1e-9)
    e = uniform_filter1d(e, 3)
    fl = uniform_filter1d(minimum_filter1d(uniform_filter1d(e, 25), 6 * FPS), 2 * FPS)
    return e - fl


def segment(ra, rb, off=10.0, gap_s=1.0, min_s=0.16):
    act = (ra > off) | (rb > off); gap = int(gap_s * FPS)
    idx = np.where(act)[0]; segs = []; s = p = idx[0]
    for i in idx[1:]:
        if i - p > gap: segs.append((s, p)); s = i
        p = i
    segs.append((s, p))
    return [(s, p) for s, p in segs if p - s >= min_s * FPS]


def cut(x, e, pre=2.0, post=S.TAIL):
    lo, hi = e - int(pre * SR), e + int(post * SR)
    out = np.zeros(hi - lo, "float32")
    a, b = max(lo, 0), min(hi, len(x))
    if b > a: out[a - lo:b - lo] = x[a:b]
    return out


# ---------- Negativ-Scan mit whisper-medium ----------
def scan_neg(dev, x, rec, cache, win=24, hop=20):
    """Fenster ohne Sprache (<3 % aktive Rahmen) werden uebersprungen; Transkripte werden gecacht."""
    sc = json.load(open(cache)) if os.path.exists(cache) else {}
    act = level_db(x) > 10
    for t in range(0, max(1, int(len(x) / SR - 2)), hop):
        k = str(t)
        if k not in sc:
            if act[t * FPS:(t + win) * FPS].mean() < 0.03: sc[k] = ""; continue
            sc[k] = S.decode(rec, x[t * SR:(t + win) * SR]); json.dump(sc, open(cache, "w"))
    return {int(k): v for k, v in sc.items()}


def finds(sc, rx):
    return sorted(k for k, v in sc.items() if rx.search(S.K.fold(v) if hasattr(S.K, "fold") else v.lower()))


# ---------- Stufe 1 ----------
class Stage1:
    def __init__(self):
        import onnxruntime as ort
        self.af = C.make_features(f"{S.KWS}/wp58/dl/oww", 1)
        so_ = ort.SessionOptions(); so_.intra_op_num_threads = 1
        self.sess = ort.InferenceSession(f"{S.KWS}/wp58/out/wendelin_v7.onnx", so_, providers=["CPUExecutionProvider"])

    def windows(self, x, chunk=120, ov=3):
        """(V, we, ms) fuer x; we = Fensterende in Samples von x. Chunks mit Ueberlappung, damit der Speicher klein bleibt."""
        Vs, wes, mss = [], [], []
        step = chunk * SR; keep = 0
        for st in range(0, max(len(x), 1), step):
            lo = max(0, st - ov * SR); y = np.concatenate([np.zeros(SR, "float32"), x[lo:st + step + 0], np.zeros(SR, "float32")])
            emb = C.embed(self.af, [y])[0]
            n = len(emb) - C.WIN + 1
            if n <= 0: continue
            W = np.stack([emb[j:j + C.WIN] for j in range(n)]).astype("float32")
            ms = self.sess.run(None, {"input": W})[0][:, 0]
            V = W.reshape(n, -1); V = V / (np.linalg.norm(V, axis=1, keepdims=True) + 1e-9)
            we = np.array([C.window_end(j) for j in range(n)]) - SR + lo
            m = we >= st if st > 0 else np.ones(n, bool)
            m &= we < st + step
            Vs.append(V[m]); wes.append(we[m]); mss.append(ms[m])
        if not Vs: return np.zeros((0, 1)), np.zeros(0, int), np.zeros(0)
        return np.concatenate(Vs), np.concatenate(wes), np.concatenate(mss)


def events(ok, refr=19):
    ev, last = [], -10 ** 9
    for j in np.where(ok)[0]:
        if j - last >= refr: ev.append(int(j)); last = j
    return ev


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=f"{S.KWS}/wp106/results/real")
    ap.add_argument("--thr", default="0.85,0.90", help="Vorlagen-Schwellen")
    ap.add_argument("--model-thr", default="0.3,0.5")
    ap.add_argument("--spk-thr", default="0.45,0.52,0.60")
    ap.add_argument("--variants", default="whisper-small,parakeet,parakeet-hw1,parakeet-hw2,parakeet-hw3")
    ap.add_argument("--scan-only", action="store_true")
    ap.add_argument("--max-neg-min", type=float, default=0, help="Test: nur die ersten N Minuten der Negativ-Datei")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True); os.makedirs(S.WORK, exist_ok=True)
    t00 = time.time()
    log = lambda *s: print(f"[{time.time() - t00:6.0f}s]", *s, flush=True)
    DEV = ["station", "mobile"]
    pos = {d: load(f"{DIR}/pos/{d}/pos_{d}.wav") for d in DEV}
    neg = {d: load(f"{DIR}/neg/{d}/neg_{d}.wav") for d in DEV}
    if a.max_neg_min: neg = {d: x[:int(a.max_neg_min * 60 * SR)] for d, x in neg.items()}
    meta = {"params": vars(a)}

    # (1) Ausrichtung
    lag_p, q_p = lag_samples(pos["station"], pos["mobile"])
    m10 = 600 * SR
    lag_n0, q_n0 = lag_samples(neg["station"][:m10], neg["mobile"][:m10])
    en, mn = len(neg["station"]), len(neg["mobile"])
    lag_n1, q_n1 = lag_samples(neg["station"][en - m10:], neg["mobile"][mn - m10:])
    lag_n1 += (en - m10) - (mn - m10)
    lag_n = lag_n0
    meta["align"] = {"pos_lag_s": lag_p / SR, "pos_corr": q_p, "neg_lag_start_s": lag_n0 / SR, "neg_corr_start": q_n0,
                     "neg_lag_end_s": lag_n1 / SR, "neg_corr_end": q_n1, "neg_drift_s": (lag_n1 - lag_n0) / SR}
    log("Ausrichtung", meta["align"])

    # (3) Negativ-Scan mit whisper-medium (Fundstellen nur als Zeitstempel, Zeit der Station-Datei)
    import sherpa_onnx as so
    Md = f"{S.H}/wp102-models/whisper-medium"
    med = so.OfflineRecognizer.from_whisper(encoder=f"{Md}/medium-encoder.int8.onnx", decoder=f"{Md}/medium-decoder.int8.onnx",
                                            tokens=f"{Md}/medium-tokens.txt", language="de", num_threads=4)
    fold = lambda s: K.fold(s)
    tag = f"{int(a.max_neg_min)}" if a.max_neg_min else "full"
    SCAN_DEV = ["station"]          # Zeitbudget: Mitnahme-Datei hat dieselbe Tonquelle, nur die Station-Datei wird gescannt
    scans = {d: scan_neg(d, neg[d], med, f"{S.WORK}/real_negscan_{d}_{tag}.json") for d in SCAN_DEV}
    shift = {"station": 0.0, "mobile": lag_n / SR}              # Station-Zeit = Mobile-Zeit + lag
    fw, fc = [], []
    for d in SCAN_DEV:
        for t, txt in scans[d].items():
            f = fold(txt)
            if WENDELIN.search(f): fw.append((t + shift[d], d))
            elif CONFUSER.search(f): fc.append((t + shift[d], d))
    mm = lambda L: sorted({int(t // 20 * 20) for t, _ in L})            # 20-s-Raster
    meta["neg_scan"] = {"wendelin_t_s": mm(fw), "verwechsler_t_s": mm(fc),
                        "scanned_devices": SCAN_DEV}
    log("Negativ-Scan: Wendelin-Fenster", len(mm(fw)), "Verwechsler-Fenster", len(mm(fc)))
    json.dump(meta, open(f"{a.out}/real_meta.json", "w"), indent=1, default=str)
    if a.scan_only: return

    # (2) Segmentierung Positiv (Zeit der Station-Datei)
    n = min(len(pos["station"]), len(pos["mobile"]) + lag_p)
    mob = np.zeros(len(pos["station"]), "float32")                    # mobile auf Stationszeit
    src = pos["mobile"][max(0, -lag_p):]; dst = max(0, lag_p)
    mob[dst:dst + len(src)] = src[:len(mob) - dst]
    ra, rb = level_db(pos["station"][:n]), level_db(mob[:n])
    segs = segment(ra, rb)
    meta["pos_segments"] = len(segs)
    log("Positiv-Segmente", len(segs), "erwartet", EXPECT_SEGS)
    if len(segs) != EXPECT_SEGS:
        sys.exit(f"Segmentzahl {len(segs)} != {EXPECT_SEGS}: Zuordnung SURE/REST/ENROLL prueft sich gegen die Daten, bitte anpassen")
    info = []
    for k, (s, p) in enumerate(segs, 1):
        info.append({"i": k, "t": s / FPS, "dur": (p - s) / FPS, "lvl_station": float(ra[s:p + 1].max()),
                     "lvl_mobile": float(rb[s:p + 1].max())})
    groups = {}
    for g, idx in {**SURE, **REST}.items():
        groups[g] = [i for i in idx if (segs[i - 1][1] - segs[i - 1][0]) / FPS >= 0.4 and max(info[i - 1]["lvl_station"], info[i - 1]["lvl_mobile"]) >= 20]
    groups["sicher"] = [i for g in SURE for i in SURE[g]]
    groups["rest"] = [i for g in REST for i in groups[g]]
    meta["groups"] = groups; meta["enroll"] = ENROLL; meta["segments"] = info
    devaud = {"station": pos["station"], "mobile": mob}

    def clip(d, i):
        s, p = segs[i - 1]
        t0, t1 = int(s * FR - CTX * SR), int((p + 1) * FR + CTX * SR)
        x = devaud[d][max(0, t0):t1]
        return x, (p + 1) * FR - max(0, t0)               # Wortende (Samples im Clip)

    # (4)+(5) Stufe 1: Fenster
    s1 = Stage1()
    spk = S.make_spk()
    thrs = [float(t) for t in a.thr.split(",")]; mthrs = [float(t) for t in a.model_thr.split(",")]
    rules = {f"T{t}": ("T", t, None) for t in thrs}
    rules.update({f"M{m}": ("M", None, m) for m in mthrs})
    rules.update({f"T{thrs[0]}|M{m}": ("TM", thrs[0], m) for m in mthrs})
    PW, tmpl, prof = {}, {}, {}
    for d in DEV:
        T, E = [], []
        for i in ENROLL:
            x, end = clip(d, i)
            V, we, ms = s1.windows(x)
            j = int(np.argmax(we >= end + 0.3 * SR)) if (we >= end + 0.3 * SR).any() else len(we) - 1
            T.append(V[j]); E.append(S.embed(spk, cut(x, int(we[j]))))
        tmpl[d] = np.stack(T)
        pr = np.mean(E, axis=0); prof[d] = pr / np.linalg.norm(pr)
        for i in groups["sicher"] + groups["rest"]:
            PW[d, i] = s1.windows(clip(d, i)[0])
    log("Positiv-Fenster fertig")
    NW = {d: s1.windows(neg[d]) for d in DEV}
    log("Negativ-Fenster fertig", {d: len(NW[d][0]) for d in DEV})

    def cand(d, win, refr=19):
        V, we, ms = win
        if not len(V): return {r: [] for r in rules}
        t = (V @ tmpl[d].T).max(axis=1)
        out = {}
        for r, (kind, th, mt) in rules.items():
            ok = (t >= th) if kind == "T" else (ms >= mt) if kind == "M" else (t >= th) | (ms >= mt)
            out[r] = [int(we[j]) for j in events(ok, refr)]
        return out

    segs_audio, EV = {}, {}      # EV[(set, dev, id, rule)] = Segment-Schluessel; Audio je Ereignis nur einmal (Cache ueber Regeln)
    for d in DEV:
        for (dd, i), win in PW.items():
            if dd != d: continue
            x = clip(d, i)[0]
            for r, es in cand(d, win).items():
                EV[("pos", d, i, r)] = []
                for e in es[:3]:
                    key = ("pos", d, i, e); segs_audio.setdefault(key, cut(x, e)); EV[("pos", d, i, r)].append(key)
        for r, es in cand(d, NW[d], NEG_REFR).items():
            EV[("neg", d, 0, r)] = []
            for e in es:
                key = ("neg", d, 0, e); segs_audio.setdefault(key, cut(neg[d], e)); EV[("neg", d, 0, r)].append(key)
    keys = list(segs_audio)
    log("Segmente fuer Stufe 2/3:", len(keys), {d: sum(k[0] == "neg" and k[1] == d for k in keys) for d in DEV}, "Ereignisse je Regel", {r: sum(len(v) for kk, v in EV.items() if kk[0] == "neg" and kk[3] == r) for r in rules})

    # Stufe 2 (+ whisper-medium zur Einordnung der Negativ-Ereignisse) und Stufe 3
    variants = a.variants.split(",")
    text = {}
    for v in variants:
        r = S.make_rec(v)
        text[v] = {k: S.decode(r, segs_audio[k]) for k in keys}
        log(v, "fertig", len(keys)); del r
    # whisper-medium nur auf Negativ-Ereignissen, die irgendeine Stufe-2-Variante durchlaesst (Zeitbudget)
    mk = [k for k in keys if k[0] == "neg" and any(K.matches_wake_word(text[v][k], 1) for v in variants)]
    text["medium"] = {k: S.decode(med, segs_audio[k]) for k in mk}
    log("medium auf", len(mk), "Negativ-Ereignissen")
    emb = {k: S.embed(spk, segs_audio[k]) for k in keys}
    cls = {}
    for k in keys:
        if k[0] != "neg": continue
        if k not in text["medium"]: cls[k] = "fa"; continue          # von keiner Variante durchgelassen: nur Stufe-1-Zeilen betroffen
        f = fold(text["medium"][k])
        cls[k] = "echt" if WENDELIN.search(f) else "verwechsler" if CONFUSER.search(f) else "fa"
    cos = lambda k: float(emb[k] @ prof[k[1]])
    log("Stufe-2-Modelle laden/decodieren beginnt")
    pct = lambda L: {p: round(float(np.percentile(L, p)), 2) for p in (5, 25, 50, 75, 95)} if L else {}
    lowr = f"T{thrs[0]}"        # weiteste Stufe-1-Regel
    meta["cos_dist"] = {d: {"eigene Stimme (Positiv-Kandidaten, Stufe 1 weit)": pct([cos(k) for k in EV.get(("pos", d, i, lowr), []) for i in groups["sicher"] + groups["rest"]]),
                            "Negativ-Ereignisse (TV/Gespraech, kein echtes Wendelin)": pct([cos(k) for k in EV[("neg", d, 0, lowr)] if cls[k] != "echt"]),
                            "Negativ-Ereignisse echtes Wendelin (laut medium)": pct([cos(k) for k in EV[("neg", d, 0, lowr)] if cls[k] == "echt"])} for d in DEV}
    log("Cosinus", json.dumps(meta["cos_dist"]))

    # Aggregation
    spks = [None] + [float(s) for s in a.spk_thr.split(",")]
    gnames = ["sicher", "satz2m", "kueche", "schnell", "rest", "rest3m", "restTV", "restLeise"]
    rows = []
    for d in DEV:
        hn = len(neg[d]) / SR / 3600
        for r in rules:
            for var in [None] + variants:
                for st in spks:
                    def ok(k):
                        if var and not K.matches_wake_word(text[var][k], 1): return False
                        return st is None or cos(k) >= st
                    row = {"device": d, "stage1": r, "stage2": var or "-", "spk": st if st is not None else "-"}
                    for g in gnames:
                        ids = groups[g]
                        hits = sum(any(ok(k) for k in EV.get(("pos", d, i, r), [])) for i in ids)
                        row[f"hit_{g}"] = round(100 * hits / max(len(ids), 1), 1); row[f"n_{g}"] = len(ids)
                    for g, nexp in EXPECT_CLIPS.items():      # bestaetigte Ereignisse im Block / erwartete Clips (max. 100 %)
                        nev = sum(1 for i in groups[g] for k in EV.get(("pos", d, i, r), []) if ok(k))
                        row[f"ev_{g}"] = round(min(100.0, 100 * nev / nexp), 1)
                    nk = [k for k in EV[("neg", d, 0, r)] if ok(k)]
                    for c in ("fa", "verwechsler", "echt"):
                        row[f"{c}_h" if c != "echt" else "echt_n"] = round(sum(cls[k] == c for k in nk) / hn, 2) if c != "echt" else sum(cls[k] == c for k in nk)
                    row["neg_h"] = round(hn, 3)
                    rows.append(row)
    with open(f"{a.out}/real_table.csv", "w", newline="") as f:
        w = csv.DictWriter(f, list(rows[0])); w.writeheader(); w.writerows(rows)
    with open(f"{a.out}/real_table.md", "w") as f:
        f.write("| Geraet | Stufe 1 | Stufe 2 | Sprecher | sicher % (n=10) | Satz2m | Kueche | schnell | Rest % (unsicher) | Ereign./Clips 3m, TV, leise % | FA/h | Verwechsler/h | echt n |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n")
        for r in rows:
            f.write(f"| {r['device']} | {r['stage1']} | {r['stage2']} | {r['spk']} | {r['hit_sicher']} | {r['hit_satz2m']} | {r['hit_kueche']} | {r['hit_schnell']} | {r['hit_rest']} | {r['ev_rest3m']}/{r['ev_restTV']}/{r['ev_restLeise']} | {r['fa_h']} | {r['verwechsler_h']} | {r['echt_n']} |\n")
    json.dump(meta, open(f"{a.out}/real_meta.json", "w"), indent=1, default=str)
    json.dump({v: {"|".join(map(str, k)): t for k, t in dct.items()} for v, dct in text.items()}, open(f"{S.WORK}/real_texts.json", "w"))
    log("fertig ->", a.out)


if __name__ == "__main__":
    main()
