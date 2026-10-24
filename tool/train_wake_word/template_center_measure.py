#!/usr/bin/env python3
"""WP134 Teil B: Vorlagen-Vergleich fuer „Wendelin“ (Kosinus der 1536er-Fenster gegen die Einlern-Vorlagen) zentrieren? Nur Messung.

Bildet den App-Weg nach: Merkmalskette wie wake_feature_chain.dart (80-ms-Bloecke, 480 Samples Kontext, Mel x/10+2, Embedding je 76 Mel-Frames,
Fenster = 16 Embeddings, Fensterende = Blockende), Einlernen wie wake_enroller.dart embedUtterance (1 s / 2 s Stille-Polster, Fenster mit Ende
300 ms nach dem Wortende), Vergleich wie wake_math/candidate_wake_engine._closest (hoechster Kosinus ueber die Vorlagen).
Varianten (Zentrieren: beide Seiten minus Mittel mu, dann Kosinus):
  V0 roh (heute) | V1 mu = Mittel ueber alle Einlern-Fenster (Wort + Hintergrund) | V2 mu = Mittel ueber neutrale Sprache (FLEURS dev)
  V2b mu = Mittel ueber neutrale Sprache, Rauschen und digitale Stille zu gleichen Teilen (alles fest, nicht aus Pruefdaten)
je mit Polster der Vorlagen „zero“ (digitale Nullen, wie heute) oder „noise“ (Rauschen mit dem Pegel der aufgenommenen Vorlaeufe).
Split (real_split.py): Vorlagen NUR huawei Block 1 bis 3, Wort „Wendelin“. Pruefung huawei Block 4 bis 6, handy2 Block 1 bis 6 (nie Einlernen),
echte Negativ-Aufnahmen, FLEURS test (Fernseher), digitale Stille, Rauschen, 300 Verwechsler (conf_say aus WP130). mu und Schwelle werden nie
auf Pruefclips gefittet: mu aus Einlern-Fenstern bzw. FLEURS dev; die Schwelle haengt nur an den Negativ-Aufnahmen (<= Ziel FA/h), nicht an den
Positiven; Gegenprobe: Schwelle vom jeweils anderen Geraet.

Venv wie die anderen Messungen (K=~/wendelin-models/kws):
  nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/template_center_measure.py run --threads 2 [--out <ordner>]
Arbeitsdaten (Fenster-Cache, Bericht) unter $K/wp134, nie im Repo. Selbsttest: test_template_center_measure.py.
"""
import argparse, csv, glob, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import real_split as R

SR = 16000
CHUNK = 1280
CTX = 480
MEL_FRAMES = 76
WIN = 16
FIRST_EMB = MEL_FRAMES // 8 + 1 - 1          # Block (0-basiert) des ersten Embeddings: 76 Frames sind nach Block 9 da
FIRST_WIN = FIRST_EMB + WIN - 1              # Block des ersten Fensters (24)
LEAD, TRAIL = SR, 2 * SR                     # Polster wie embedUtterance
TEMPLATE_OFFSET = int(0.3 * SR)              # templateOffset 300 ms
REFR = 1.5                                   # s zwischen zwei Ereignissen (wie words_measure)
KWS = os.path.expanduser("~/wendelin-models/kws")
FIX = os.path.expanduser("~/wendelin-fixtures/wake/words")
WORK121 = f"{KWS}/wp121/work"
WORKDIR = f"{KWS}/wp134"
OWW = f"{KWS}/wp58/dl/oww"
TRAIN_DEVICE, TRAIN_BLOCKS = "huawei", (1, 2, 3)
DEVICES = ("huawei", "handy2")
WORDS = ("Wendelin", "Hey Wendelin")
VARIANTS = ("V0", "V1", "V2", "V2b")
PADS = ("zero", "noise")


# ---------- reine Funktionen (Selbsttest) ----------
def window_end(k):
    """Fensterende (Samples im Strom) des k-ten Fensters: Blockende wie WakeWindow.endSample."""
    return (FIRST_WIN + k + 1) * CHUNK


def windows_from_emb(E):
    """(m,96) Embeddings -> (m-15,1536) Fenster (je 16 aufeinanderfolgende, aelteste zuerst)."""
    m = len(E)
    if m < WIN: return np.zeros((0, WIN * 96), "float32")
    idx = np.arange(m - WIN + 1)[:, None] + np.arange(WIN)[None, :]
    return E[idx].reshape(m - WIN + 1, WIN * 96).astype("float32")


