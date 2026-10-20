#!/usr/bin/env python3
"""WP106 Teil 1: Wake Word im Stationsmodus (Messung, kein App-Code, keine Daten im Repo).

Aufruf (venv mit openwakeword/onnxruntime/sherpa-onnx, alles Weitere liegt unter ~/wendelin-models/kws):
  K=~/wendelin-models/kws
  nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/station_measure.py \
      [--cond clean,both,station] [--thr 0.85] [--model-thr 0.3] [--spk-thr 0.25,0.30,0.35,0.45,0.52,0.60] \
      [--neg-min 7] [--limit-pos N] [--out $K/wp106/results]
Schritte: (1) Negativkorpus pruefen (Clips mit "Wendelin" ausschliessen), (2) Stufe 1 (Vorlagen + Modell v7)
je Stimme/Bedingung, (3) Stufe 2 je Variante (Whisper small, Parakeet v3 ohne/mit Hotword Score 1/2/3/5),
(4) Stufe 3 Sprecherpruefung (CAM++), (5) Tabellen (CSV + Markdown) nach --out, (6) RAM-Spitze je Stufe
(Unterprozess, --probe). Bedingungen: clean; both = Rauschen 10 dB + Hall 0,5 s; station = Abstand 2-3 m
(Hall RT60 0,7, Pegel -10..-15 dB, Fernsehton = FLEURS-Sprache + synthetische Musik bei SNR 5..10 dB,
Mikrofonrauschen 25 dB). Negativ-Mengen: "neg" (Systemstimmen-Sprache) und "tv" (FLEURS-Sprache allein).
Stufe 2 spiegelt matchesWakeWord aus kws_measure.py in zwei Regeln: "d1" (Abstand 1) und "app" (App: Abstand 2,
Zwei-Aenderungs-Regel nur fuer ein Wort, Zweiwort-Treffer nie vor Funktionswort); Spalte "match" in den Tabellen.
Basis des Boosts ist "parakeet-bs" (modified_beam_search ohne Hotwords), nicht das greedy-"parakeet". Zwischendaten nur unter
~/wendelin-models/kws/wp106/work. Voraussetzung: FLEURS-dev entpackt nach work/fleurs, CAM++ nach wp106/models.
"""
import argparse, csv, glob, json, os, re, resource, subprocess, sys, time
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import common as C                      # noqa: E402
import kws_measure as K                 # noqa: E402

SR = C.SR
KWS = os.path.expanduser("~/wendelin-models/kws")
# Modelle (Whisper/Parakeet/BPE) liegen im Handoff-Ordner neben dem Repo; Env WENDELIN_HANDOFF ueberschreibt
MODELS = os.environ.get("WENDELIN_MODELS") or os.path.expanduser("~/wendelin-fixtures/models")
H = os.environ.get("WENDELIN_HANDOFF") or os.path.abspath(os.path.join(HERE, "..", "..", "..", "handoff"))
WORK = f"{KWS}/wp106/work"
SPEAKER = f"{KWS}/wp106/models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx"
TAIL = 0.9
VARIANTS = ["whisper-small", "parakeet", "parakeet-bs", "parakeet-hw1", "parakeet-hw2", "parakeet-hw3", "parakeet-hw5"]
RULES = {"T": "Vorlage", "M": "Modell v7", "TM": "Modell v7 ODER Vorlage"}


