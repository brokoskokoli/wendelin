#!/usr/bin/env python3
"""Misst sherpa-onnx-KWS fuer das Wake Word (WP42-Spike), ohne Geraet.

Aufruf (Python-venv ausserhalb des Repos, siehe tool/kws_measure.md):
  ~/wendelin-models/kws/venv/bin/python tool/kws_measure.py \
      --model-dir <entpacktes KWS-Modell> --pos <wav-ordner> --neg <wav-ordner> \
      [--chunk 8|16] [--bpe] [--cond clean,noise,reverb] \
      [--thr 0.1,0.25,0.4] [--boost 1.0,2.0,3.0] [--kw "V EH1 N D AH0 L IY2 N" ...]

Ausgabe: Markdown-Tabellen (Variante x Schwelle x Bedingung -> Trefferquote,
Falschausloesungen/h, Latenz, Echtzeitfaktor). Aufnahmen bleiben lokal.
Mono-WAVs mit 16 kHz; andere Raten werden einfach resampled.

Zweistufige Entscheidung (WP44 Nachtrag 2, K29), Python-venv mit openwakeword,
onnxruntime und sherpa-onnx (~/wendelin-models/kws/wp58/venv):
  python -I tool/kws_measure.py --two-stage --enroll <wav-ordner Stimme_NN.wav> \
      --pos <wav-ordner> --neg <wav-ordner> --oww <ordner mit melspectrogram/embedding_model.onnx> \
      --whisper <sherpa-whisper-ordner> [--model wendelin.onnx] [--neg-max-h 1.0] [--cond clean,both]
Je Stimme sind die ersten 15 Einlern-Aufnahmen die Vorlagen, die Positiv-Clips derselben Stimme der Test.
Stufe 1 = Modell ueber niedriger Schwelle ODER Kosinus-Aehnlichkeit zu einer Vorlage; Stufe 2 =
Whisper-Transkript der letzten 2 s enthaelt unscharf "Wendelin" (Spiegel von matchesWakeWord in Dart).
"""
import argparse, glob, os, sys, time
import numpy as np
import soundfile as sf

SR = 16000