def unit(V):
    """Zeilen auf Laenge 1; Nullzeile bleibt 0 (wie cosineSimilarity: 0 bei Nullvektor)."""
    n = np.linalg.norm(V, axis=-1, keepdims=True)
    return np.where(n > 0, V / np.maximum(n, 1e-30), 0.0).astype("float32")


def prep(V, mu):
    """Vergleichsvektoren: roh (mu None) oder zentriert, jeweils auf Laenge 1."""
    return unit(V if mu is None else V - mu)


def best_sim(W, T, mu, block=4096):
    """Hoechster Kosinus je Fenster ueber alle Vorlagen T (n_t,1536); W (n,1536)."""
    Tn = prep(T, mu)
    out = np.empty(len(W), "float32")
    for i in range(0, len(W), block):
        out[i:i + block] = (prep(W[i:i + block], mu) @ Tn.T).max(axis=1)
    return out


def events(t, v, thr, refr=REFR):
    """Zeiten der Ereignisse: Wert >= thr, danach fruehestens nach refr s das naechste (words_measure.score_events)."""
    out, last = [], -1e9
    for i in np.where(np.asarray(v) >= thr)[0]:
        if t[i] - last >= refr:
            out.append(float(t[i])); last = t[i]
    return out


def n_events(t, v, thr, refr=REFR):
    return len(events(t, v, thr, refr))


def wilson(k, n, z=1.96):
    if n == 0: return (0.0, 0.0)
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def poisson_upper(k, hours):
    from scipy.stats import chi2
    return float(chi2.ppf(0.975, 2 * (k + 1)) / 2 / max(hours, 1e-9))


def fa_limit(target, hours):
    return int(np.floor(target * hours + 1e-9))


def pick_threshold(grid, count_fn, allowed):
    """Niedrigster Wert der aufsteigenden grid mit count_fn(thr) <= allowed; None, wenn keiner."""
    for g in grid:
        if count_fn(g) <= allowed: return float(g)
    return None


def label_window(start, end, status):
    return (start - 0.5, end + 2.0) if status == "unsicher" else (start - 0.3, end + 1.2)


def is_train_row(r):
    """Einlern-Vorlage: huawei, Block 1 bis 3, nur „Wendelin“, ok (unsicher nur bis 2 s), wie real_split.is_train_clip."""
    try:
        return (r["geraet"] == TRAIN_DEVICE and int(r["block"]) in TRAIN_BLOCKS and r["wort"] == "Wendelin"
                and r["status"] in ("ok", "unsicher") and 0 < float(r["ende"]) - float(r["start"]) <= 2.0)
    except (KeyError, ValueError, TypeError):
        return False


def pruef_rows(labels):
    """Pruefclips: is_eval_row ohne Aufnahmen, die dieselbe Sitzung wie eine Trainingsaufnahme sind (real_split.paired_sessions, z. B. zweites Handy Block 1 bis 3)."""
    pairs = R.paired_sessions(labels)
    return [r for r in labels if is_eval_row(r) and (r["geraet"], int(r["block"])) not in pairs]


def is_eval_row(r):
    """Pruefclip: Wendelin / Hey Wendelin, nie huawei Block 1 bis 3, Status ok oder unsicher."""
    try:
        if r["status"] == "fehler" or r["wort"] not in WORDS or r["geraet"] not in DEVICES: return False
        return not (r["geraet"] == TRAIN_DEVICE and int(r["block"]) in TRAIN_BLOCKS)
    except (KeyError, ValueError, TypeError):
        return False


def capture_bounds(x, start, end, block=320, lead=10, tail=8):
    """pcm und speechEnd wie UtteranceCapture._finish: erster Sprachblock minus 200 ms bis letzter Block plus 160 ms.
    Erster / letzter Sprachblock aus den Labelzeiten (Blockraster)."""
    first, last = int(start * SR) // block, int(end * SR) // block
    a = max(0, (first - lead) * block)
    b = min(len(x), (last + 1 + tail) * block)
    return a, b, (last + 1) * block - a


def pad_stream(pcm, speech_end, pad, rng, lead=LEAD, trail=TRAIL):
    """Gepolsterter Einlern-Strom. pad: zero = digitale Nullen (heute), noise = weisses Rauschen mit dem RMS der ersten 200 ms von pcm."""
    pcm = np.asarray(pcm, "int16")
    if pad == "zero":
        p = np.zeros(lead + len(pcm) + trail, "int16")
        p[lead:lead + len(pcm)] = pcm
        return p, lead + speech_end
    lvl = float(np.sqrt(np.mean(pcm[:3200].astype("float64") ** 2))) if len(pcm) else 0.0
    mk = lambda n: np.clip(rng.normal(0, max(lvl, 1.0), n), -32768, 32767).astype("int16")
    return np.concatenate([mk(lead), pcm, mk(trail)]), lead + speech_end


