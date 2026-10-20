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
WP111 (--compare): Vergleich „Wendelin“ gegen „Hey Wendelin“ und mehrerer Stufe-1-Programme (Vorlagen T, openWakeWord-Modell M, microWakeWord W,
sherpa-onnx-KWS K) auf denselben Audiodaten, siehe compare_main und docs/notes/wake-word-compare.md.
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
DATA111 = f"{KWS}/wp111/data"
WORK111 = f"{KWS}/wp111/work"
VOICES = ["Anna", "Eddy", "Flo", "Grandma", "Grandpa", "Reed", "Rocko", "Sandy", "Shelley"]
# WP111: je Wort Positivclips, Einlernclips (Vorlagen), Hotword-Liste der Stufe 2 und Stufe-2-Regel
WORDS = {
    "wendelin": {"pos": f"{DATA111}/pos_wendelin", "enroll": f"{KWS}/data/enroll", "hot": ["Wendelin"], "match": K.matches_wake_word,
                 "kws_bpe": ["WENDELIN", "VENDELIN", "VENDELINE"], "kws_ph": ["V EH1 N D AH0 L IY2 N", "W EH1 N D AH0 L IH0 N"]},
    "hey": {"pos": f"{DATA111}/pos_hey", "enroll": f"{DATA111}/enroll_hey", "hot": ["Hey Wendelin", "Wendelin"],
            "match": K.matches_hey_wake_word,
            "kws_bpe": ["HEY WENDELIN", "HEY VENDELIN", "HEY VENDELINE"],
            "kws_ph": ["HH EY1 V EH1 N D AH0 L IY2 N", "HH EY1 W EH1 N D AH0 L IH0 N"]},
}
VARIANTS = ["whisper-small", "parakeet", "parakeet-bs", "parakeet-hw1", "parakeet-hw2", "parakeet-hw3", "parakeet-hw5"]
RULES = {"T": "Vorlage", "M": "Modell v7", "TM": "Modell v7 ODER Vorlage"}


# ---------- Recognizer ----------
def make_rec(name, threads=4):
    """name: whisper-small, parakeet, parakeet-bs oder parakeet-hw<Score>[@<Wort>] (WP111: Hotwords je Wort)."""
    import sherpa_onnx as so
    name, _, word = name.partition("@")
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
    if word:                       # WP111: Hotword-Liste je Wort („Hey Wendelin“ und „Wendelin“)
        os.makedirs(WORK111, exist_ok=True)
        hw = f"{WORK111}/hotwords-{word}-{score}.txt"
        open(hw, "w").write("".join(f"{h}\n" for h in WORDS[word]["hot"]))
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
    elif name == "mww":                    # WP111: Pfad in der Umgebungsvariable WENDELIN_MWW
        from mww_stage import MwwScorer
        MwwScorer(os.environ["WENDELIN_MWW"]).probs(x)
    elif name.startswith("kws"):
        r = KwsRunner(name[3:] or "g"); r.hits(x, r.line("wendelin", 2.0, 0.25))
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
def exclusion_names(clips, scan):
    """Ausgeschlossen wird nach Treffern eines der beiden Erkenner (Parakeet `hit` ODER Whisper `hit2`) und b6-*; Labels/Referenztexte der Clips spielen keine Rolle."""
    return [c["name"] for c in clips if scan[c["name"]]["hit"] or scan[c["name"]].get("hit2") or c["name"].startswith("b6-")]


def scan_current(entry, n, need_other):
    """Gilt ein Cache-Eintrag des Negativscans noch? Gleiche Laenge `n`, und mit zweitem Erkenner (`need_other`) muss `hit2` vorliegen."""
    return entry is not None and entry["n"] == n and (not need_other or "hit2" in entry)


def check_pairs(files_a, files_b):
    """Positivmengen „Wendelin“/„Hey Wendelin“ muessen dieselben Dateinamen haben (gleiche Saetze, Tempi, Rausch-Seeds)."""
    assert [os.path.basename(f) for f in files_a] == [os.path.basename(f) for f in files_b], "Paare passen nicht"