# ---------- Recognizer ----------
def make_rec(name, threads=4):
    import sherpa_onnx as so
    M = MODELS
    if name == "whisper-small":
        d = f"{M}/whisper-small"
        return so.OfflineRecognizer.from_whisper(
            encoder=f"{d}/small-encoder.int8.onnx", decoder=f"{d}/small-decoder.int8.onnx",
            tokens=f"{d}/small-tokens.txt", language="de", num_threads=threads)
    d = f"{M}/parakeet-v3"
    kw = dict(encoder=f"{d}/encoder.int8.onnx", decoder=f"{d}/decoder.int8.onnx", joiner=f"{d}/joiner.int8.onnx",
              tokens=f"{d}/tokens.txt", num_threads=threads, model_type="nemo_transducer")
    if name == "parakeet":                 # greedy (nur zur Information; NICHT die Basis fuer den Boost)
        return so.OfflineRecognizer.from_transducer(**kw)
    if name == "parakeet-bs":              # Basis des Boosts: gleiche Suche (modified_beam_search), aber ohne Hotwords
        return so.OfflineRecognizer.from_transducer(**kw, decoding_method="modified_beam_search")
    score = float(name.removeprefix("parakeet-hw"))
    os.makedirs(WORK, exist_ok=True)
    hw = f"{WORK}/hotwords-{score}.txt"
    open(hw, "w").write("Wendelin\n")
    bpe = f"{M}/parakeet-bpe/bpe.vocab"          # Pflicht: ohne bpe_vocab wirkt der Boost nicht (WP102)
    assert os.path.exists(bpe), bpe
    return so.OfflineRecognizer.from_transducer(
        **kw, decoding_method="modified_beam_search", hotwords_file=hw, hotwords_score=score,
        modeling_unit="bpe", bpe_vocab=bpe)


def decode(rec, x):
    s = rec.create_stream()
    s.accept_waveform(SR, x.astype("float32"))
    rec.decode_stream(s)
    return s.result.text


def make_spk():
    import sherpa_onnx as so
    return so.SpeakerEmbeddingExtractor(so.SpeakerEmbeddingExtractorConfig(model=SPEAKER, num_threads=1))


def embed(ex, x):
    s = ex.create_stream()
    s.accept_waveform(SR, x.astype("float32"))
    s.input_finished()
    v = np.array(ex.compute(s), "float32")
    return v / (np.linalg.norm(v) + 1e-9)


def probe(name):
    """Unterprozess: Modell laden, 3 s decodieren, Spitzen-RSS und Ladezeit ausgeben."""
    x = (np.random.default_rng(0).standard_normal(3 * SR) * 0.01).astype("float32")
    t = time.time()
    if name == "spk":
        embed(make_spk(), x)
    elif name == "stage1":
        import onnxruntime as ort
        af = C.make_features(f"{KWS}/wp58/dl/oww", 1)
        so_ = ort.SessionOptions(); so_.intra_op_num_threads = 1
        ort.InferenceSession(f"{KWS}/wp58/out/wendelin_v7.onnx", so_, providers=["CPUExecutionProvider"])
        C.embed(af, [x])
    else:
        decode(make_rec(name), x)
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1048576      # macOS: Bytes
    print(json.dumps({"name": name, "rss_mb": round(rss), "load_s": round(time.time() - t, 1)}))


# ---------- Signalerzeugung ----------
def music(n, rng):
    """Synthetische Musik: Dreiklaenge mit Obertoenen im 0,5-s-Raster plus Bass."""
    out = np.zeros(n, "float32")
    beat = SR // 2
    for b in range(0, n, beat):
        r = rng.choice([220.0, 246.9, 261.6, 293.7, 329.6]) * 2.0 ** rng.integers(-1, 1)
        t = np.arange(min(beat * 2, n - b)) / SR
        note = 0.8 * np.sin(2 * np.pi * r / 2 * t)
        for mult in (1.0, 1.25 if rng.random() < .5 else 1.19, 1.5):
            for h in range(1, 6):
                note += np.sin(2 * np.pi * r * mult * h * t + rng.uniform(0, 6)) / h
        out[b:b + len(t)] += (note * np.exp(-3.0 * t)).astype("float32")
    return out / (np.abs(out).max() + 1e-9)


def rms(x):
    return float(np.sqrt((x ** 2).mean() + 1e-12))


def scale_to(x, target_rms):
    return (x * (target_rms / rms(x))).astype("float32")


def tv_track(n, rng, fleurs):
    """Fernsehton: aneinandergereihte FLEURS-Saetze plus Musik (6 dB leiser)."""
    parts, tot = [], 0
    while tot < n:
        x = fleurs[rng.integers(len(fleurs))]
        parts.append(x); tot += len(x)
    return (scale_to(np.concatenate(parts)[:n], 0.1) + scale_to(music(n, rng), 0.05)).astype("float32")


