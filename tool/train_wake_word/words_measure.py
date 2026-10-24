#!/usr/bin/env python3
"""WP121 Etappe 2: fairer Vergleich der fuenf Woerter auf echten Aufnahmen (Schwellen-Sweep, gleiche FA/h, DET).

Venv und Rechner wie station_measure.py (`K=~/wendelin-models/kws`, `P="nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/words_measure.py"`).
Ergebnisse lokal unter `$K/wp121/results` (nie im Repo). Jeder Schritt faehrt nur nach, was im Cache fehlt:
  $P s1 oww               # openWakeWord (v7: Wendelin/Hey Wendelin, alexa.onnx: Alexa) und microWakeWord: Wertekurven je Fenster
  $P s1 kws --jobs 4      # sherpa-KWS Kz/Kg, alle Woerter, Schwellen-Sweep (ein Prozess je Konfiguration x Quelle)
  $P s2 --variants bs,hw2,hw3   # Stufe 2: Parakeet auf den Kandidaten aller Konfigurationen
  $P report               # grid.csv, tables.md, det.csv, det.png
  $P kontrolle            # Stufe 1 an den echten Labels (Kontrollen Alexa/Kobalos)
Quellen: pos_<geraet> (13 min, Labels), neg_<geraet> (37 min "Alltag leise", echt), syn (synthetische Negativsprache WP111),
fleurs (FLEURS test, erste 1,0 h). Labels: labels/labels.csv (Etappe 1); Status "fehler" wird nie gewertet.
"""
import argparse, csv, glob, json, os, re, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np
import soundfile as sf
import kws_measure as K
import station_measure as S

SR = 16000
KWS = os.path.expanduser("~/wendelin-models/kws")
OUT = os.environ.get("WENDELIN_WP121_OUT") or f"{KWS}/wp121/results"
WORK = f"{KWS}/wp121/work"
FIX = os.path.expanduser("~/wendelin-fixtures/wake/words")
DEVICES = ["huawei", "handy2"]
WORDS = ["Wendelin", "Hey Wendelin", "Alexa", "Hey Octavia", "Kobalos"]
PROGRAMS = ["M", "W", "Kz", "Kg"]            # M openWakeWord, W microWakeWord, Kz/Kg sherpa-KWS (zh-en / gigaspeech)
REFR = 1.5                                   # s: ein Wort loest hoechstens einmal je 1,5 s aus
TAIL = S.TAIL                                # Stufe 2 hoert bis 0,9 s nach dem Treffer
OWW_THR = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.98, 0.99]
KWS_CFG = [(3, 0.03), (3, 0.12), (3, 0.25), (3, 0.4), (6, 0.03), (6, 0.12), (10, 0.03), (10, 0.12)]     # (Boost, Schwelle) von sherpa-KWS
MAX_CAND = 8000                              # mehr Negativ-Kandidaten: Konfiguration in Stufe 2 uebersprungen
STAGES = ["-", "bs", "hw2", "hw3"]           # "-" = nur Stufe 1
ALL_SRC = [f"pos_{d}" for d in DEVICES] + [f"neg_{d}" for d in DEVICES] + ["syn", "fleurs"]
NEG_SRC = [s for s in ALL_SRC if not s.startswith("pos_")]


def key(word): return word.lower().replace(" ", "_")


def _prod(*slots):
    """Alle Kombinationen der Slot-Alternativen (je Slot eine Liste von Phonemfolgen) als Phonemfolgen."""
    out = [""]
    for alts in slots: out = [f"{o} {a}".strip() for o in out for a in alts]
    return out


# Aussprachevarianten (Befund 2): fuer ALLE Woerter gleich abgeleitet, nicht an den Aufnahmen ausgewaehlt. Je Wort werden die
# Stellen markiert, an denen die englische Lesung (CMUdict-Stil) und die deutsche Leseregel (Buchstabe -> Laut, Betonung auf dem
# Namensstamm) auseinandergehen; jedes Wort bekommt ALLE Kombinationen dieser Stellen (keine wird weggelassen).
#   Wendelin:  Anlaut W (en) / V (de); Auslaut IH0 (en, reduziert) / IY2, IY1 (de, langes i).
#   Octavia:   erstes O  AA0 (en) / AO0 (de, offen: Ok-TAH-via); Betonung EY1 (en) / AA1 (de); Ausgang AH0 (en) / AA0 (de).
#   Kobalos:   erstes O  OW1 (en) / AO1 (de, offen); zweite Silbe AH0 (en, reduziert) / AA1 (de, betont); Ausgang OW0 / AH0.
#   Alexa:     erstes A  AH0 (en) / AA0 (de); Ausgang AH0 (en) / AA0 (de).
_WEN = _prod(["W", "V"], ["EH1 N D AH0 L"], ["IH0 N", "IY2 N", "IY1 N"])
_OCT = _prod(["AA0", "AO0"], ["K T"], ["EY1", "AA1"], ["V IY0"], ["AH0", "AA0"])
_KOB = _prod(["K"], ["OW1", "AO1"], ["B"], ["AH0", "AA1"], ["L"], ["OW0", "AH0"], ["S"])
_ALX = _prod(["AH0", "AA0"], ["L EH1 K S"], ["AH0", "AA0"])