def load(path):
    x, sr = sf.read(path, dtype="float32", always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        n = int(len(x) * SR / sr)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype("float32")
    return x


def speech_end(x, thr_db=-40.0):
    """Zeitpunkt (s) des letzten Frames mit Pegel ueber Schwelle (Wortende)."""
    f = 160
    n = len(x) // f
    rms = np.sqrt((x[: n * f].reshape(n, f) ** 2).mean(axis=1) + 1e-12)
    db = 20 * np.log10(rms / (np.abs(x).max() + 1e-9) + 1e-12)
    idx = np.where(db > thr_db)[0]
    return (idx[-1] + 1) * f / SR if len(idx) else 0.0


def add_noise(x, snr_db, rng):
    # rosa-ish Rauschen: Weiss, tiefpassgefiltert
    n = rng.standard_normal(len(x)).astype("float32")
    n = np.convolve(n, np.ones(4) / 4, mode="same")
    p = (x ** 2).mean() + 1e-9
    n *= np.sqrt(p / (10 ** (snr_db / 10)) / ((n ** 2).mean() + 1e-12))
    return (x + n).astype("float32")


def add_reverb(x, rt60, rng):
    t = np.arange(int(rt60 * SR)) / SR
    ir = rng.standard_normal(len(t)) * np.exp(-6.9 * t / rt60)
    ir[0] = 1.0
    y = np.convolve(x, ir.astype("float32"))[: len(x)]
    return (y * (np.abs(x).max() / (np.abs(y).max() + 1e-9))).astype("float32")


def condition(x, name, rng):
    if name == "clean":
        return x
    if name == "noise":
        return add_noise(x, 10, rng)
    if name == "reverb":
        return add_reverb(x, 0.5, rng)
    if name == "both":
        return add_noise(add_reverb(x, 0.5, rng), 10, rng)
    raise SystemExit(f"unbekannte Bedingung {name}")


def make_spotter(model_dir, chunk, bpe, threads):
    import sherpa_onnx
    def pick(kind):
        pat = f"{kind}-*chunk-{chunk}-left-64.int8.onnx"
        r = glob.glob(os.path.join(model_dir, pat))
        if not r:  # Decoder gibt es nur als fp32 (klein)
            pat = f"{kind}-*chunk-{chunk}-left-64.onnx"
            r = glob.glob(os.path.join(model_dir, pat))
        if not r:
            raise SystemExit(f"{pat} nicht in {model_dir}")
        return r[0]
    dummy = os.path.join(model_dir, "_dummy_keywords.txt")
    open(dummy, "w").write("▁HE LL O @X\n" if bpe else "HH AH0 L OW1 @X\n")
    return sherpa_onnx.KeywordSpotter(
        tokens=os.path.join(model_dir, "tokens.txt"),
        encoder=pick("encoder"), decoder=pick("decoder"), joiner=pick("joiner"),
        keywords_file=dummy, num_threads=threads, provider="cpu",
    )


def run(spotter, x, kwline, tail=0.6, step=0.1):
    """Streamt x; liefert (Trefferzeiten in s, Rechenzeit)."""
    s = spotter.create_stream(kwline)
    hits = []
    n = int(step * SR)
    xx = np.concatenate([x, np.zeros(int(tail * SR), "float32")])
    t0 = time.process_time()
    for i in range(0, len(xx), n):
        s.accept_waveform(SR, xx[i:i + n])
        while spotter.is_ready(s):
            spotter.decode_stream(s)
            r = spotter.get_result(s)
            if r:
                hits.append(min(i + n, len(xx)) / SR)
                spotter.reset_stream(s)
    return hits, time.process_time() - t0


def main():
    if "--two-stage" in sys.argv:
        sys.argv.remove("--two-stage")
        return two_stage_main()
    a = argparse.ArgumentParser()
    a.add_argument("--model-dir", required=True)
    a.add_argument("--pos", required=True)
    a.add_argument("--neg", required=True)
    a.add_argument("--chunk", type=int, default=16)
    a.add_argument("--bpe", action="store_true", help="BPE-Modell (gigaspeech) statt Phoneme")
    a.add_argument("--bpe-model")
    a.add_argument("--kw", action="append", help="Schluesselwort-Tokens; BPE: Wort, z. B. WENDELIN")
    a.add_argument("--thr", default="0.1,0.25,0.4")
    a.add_argument("--boost", default="1.0,2.0,3.0")
    a.add_argument("--cond", default="clean,noise,reverb")
    a.add_argument("--threads", type=int, default=1)
    a.add_argument("--seed", type=int, default=1)
    a.add_argument("--neg-max-h", type=float, default=0, help="Negativ-Audio auf Stunden begrenzen")
    a = a.parse_args()
    rng = np.random.default_rng(a.seed)
    kws = a.kw or ["V EH1 N D AH0 L IY2 N", "W EH1 N D AH0 L IH0 N", "V EH1 N D AH0 L IH0 N"]
    if a.bpe:
        import sentencepiece as spm
        sp = spm.SentencePieceProcessor()
        sp.load(a.bpe_model or os.path.join(a.model_dir, "bpe.model"))
        kws = [" ".join(sp.encode(w.upper(), out_type=str)) for w in kws]
    sp_ = make_spotter(a.model_dir, a.chunk, a.bpe, a.threads)
    pos = sorted(glob.glob(os.path.join(a.pos, "*.wav")))
    neg = sorted(glob.glob(os.path.join(a.neg, "*.wav")))
    print(f"Positiv: {len(pos)} Dateien, Negativ: {len(neg)} Dateien, Chunk {a.chunk}, "
          f"{'BPE' if a.bpe else 'Phoneme'}\n")
    posx = [load(p) for p in pos]
    negx = []
    for p in neg:
        negx.append(load(p))
        if a.neg_max_h and sum(len(x) for x in negx) / SR / 3600 >= a.neg_max_h:
            break
    print("| Bedingung | Variante | Boost | Schwelle | Trefferquote | FA/h | Latenz median (s) | RTF |")
    print("|---|---|---|---|---|---|---|---|")
    for cond in a.cond.split(","):
        px = [condition(x, cond, rng) for x in posx]
        nx = [condition(x, cond, rng) for x in negx]
        nh = sum(len(x) for x in nx) / SR / 3600
        for kw in kws:
            for b in map(float, a.boost.split(",")):
                for th in map(float, a.thr.split(",")):
                    line = f"{kw} :{b} #{th} @WENDELIN"
                    ok, lat, cpu, dur = 0, [], 0.0, 0.0
                    for x, p in zip(px, pos):
                        h, c = run(sp_, x, line)
                        cpu += c; dur += len(x) / SR
                        ok += bool(h)
                        if h and "_solo" in os.path.basename(p):
                            lat.append(h[0] - speech_end(x))
                    fa = 0
                    for x in nx:
                        h, c = run(sp_, x, line)
                        cpu += c; dur += len(x) / SR
                        fa += len(h)
                    l = f"{np.median(lat):.2f}" if lat else "-"
                    print(f"| {cond} | {kw} | {b} | {th} | {ok}/{len(px)} = {100*ok/max(1,len(px)):.0f} % "
                          f"| {fa/nh if nh else 0:.1f} ({fa}) | {l} | {cpu/dur:.3f} |", flush=True)
    print(f"\nNegativ-Audio je Bedingung: {nh:.2f} h")


# ---------- zweistufige Entscheidung (WP44 Nachtrag 2) ----------
SPELL = ["wendelin", "wendeline", "wendelien", "wendlin", "vendelin", "wendeling", "wendelyn", "wendellin"]


def fold(t):
    import unicodedata
    t = t.lower().replace("ß", "ss")
    t = "".join(c for c in unicodedata.normalize("NFD", t) if unicodedata.category(c) != "Mn")
    return " ".join("".join(c if c.isalnum() else " " for c in t).split())


def dist(a, b):
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] != b[j - 1]))
        prev = cur
    return prev[-1]