def pick_neg(args, rec_plain, rec_other=None, cache=None):
    """Kurze Clips komplett, lange Clips (1..neg_long_max, je andere Stimme) die ersten --neg-min Minuten.
    Clips, deren Transkript "Wendelin" enthaelt (oder b6-*), werden ausgeschlossen. WP111: mit `rec_other` (zweiter, unabhaengiger
    Erkenner, Whisper) und `cache` entscheidet die Oder-Verknuepfung beider Erkenner (`exclusion_names`). Textvorlagen der Clips
    gehen nicht ein; der Ausschluss haengt nur an den Erkenner-Treffern und der Namensregel b6-*."""
    long_max = getattr(args, "neg_long_max", 8)
    clips = []
    for f in sorted(glob.glob(f"{KWS}/data/neg/*.wav")):
        b = os.path.basename(f)
        x = K.load(f)
        if b.startswith("long"):
            if int(re.match(r"long(\d+)", b).group(1)) > long_max:
                continue
            x = x[: int(args.neg_min * 60 * SR)]
        m = re.search(r"_([A-Za-z]+)\.wav$", b)
        clips.append({"name": b, "x": x, "voice": m.group(1) if m else None})
    cache = cache or f"{WORK}/neg_scan.json"
    scan = json.load(open(cache)) if os.path.exists(cache) else {}
    for c in clips:
        if scan_current(scan.get(c["name"]), len(c["x"]), rec_other is not None):
            continue
        chunks = [c["x"][i:i + 20 * SR] for i in range(0, len(c["x"]), 20 * SR)]
        texts = [decode(rec_plain, y) for y in chunks]
        hit = [t for t in texts if K.matches_wake_word(t, 1)]
        scan[c["name"]] = {"n": len(c["x"]), "hit": bool(hit), "text": " | ".join(hit)[:200]}
        if rec_other is not None:
            hit2 = [t for t in (decode(rec_other, y) for y in chunks) if K.matches_wake_word(t, 1)]
            scan[c["name"]].update({"hit2": bool(hit2), "text2": " | ".join(hit2)[:200]})
        json.dump(scan, open(cache, "w"))
    excl = exclusion_names(clips, scan)
    return [c for c in clips if c["name"] not in excl], excl, scan


# ---------- WP111: Vergleich Woerter x Programme (--compare) ----------
KWS_DIRS = {"g": ("x-sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01", True),
            "z": ("x-sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20", False)}
STAGE1_NAMES = {"T": "Vorlagen", "M": "openWakeWord v7", "W": "microWakeWord", "K": "sherpa-onnx KWS"}


class KwsRunner:
    """sherpa-onnx Keyword Spotting mit frei eingegebenem Wort (g = gigaspeech-BPE englisch, z = zh-en Phoneme)."""

    def __init__(self, m):
        d, self.bpe = KWS_DIRS[m]
        root = glob.glob(f"{KWS}/{d}/*/")[0]
        if self.bpe:
            import sentencepiece as spm
            self.sp = spm.SentencePieceProcessor(); self.sp.load(f"{root}bpe.model")
        self.spotter = K.make_spotter(root, 16, self.bpe, 1)

    def line(self, word, boost, thr):
        w = WORDS[word]
        toks = [" ".join(self.sp.encode(t, out_type=str)) for t in w["kws_bpe"]] if self.bpe else w["kws_ph"]
        return "/".join(f"{t} :{boost} #{thr} @{word.upper()}" for t in toks)

    def hits(self, x, line):
        return K.run(self.spotter, x, line)[0]