SPEC = {
    "Wendelin": {"hot": ["Wendelin"], "bpe": [s.replace(" ", "") for s in _prod(["W", "V"], ["ENDELIN", "ENDELINE"])],
                 "ph": _WEN, "oww": "v7", "mww": "wendelin"},
    "Hey Wendelin": {"hot": ["Hey Wendelin", "Wendelin"], "bpe": ["HEY " + s.replace(" ", "") for s in _prod(["W", "V"], ["ENDELIN", "ENDELINE"])],
                     "ph": ["HH EY1 " + p for p in _WEN], "oww": "v7", "mww": "hey"},
    "Alexa": {"hot": ["Alexa"], "bpe": ["ALEXA", "ALEKSA"], "ph": _ALX, "oww": "alexa", "mww": None},
    "Hey Octavia": {"hot": ["Hey Octavia", "Octavia"],
                    "bpe": ["HEY " + s.replace(" ", "") for s in _prod(["OC", "OK"], ["TAVIA", "TAWIA"])],
                    "ph": ["HH EY1 " + p for p in _OCT], "oww": "oct", "mww": None},
    "Kobalos": {"hot": ["Kobalos"], "bpe": [s.replace(" ", "") for s in _prod(["K", "C"], ["OBALOS", "OBALUS"])],
                "ph": _KOB, "oww": "kob", "mww": None},
}


# ---------- Stufe-2-Regeln fuer die neuen Woerter (Aufbau wie kws_measure.matches_*) ----------
ALEXA_SPELL = {"alexa", "aleksa", "alexah", "alexer", "alecksa", "aleksah", "alexxa", "alexsa", "alekssa", "alecsa"}
ALEXA_NOT = {"alexi", "alexe", "alexo", "alexy", "alexis", "alexia"}
OCTAVIA_SPELL = {"octavia", "oktavia", "ottavia", "octavja", "oktavja", "oktawia", "octawia", "octavea", "oktavea", "octaviah", "oktaviah",
                 "octavya", "oktavya"}
OCTAVIA_NOT = {"oktave", "oktaven", "oktavian", "octavian", "octavio", "oktavio", "ottavio", "octavius", "oktavius", "olivia",
               "oktavias", "ottaviana", "octaviana", "oktaviana"}
KOBALOS_SPELL = {"kobalos", "cobalos", "kobalus", "cobalus", "kobbalos", "cobbalos", "kobalo", "cobalo", "kobalas", "cobalas", "kowalos"}
KOBALOS_NOT = {"kobalt", "cobalt", "kobold", "kobolde", "kobolds", "kobaltos", "cobaltos", "carlos", "karlos", "colonos", "kolonos"}


def _near(s, spell, nots, targets, minlen=6):
    """Bekannte Schreibweise, sonst hoechstens eine Aenderung zu einem Ziel (ab minlen Zeichen), Verwechsler ausgenommen."""
    if s in spell: return True
    if s in nots or len(s) < minlen: return False
    return min(K.dist(s, t) for t in targets) <= 1


def _words_match(text, near):
    """Ein Wort oder zwei benachbarte Teile (nicht durch Funktionswort getrennt) treffen."""
    w = K.fold(text).split()
    for i in range(len(w)):
        if near(w[i]): return True
        if i + 1 < len(w) and w[i + 1] not in K.NOT_SPLIT_TAIL and near(w[i] + w[i + 1]): return True
    return False


def _hey_match(text, near):
    """Hey-Wort direkt vor dem Namen (auch zusammengeschrieben/getrennt)."""
    w = K.fold(text).split()
    for i in range(len(w)):
        if w[i] in K.HEY_WORDS and i + 1 < len(w):
            if near(w[i + 1]): return True
            if i + 2 < len(w) and w[i + 2] not in K.NOT_SPLIT_TAIL and near(w[i + 1] + w[i + 2]): return True
        for h in ("hey", "hei"):
            if w[i].startswith(h) and len(w[i]) > len(h) + 5 and near(w[i][len(h):]): return True
    return False


def matches_alexa(text, max_dist=2):
    near = lambda s: _near(s, ALEXA_SPELL, ALEXA_NOT, ("alexa", "aleksa"), 5)
    w = K.fold(text).split()
    return any(near(a) or (a == "alex" and b == "a") for a, b in zip(w, w[1:] + [""]))


def matches_hey_octavia(text, max_dist=2):
    return _hey_match(text, lambda s: _near(s, OCTAVIA_SPELL, OCTAVIA_NOT, ("octavia", "oktavia")))


def matches_kobalos(text, max_dist=2):
    return _words_match(text, lambda s: _near(s, KOBALOS_SPELL, KOBALOS_NOT, ("kobalos", "cobalos")))


MATCH = {"Wendelin": K.matches_wake_word, "Hey Wendelin": K.matches_hey_wake_word, "Alexa": matches_alexa,
         "Hey Octavia": matches_hey_octavia, "Kobalos": matches_kobalos}