def room(x, rng, rt60, peak_db):
    y = K.add_reverb(x, rt60, rng)
    return (y / (np.abs(y).max() + 1e-9) * 10 ** (peak_db / 20)).astype("float32")


def apply_cond(x, cond, kind, rng, fleurs):
    """kind pos/neg: im Station-Fall Fernsehton bei SNR 5..10 dB darunter; kind tv: nur der Fernseher."""
    if cond != "station":
        return K.condition(x, cond, rng)
    y = room(x, rng, 0.7, rng.uniform(-15, -10))
    if kind != "tv":
        tv = room(tv_track(len(x), rng, fleurs), rng, 0.7, 0.0)
        y = y + scale_to(tv, rms(y) / 10 ** (rng.uniform(5, 10) / 20))
    return K.add_noise(y, 25, rng)


# ---------- Negativkorpus ----------
def pick_neg(args, rec_plain):
    """Kurze Clips komplett, lange Clips (1..8, je andere Stimme) die ersten --neg-min Minuten.
    Clips, deren Transkript "Wendelin" enthaelt (oder b6-*), werden ausgeschlossen."""
    clips = []
    for f in sorted(glob.glob(f"{KWS}/data/neg/*.wav")):
        b = os.path.basename(f)
        x = K.load(f)
        if b.startswith("long"):
            if int(re.match(r"long(\d+)", b).group(1)) > 8:
                continue
            x = x[: int(args.neg_min * 60 * SR)]
        m = re.search(r"_([A-Za-z]+)\.wav$", b)
        clips.append({"name": b, "x": x, "voice": m.group(1) if m else None})
    cache = f"{WORK}/neg_scan.json"
    scan = json.load(open(cache)) if os.path.exists(cache) else {}
    for c in clips:
        if c["name"] in scan and scan[c["name"]]["n"] == len(c["x"]):
            continue
        texts = [decode(rec_plain, c["x"][i:i + 20 * SR]) for i in range(0, len(c["x"]), 20 * SR)]
        hit = [t for t in texts if K.matches_wake_word(t, 1)]
        scan[c["name"]] = {"n": len(c["x"]), "hit": bool(hit), "text": " | ".join(hit)[:200]}
        json.dump(scan, open(cache, "w"))
    excl = [c["name"] for c in clips if scan[c["name"]]["hit"] or c["name"].startswith("b6-")]
    return [c for c in clips if c["name"] not in excl], excl, scan