def matches_wake_word(text, max_dist=1):
    w = fold(text).split()
    near = lambda s: any(abs(len(s) - len(p)) <= 3 and dist(s, p) <= max_dist for p in SPELL)
    return any(near(w[i]) or (i + 1 < len(w) and near(w[i] + w[i + 1])) for i in range(len(w)))


def two_stage_main():
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, os.path.join(here, "train_wake_word"))
    import common as C
    import sherpa_onnx
    a = argparse.ArgumentParser()
    a.add_argument("--enroll", required=True); a.add_argument("--pos", required=True)
    a.add_argument("--neg", required=True); a.add_argument("--oww", required=True)
    a.add_argument("--whisper", required=True); a.add_argument("--whisper-name", default="base")
    a.add_argument("--model"); a.add_argument("--model-thr", default="0.3,0.5")
    a.add_argument("--thr", default="0.7,0.8,0.85,0.9,0.95")
    a.add_argument("--n-templates", type=int, default=15)
    a.add_argument("--tmpl-offset", type=float, default=0.3, help="Fensterende nach Wortende (s) fuer die Vorlage")
    a.add_argument("--pool", action="store_true", help="Mittelwert der letzten 8 Embeddings statt 16x96")
    a.add_argument("--neg-max-h", type=float, default=1.0); a.add_argument("--cond", default="clean,both")
    a.add_argument("--seed", type=int, default=1)
    a = a.parse_args()
    rng = np.random.default_rng(a.seed)
    af = C.make_features(a.oww, 1)
    sess = None
    if a.model:
        import onnxruntime as ort
        so = ort.SessionOptions(); so.intra_op_num_threads = 1
        sess = ort.InferenceSession(a.model, so, providers=["CPUExecutionProvider"])
    w = a.whisper
    rec = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=f"{w}/{a.whisper_name}-encoder.int8.onnx", decoder=f"{w}/{a.whisper_name}-decoder.int8.onnx",
        tokens=f"{w}/{a.whisper_name}-tokens.txt", language="de", num_threads=4)
    pad = lambda x: np.concatenate([np.zeros(C.SR, "float32"), x, np.zeros(C.SR, "float32")])

    def windows(x):
        """Fenster-Vektoren (N,D) normiert, Fensterenden, Modellwerte."""
        emb = C.embed(af, [pad(x)])[0]
        n = len(emb) - C.WIN + 1
        if n <= 0:
            return np.zeros((0, 1)), np.zeros(0, int), np.zeros(0)
        W = np.stack([emb[j:j + C.WIN] for j in range(n)]).astype("float32")
        ms = sess.run(None, {"input": W})[0][:, 0] if sess else np.zeros(n)
        V = W[:, -8:].mean(axis=1) if a.pool else W.reshape(n, -1)
        V = V / (np.linalg.norm(V, axis=1, keepdims=True) + 1e-9)
        return V, np.array([C.window_end(j) for j in range(n)]), ms

    def transcribe(x, end):
        seg = x[max(0, end - 2 * C.SR):end]
        s = rec.create_stream(); s.accept_waveform(C.SR, seg.astype("float32")); rec.decode_stream(s)
        return s.result.text

    def events(hit_idx, refr=19):
        ev, last = [], -10 ** 9
        for j in hit_idx:
            if j - last >= refr:
                ev.append(j)
                last = j
        return ev

    voices = {}
    for f in sorted(glob.glob(os.path.join(a.enroll, "*.wav"))):
        voices.setdefault(os.path.basename(f).split("_")[0], []).append(f)
    posf = {}
    for f in sorted(glob.glob(os.path.join(a.pos, "*.wav"))):
        posf.setdefault(os.path.basename(f).split("_")[1].split(".")[0], []).append(f)
    tmpl = {}
    for v, fs in voices.items():
        T = []
        for f in fs[: a.n_templates]:
            x = load(f); V, we, _ = windows(x)
            j = int(np.argmax(we >= (C.SR + speech_end(x) * C.SR + a.tmpl_offset * C.SR)))
            T.append(V[j])
        tmpl[v] = np.stack(T)
    negx = []
    for p in sorted(glob.glob(os.path.join(a.neg, "*.wav"))):
        negx.append(load(p))
        if sum(map(len, negx)) / C.SR / 3600 >= a.neg_max_h:
            break
    thrs = [float(t) for t in a.thr.split(",")]
    mthrs = [float(t) for t in a.model_thr.split(",")] if sess else []
    rules = [("Vorlage", "t", t) for t in thrs] + [("Modell", "m", t) for t in mthrs] + \
            ([("Modell " + str(mthrs[0]) + " ODER Vorlage", "tm", t) for t in thrs[1:3]] if mthrs else [])
    print(f"Einlerner (Stimmen): {len(tmpl)}, Vorlagen je Stimme: {a.n_templates}, Negativ {sum(map(len, negx))/C.SR/3600:.2f} h, "
          f"Whisper {a.whisper_name}, Merkmal {'Mittel 8' if a.pool else '16x96'}, Vorlagenversatz {a.tmpl_offset} s\n")
    print("| Bedingung | Regel | Schwelle | Treffer Stufe 1 | Kandidaten/h | Treffer nach Stufe 2 (Abstand 1 / 2) | bestaetigt/h (Abstand 1 / 2) | Whisper-RTF |")
    print("|---|---|---|---|---|---|---|---|")
    for cond in a.cond.split(","):
        P = {v: [condition(load(f), cond, rng) for f in fs] for v, fs in posf.items()}
        N = [condition(x, cond, rng) for x in negx]
        nh = sum(map(len, N)) / C.SR / 3600
        PW = {v: [windows(x) for x in xs] for v, xs in P.items()}
        NW = [windows(x) for x in N]
        cache, wt, wd = {}, 0.0, 0.0
        for name, kind, thr in rules:
            tot = {"hit1": 0, "hit2": 0, "n": 0, "c": 0, "k": 0, "hit2b": 0, "kb": 0}
            for v, T in tmpl.items():
                def idx(win, kind=kind, thr=thr, T=T):
                    V, we, ms = win
                    if not len(V): return []
                    sim = (V @ T.T).max(axis=1)
                    mt = (mthrs[0] if kind == "tm" else thr)
                    ok = np.zeros(len(V), bool)
                    if "t" in kind: ok |= sim >= thr
                    if "m" in kind: ok |= ms >= mt
                    return events(np.where(ok)[0])
                def confirm(key, x, we, j, d=1):
                    nonlocal wt, wd
                    if key not in cache:
                        t0 = time.time(); cache[key] = transcribe(x, we[j])
                        wt += time.time() - t0; wd += min(2 * C.SR, we[j]) / C.SR
                    return matches_wake_word(cache[key], d)
                for ci, (x, win) in enumerate(zip(P[v], PW[v])):
                    ev = idx(win); tot["n"] += 1; tot["hit1"] += bool(ev)
                    xp = pad(x)
                    tot["hit2"] += any(confirm(("p", v, ci, j), xp, win[1], j) for j in ev[:3])
                    tot["hit2b"] += any(confirm(("p", v, ci, j), xp, win[1], j, 2) for j in ev[:3])
                for ci, (x, win) in enumerate(zip(N, NW)):
                    ev = idx(win); tot["c"] += len(ev)
                    xp = pad(x)
                    tot["k"] += sum(confirm(("n", ci, j), xp, win[1], j) for j in ev)
                    tot["kb"] += sum(confirm(("n", ci, j), xp, win[1], j, 2) for j in ev)
            nv = len(tmpl)
            print(f"| {cond} | {name} | {thr} | {tot['hit1']}/{tot['n']} = {100*tot['hit1']/tot['n']:.0f} % | "
                  f"{tot['c']/nv/nh:.1f} | {100*tot['hit2']/tot['n']:.0f} / {100*tot['hit2b']/tot['n']:.0f} % | "
                  f"{tot['k']/nv/nh:.2f} / {tot['kb']/nv/nh:.2f} | "
                  f"{wt/max(wd,1e-9):.2f} |", flush=True)
        print(f"\nNegativ-Audio ({cond}): {nh:.2f} h\n")


if __name__ == "__main__":
    main()