# ---------- Reine Helfer (Selbsttests in test_measure.py) ----------
def score_events(t, v, thr, refr=REFR):
    """Zeiten (s) der Ereignisse: Wert >= thr; nach einem Ereignis fruehestens nach `refr` s das naechste."""
    out, last = [], -1e9
    for i in np.where(np.asarray(v) >= thr)[0]:
        if t[i] - last >= refr:
            out.append(float(t[i])); last = t[i]
    return out


def merge_times(times, refr=REFR):
    out, last = [], -1e9
    for x in sorted(times):
        if x - last >= refr:
            out.append(x); last = x
    return out


def label_window(start, end, status):
    """Zeitfenster (s), in dem ein Treffer zum Label zaehlt; "unsicher" (zusammengezogene/lange Aeusserung) toleranter (Maintainer 2026-10-21)."""
    return (start - 0.5, end + 2.0) if status == "unsicher" else (start - 0.3, end + 1.2)


def read_labels(path=None):
    rows = []
    for r in csv.DictReader(open(path or f"{FIX}/labels/labels.csv")):
        if r["status"] == "fehler": continue          # Versprecher (B2, ca. 165,5 s) nie werten
        rows.append({"dev": r["geraet"], "block": int(r["block"]), "round": int(r["runde"]), "word": r["wort"],
                     "start": float(r["start"]), "end": float(r["ende"]), "status": r["status"]})
    return rows


def fa_limit(target_per_h, hours):
    """Hoechste Zahl Fehlalarme, bei der die Rate noch <= Ziel ist."""
    return int(np.floor(target_per_h * hours + 1e-9))


def pick_op(points, hours, target):
    """Beste Konfiguration mit FA-Rate <= target: hoechster Treffer, bei Gleichstand weniger FA, dann frueherer Eintrag.
    points: [{"hit": int, "fa": int, ...}]; None, wenn keine Konfiguration die Grenze einhaelt."""
    lim = fa_limit(target, hours)
    ok = [(i, p) for i, p in enumerate(points) if p["fa"] <= lim]
    return min(ok, key=lambda ip: (-ip[1]["hit"], ip[1]["fa"], ip[0]))[1] if ok else None


def pareto(points):
    """Nicht dominierte (fa, hit)-Punkte (weniger FA, mehr Treffer), aufsteigend nach fa."""
    best, out = -1, []
    for p in sorted(points, key=lambda p: (p["fa"], -p["hit"])):
        if p["hit"] > best:
            out.append(p); best = p["hit"]
    return out


# ---------- Daten ----------
def clip_list(src):
    """[(name, pfad)]: synthetische Negativ-Clips (WP111, mit dessen Ausschluss) bzw. FLEURS test bis 1,0 h."""
    if src == "syn":
        scan = json.load(open(f"{KWS}/wp111/work/neg_scan.json"))
        out = []
        for f in sorted(glob.glob(f"{KWS}/data/neg/*.wav")):
            b = os.path.basename(f)
            m = re.match(r"long(\d+)", b)
            e = scan.get(b)
            if (m and int(m.group(1)) > 16) or b.startswith("b6-") or (e and (e["hit"] or e.get("hit2"))): continue
            out.append((b, f))
        return out
    out, tot = [], 0.0
    for f in sorted(glob.glob(f"{KWS}/wp111/work/fleurs/test/*.wav")):
        if tot >= 1.0: break
        out.append((os.path.basename(f), f)); tot += sf.info(f).duration / 3600
    return out


def load_item(src, name):
    if src.startswith("pos_"): return K.load(f"{WORK}/all_{src[4:]}.wav")
    if src.startswith("neg_"): return K.load(f"{WORK}/neg_{src[4:]}.wav")
    x = K.load(dict(clip_list(src))[name])
    if src == "syn" and name.startswith("long"): x = x[: 7 * 60 * SR]
    return x / (np.abs(x).max() + 1e-9) if src == "fleurs" else x


def item_names(src):
    return [src] if src.startswith(("pos_", "neg_")) else [n for n, _ in clip_list(src)]


def iter_items(src):
    for n in item_names(src):
        yield n, load_item(src, n)


def src_hours(src):
    p = f"{OUT}/hours.json"
    d = json.load(open(p)) if os.path.exists(p) else {}
    if src not in d:
        d[src] = round(sum(len(x) for _, x in iter_items(src)) / SR / 3600, 4)
        os.makedirs(OUT, exist_ok=True); json.dump(d, open(p, "w"))
    return d[src]