def parse_rules(spec):
    """T0.85 (Vorlagen-Kosinus), M0.5 (openWakeWord), W0.7 (microWakeWord), Kg2/0.25 (KWS Modell g|z, Boost/Schwelle)."""
    out = []
    for r in spec.split(","):
        r = r.strip()
        if r[0] == "K":
            b, t = r[2:].split("/")
            out.append({"name": r, "kind": "K", "model": r[1], "boost": float(b), "thr": float(t)})
        else:
            out.append({"name": r, "kind": r[0], "thr": float(r[1:])})
    return out


def wilson(k, n, z=1.96):
    if n == 0: return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def poisson_upper(k, hours):
    """Obere 95-%-Grenze (zweiseitig exakt, 97,5 % einseitig) der Rate in 1/h bei k Ereignissen in `hours`."""
    from scipy.stats import chi2
    return float(chi2.ppf(0.975, 2 * (k + 1)) / 2 / max(hours, 1e-9))


def render_compare(rows, path):
    """Markdown je Wort und Bedingung: Treffer mit Wilson-95-%-Intervall, FA/h mit Poisson-Obergrenze."""
    f = lambda v: str(v).replace(".", ",")
    out = []
    for word in sorted({r["word"] for r in rows}):
        for cond in dict.fromkeys(r["cond"] for r in rows):
            R = [r for r in rows if r["word"] == word and r["cond"] == cond]
            if not R: continue
            out.append(f"\n### Wort {word}, Bedingung {cond}\n")
            out.append("| Stufe 1 | Stufe 2 | Treffer % (n) [Wilson] | nur S1 % | Kand./h S1 | FA/h Sprache (≤95 %) | FA/h Fernseher (≤95 %) | Verwechsler % (n) | andere Phrase löst aus % |")
            out.append("|---|---|---|---|---|---|---|---|---|")
            for r in R:
                n, k, k1 = int(r["n_pos"]), int(r["hit"]), int(r["hit1"])
                lo, hi = wilson(k, n)
                hn, hv = float(r["h_neg"]), float(r["h_tv"])
                fa, fv = int(r["fa_neg"]), int(r["fa_tv"])
                nc, kc = int(r["n_conf"]), int(r["conf_hit"])
                nx, kx = int(r["n_cross"]), int(r["cross_hit"])
                out.append(f"| {r['rule']} | {r['stage2']} | {f(round(100 * k / max(n, 1), 1))} ({n}) [{f(round(100 * lo))}–{f(round(100 * hi))}] | "
                           f"{f(round(100 * k1 / max(n, 1), 1))} | {f(round(int(r['cand_neg']) / max(hn, 1e-9)))} | "
                           f"{f(round(fa / max(hn, 1e-9), 2))} (≤{f(round(poisson_upper(fa, hn), 1))}) | "
                           f"{f(round(fv / max(hv, 1e-9), 2))} (≤{f(round(poisson_upper(fv, hv), 1))}) | "
                           f"{f(round(100 * kc / max(nc, 1), 1))} ({nc}) | {f(round(100 * kx / max(nx, 1), 1))} ({nx}) |")
    open(path, "w").write("\n".join(out) + "\n")


class Oww:
    """Stufe 1 mit openWakeWord-Merkmalen: Fenster (Vorlagen-Vektoren, Fensterende, Klassifikatorwert) je Clip."""

    def __init__(self, model):
        import onnxruntime as ort
        self.af = C.make_features(f"{KWS}/wp58/dl/oww", 1)
        so_ = ort.SessionOptions(); so_.intra_op_num_threads = 1
        self.sess = ort.InferenceSession(model, so_, providers=["CPUExecutionProvider"])
        self.cpu = 0.0

    def windows(self, xp):
        t0 = time.process_time()
        emb = C.embed(self.af, [xp])[0]
        n = len(emb) - C.WIN + 1
        if n <= 0:
            return np.zeros((0, 1)), np.zeros(0, int), np.zeros(0)
        W = np.stack([emb[j:j + C.WIN] for j in range(n)]).astype("float32")
        ms = self.sess.run(None, {"input": W})[0][:, 0]
        V = W.reshape(n, -1)
        V = V / (np.linalg.norm(V, axis=1, keepdims=True) + 1e-9)
        self.cpu += time.process_time() - t0
        return V, np.array([C.window_end(j) for j in range(n)]), ms