# ---------- Hauptlauf ----------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cond", default="clean,both,station")
    ap.add_argument("--thr", type=float, default=0.85)
    ap.add_argument("--model-thr", type=float, default=0.3)
    ap.add_argument("--spk-thr", default="0.25,0.30,0.35,0.45,0.52,0.60")
    ap.add_argument("--neg-min", type=float, default=7.0, help="Minuten je langem Negativ-Clip")
    ap.add_argument("--limit-pos", type=int, default=0, help="nur die ersten N Positiv-Clips je Stimme (Test)")
    ap.add_argument("--tv-max-h", type=float, default=1.0)
    ap.add_argument("--variants", default=",".join(VARIANTS))
    ap.add_argument("--out", default=f"{KWS}/wp106/results")
    ap.add_argument("--probe")
    ap.add_argument("--no-probe", action="store_true")
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    if a.probe:
        return probe(a.probe)
    os.makedirs(a.out, exist_ok=True); os.makedirs(WORK, exist_ok=True)
    rng = np.random.default_rng(a.seed)
    t00 = time.time()
    log = lambda *s: print(f"[{time.time() - t00:6.0f}s]", *s, flush=True)
    variants = a.variants.split(",")

    fleurs = [K.load(f) for f in sorted(glob.glob(f"{WORK}/fleurs/dev/*.wav"))]
    fleurs = [x / (np.abs(x).max() + 1e-9) for x in fleurs]
    tvonly, th = [], 0.0
    for x in fleurs:
        if th >= a.tv_max_h: break
        tvonly.append(x); th += len(x) / SR / 3600
    log(f"FLEURS {len(fleurs)} Clips, TV-only {len(tvonly)} Clips = {th:.2f} h")

    plain = make_rec("parakeet")
    neg, excl, scan = pick_neg(a, plain)
    del plain
    nh = sum(len(c["x"]) for c in neg) / SR / 3600
    log(f"Negativ: {len(neg)} Clips = {nh:.2f} h; ausgeschlossen (enthalten Wendelin): {len(excl)}: {excl}")

    # --- Stufe 1 ---
    import onnxruntime as ort
    af = C.make_features(f"{KWS}/wp58/dl/oww", 1)
    so_ = ort.SessionOptions(); so_.intra_op_num_threads = 1
    sess = ort.InferenceSession(f"{KWS}/wp58/out/wendelin_v7.onnx", so_, providers=["CPUExecutionProvider"])
    pad = lambda x: np.concatenate([np.zeros(SR, "float32"), x, np.zeros(SR, "float32")])
    s1 = {"t": 0.0, "dur": 0.0}

    def windows(x):
        t0 = time.process_time()
        emb = C.embed(af, [pad(x)])[0]
        n = len(emb) - C.WIN + 1
        if n <= 0:
            return np.zeros((0, 1)), np.zeros(0, int), np.zeros(0)
        W = np.stack([emb[j:j + C.WIN] for j in range(n)]).astype("float32")
        ms = sess.run(None, {"input": W})[0][:, 0]
        V = W.reshape(n, -1)
        V = V / (np.linalg.norm(V, axis=1, keepdims=True) + 1e-9)
        s1["t"] += time.process_time() - t0; s1["dur"] += len(x) / SR
        return V, np.array([C.window_end(j) for j in range(n)]), ms

    voices = {}
    for f in sorted(glob.glob(f"{KWS}/data/enroll/*.wav")):
        voices.setdefault(os.path.basename(f).split("_")[0], []).append(f)
    posf = {}
    for f in sorted(glob.glob(f"{KWS}/data/pos/*.wav")):
        posf.setdefault(os.path.basename(f).split("_")[1].split(".")[0], []).append(f)
    tmpl = {}
    for v, fs in voices.items():
        T = []
        for f in fs[:15]:
            x = K.load(f); V, we, _ = windows(x)
            T.append(V[int(np.argmax(we >= (SR + K.speech_end(x) * SR + 0.3 * SR)))])
        tmpl[v] = np.stack(T)
    s1["t"] = s1["dur"] = 0.0     # RTF nur ueber die Messdaten

    def events(ok, refr=19):
        ev, last = [], -10 ** 9
        for j in np.where(ok)[0]:
            if j - last >= refr:
                ev.append(int(j)); last = j
        return ev

    segs, recs = {}, []            # segs[key] = Audio (3 s); recs = Messpunkte je Stimme/Clip
    for cond in a.cond.split(","):
        P = {v: [apply_cond(K.load(f), cond, "pos", rng, fleurs) for f in (fs[:a.limit_pos] if a.limit_pos else fs)]
             for v, fs in posf.items()}
        N = [apply_cond(c["x"], cond, "neg", rng, fleurs) for c in neg]
        TV = [apply_cond(x, cond, "tv", rng, fleurs) for x in tvonly]
        log(f"{cond}: Fenster berechnen")
        PW = {v: [windows(x) for x in xs] for v, xs in P.items()}
        NW = [windows(x) for x in N]
        TW = [windows(x) for x in TV]
        for v, T in tmpl.items():
            def cand(win):
                V, we, ms = win
                if not len(V): return {k: [] for k in RULES}, we
                t = (V @ T.T).max(axis=1) >= a.thr; m = ms >= a.model_thr
                return {"T": events(t), "M": events(m), "TM": events(t | m)}, we

            def seg(tag, ci, j, x, we):
                key = (cond, tag, ci, j)
                if key not in segs:
                    e = we[j]
                    segs[key] = pad(x)[max(0, e - 2 * SR): e + int(TAIL * SR)].copy()
                return key
            for setn, X, WN, tagf in (("pos", P[v], PW[v], lambda ci: "pos" + v), ("neg", N, NW, lambda ci: "neg"),
                                      ("tv", TV, TW, lambda ci: "tv")):
                for ci, (x, win) in enumerate(zip(X, WN)):
                    ev, we = cand(win)
                    recs.append({"cond": cond, "voice": v, "set": setn, "h": len(x) / SR / 3600,
                                 "own": setn == "neg" and neg[ci]["voice"] == v,
                                 "ev": {r: [seg(tagf(ci), ci, j, x, we) for j in (e[:3] if setn == "pos" else e)]
                                        for r, e in ev.items()}})
    stage1_rtf = s1["t"] / max(s1["dur"], 1e-9)
    log(f"Stufe 1 fertig, {len(segs)} Segmente; Stufe-1-RTF {stage1_rtf:.3f} (CPU-Zeit/Audio)")

    # --- Stufe 2 ---
    keys = list(segs)
    text, tstat = {}, {}
    sec = sum(len(segs[k]) for k in keys) / SR
    tcache = f"{WORK}/station_texts.json"
    old = json.load(open(tcache)) if os.path.exists(tcache) else {}
    kj = lambda k: "|".join(map(str, k))
    for var in variants:
        if var in old and all(kj(k) in old[var] for k in keys):
            text[var] = {k: old[var][kj(k)] for k in keys}
            log(f"{var}: Transkripte aus Cache"); continue
        rec = make_rec(var)
        t0 = time.time()
        text[var] = {k: decode(rec, segs[k]) for k in keys}
        el = time.time() - t0
        tstat[var] = {"rtf": el / max(sec, 1e-9), "ms_per_seg": 1000 * el / max(len(keys), 1)}
        del rec
        log(f"{var}: {len(keys)} Segmente, RTF {tstat[var]['rtf']:.3f}, {tstat[var]['ms_per_seg']:.0f} ms/Segment")
    sanity = {}          # Beleg, dass der Boost wirkt (Text mit/ohne Hotword unterscheidet sich)
    base = "parakeet-bs" if "parakeet-bs" in text else "parakeet"
    if base in text:
        for var in text:
            if var.startswith("parakeet-hw"):
                diff = [k for k in keys if text[var][k].lower() != text[base][k].lower()]
                gain = [k for k in diff if K.matches_wake_word(text[var][k], 1) and not K.matches_wake_word(text[base][k], 1)]
                sanity[var] = {"differ": len(diff), "of": len(keys), "newly_matching": len(gain),
                               "base": base}
                log(f"SANITY {var} gegen {base}: Text weicht auf {len(diff)}/{len(keys)} Segmenten ab, {len(gain)} neu als Wendelin")
                if not diff:
                    log(f"WARNUNG: {var} unveraendert, Boost wirkt NICHT (Messfehler wie WP102)")

    # --- Stufe 3 ---
    ex = make_spk()
    t0 = time.time()
    emb = {k: embed(ex, segs[k]) for k in keys}
    spk_ms = 1000 * (time.time() - t0) / max(len(keys), 1)
    prof = {}
    for v, fs in voices.items():
        e = np.mean([embed(ex, K.load(f)) for f in fs[:15]], axis=0)
        prof[v] = e / np.linalg.norm(e)
    gen = [float(emb[k] @ prof[r["voice"]]) for r in recs if r["set"] == "pos" for k in r["ev"]["TM"]]
    imp = [float(emb[k] @ prof[r["voice"]]) for r in recs if r["set"] != "pos" and not r["own"] for k in r["ev"]["TM"]]
    pct = lambda L: {p: round(float(np.percentile(L, p)), 2) for p in (5, 25, 50, 75, 95)} if L else {}
    dist = {"eigene Stimme (Positiv-Kandidaten)": pct(gen), "fremde/Fernseher (Negativ-Kandidaten)": pct(imp)}
    log(f"Sprecher: {spk_ms:.0f} ms je Segment; Cosinus-Verteilung {dist}")

    # --- Aggregation ---
    spk_thrs = [None] + [float(s) for s in a.spk_thr.split(",")]
    rows = []
    for mdist, mname in ((1, "d1"), (2, "app")):
      for cond in a.cond.split(","):
        R = [r for r in recs if r["cond"] == cond]
        pos = [r for r in R if r["set"] == "pos"]
        hours = lambda sel: sum(r["h"] for r in R if sel(r)) or 1e-9
        h_neg, h_for, h_tv = (hours(lambda r: r["set"] == "neg"), hours(lambda r: r["set"] == "neg" and not r["own"]),
                              hours(lambda r: r["set"] == "tv"))
        for rule in RULES:
            for var in [None] + variants:
                for st in spk_thrs:
                    def ok(r, k):
                        if var and not K.matches_wake_word(text[var][k], mdist): return False
                        return st is None or float(emb[k] @ prof[r["voice"]]) >= st
                    cnt = lambda sel: sum(ok(r, k) for r in R if sel(r) for k in r["ev"][rule])
                    hit = sum(any(ok(r, k) for k in r["ev"][rule]) for r in pos)
                    hit1 = sum(bool(r["ev"][rule]) for r in pos)
                    fa_neg = cnt(lambda r: r["set"] == "neg")
                    rows.append({
                        "match": mname, "cond": cond, "stage1": rule, "stage2": var or "-", "spk_thr": st if st is not None else "-",
                        "hit_pct": round(100 * hit / len(pos), 1), "hit_stage1_pct": round(100 * hit1 / len(pos), 1),
                        "fa_h_neg": round(fa_neg / h_neg, 2),
                        "fa_h_neg_foreign": round(cnt(lambda r: r["set"] == "neg" and not r["own"]) / h_for, 2),
                        "fa_h_tv": round(cnt(lambda r: r["set"] == "tv") / h_tv, 2),
                        "n_pos": len(pos), "fa_neg": fa_neg, "h_neg": round(h_neg, 2), "h_tv": round(h_tv, 2)})
    with open(f"{a.out}/station_table.csv", "w", newline="") as f:
        w = csv.DictWriter(f, list(rows[0])); w.writeheader(); w.writerows(rows)
    with open(f"{a.out}/station_table.md", "w") as f:
        f.write("| Match | Bedingung | Stufe 1 | Stufe 2 | Sprecher >= | Treffer % (nur S1) | FA/h neg | FA/h neg fremde Stimme | FA/h Fernseher |\n"
                "|---|---|---|---|---|---|---|---|---|\n")
        for r in rows:
            f.write(f"| {r['match']} | {r['cond']} | {r['stage1']} | {r['stage2']} | {r['spk_thr']} | {r['hit_pct']} ({r['hit_stage1_pct']}) | "
                    f"{r['fa_h_neg']} | {r['fa_h_neg_foreign']} | {r['fa_h_tv']} |\n")
    ram = []
    if not a.no_probe:
        for nm in ["stage1"] + variants + ["spk"]:
            r = subprocess.run([sys.executable, "-I", os.path.abspath(__file__), "--probe", nm], capture_output=True, text=True)
            try: ram.append(json.loads(r.stdout.strip().splitlines()[-1]))
            except Exception: ram.append({"name": nm, "error": r.stderr[-200:]})
    meta = {"neg_h": nh, "neg_clips": len(neg), "excluded": excl,
            "excluded_hits": {n: scan[n]["text"] for n in excl if n in scan}, "tv_h": th, "segments": len(keys),
            "sanity": sanity, "stage1_cpu_rtf": stage1_rtf, "spk_ms_per_seg": spk_ms, "stage2": tstat, "ram_mb": ram,
            "cos_dist": dist, "params": vars(a), "voices": len(tmpl), "tail_s": TAIL}
    json.dump(meta, open(f"{a.out}/station_meta.json", "w"), indent=1, default=str)
    merged = dict(old)
    merged.update({v: {"|".join(map(str, k)): t for k, t in d.items()} for v, d in text.items()})
    json.dump(merged, open(tcache, "w"))
    log("fertig ->", a.out)


if __name__ == "__main__":
    main()