# ---------- Stufe 1 ----------
def run_oww(srcs):
    """Wertekurven von v7, alexa.onnx und microWakeWord je Fenster (ein Embedding je Clip) -> s1/oww/<src>.npz"""
    import onnxruntime as ort
    from mww_stage import MwwScorer
    O = S.Oww(f"{KWS}/wp58/out/wendelin_v7.onnx")
    so_ = ort.SessionOptions(); so_.intra_op_num_threads = 1
    alexa = ort.InferenceSession(f"{KWS}/wp58/dl/oww-alexa/alexa.onnx", so_, providers=["CPUExecutionProvider"])
    nm = alexa.get_inputs()[0].name
    fixed = isinstance(alexa.get_inputs()[0].shape[0], int)          # Originalmodell mit fester Batchgroesse 1
    mp_ = lambda s: f"{KWS}/wp111/mww/trained_{s}_main/tflite_stream_state_internal_quant/stream_state_internal_quant.tflite"
    mww = {"wendelin": MwwScorer(mp_("w")), "hey": MwwScorer(mp_("h"))}
    pad = lambda x: np.concatenate([np.zeros(SR, "float32"), x, np.zeros(SR, "float32")])
    for src in srcs:
        path = f"{OUT}/s1/oww/{src}.npz"
        if os.path.exists(path): continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        d, t0 = {}, time.time()
        for name, x in iter_items(src):
            xp = pad(x)
            emb = S.C.embed(O.af, [xp])[0]
            n = len(emb) - S.C.WIN + 1
            if n <= 0: continue
            W = np.stack([emb[j:j + S.C.WIN] for j in range(n)]).astype("float32")
            we = np.array([S.C.window_end(j) for j in range(n)])
            d[f"{name}|t"] = ((we - SR) / SR).astype("float32")           # Fensterende in Sekunden der Aufnahme (ohne Polster)
            d[f"{name}|v7"] = O.sess.run(None, {"input": W})[0][:, 0].astype("float32")
            d[f"{name}|alexa"] = (np.array([alexa.run(None, {nm: W[k:k + 1]})[0][0, 0] for k in range(n)]) if fixed
                                  else alexa.run(None, {nm: W})[0][:, 0]).astype("float32")
            for k, m in mww.items():
                d[f"{name}|mww_{k}"] = m.on_grid(xp, we).astype("float32")
        np.savez_compressed(path, **d)
        print(f"oww {src}: {len(d)} Felder, {time.time() - t0:.0f} s", flush=True)


DUMMY_LABEL = "X"
DUMMY_KW = {False: "ZH OY1 Z OY1 ZH @X\n", True: "Q Z Q Z @X\n"}      # (bpe) -> Platzhalter, praktisch nie gesprochen


def own_hits(spotter, x, line, label, tail=0.6, step=0.1):
    """Trefferzeiten (s) nur fuer `label`. Der Platzhalter der Spotter-Datei (Label X, frueher "hello") feuert auch in Streams mit
    eigenen Woertern und wurde als Treffer jedes Worts gezaehlt (konstante FA je Wort, Hey Octavia Kz 0 Treffer / 17 FA, Befund 1)."""
    s = spotter.create_stream(line)
    hits, n = [], int(step * SR)
    xx = np.concatenate([x, np.zeros(int(tail * SR), "float32")])
    for i in range(0, len(xx), n):
        s.accept_waveform(SR, xx[i:i + n])
        while spotter.is_ready(s):
            spotter.decode_stream(s)
            r = spotter.get_result(s)
            if r:
                if r == label: hits.append(min(i + n, len(xx)) / SR)
                spotter.reset_stream(s)
    return hits


OWW_X = {"oct": "oct.onnx", "kob": "kob.onnx"}       # eigene Modelle (run_words.sh) unter $KWS/wp121/models, Spalten in s1/oww/<src>.x.npz


def run_oww_x(srcs):
    """Wertekurven der Modelle oct/kob (Hey Octavia, Kobalos) auf demselben Fenstergitter wie run_oww -> s1/oww/<src>.x.npz"""
    O = S.Oww(f"{KWS}/wp58/out/wendelin_v7.onnx")                    # nur Mel/Embedding (af), gleiche Fenster wie bei v7
    import onnxruntime as ort
    so_ = ort.SessionOptions(); so_.intra_op_num_threads = 1
    ses = {k: ort.InferenceSession(f"{KWS}/wp121/models/{f}", so_, providers=["CPUExecutionProvider"]) for k, f in OWW_X.items()}
    pad = lambda x: np.concatenate([np.zeros(SR, "float32"), x, np.zeros(SR, "float32")])
    for src in srcs:
        path = f"{OUT}/s1/oww/{src}.x.npz"
        if os.path.exists(path): continue
        d, t0 = {}, time.time()
        for name, x in iter_items(src):
            emb = S.C.embed(O.af, [pad(x)])[0]
            n = len(emb) - S.C.WIN + 1
            if n <= 0: continue
            W_ = np.stack([emb[j:j + S.C.WIN] for j in range(n)]).astype("float32")
            d[f"{name}|t"] = ((np.array([S.C.window_end(j) for j in range(n)]) - SR) / SR).astype("float32")
            for k, ss in ses.items(): d[f"{name}|{k}"] = ss.run(None, {"input": W_})[0][:, 0].astype("float32")
        np.savez_compressed(path, **d)
        print(f"oww-x {src}: {len(d)} Felder, {time.time() - t0:.0f} s", flush=True)