def _events(ok, refr=19):
    ev, last = [], -10 ** 9
    for j in np.where(ok)[0]:
        if j - last >= refr:
            ev.append(int(j)); last = j
    return ev


def compare_main(a):
    """Gleiche Audiodaten fuer alle Woerter und Programme: Stufe 1 (T/M/W/K) -> Stufe 2 (Parakeet ohne/mit Hotwords).
    Pos: 9 macOS-Stimmen, Paare „Wendelin“/„Hey Wendelin“ (gleiche Saetze, Tempi, Rausch-Parameter). Negativ: Sprache (>= 1,5 h), Fernseher
    (FLEURS test), Verwechsler. Ausgabe: compare_table.csv/.md, compare_meta.json in --out."""
    import hashlib
    t00 = time.time()
    log = lambda *s: print(f"[{time.time() - t00:6.0f}s]", *s, flush=True)
    words, conds, rules = a.words.split(","), a.cond.split(","), parse_rules(a.rules)
    variants = [v for v in a.variants.split(",") if v]
    mww_paths = dict(p.split("=") for p in a.mww.split(",") if p)
    os.makedirs(a.out, exist_ok=True); os.makedirs(WORK111, exist_ok=True)

    fleurs = [K.load(f) for f in sorted(glob.glob(f"{a.fleurs}/*.wav"))]
    fleurs = [x / (np.abs(x).max() + 1e-9) for x in fleurs]
    tvonly, th = [], 0.0
    for x in fleurs:
        if th >= a.tv_max_h: break
        tvonly.append(x); th += len(x) / SR / 3600
    log(f"FLEURS {len(fleurs)} Clips ({a.fleurs}), TV-only {len(tvonly)} Clips = {th:.2f} h")

    plain, other = make_rec("parakeet"), make_rec("whisper-small")
    neg, excl, scan = pick_neg(a, plain, other, cache=f"{WORK111}/neg_scan.json")
    del plain, other
    nh = sum(len(c["x"]) for c in neg) / SR / 3600
    log(f"Negativ: {len(neg)} Clips = {nh:.2f} h; ausgeschlossen (Parakeet ODER Whisper small hoeren (Hey) Wendelin): {len(excl)}")
    if nh < 1.5:
        log("WARNUNG: Negativsprache unter 1,5 h")

    posf = {w: sorted(glob.glob(f"{WORDS[w]['pos']}/*.wav")) for w in WORDS}
    check_pairs(posf["wendelin"], posf["hey"])
    conff = sorted(glob.glob(f"{DATA111}/conf/*.wav"))
    vof = lambda f: os.path.basename(f).split("_")[0]
    fp = hashlib.sha1(json.dumps([a.seed, conds, a.fleurs, a.tv_max_h, a.neg_min, a.neg_long_max,
                                  [c["name"] for c in neg], [os.path.basename(f) for f in posf["hey"]],
                                  [os.path.basename(f) for f in conff]]).encode()).hexdigest()[:10]

    O = Oww(a.model)
    pad = lambda x: np.concatenate([np.zeros(SR, "float32"), x, np.zeros(SR, "float32")])
    txt = " ".join(open(f).read().lower() for f in glob.glob(f"{KWS}/data/text/*.txt"))
    log(f"Textvorlagen der Negativ-Clips enthalten 'wendel': {'wendel' in txt}")
    mww = {}
    if any(r["kind"] == "W" for r in rules):
        from mww_stage import MwwScorer
        mww = {w: MwwScorer(mww_paths[w]) for w in words}
    kws = {m: KwsRunner(m) for m in {r["model"] for r in rules if r["kind"] == "K"}}
    tmpl = {}
    for w in words:                          # Vorlagen je Wort und Stimme (15 Einlernclips)
        by = {}
        for f in sorted(glob.glob(f"{WORDS[w]['enroll']}/*.wav")):
            by.setdefault(vof(f), []).append(f)
        tmpl[w] = {}
        for v, fs in by.items():
            T = []
            for f in fs[:15]:
                x = K.load(f); V, we, _ = O.windows(pad(x))
                T.append(V[int(np.argmax(we >= (SR + K.speech_end(x) * SR + 0.3 * SR)))])
            tmpl[w][v] = np.stack(T)
    O.cpu = 0.0
    cpu = {"T": 0.0, "M": 0.0, "W": 0.0, "K": 0.0}; aud = {"s": 0.0}

    segs, recs, lat = {}, [], {}

    def seg(key, xp, e):
        if key not in segs:
            segs[key] = (np.clip(xp[max(0, e - 2 * SR): e + int(TAIL * SR)], -1, 1) * 32767).astype("int16")
        return key

    for ci, cond in enumerate(conds):
        sets = {}
        for sn, files, kind, cls in (("pos_wendelin", posf["wendelin"], "pos", 1), ("pos_hey", posf["hey"], "pos", 1),
                                     ("conf", conff, "pos", 4)):
            sets[sn] = [apply_cond(K.load(f), cond, kind, np.random.default_rng([a.seed, ci, cls, i]), fleurs)
                        for i, f in enumerate(files)]
        sets["neg"] = [apply_cond(c["x"], cond, "neg", np.random.default_rng([a.seed, ci, 2, i]), fleurs) for i, c in enumerate(neg)]
        sets["tv"] = [apply_cond(x, cond, "tv", np.random.default_rng([a.seed, ci, 3, i]), fleurs) for i, x in enumerate(tvonly)]
        names = {"pos_wendelin": posf["wendelin"], "pos_hey": posf["hey"], "conf": conff}
        log(f"{cond}: Fenster berechnen")
        W = {sn: [O.windows(pad(x)) for x in xs] for sn, xs in sets.items()}
        aud["s"] += sum(len(x) for xs in sets.values() for x in xs) / SR
        for w in words:
            for sn, xs in sets.items():
                role = "own" if sn == f"pos_{w}" else "cross" if sn.startswith("pos_") else sn
                for i, x in enumerate(xs):
                    V, we, ms = W[sn][i]
                    xp = pad(x)
                    voice = vof(names[sn][i]) if sn in names else None
                    rec = {"cond": cond, "word": w, "set": role, "h": len(x) / SR / 3600, "ev": {}, "mult": {}}
                    wsc = None
                    for r in rules:
                        js, mult = [], 1
                        if len(we):
                            if r["kind"] == "T":
                                t0 = time.process_time()
                                vs = [voice] if voice in tmpl[w] else list(tmpl[w])
                                for v in vs:
                                    js += _events((V @ tmpl[w][v].T).max(axis=1) >= r["thr"])
                                mult = 1 if voice in tmpl[w] else len(vs)       # Negativ: jede Vorlagenstimme einzeln
                                cpu["T"] += time.process_time() - t0
                            elif r["kind"] == "M":
                                js = _events(ms >= r["thr"])
                            elif r["kind"] == "W":
                                t0 = time.process_time()
                                if wsc is None: wsc = mww[w].on_grid(xp, we)
                                js = _events(wsc >= r["thr"])
                                cpu["W"] += time.process_time() - t0
                            else:
                                t0 = time.process_time()
                                hs = kws[r["model"]].hits(x, kws[r["model"]].line(w, r["boost"], r["thr"]))
                                cpu["K"] += time.process_time() - t0
                                js = _events(np.isin(np.arange(len(we)), np.minimum(len(we) - 1, np.searchsorted(we, [h * SR + SR for h in hs]))))
                        if role in ("own", "cross", "conf"):
                            js = js[:3]
                        rec["ev"][r["name"]] = [seg((cond, sn, i, j), xp, int(we[j])) for j in js]
                        rec["mult"][r["name"]] = mult
                        if role == "own" and cond == "clean" and "_f0_" in os.path.basename(names[sn][i]) and js:
                            lat.setdefault(f"{w}|{r['name']}", []).append(float((we[js[0]] - SR) / SR - K.speech_end(x)))
                    recs.append(rec)
        del W, sets
        log(f"{cond}: Stufe 1 fertig, {len(segs)} Segmente gesamt")
    cpu["M"] = O.cpu
    s1_rtf = {k: v / max(aud["s"] * len(words) if k != "M" else aud["s"], 1e-9) for k, v in cpu.items()}
    cnt = {}
    for rec in recs:
        for rn, ks in rec["ev"].items():
            c = cnt.setdefault((rec["word"], rec["cond"], rn), 0); cnt[(rec["word"], rec["cond"], rn)] = c + len(ks)
    log("Kandidaten je Wort/Bedingung/Regel:", {f"{w}|{c}|{r}": n for (w, c, r), n in cnt.items()})

    if a.s1_only:
        json.dump({"candidates": {f"{w}|{c}|{r}": n for (w, c, r), n in cnt.items()}, "neg_h": nh, "tv_h": th, "segments": len(segs),
                   "stage1_cpu_rtf": s1_rtf}, open(f"{a.out}/compare_s1_only.json", "w"), indent=1)
        return log("nur Stufe 1 ->", a.out)

    # --- Stufe 2 ---
    tcache = f"{WORK111}/texts_{fp}.json"
    old = json.load(open(tcache)) if os.path.exists(tcache) else {}
    kj = lambda k: "|".join(map(str, k))
    text, tstat = {}, {}
    for var in variants:
        for w in ([None] if var == "parakeet-bs" else words):
            vn = var if w is None else f"{var}@{w}"
            need = {k for rec in recs if w is None or rec["word"] == w for ks in rec["ev"].values() for k in ks}
            have = old.get(vn, {})
            todo = [k for k in need if kj(k) not in have]
            text[vn] = {k: have[kj(k)] for k in need if kj(k) in have}
            if todo:
                rec_ = make_rec(vn)
                t0 = time.time()
                for k in todo:
                    text[vn][k] = decode(rec_, segs[k].astype("float32") / 32767)
                el = time.time() - t0
                tstat[vn] = {"segments": len(todo), "rtf": el / max(sum(len(segs[k]) for k in todo) / SR, 1e-9),
                             "ms_per_seg": 1000 * el / len(todo)}
                del rec_
                log(f"{vn}: {len(todo)} neue Segmente (von {len(need)}), RTF {tstat[vn]['rtf']:.3f}")
                old.setdefault(vn, {}).update({kj(k): t for k, t in text[vn].items()})
                json.dump(old, open(tcache, "w"))
    if "parakeet-bs" in text:                # Sanity: Hotwords veraendern den Text (Messfehler WP102 ausschliessen)
        for vn in text:
            if "-hw" in vn:
                diff = sum(1 for k, t in text[vn].items() if k in text["parakeet-bs"] and t.lower() != text["parakeet-bs"][k].lower())
                log(f"SANITY {vn}: Text weicht von parakeet-bs auf {diff}/{len(text[vn])} Segmenten ab")

    # --- Aggregation ---
    rows = []
    for w in words:
        match = WORDS[w]["match"]
        for cond in conds:
            R = [r for r in recs if r["word"] == w and r["cond"] == cond]
            for r_ in rules:
                rn = r_["name"]
                for var in [None] + variants:
                    vn = None if var is None else (var if var == "parakeet-bs" else f"{var}@{w}")
                    ok = lambda k: vn is None or match(text[vn][k], 2)
                    hit = lambda sel: sum(any(ok(k) for k in r["ev"][rn]) for r in R if r["set"] == sel)
                    cnts = lambda sel: sum(ok(k) for r in R if r["set"] == sel for k in r["ev"][rn])
                    hrs = lambda sel: sum(r["h"] * r["mult"][rn] for r in R if r["set"] == sel)
                    rows.append({"word": w, "cond": cond, "rule": rn, "stage2": var or "-",
                                 "n_pos": sum(r["set"] == "own" for r in R), "hit": hit("own"),
                                 "hit1": sum(bool(r["ev"][rn]) for r in R if r["set"] == "own"),
                                 "n_cross": sum(r["set"] == "cross" for r in R), "cross_hit": hit("cross"),
                                 "n_conf": sum(r["set"] == "conf" for r in R), "conf_hit": hit("conf"),
                                 "h_neg": round(hrs("neg"), 3), "fa_neg": cnts("neg"),
                                 "cand_neg": sum(len(r["ev"][rn]) for r in R if r["set"] == "neg"),
                                 "h_tv": round(hrs("tv"), 3), "fa_tv": cnts("tv")})
    with open(f"{a.out}/compare_table.csv", "w", newline="") as f:
        wr = csv.DictWriter(f, list(rows[0])); wr.writeheader(); wr.writerows(rows)
    render_compare(rows, f"{a.out}/compare_table.md")

    ram = []
    if not a.no_probe:
        envs = dict(os.environ, WENDELIN_MWW=next(iter(mww_paths.values()), ""))
        for nm in ["stage1"] + (["mww"] if mww else []) + [f"kws{m}" for m in kws] + ["parakeet-hw2@hey"]:
            r = subprocess.run([sys.executable, "-I", os.path.abspath(__file__), "--probe", nm], capture_output=True, text=True, env=envs)
            try: ram.append(json.loads(r.stdout.strip().splitlines()[-1]))
            except Exception: ram.append({"name": nm, "error": r.stderr[-200:]})
    meta = {"neg_h": nh, "neg_clips": len(neg), "excluded": excl, "tv_h": th, "segments": len(segs), "fingerprint": fp,
            "stage1_cpu_rtf": s1_rtf, "stage2": tstat, "ram_mb": ram, "candidates": {f"{w}|{c}|{r}": n for (w, c, r), n in cnt.items()},
            "latency_median_s": {k: round(float(np.median(v)), 2) for k, v in lat.items()}, "latency_n": {k: len(v) for k, v in lat.items()},
            "params": vars(a)}
    json.dump(meta, open(f"{a.out}/compare_meta.json", "w"), indent=1, default=str)
    log("fertig ->", a.out)


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
    # WP111 (--compare)
    ap.add_argument("--compare", action="store_true", help="WP111: Vergleich Woerter x Programme (compare_main)")
    ap.add_argument("--words", default="wendelin,hey")
    ap.add_argument("--rules", default="T0.9,M0.3,M0.5,W0.5,W0.8,Kg2/0.25")
    ap.add_argument("--mww", default="", help="Wort=Pfad.tflite,... (microWakeWord je Wort)")
    ap.add_argument("--model", default=f"{KWS}/wp58/out/wendelin_v7.onnx", help="openWakeWord-Klassifikator fuer die Regeln M")
    ap.add_argument("--neg-long-max", type=int, default=8, help="lange Negativ-Clips 1..N (WP111: 16 fuer >= 1,5 h)")
    ap.add_argument("--fleurs", default=f"{WORK}/fleurs/dev", help="FLEURS-Ordner fuer Fernsehton (WP111: test)")
    ap.add_argument("--s1-only", action="store_true", help="WP111: nur Stufe 1 und Kandidatenzahlen (Planung des Stufe-2-Aufwands)")
    ap.add_argument("--render", help="nur Tabelle aus compare_table.csv neu schreiben (Pfad der CSV)")
    a = ap.parse_args()
    if a.render:
        return render_compare(list(csv.DictReader(open(a.render))), os.path.splitext(a.render)[0] + ".md")
    if a.probe:
        return probe(a.probe)
    if a.compare:
        return compare_main(a)
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