def pick_window(n_win, target_end):
    """Index des Fensters, dessen Ende am naechsten an target_end liegt (erstes bei Gleichstand, wie embedUtterance)."""
    best, bd = None, None
    for k in range(n_win):
        d = abs(window_end(k) - target_end)
        if bd is None or d < bd: best, bd = k, d
    return best


# ---------- Merkmalskette (Port von wake_feature_chain.dart) ----------
class Chain:
    def __init__(self, threads=2, models=OWW):
        import onnxruntime as ort
        so = ort.SessionOptions(); so.intra_op_num_threads = threads
        mk = lambda n: ort.InferenceSession(f"{models}/{n}.onnx", so, providers=["CPUExecutionProvider"])
        self.mel, self.emb = mk("melspectrogram"), mk("embedding_model")

    def embeddings(self, x):
        """int16-Strom -> (m,96): ein Embedding je Block ab Block 9 (nach 76 Mel-Frames)."""
        x = np.asarray(x, "int16")
        n = len(x) // CHUNK
        if n < FIRST_EMB + 1: return np.zeros((0, 96), "float32")
        xf = np.concatenate([np.zeros(CTX, "float32"), x[:n * CHUNK].astype("float32")])
        frames = []
        for i in range(0, n, 2048):
            j = min(n, i + 2048)
            inp = np.stack([xf[c * CHUNK:c * CHUNK + CTX + CHUNK] for c in range(i, j)])
            frames.append(self.mel.run(None, {"input": inp})[0].reshape(j - i, 8, 32))
        M = np.concatenate(frames).reshape(n * 8, 32) / 10.0 + 2.0
        outs, cs = [], list(range(FIRST_EMB, n))
        for i in range(0, len(cs), 256):
            part = cs[i:i + 256]
            inp = np.stack([M[(c + 1) * 8 - MEL_FRAMES:(c + 1) * 8] for c in part])[..., None].astype("float32")
            outs.append(self.emb.run(None, {"input_1": inp})[0].reshape(len(part), 96))
        return np.concatenate(outs).astype("float32")


def win_times(n, pad=0):
    """Fensterende (s) der Fenster 0..n-1; pad = vorangestellte Samples."""
    return np.array([(window_end(k) - pad) / SR for k in range(n)])