class KwsX(S.KwsRunner):
    """sherpa-KWS mit den Woertern dieses Skripts (Tokens aus SPEC)."""

    def __init__(self, m):
        super().__init__(m)
        d, bpe = S.KWS_DIRS[m]
        self.spotter = K.make_spotter(glob.glob(f"{KWS}/{d}/*/")[0], 16, bpe, 1, DUMMY_KW[bool(bpe)])

    def own_hits(self, word, x, line): return own_hits(self.spotter, x, line, key(word).upper())

    def line(self, word, boost, thr):
        w = SPEC[word]
        toks = [" ".join(self.sp.encode(t, out_type=str)) for t in w["bpe"]] if self.bpe else w["ph"]
        return "/".join(f"{t} :{boost} #{thr} @{key(word).upper()}" for t in toks)


def cfg_s(cfg):
    """Konfigurationsname: KWS "boost/schwelle", sonst Schwelle."""
    return f"{cfg[0]:g}/{cfg[1]:g}" if isinstance(cfg, tuple) else f"{cfg:g}"


def cfg_order(cfg):
    """Vorsichtiger = groessere Zahl (hoehere Schwelle, kleinerer Boost); nur fuer den Gleichstand der Kalibrierung."""
    return cfg[1] - cfg[0] / 1000 if isinstance(cfg, tuple) else cfg


def kws_path(model, word, cfg, src):
    return f"{OUT}/s1/kws/{model}_{key(word)}_b{cfg[0]:g}_t{cfg[1]:g}/{src}.json"


def kws_task(a):
    model, word, cfg, src = a
    path = kws_path(model, word, cfg, src)
    if os.path.exists(path): return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    r = KwsX(model)
    line = r.line(word, cfg[0], cfg[1])
    res = {name: merge_times(r.own_hits(word, x, line)) for name, x in iter_items(src)}
    json.dump(res, open(path + ".tmp", "w")); os.replace(path + ".tmp", path)
    return path


def run_kws(jobs, models, words, srcs, cfgs):
    import multiprocessing as mp
    tasks = [(m, w, c, s) for s in srcs for m in models for w in words for c in cfgs]
    print(f"KWS: {len(tasks)} Aufgaben, {jobs} Prozesse", flush=True)
    with mp.get_context("spawn").Pool(jobs) as pool:
        for i, _ in enumerate(pool.imap_unordered(kws_task, tasks)):
            if i % 10 == 0: print(f"  {i + 1}/{len(tasks)}", flush=True)


class Stage1:
    """Ereignisse (Zeiten in s) je Programm x Wort x Schwelle x Quelle aus den Caches."""

    def __init__(self): self.npz = {}

    def _npz(self, src):
        if src not in self.npz:
            p = f"{OUT}/s1/oww/{src}.npz"
            self.npz[src] = dict(np.load(p)) if os.path.exists(p) else None
            px = p[:-4] + ".x.npz"
            if self.npz[src] is not None and os.path.exists(px):
                x = np.load(px)
                for k in x.files:
                    if not k.endswith("|t"): self.npz[src][k] = x[k]       # Spalten der eigenen Modelle (t ist dasselbe Gitter)
        return self.npz[src]

    def events(self, prog, word, cfg, src):
        """{item: [Zeit]} oder None, wenn (noch) keine Daten vorliegen."""
        if prog in ("Kz", "Kg"):
            p = kws_path(prog[1], word, cfg, src)
            return json.load(open(p)) if os.path.exists(p) else None
        z, col = self._npz(src), (SPEC[word]["oww"] if prog == "M" else SPEC[word]["mww"])
        if z is None or col is None: return None
        col = col if prog == "M" else f"mww_{col}"
        return {k[:-2]: score_events(z[k], z[f"{k[:-2]}|{col}"], cfg) for k in z if k.endswith("|t")}


def configs(prog): return KWS_CFG if prog in ("Kz", "Kg") else OWW_THR


def supported(prog, word):
    return prog.startswith("K") or SPEC[word]["oww" if prog == "M" else "mww"] is not None


# ---------- Stufe 2 ----------
def seg_key(src, item, t): return f"{src}|{item}|{int(round(t * SR / 160))}"


def segment(x, k):
    e = int(k.rsplit("|", 1)[1]) * 160
    return x[max(0, e - 2 * SR): e + int(TAIL * SR)]


def all_events(st, w, prog, thr):
    ev = {src: st.events(prog, w, thr, src) for src in ALL_SRC}
    return None if any(v is None for v in ev.values()) else ev


def collect_candidates(st):
    cand, skipped = {w: set() for w in WORDS}, []
    for w in WORDS:
        for prog in (p for p in PROGRAMS if supported(p, w)):
            for thr in configs(prog):
                ev = all_events(st, w, prog, thr)
                if ev is None: continue
                nneg = sum(len(t) for src in NEG_SRC for t in ev[src].values())
                if nneg > MAX_CAND:
                    skipped.append((w, prog, thr, nneg)); continue
                for src, d in ev.items():
                    for item, ts in d.items():
                        cand[w].update(seg_key(src, item, t) for t in ts)
    return cand, skipped


def var_name(var, w): return "bs" if var == "bs" else f"{var}@{key(w)}"


def run_s2(variants, threads):
    st = Stage1()
    cand, skipped = collect_candidates(st)
    print("uebersprungen (zu viele Negativ-Kandidaten):", skipped, flush=True)
    for w in WORDS:                                  # Hotwords je Wort fuer station_measure.make_rec
        S.WORDS.setdefault(key(w), {})["hot"] = SPEC[w]["hot"]
    S.WORK111 = f"{WORK}/hw"
    os.makedirs(f"{OUT}/s2", exist_ok=True)
    for var in variants:
        for w in ([None] if var == "bs" else WORDS):
            keys = set().union(*cand.values()) if w is None else cand[w]
            p = f"{OUT}/s2/{var_name(var, w)}.json"
            have = json.load(open(p)) if os.path.exists(p) else {}
            todo = sorted(k for k in keys if k not in have)
            print(f"{var_name(var, w)}: {len(todo)} neue Segmente (von {len(keys)})", flush=True)
            if not todo: continue
            rec = S.make_rec("parakeet-bs" if var == "bs" else f"parakeet-{var}@{key(w)}", threads)
            by_item = {}
            for k in todo:
                src, item, _ = k.split("|")
                by_item.setdefault((src, item), []).append(k)
            t_dump = time.time()
            for (src, item), ks in by_item.items():
                x = load_item(src, item)
                for k in ks:
                    have[k] = S.decode(rec, segment(x, k).astype("float32"))
                if time.time() - t_dump > 120:
                    json.dump(have, open(p, "w")); t_dump = time.time()
            json.dump(have, open(p, "w"))
            del rec


# ---------- Auswertung ----------
def texts(var, w):
    p = f"{OUT}/s2/{var_name(var, w)}.json"
    return json.load(open(p)) if os.path.exists(p) else {}


def grid_rows(st, labels):
    """Eine Zeile je Geraet x Wort x Programm x Schwelle x Stufe 2 (nur vollstaendig gemessene Konfigurationen)."""
    rows = []
    hr = {s: src_hours(s) for s in NEG_SRC}
    for w in WORDS:
        tx = {v: texts(v, w) for v in STAGES[1:]}
        for prog in (p for p in PROGRAMS if supported(p, w)):
            for thr in configs(prog):
                ev = all_events(st, w, prog, thr)
                if ev is None: continue
                for var in STAGES:
                    if var != "-" and not tx[var]: continue

                    def passes(src, item, t):
                        if var == "-": return True
                        return MATCH[w](tx[var][seg_key(src, item, t)], 2)       # KeyError = fehlende Stufe-2-Zeile -> sichtbar

                    try:
                        fa = {s: sum(passes(s, i, t) for i, ts in ev[s].items() for t in ts) for s in NEG_SRC}
                        rows += rows_for(w, prog, thr, var, ev, passes, fa, hr, labels)
                    except KeyError:
                        continue                    # Stufe 2 fuer diese Konfiguration (noch) unvollstaendig
    return rows


def rows_for(w, prog, thr, var, ev, passes, fa, hr, labels):
    out = []
    for dev in DEVICES:
        L = [r for r in labels if r["dev"] == dev]
        dets = ev[f"pos_{dev}"][f"pos_{dev}"]

        def hit(lb):
            lo, hi = label_window(lb["start"], lb["end"], lb["status"])
            return any(passes(f"pos_{dev}", f"pos_{dev}", t) for t in dets if lo <= t <= hi)

        own = [lb for lb in L if lb["word"] == w]
        h = [hit(lb) for lb in own]
        row = {"dev": dev, "word": w, "prog": prog, "thr": cfg_s(thr), "ord": cfg_order(thr), "stage2": var, "n": len(own), "hit": sum(h),
               "n_ok": sum(lb["status"] == "ok" for lb in own), "hit_ok": sum(x for x, lb in zip(h, own) if lb["status"] == "ok"),
               "fa_real": fa[f"neg_{dev}"], "h_real": hr[f"neg_{dev}"], "fa_syn": fa["syn"], "h_syn": hr["syn"],
               "fa_fleurs": fa["fleurs"], "h_fleurs": hr["fleurs"], "cand_real": sum(len(t) for t in ev[f"neg_{dev}"].values())}
        for b in range(1, 7):
            sel = [x for x, lb in zip(h, own) if lb["block"] == b]
            row[f"n_b{b}"], row[f"hit_b{b}"] = len(sel), sum(sel)
        for o in WORDS:
            if o != w: row[f"x_{key(o)}"] = sum(hit(lb) for lb in L if lb["word"] == o)       # Treffer auf andere Woerter (Verwechsler)
        out.append(row)
    return out


def calib_point(r, calib):
    if calib == "real": return dict(r, fa=r["fa_real"], hours=r["h_real"])
    return dict(r, fa=r["fa_syn"] + r["fa_fleurs"], hours=r["h_syn"] + r["h_fleurs"])


def op_table(rows, target, calib):
    """Je Geraet x Wort x Programm: Konfiguration mit bestem Treffer bei FA/h <= target auf der Kalibrierungsquelle."""
    out = []
    for dev in DEVICES:
        for w in WORDS:
            for prog in PROGRAMS:
                pts = sorted((calib_point(r, calib) for r in rows if r["dev"] == dev and r["word"] == w and r["prog"] == prog),
                             key=lambda p: (p["stage2"] == "-", -p["ord"]))        # Gleichstand: mit Stufe 2, vorsichtigere Konfiguration
                if pts: out.append(pick_op(pts, pts[0]["hours"], target) or {"dev": dev, "word": w, "prog": prog, "hit": None})
    return out