# ---------- Audio ----------
def load16(path):
    import soundfile as sf
    x, sr = sf.read(path, dtype="float32", always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        n = int(len(x) * SR / sr)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype("float32")
    return x


def to16(x):
    return np.clip(np.round(np.asarray(x, "float64") * 32767), -32768, 32767).astype("int16")


def colored(n, power, rng):
    """Rauschen mit 1/f^power-Spektrum, auf RMS 1 normiert."""
    f = np.fft.rfftfreq(n, 1 / SR); f[0] = f[1]
    s = np.fft.irfft((rng.normal(size=len(f)) + 1j * rng.normal(size=len(f))) / f ** (power / 2), n)
    return s / (s.std() + 1e-12)


def read_labels():
    return list(csv.DictReader(open(f"{FIX}/labels/labels.csv", encoding="utf-8")))


# ---------- Cache der Embeddings ----------
class Cache:
    def __init__(self, chain, d=WORKDIR):
        self.chain, self.d = chain, f"{d}/cache"; os.makedirs(self.d, exist_ok=True)

    def get(self, name, make):
        """make() -> {clip: int16-Strom}; Ergebnis {clip: E} aus dem Cache (npz) oder neu gerechnet."""
        p = f"{self.d}/{name}.npz"
        if os.path.exists(p):
            z = np.load(p); return {k: z[k] for k in z.files}
        t0 = time.time(); out = {k: self.chain.embeddings(v) for k, v in make().items()}
        np.savez(p, **out); print(f"cache {name}: {len(out)} Teile, {time.time() - t0:.0f} s", flush=True)
        return out


def pad1(x): return np.concatenate([np.zeros(SR, "int16"), x, np.zeros(SR, "int16")])


def sources(rng_seed=134):
    """Fabriken der Pruef-/Negativquellen -> {name: callable -> {clip: int16}}; Stunden separat."""
    rng = np.random.default_rng(rng_seed)
    room = lambda n, lvl=10: to16(colored(n, 1.0, rng) * lvl / 32767)          # leiser Raum (rosa, RMS ~10 LSB)

    def pos(dev): return lambda: {dev: pad1(to16(load16(f"{WORK121}/all_{dev}.wav")))}
    def neg(dev): return lambda: {dev: to16(load16(f"{WORK121}/neg_{dev}.wav"))}

    def fleurs_test():
        out, tot = {}, 0.0
        for f in sorted(glob.glob(f"{KWS}/wp111/work/fleurs/test/*.wav")):
            if tot >= 1.0: break
            x = load16(f); x = x / (np.abs(x).max() + 1e-9)
            out[os.path.basename(f)] = to16(x); tot += len(x) / SR / 3600
        return out

    def fleurs_dev():
        out, tot = {}, 0.0
        for f in sorted(glob.glob(f"{WORKDIR}/fleurs_dev/dev/*.wav")):
            if tot >= 0.5: break
            x = load16(f); x = x / (np.abs(x).max() + 1e-9)
            out[os.path.basename(f)] = to16(x); tot += len(x) / SR / 3600
        return out

    def conf():
        out = {}
        for f in sorted(glob.glob(f"{KWS}/wp130/results/conf_say/*.wav")):
            out[os.path.basename(f)] = np.concatenate([room(2 * SR), to16(load16(f)), room(2 * SR)])
        return out

    def synth():
        n = 120 * SR
        d = {"stille": np.zeros(n, "int16")}
        for lvl in (3, 10, 30):
            d[f"weiss{lvl}"] = to16(rng.normal(0, lvl, n) / 32767)
        for lvl in (10, 100):
            d[f"rosa{lvl}"] = to16(colored(n, 1.0, rng) * lvl / 32767)
        return d

    return {"pos_huawei": pos("huawei"), "pos_handy2": pos("handy2"), "neg_huawei": neg("huawei"), "neg_handy2": neg("handy2"),
            "fleurs_test": fleurs_test, "fleurs_dev": fleurs_dev, "conf": conf, "synth": synth}


# ---------- Einlernen ----------
def enroll(chain, x, rows, pad, seed=134):
    """Vorlagen nach embedUtterance (pad zero/noise): -> (T (n,1536), Wall (alle Fenster aller Einlern-Stroeme), Info je Vorlage)."""
    rng = np.random.default_rng(seed)
    T, allw, info = [], [], []
    for r in rows:
        a, b, se = capture_bounds(x, float(r["start"]), float(r["ende"]))
        s, tgt = pad_stream(to16(x[a:b]), se, pad, rng)
        W = windows_from_emb(chain.embeddings(s))
        if not len(W): continue
        k = pick_window(len(W), tgt + TEMPLATE_OFFSET)
        T.append(W[k]); allw.append(W)
        zero_share = float((s[max(0, window_end(k) - (WIN + 9) * CHUNK + 0):window_end(k)] == 0).mean())
        info.append({"block": int(r["block"]), "runde": int(r["runde"]), "k": k, "nullanteil": round(zero_share, 2)})
    return np.stack(T), np.concatenate(allw), info


def neutral_means(chain, cache, srcs):
    """Feste Mittel aus neutralem Audio: V2 (FLEURS dev), V2b (gleiche Teile Sprache, Rauschen, Stille)."""
    sp = windows_from_emb(np.concatenate(list(cache.get("fleurs_dev", srcs["fleurs_dev"]).values())))
    mu_sp = sp.mean(axis=0)
    sy = cache.get("synth", srcs["synth"])
    noise = np.concatenate([windows_from_emb(v) for k, v in sy.items() if k != "stille"])
    sil = windows_from_emb(sy["stille"])
    mu_mix = (mu_sp + noise.mean(axis=0) + sil.mean(axis=0)) / 3
    return {"V2": mu_sp.astype("float32"), "V2b": mu_mix.astype("float32")}, len(sp)


# ---------- Messung ----------
def sims_of(Ed, T, mu, pad=0):
    """{clip: (t, sim)} fuer alle Fenster."""
    out = {}
    for k, E in Ed.items():
        W = windows_from_emb(E)
        out[k] = (win_times(len(W), pad), best_sim(W, T, mu)) if len(W) else (np.zeros(0), np.zeros(0))
    return out


def hours_of(Ed):
    return sum(max(0, len(E) + FIRST_EMB) * CHUNK for E in Ed.values()) / SR / 3600


def one(Sd):
    """Der einzige Strom einer Quelle mit nur einem Clip."""
    return next(iter(Sd.values()))


def hit_rows(Sd, rows, dev):
    """Spitzenwert je Label (hoechste Aehnlichkeit mit Fensterende im Label-Zeitfenster)."""
    t, v = one(Sd)
    out = []
    for r in rows:
        if r["geraet"] != dev: continue
        lo, hi = label_window(float(r["start"]), float(r["ende"]), r["status"])
        m = (t >= lo) & (t <= hi)
        out.append({"word": r["wort"], "block": int(r["block"]), "peak": float(v[m].max()) if m.any() else -1.0})
    return out


def clean_peaks(peaks, blocks, word):
    """Spitzen der sauberen Pruefmenge: huawei Block 4-6 und handy2 Block 4-6 (handy2 Block 1-3 ist dieselbe Sitzung wie die Vorlagen).
    Die Spitzen je Geraet/Wort stehen in Label-Reihenfolge; hier wird belegt, dass sie nach Block sortiert sind
    (sonst waere die Zuordnung Spitze -> Block falsch) und dass die Laengen zusammenpassen."""
    out = []
    for d in DEVICES:
        b, p = blocks[d][word], peaks[d][word]
        assert len(b) == len(p), "Spitzen und Bloecke verschieden lang"
        assert b == sorted(b), f"Spitzen {d}/{word} nicht nach Block sortiert: {b}"
        out += [x for x, bk in zip(p, b) if bk >= 4]
    return out


def grid_for(variant):
    return np.round(np.arange(0.50, 1.0, 0.005), 3) if variant == "V0" else np.round(np.arange(-0.30, 1.0, 0.01), 3)


def measure(chain, cache, srcs, x_huawei, labels, target, log):
    """Alle Varianten -> Liste von Ergebnis-Dictionaries."""
    train_rows = [r for r in labels if is_train_row(r)]
    eval_rows = pruef_rows(labels)
    assert not any(is_train_row(r) for r in eval_rows), "Einlern-Clip im Pruef-Split"
    assert all(r["geraet"] == TRAIN_DEVICE and int(r["block"]) in TRAIN_BLOCKS for r in train_rows)
    log(f"Vorlagen-Clips: {len(train_rows)}, Pruef-Labels: {len(eval_rows)}")
    E = {n: cache.get(n, srcs[n]) for n in ("pos_huawei", "pos_handy2", "neg_huawei", "neg_handy2", "fleurs_test", "conf", "synth")}
    mus, n_sp = neutral_means(chain, cache, srcs)
    log(f"neutrale Fenster (FLEURS dev): {n_sp}")
    hrs = {"neg_huawei": hours_of(E["neg_huawei"]), "neg_handy2": hours_of(E["neg_handy2"]), "fleurs_test": hours_of(E["fleurs_test"])}
    tv = sorted(E["fleurs_test"])
    tv_a, tv_b = tv[::2], tv[1::2]
    hrs["tv_a"], hrs["tv_b"] = hours_of({k: E["fleurs_test"][k] for k in tv_a}), hours_of({k: E["fleurs_test"][k] for k in tv_b})
    res = []
    for pad in PADS:
        T, Wall, info = enroll(chain, x_huawei, train_rows, pad)
        log(f"pad={pad}: {len(T)} Vorlagen, Fenster zum Mitteln {len(Wall)}")
        mu_enroll = Wall.mean(axis=0)
        for var in VARIANTS:
            mu = {"V0": None, "V1": mu_enroll, "V2": mus["V2"], "V2b": mus["V2b"]}[var]
            S = {n: sims_of(E[n], T, mu, SR if n.startswith("pos_") else 0) for n in E}
            g = grid_for(var)
            negs = {k: one(S[k]) for k in ("neg_huawei", "neg_handy2")}
            cnt = lambda key, thr: n_events(*negs[key], thr)
            thr_all = pick_threshold(g, lambda th: sum(cnt(k, th) for k in negs), fa_limit(target, hrs["neg_huawei"] + hrs["neg_handy2"]))
            thr_x = {d: pick_threshold(g, lambda th, o=o: cnt("neg_" + o, th), fa_limit(target, hrs["neg_" + o]))
                     for d, o in (("huawei", "handy2"), ("handy2", "huawei"))}     # Schwelle aus dem anderen Geraet
            # streng: zusaetzlich Fernseher (FLEURS test), Auswahl nur auf der Haelfte A, Bericht auf B (nie dieselben Clips)
            tva = lambda th: sum(n_events(*S["fleurs_test"][k], th) for k in tv_a)
            thr_s = pick_threshold(g, lambda th: sum(cnt(k, th) for k in negs) + tva(th),
                                   fa_limit(target, hrs["neg_huawei"] + hrs["neg_handy2"] + hrs["tv_a"]))
            res.append(dict(pad=pad, var=var, T=len(T), Tm=T, info=info, thr=thr_all, thr_s=thr_s, thr_x=thr_x, hours=hrs, tv_b=tv_b, sil_w=windows_from_emb(E["synth"]["stille"])[100:101],
                            hours_tv_b=hrs["tv_b"], mu_norm=None if mu is None else float(np.linalg.norm(mu)), target=target, S=S, grid=g, rows=eval_rows))
    return res


def summarize(r, target):
    """Kennzahlen eines Ergebnisses: Verteilungen und, fuer die Schwellen thr (ruhiger Alltag) und thr_s (streng, mit Fernseher), die Tabelle."""
    S, hrs = r["S"], r["hours"]
    q = lambda v, p: float(np.percentile(v, p))
    out = {"pad": r["pad"], "var": r["var"], "thr_x": r["thr_x"], "mu_norm": r["mu_norm"]}
    sil = S["synth"]["stille"][1]
    out["stille"] = {"max": float(sil.max()), "med": float(np.median(sil))}
    out["rauschen"] = {k: float(S["synth"][k][1].max()) for k in S["synth"] if k != "stille"}
    for k in ("neg_huawei", "neg_handy2", "fleurs_test"):
        v = np.concatenate([x[1] for x in S[k].values()])
        out[k] = {"p50": q(v, 50), "p99": q(v, 99), "p999": q(v, 99.9), "max": float(v.max())}
    pk = {d: hit_rows(S["pos_" + d], r["rows"], d) for d in DEVICES}
    out["pos_peaks"] = {d: {w: [p["peak"] for p in pk[d] if p["word"] == w] for w in WORDS} for d in DEVICES}
    out["pos_blocks"] = {d: {w: [p["block"] for p in pk[d] if p["word"] == w] for w in WORDS} for d in DEVICES}
    out["pos_all"] = {}
    for w in WORDS:
        v = [p["peak"] for d in DEVICES for p in pk[d] if p["word"] == w]
        out["pos_all"][w] = {"min": float(min(v)), "med": float(np.median(v)), "max": float(max(v))}
    cp = np.array([S["conf"][k][1].max() if len(S["conf"][k][1]) else -1.0 for k in sorted(S["conf"])])
    out["conf"] = {"p50": float(np.median(cp)), "p90": q(cp, 90), "max": float(cp.max())}
    tvb = [S["fleurs_test"][k] for k in r["tv_b"]]
    peaks = lambda w: [p for d in DEVICES for p in out["pos_peaks"][d][w]]

    def at(thr):
        if thr is None: return None
        o = {"thr": thr, "fa_neg": [n_events(*one(S[k]), thr) for k in ("neg_huawei", "neg_handy2")],
             "fa_tv": sum(n_events(t, v, thr) for t, v in tvb), "conf_hit": int((cp >= thr).sum()),
             "warm": {"stille": bool(sil.max() >= thr), **{k: bool(m >= thr) for k, m in out["rauschen"].items()}}, "hit": {}}
        for d in DEVICES:
            for w in WORDS:
                v = out["pos_peaks"][d][w]; o["hit"][f"{d}|{w}"] = (int(sum(p >= thr for p in v)), len(v))
        for w in WORDS:
            v = peaks(w); o["hit"][f"alle|{w}"] = (int(sum(p >= thr for p in v)), len(v))
            v = clean_peaks(out["pos_peaks"], out["pos_blocks"], w); o["hit"][f"sauber|{w}"] = (int(sum(p >= thr for p in v)), len(v))
        return o

    # Kurvenvergleich (keine Auswahl fuer den Einsatz): Schwelle mit hoechstens target FA/h auf dem GANZEN Fernseher-Satz
    allowed_tv = fa_limit(r["target"], hrs["fleurs_test"])
    thr_c = pick_threshold(r["grid"], lambda th: sum(n_events(t, v, th) for t, v in S["fleurs_test"].values()), allowed_tv)
    out["q"], out["s"], out["c"] = at(r["thr"]), at(r["thr_s"]), at(thr_c)
    out["fa_x"] = {d: (None if r["thr_x"][d] is None else n_events(*one(S["neg_" + d]), r["thr_x"][d])) for d in DEVICES}
    out["hours_tv_b"] = r["hours_tv_b"]
    return out


def render(sums, hrs, target):
    f = lambda v: f"{v:.2f}".replace(".", ",")
    pct = lambda k, n: f"{100 * k / max(n, 1):.0f} % ({k}/{n}) [{100 * wilson(k, n)[0]:.0f}–{100 * wilson(k, n)[1]:.0f}]".replace(".", ",")
    L, h_neg = [], hrs["neg_huawei"] + hrs["neg_handy2"]
    L.append(f"Negativ echt: huawei {hrs['neg_huawei']:.2f} h, handy2 {hrs['neg_handy2']:.2f} h (zusammen {h_neg:.2f} h, erlaubt {fa_limit(target, h_neg)} Ereignisse bei {target:g}/h); "
             f"FLEURS-Fernseher test {hrs['fleurs_test']:.2f} h (Auswahlhälfte {hrs['tv_a']:.2f} h, Berichtshälfte {hrs['tv_b']:.2f} h).")
    L.append("")
    L.append("**Verteilungen der Ähnlichkeit** (Spitze je Strom bzw. Clip):")
    L.append("")
    L.append("| Polster | Var. | Stille max | Rauschen max (weiß 3/10/30, rosa 10/100) | Negativ echt p99,9 / max (hu; h2) | Fernseher p99,9 / max | Wendelin Spitze min / Median / max | Verwechsler Median / p90 / max |")
    L.append("|---|---|---|---|---|---|---|---|")
    for s in sums:
        rs, pa = s["rauschen"], s["pos_all"]["Wendelin"]
        L.append(f"| {s['pad']} | {s['var']} | {f(s['stille']['max'])} | {' / '.join(f(rs[k]) for k in ('weiss3', 'weiss10', 'weiss30', 'rosa10', 'rosa100'))} | "
                 f"{f(s['neg_huawei']['p999'])} / {f(s['neg_huawei']['max'])}; {f(s['neg_handy2']['p999'])} / {f(s['neg_handy2']['max'])} | "
                 f"{f(s['fleurs_test']['p999'])} / {f(s['fleurs_test']['max'])} | {f(pa['min'])} / {f(pa['med'])} / {f(pa['max'])} | "
                 f"{f(s['conf']['p50'])} / {f(s['conf']['p90'])} / {f(s['conf']['max'])} |")
    for key, title in (("q", f"**Schwelle ruhig:** niedrigster Wert mit höchstens {target:g} FA/h auf den echten Negativ-Aufnahmen (beide Geräte zusammen)"),
                       ("s", f"**Schwelle streng:** wie ruhig, zusätzlich mit der Auswahlhälfte des Fernsehers (FA/h Fernseher auf der anderen Hälfte)"),
                       ("c", f"**Kurvenvergleich:** Schwelle mit höchstens {target:g} FA/h auf dem ganzen Fernseher-Satz (keine Einsatz-Schwelle, nur gleiche FA-Rate je Variante)")):
        L += ["", title + ":", "",
              "| Polster | Var. | Schwelle | FA echt hu / h2 | FA/h Fernseher (Ereignisse) | Wendelin huawei B4–6 | Wendelin handy2 | Wendelin gesamt | Hey Wendelin gesamt | Wendelin sauber | Hey Wendelin sauber | Verwechsler-Clips | löst nach Warmstart aus (Stille / Rauschen) |",
              "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for s in sums:
            a = s[key]
            if a is None:
                L.append(f"| {s['pad']} | {s['var']} | keine Schwelle unter dem Ziel | | | | | | | | | | |"); continue
            h = a["hit"]
            wl = [k for k, v in a["warm"].items() if v]
            L.append(f"| {s['pad']} | {s['var']} | {f(a['thr'])} | {a['fa_neg'][0]} / {a['fa_neg'][1]} | "
                     f"{'–' if key == 'c' else format(a['fa_tv'] / hrs['tv_b'], '.1f') + ' (' + str(a['fa_tv']) + ')'} | {pct(*h['huawei|Wendelin'])} | {pct(*h['handy2|Wendelin'])} | "
                     f"{pct(*h['alle|Wendelin'])} | {pct(*h['alle|Hey Wendelin'])} | {pct(*h['sauber|Wendelin'])} | {pct(*h['sauber|Hey Wendelin'])} | {a['conf_hit']}/300 | {'ja (' + ', '.join(wl) + ')' if wl else 'nein'} |".replace(".", ","))
    L += ["", "**Gegenprobe Gerät:** Schwelle nur aus dem Negativ des anderen Geräts (huawei-Schwelle aus handy2 und umgekehrt), FA auf dem eigenen Negativ, Treffer „Wendelin“ auf dem eigenen Gerät:", "",
          "| Polster | Var. | -> huawei: Schwelle, FA, Treffer | -> handy2: Schwelle, FA, Treffer |", "|---|---|---|---|"]
    for s in sums:
        cells = []
        for d in DEVICES:
            tx = s["thr_x"][d]
            if tx is None: cells.append("keine"); continue
            v = s["pos_peaks"][d]["Wendelin"]
            cells.append(f"{f(tx)}, {s['fa_x'][d]}, {sum(p >= tx for p in v)}/{len(v)}")
        L.append(f"| {s['pad']} | {s['var']} | {cells[0]} | {cells[1]} |")
    return "\n".join(L) + "\n"


def diagnose(res, log):
    """Polster-Diagnose (V0): Nullanteil im Vorlagenfenster, Aehnlichkeit jeder Vorlage zur digitalen Stille und Vorlage-gegen-Vorlage (leave-one-out)."""
    out = {}
    for r in res:
        if r["var"] != "V0": continue
        nz = [i["nullanteil"] for i in r["info"]]
        Tn = unit(r["Tm"]); ts = (Tn @ unit(r["sil_w"]).T).ravel()
        G = Tn @ Tn.T; np.fill_diagonal(G, -1); loo = G.max(axis=1)
        out[r["pad"]] = {"nullanteil": [min(nz), float(np.median(nz)), max(nz)], "vorlage_stille": [float(ts.min()), float(np.median(ts)), float(ts.max())],
                         "loo": [float(loo.min()), float(np.median(loo)), float(loo.max())]}
        log(f"Polster {r['pad']}: Nullanteil min/med/max {out[r['pad']]['nullanteil']}, Vorlage-Stille {out[r['pad']]['vorlage_stille']}, leave-one-out {out[r['pad']]['loo']}")
    return out


CENTER_VARIANT = "V2b"
CENTER_ID = "v2b-1"


def dart_center_source(mu, feature_version):
    """Quelltext von wake_center_mean.g.dart: festes Mittel (1536 float32, little-endian, base64), gebunden an die Feature-Version."""
    import base64
    mu = np.asarray(mu, "<f4")
    assert mu.shape == (WIN * 96,), mu.shape
    assert np.isfinite(mu).all()
    b64 = base64.b64encode(mu.tobytes()).decode()
    lines = [b64[i:i + 76] for i in range(0, len(b64), 76)]
    body = "\n".join(f"    '{ln}'" for ln in lines)
    return f"""// GENERATED by tool/train_wake_word/template_center_measure.py export - do not edit.
//
// Fixed mean of the 16x96 wake embedding windows (variant {CENTER_VARIANT}, WP134):
// equal parts FLEURS dev speech (CC-BY 4.0, Google, 0.5 h, separate from the
// FLEURS test split and from all enrollment and evaluation recordings),
// synthetic white/pink noise and digital silence. No fit on evaluation data.
// Bound to the feature models [wakeCenterFeatureVersion]; a new feature version
// needs a new mean (see docs/notes/wake-word-compare.md, "Vorlagen zentriert").

/// Feature version ([WakeFeatureChain.featureVersion]) the mean belongs to.
const wakeCenterFeatureVersion = '{feature_version}';

/// Identifier stored in the templates JSON (`center`); old templates have none.
const wakeCenterId = '{CENTER_ID}';

/// Base64 of 1536 little-endian float32 values.
const wakeCenterMeanBase64 =
{body};
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["run", "export"])
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--target", type=float, default=2.0, help="FA/h")
    ap.add_argument("--out", default=WORKDIR)
    ap.add_argument("--dart", default=os.path.join(HERE, "..", "..", "packages", "wendelin_voice", "lib", "src", "wake", "wake_center_mean.g.dart"))
    ap.add_argument("--feature-version", default="oww-0.5.1-mel-emb-1")
    a = ap.parse_args()
    t00 = time.time()
    log = lambda *s: print(f"[{time.time() - t00:6.0f}s]", *s, flush=True)
    os.makedirs(a.out, exist_ok=True)
    chain = Chain(a.threads)
    cache = Cache(chain, a.out)
    if a.cmd == "export":
        mus, n_sp = neutral_means(chain, cache, sources())
        open(a.dart, "w").write(dart_center_source(mus[CENTER_VARIANT], a.feature_version))
        log(f"{CENTER_VARIANT} nach {a.dart} (Sprachfenster {n_sp}, Norm {np.linalg.norm(mus[CENTER_VARIANT]):.3f})")
        return
    x = load16(f"{WORK121}/all_{TRAIN_DEVICE}.wav")
    res = measure(chain, cache, sources(), x, read_labels(), a.target, log)
    dg = diagnose(res, log)
    sums = [summarize(r, a.target) for r in res]
    json.dump({"diag": dg, "sums": sums}, open(f"{a.out}/summary.json", "w"), indent=1, default=str)
    md = render(sums, res[0]["hours"], a.target)
    open(f"{a.out}/report.md", "w").write(md)
    print(md)
    log("fertig")


if __name__ == "__main__":
    main()