FOLDS = [((1, 2, 3), (4, 5, 6)), ((4, 5, 6), (1, 2, 3))]       # (Auswahl-Blocks, Test-Blocks): Kreuz-Auswahl je Wort/Programm


def cv_pick(pts, hours, target, folds=FOLDS):
    """Kreuz-Auswahl: Konfiguration auf den Auswahl-Blocks waehlen (hoechster Treffer bei FA/h <= target, Reihenfolge von pts als
    Gleichstand), Treffer auf den Test-Blocks derselben Konfiguration zaehlen. -> (Treffer, n, [Konfiguration je Fold]);
    Treffer None, wenn in einem Fold keine Konfiguration die FA-Grenze einhaelt."""
    hit = n = 0
    cfgs = []
    for sel, test in folds:
        if sum(pts[0][f"n_b{b}"] for b in test) == 0:       # leerer Test-Fold wuerde still 0/0 zaehlen und n verzerren: fail-closed
            raise ValueError(f"cv_pick: Test-Fold {test} ohne Aufnahmen (n=0); Folds der Zelle vorher filtern")
        ptsx = [dict(p, hit=sum(p[f"hit_b{b}"] for b in sel)) for p in pts]
        best = pick_op(ptsx, hours, target)
        if best is None: return None, sum(pts[0][f"n_b{b}"] for _, t in folds for b in t), None
        hit += sum(best[f"hit_b{b}"] for b in test); n += sum(best[f"n_b{b}"] for b in test)
        cfgs.append(f"{best['prog']}{best['thr']}+{best['stage2']}")
    return hit, n, cfgs


def cv_table(rows, target, calib):
    """Wie op_table, aber mit Kreuz-Auswahl (Befund 3): {(dev, word, prog): (hit, n, cfgs)}."""
    out = {}
    for dev in DEVICES:
        for w in WORDS:
            for prog in PROGRAMS:
                pts = sorted((calib_point(r, calib) for r in rows if r["dev"] == dev and r["word"] == w and r["prog"] == prog),
                             key=lambda p: (p["stage2"] == "-", -p["ord"]))
                if pts: out[(dev, w, prog)] = cv_pick(pts, pts[0]["hours"], target)
    return out


def fc(v): return str(v).replace(".", ",")


def fmt_hit(hit, n):
    lo, hi = S.wilson(hit, n)
    return f"{round(100 * hit / n)} % [{round(100 * lo)}–{round(100 * hi)}] ({hit}/{n})"


def write_report(rows):
    os.makedirs(OUT, exist_ok=True)
    with open(f"{OUT}/grid.csv", "w", newline="") as fh:
        wr = csv.DictWriter(fh, list(dict.fromkeys(k for r in rows for k in r)), restval=""); wr.writeheader(); wr.writerows(rows)
    md = []
    for calib in ("real", "syn"):
        for target in (1, 2):
            md.append(f"\n## Kalibrierung {'echte Negativ-Aufnahme' if calib == 'real' else 'synthetisch + FLEURS'}, Ziel {target} FA/h\n")
            T = op_table(rows, target, calib)
            CV = cv_table(rows, target, calib)
            md.append("n = 30 Äußerungen je Wort; Huawei und handy2 nahmen dieselben Äußerungen gleichzeitig auf (nicht addieren, effektiv n = 30). "
                      "Kreuz: Konfiguration auf Block 1–3 gewählt und auf 4–6 gezählt, und umgekehrt; in-sample: auf allen 30 gewählt (optimistisch).\n")
            for dev in DEVICES:
                md += [f"\n### {dev}\n", "| Wort | Programm | Treffer Kreuz | Treffer in-sample | Konfiguration in-sample | Konfiguration Kreuz (1–3 / 4–6) | FA/h Kalibrierung (≤95 %) | FA/h Gegenprobe | Block 1..6 |",
                       "|---|---|---|---|---|---|---|---|---|"]
                for r in (t for t in T if t["dev"] == dev):
                    ch, cn, cc = CV[(dev, r["word"], r["prog"])]
                    cross = "keine Konfiguration" if ch is None else fmt_hit(ch, cn)
                    if r["hit"] is None:
                        md.append(f"| {r['word']} | {r['prog']} | {cross} | keine Konfiguration mit FA/h ≤ {target} | | | | | |"); continue
                    c, o = calib_point(r, calib), calib_point(r, "syn" if calib == "real" else "real")
                    blocks = " ".join(f"{r[f'hit_b{b}']}/{r[f'n_b{b}']}" for b in range(1, 7))
                    md.append(f"| {r['word']} | {r['prog']} | {cross} | {fmt_hit(r['hit'], r['n'])} | {r['prog']}{r['thr']} + {r['stage2']} | "
                              f"{' / '.join(cc) if cc else ''} | {fc(round(c['fa'] / c['hours'], 2))} (≤{fc(round(S.poisson_upper(c['fa'], c['hours']), 1))}) | "
                              f"{'synth.' if calib == 'real' else 'echt'} {fc(round(o['fa'] / o['hours'], 2))} | {blocks} |")
    open(f"{OUT}/tables.md", "w").write("\n".join(md) + "\n")
    det_csv(rows)
    det_png(rows)


def det_points(rows, dev, w, prog, calib):
    pts = []
    for r in rows:
        if r["dev"] == dev and r["word"] == w and r["prog"] == prog:
            c = calib_point(r, calib)
            pts.append({"fa": c["fa"], "hit": r["hit"], "rate": c["fa"] / c["hours"], "pct": 100 * r["hit"] / r["n"],
                        "cfg": f"{prog}{r['thr']}+{r['stage2']}"})
    return pareto(pts)


def det_csv(rows):
    with open(f"{OUT}/det.csv", "w", newline="") as fh:
        wr = csv.writer(fh); wr.writerow(["calib", "dev", "word", "prog", "fa_per_h", "hit_pct", "config"])
        for calib in ("real", "syn"):
            for dev in DEVICES:
                for w in WORDS:
                    for prog in PROGRAMS:
                        for p in det_points(rows, dev, w, prog, calib):
                            wr.writerow([calib, dev, w, prog, round(p["rate"], 3), round(p["pct"], 1), p["cfg"]])


def det_png(rows):
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    col = {"M": "#1b6ca8", "W": "#8a6d00", "Kz": "#a8321b", "Kg": "#4a8f3a"}
    pairs = [(d, c) for d in DEVICES for c in ("real", "syn")]
    fig, ax = plt.subplots(len(pairs), len(WORDS), figsize=(4 * len(WORDS), 3 * len(pairs)), sharey=True)
    for j, w in enumerate(WORDS):
        for i, (dev, calib) in enumerate(pairs):
            a = ax[i][j]
            for prog in PROGRAMS:
                P = det_points(rows, dev, w, prog, calib)
                if P: a.step([p["rate"] for p in P], [p["pct"] for p in P], where="post", marker="o", ms=3, color=col[prog], label=prog)
            for t in (1, 2): a.axvline(t, color="#999", lw=0.6, ls=":")
            a.set_xlim(-0.2, 12); a.set_ylim(0, 100)
            a.set_title(f"{w} / {dev} / {'echt' if calib == 'real' else 'synth.+FLEURS'}", fontsize=8)
            if i == len(pairs) - 1: a.set_xlabel("FA/h")
            if j == 0: a.set_ylabel("Treffer %")
    ax[0][0].legend(fontsize=7)
    fig.tight_layout(); fig.savefig(f"{OUT}/det.png", dpi=110)


def cmd_control():
    """Stufe 1 an den echten Labels je Wort x Programm x Schwelle (nur Zahlen)."""
    st, labels = Stage1(), read_labels()
    for w in WORDS:
        for prog in (p for p in PROGRAMS if supported(p, w)):
            for thr in configs(prog):
                for dev in DEVICES:
                    d = st.events(prog, w, thr, f"pos_{dev}")
                    if d is None: continue
                    dets = d[f"pos_{dev}"]
                    own = [lb for lb in labels if lb["dev"] == dev and lb["word"] == w]
                    n = sum(any(label_window(lb["start"], lb["end"], lb["status"])[0] <= t <= label_window(lb["start"], lb["end"], lb["status"])[1]
                                for t in dets) for lb in own)
                    print(f"{w:13s} {prog:2s} cfg={cfg_s(thr):<8s} {dev:7s} Stufe 1: {n}/{len(own)} Treffer, {len(dets)} Ereignisse")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    a = sp.add_parser("s1"); a.add_argument("prog", choices=["oww", "kws"]); a.add_argument("--jobs", type=int, default=4)
    a.add_argument("--models", default="z,g"); a.add_argument("--words", default=",".join(WORDS))
    a.add_argument("--src", default=",".join(ALL_SRC)); a.add_argument("--cfg", default="", help="KWS: boost/schwelle,...")
    b = sp.add_parser("s2"); b.add_argument("--variants", default="bs,hw2,hw3"); b.add_argument("--threads", type=int, default=4)
    sp.add_parser("report"); sp.add_parser("kontrolle")
    args = ap.parse_args()
    os.makedirs(WORK, exist_ok=True)
    if args.cmd == "s1" and args.prog == "oww":
        run_oww(args.src.split(","))
        if all(os.path.exists(f"{KWS}/wp121/models/{f}") for f in OWW_X.values()): run_oww_x(args.src.split(","))
    elif args.cmd == "s1":
        cfgs = [tuple(float(y) for y in x.split("/")) for x in args.cfg.split(",")] if args.cfg else KWS_CFG
        run_kws(args.jobs, args.models.split(","), args.words.split(","), args.src.split(","), cfgs)
    elif args.cmd == "s2":
        run_s2(args.variants.split(","), args.threads)
    elif args.cmd == "kontrolle":
        cmd_control()
    else:
        rows = grid_rows(Stage1(), read_labels())
        write_report(rows)
        print(f"{len(rows)} Zeilen -> {OUT}")


if __name__ == "__main__":
    main()
