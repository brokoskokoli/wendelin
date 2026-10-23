#!/usr/bin/env python3
"""WP137 Teil 2: Daten fuer den wortspezifischen Pruefer (Stufe 2 nach Stufe 1, nur im Band 0,98 bis 0,999).

Ausschnitte (Training wie Pruefung) werden am Entscheidungsfenster der App (Halten, stage2_cut.app_events) um `pre` s vor und `tail` s nach
dem Entscheidungszeitpunkt geschnitten, auf Spitze 0,5 normalisiert und mit denselben openWakeWord-Modellen wie Stufe 1 in Embeddings (F x 96) gewandelt.

Phasen (jede mit --probe: wenig Daten, eigener Ordner <VER>/probe, Minuten; Cache sonst unter <VER> = $K/wp137/verifier, nie im Repo):
  gen       Piper-Clips mit Text-Sidecar (Positive mit Wortart, Verwechsler NUR aus Trainings-Texten, nur Stimmen des Stimmensets clean)
  check     Leckpruefung (fail-closed) der Trainingsquellen
  features  Stufe-1-Modell ueber Streams laufen lassen, Ereignisse (Band ab 0,98 wie die Pruefung; optional Zusatz-Negative 0,9 bis 0,98) ausschneiden und einbetten -> <VER>/feat/<modell>/<cut>.npz

Verwechsler-Texte: fester Hash-Split der conf_v8-Basistexte (sha1 des normalisierten Basistexts mod 10 < 7 = Training, sonst Test). Der Pruefer
sieht nie Test-Texte; die Verwechsler-Zahl des Vergleichs kommt aus den Pruef-Verwechslern (macOS-say, v8_measure.conf_say) mit Test-Texten
(und getrennt mit Trainings-Texten, zeigt Ueberanpassung). Die schon vorhandenen conf_v8-Clips haben keinen Text im Dateinamen; deshalb erzeugt `gen`
eigene Clips mit Sidecar (verwendet werden nur diese). Selbsttest: test_verifier_data.py."""
import argparse, glob, hashlib, json, os, re, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np
import soundfile as sf
import common as CM
import real_split as R

SR = CM.SR
KWS = os.path.expanduser("~/wendelin-models/kws")
VER = os.environ.get("WENDELIN_WP137_VER") or f"{KWS}/wp137/verifier"
CLEAN = f"{KWS}/wp137/clean"
OWW_DIR = f"{KWS}/wp130/dl/oww"
VOICES_ALLOWED_ENV = "WENDELIN_WP137_VOICES_ALLOWED"  # Pfad der lokalen Liste erlaubter Stimmen (eine je Zeile), Standard <clean>/voices.allowed
BAND = (0.98, 0.999)                                 # Spitzenwert Stufe 1, den der Pruefer sieht
NORM_PEAK = 0.5
PRE, TAIL = 1.9, 0.85                                # Standard-Ausschnitt (Wahl nur auf der Trainingsseite, mehrere --feat in verifier_train)
TRAIN_MOD = 7                                        # sha1(Basistext) mod 10 < 7 = Training
KIND = {"pos_syn": 0, "pos_real": 1, "conf": 2, "filler": 3, "mined": 4, "extra": 5}   # Herkunft eines Beispiels; extra = Zusatz-Negative mit Spitze unter dem Band
NEG_KINDS = (KIND["conf"], KIND["filler"], KIND["mined"], KIND["extra"])
EXTRA_LO = 0.9                                       # Standard der Zusatz-Negative (Spitze in [EXTRA_LO, BAND[0])); 0 = abgeschaltet

# Quellen, die nie im Training vorkommen duerfen (Teilstrings des aufgeloesten Pfads, kleingeschrieben)
FORBIDDEN = ("/wp130/gen", "/wp58/", "/nok/", "/fleurs/test", "mls_de_test", "conf_say", "/handy2", "handy2", "raw-neg", "neg_huawei", "neg_handy2",
             "all_huawei", "/data/neg", "/wp111/", "/wp121/", "/wendelin-fixtures", "/syn/", "/fleurs_rest", "/mls_de")


class LeakError(SystemExit):
    """Datenleck: Abbruch (fail-closed)."""


# ---------- Text-Split ----------
def norm_text(t):
    return " ".join(re.sub(r"[.,!?]", " ", t.lower()).split())


def text_split(text):
    """"train" | "test" nach sha1 des normalisierten Basistexts (fest, reproduzierbar)."""
    return "train" if int(hashlib.sha1(norm_text(text).encode("utf-8")).hexdigest(), 16) % 10 < TRAIN_MOD else "test"


def base_text(text, cut):
    """Basistext eines Verwechsler-Clips: bei abgeschnittenen Befehlssatz-Varianten („Wort, Befehl“, Wort einwortig) das Wort, sonst der Text."""
    return text.partition(", ")[0] if cut else text


def conf_pool(split):
    import gen_samples as G
    return [c for c in dict.fromkeys(G.CONF_V8) if text_split(c) == split]


def draw_conf(rng, split="train"):
    """-> (text, cut) aus den Basistexten des Splits (wie gen_samples.v8_text, aber nur Texte dieses Splits)."""
    import gen_samples as G
    pool = conf_pool(split)
    w = pool[int(rng.integers(len(pool)))]
    if " " not in w.strip() and rng.random() < 0.25:
        return f"{w}, {G.CMD_V8[int(rng.integers(len(G.CMD_V8)))]}", True
    return w, False


def draw_pos(rng):
    """-> (text, cut, wortart) wie gen_samples.v8_text("pos_v8"), dazu die Wortart (hey | bare)."""
    import gen_samples as G
    text, cut = G.v8_text("pos_v8", rng)
    return text, cut, "hey" if text.lower().startswith("hey") else "bare"


def conf_say_info(n=None, seed=None):
    """{Dateiname: (Basistext, Split)} der Pruef-Verwechsler (v8_measure.conf_say) aus dem reproduzierbaren Plan."""
    import v8_measure as V
    out = {}
    for i, (text, cut, _voice, _rate) in enumerate(V.conf_plan(n or V.CONF_N, seed or V.CONF_SEED)):
        b = base_text(text, cut)
        out[f"conf{seed or V.CONF_SEED}_{i:04d}.wav"] = (b, text_split(b))
    return out


# ---------- Leckpruefung ----------
def forbidden_reason(path):
    p = os.path.realpath(path).lower()
    for f in FORBIDDEN:
        if f in p: return f
    return None


def _under(p, root):
    p, root = os.path.realpath(p), os.path.realpath(root)
    return p == root or p.startswith(root + os.sep)


def check_roots(roots):
    """roots: {Name: (Pfad, extern)}; extern = FLEURS-Ordner train/dev (liegen per Link ausserhalb). Jeder Wurzelordner muss existieren;
    nicht-externe Wurzeln und ihr aufgeloester Pfad duerfen kein verbotenes Muster tragen, externe muessen real/train oder real/dev heissen."""
    for name, (p, ext) in roots.items():
        if not os.path.isdir(p): raise LeakError(f"Trainingsquelle {name} fehlt: {p}")
        rp = os.path.realpath(p)
        if ext:
            if os.path.basename(rp) not in ("train", "dev") or os.path.basename(os.path.dirname(rp)) != "real" or "test" in rp.lower().split(os.sep)[-3:]:
                raise LeakError(f"externe Quelle {name} ist nicht FLEURS train/dev: {rp}")
        else:
            r = forbidden_reason(p) or forbidden_reason(rp)
            if r: raise LeakError(f"Trainingsquelle {name} liegt in verbotener Quelle ({r}): {rp}")


def assert_train_files(files, roots):
    """Jede Trainingsdatei muss unter einer erlaubten Wurzel liegen und (ausser FLEURS train/dev) kein verbotenes Muster tragen."""
    ext = [p for p, e in roots.values() if e]
    allowed = [p for p, _ in roots.values()]
    for f in files:
        if not any(_under(f, a) for a in allowed): raise LeakError(f"Trainingsdatei ausserhalb der erlaubten Quellen: {f}")
        if not any(_under(f, e) for e in ext):
            r = forbidden_reason(f)
            if r: raise LeakError(f"Trainingsdatei aus verbotener Quelle ({r}): {f}")


def assert_conf_texts(d):
    """Alle Verwechsler-Clips im Ordner brauchen einen Sidecar-Eintrag, dessen Basistext (neu berechnet, dem Sidecar wird nicht getraut) im Trainings-Split liegt."""
    texts = load_texts(d)
    for f in sorted(glob.glob(os.path.join(d, "*.wav"))):
        e = texts.get(os.path.basename(f))
        if e is None: raise LeakError(f"Verwechsler-Clip ohne Text: {f}")
        if text_split(base_text(e["text"], e.get("cut", False))) != "train": raise LeakError(f"Pruef-Text im Training: {e['text']!r} ({f})")


def assert_text_disjoint(train_bases, test_bases):
    both = {norm_text(t) for t in train_bases} & {norm_text(t) for t in test_bases}
    if both: raise LeakError(f"Texte in Training und Pruefung: {sorted(both)[:5]}")


def voice_weights():
    """Lokale Liste der erlaubten Stimmen des Stimmensets clean (ausserhalb des Repos, Pfad per Umgebungsvariable oder <clean>/voices.allowed):
    eine Stimme je Zeile, optional mit Gewicht ("name 4", Standard 1). Fehlt die Datei oder ist sie leer: LeakError (fail-closed)."""
    f = os.environ.get(VOICES_ALLOWED_ENV) or os.path.join(CLEAN, "voices.allowed")
    try:
        rows = [l.split() for l in open(f, encoding="utf-8") if l.strip() and not l.lstrip().startswith("#")]
    except OSError:
        raise LeakError(f"Liste der erlaubten Stimmen fehlt: {f}")
    if not rows: raise LeakError(f"Liste der erlaubten Stimmen leer: {f}")
    return {r[0][2:] if r[0].startswith("v-") else r[0]: (float(r[1]) if len(r) > 1 else 1.0) for r in rows}


def allowed_voices(): return list(voice_weights())


def assert_clean_voices(voices_dir):
    names = [os.path.basename(d)[2:] for d in sorted(glob.glob(os.path.join(voices_dir, "v-*")))]
    ok = allowed_voices()
    bad = [n for n in names if n not in ok]
    if not names or bad: raise LeakError(f"Stimmen nicht im Stimmenset clean: {bad or 'keine Stimme'} in {voices_dir}")
    return names


def _read(f):
    with open(f, "rb") as fh: return fh.read()


def _sha(f): return hashlib.sha1(_read(f)).hexdigest()


def assert_no_audio_overlap(train_files, eval_dirs, allow_missing=False):
    """Kein Trainings-Clip ist bytegleich mit einem Pruef-Clip (conf_say, FLEURS test, MLS test, syn ...). Fehlt ein Pruef-Ordner, ist der Vergleich
    unvollstaendig: Abbruch (fail-closed); nur im Probe-Modus (allow_missing) wird er gemeldet und uebersprungen."""
    ev = {}
    for d in eval_dirs:
        if not os.path.isdir(d):
            if not allow_missing: raise LeakError(f"Pruef-Ordner fehlt, Byte-Vergleich unvollstaendig: {d}")
            print(f"Hinweis (Probe): Pruef-Ordner fehlt, Byte-Vergleich uebersprungen: {d}", flush=True); continue
        for f in glob.glob(os.path.join(d, "**", "*.*"), recursive=True):
            if f.lower().endswith((".wav", ".flac")): ev[_sha(f)] = f
    for f in train_files:
        h = _sha(f)
        if h in ev: raise LeakError(f"Trainings-Clip gleich Pruef-Clip: {f} == {ev[h]}")


def assert_group_blocks(real_dir):
    R.check_dir(real_dir, require_nonempty=True)


def _jload(f):
    with open(f, encoding="utf-8") as fh: return json.load(fh)


def _jdump(o, f):
    with open(f, "w", encoding="utf-8") as fh: json.dump(o, fh, ensure_ascii=False)


def load_texts(d):
    out = {}
    for f in sorted(glob.glob(os.path.join(d, "texts*.json"))): out.update(_jload(f))
    return out


# ---------- Ausschnitte ----------
def segment(x, te, pre=PRE, tail=TAIL):
    """Ausschnitt [e - pre, e + tail] zur Entscheidungszeit te (Raster 10 ms wie seg_key), ausserhalb des Signals mit Nullen aufgefuellt (feste Laenge)."""
    e = int(round(te * SR / 160)) * 160
    a, b = e - int(round(pre * SR)), e + int(round(tail * SR))
    out = np.zeros(b - a, "float32")
    lo, hi = max(a, 0), min(b, len(x))
    if hi > lo: out[lo - a:hi - a] = x[lo:hi]
    return out


def normalize(seg, peak=NORM_PEAK):
    seg = np.asarray(seg, "float32")
    m = float(np.abs(seg).max()) if seg.size else 0.0
    return seg if m <= 1e-6 else (seg * (peak / m)).astype("float32")


def level_db(x):
    """Pegel eines Ausschnitts in dBFS (RMS)."""
    x = np.asarray(x, "float64")
    return float(10 * np.log10((x ** 2).mean() + 1e-12)) if x.size else -120.0


def stream_events(curve_fn, x, lower=BAND[0]):
    """Ereignisse der App-Logik auf einem Stream: [(Entscheidungszeit, Spitzenwert)] (stage2_cut.app_events, Halten).
    Training und Pruefung (verifier_eval.py: events_cut(.., 0.98, "app", 0.999)) verwenden dieselbe Untergrenze BAND[0]; Entscheidungszeit und Spitze
    haengen von `lower` ab, deshalb darf das Training sie nicht mit einer anderen Untergrenze bilden."""
    import stage2_cut as C
    t, v = curve_fn(x)
    return C.app_events(t, v, lower, upper=BAND[1])       # Halten bis zur Direktannahme (acceptFrom = Band-Obergrenze)


def extra_events(curve_fn, x, lo=EXTRA_LO):
    """Zusatz-Negative: Ereignisse mit Spitze in [lo, BAND[0]), ausgerichtet an ihrer eigenen Ueberschreitung von `lo` (nicht an der Pruefmenge).
    Eigene KIND (extra), nie in Band-Masken oder Schwellen (Spitze liegt unter dem Band). lo <= 0 oder >= BAND[0]: keine."""
    if not lo or lo <= 0 or lo >= BAND[0]: return []
    return [(te, pk) for te, pk in stream_events(curve_fn, x, lo) if pk < BAND[0]]


def label_examples(x, events, word_end, curve_pos_min, pre, tail, win=(-0.3, 1.2)):
    """Ereignisse eines Streams -> [(Ausschnitt, Spitze, ziel)] ; ziel = Ereignis nahe dem Wortende (word_end in s, None = kein Wort).
    Ziel-Ereignisse mit Spitze unter curve_pos_min werden verworfen (Stufe 1 schlaegt nicht an: der Pruefer sieht sie nie)."""
    out = []
    for te, pk in events:
        tgt = word_end is not None and word_end + win[0] <= te <= word_end + win[1]
        if tgt and pk < curve_pos_min: continue
        out.append((segment(x, te, pre, tail), float(pk), bool(tgt)))
    return out


# ---------- Beispielsatz ----------
class Examples:
    """Spaltenweise: emb (N,F,96) f16, peak, kind, yw, yhw (1/0), group (Faltung)."""
    COLS = ("emb", "peak", "kind", "yw", "yhw", "group")

    def __init__(self, **kw): self.d = kw

    @classmethod
    def concat(cls, parts):
        parts = [p for p in parts if p is not None and len(p) > 0]
        return cls(**{c: np.concatenate([p.d[c] for p in parts]) for c in cls.COLS}) if parts else None

    def __len__(self): return len(self.d["peak"])

    def save(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        np.savez_compressed(path, **self.d)

    @classmethod
    def load(cls, path):
        z = np.load(path)
        return cls(**{c: z[c] for c in cls.COLS})

    def take(self, idx): return Examples(**{c: v[idx] for c, v in self.d.items()})


def make_rows(emb, peak, kind, word, group):
    """Spalten fuer Beispiele gleicher Herkunft: word = hey | bare | None (Negativ). yw: „Wendelin“-Kopf (bare und hey positiv), yhw: „Hey Wendelin“-Kopf (nur hey)."""
    n = len(peak)
    yw = np.full(n, 1 if word else 0, "int8"); yhw = np.full(n, 1 if word == "hey" else 0, "int8")
    return dict(emb=np.asarray(emb, "float16"), peak=np.asarray(peak, "float32"), kind=np.full(n, kind, "int8"), yw=yw, yhw=yhw,
                group=np.asarray(group, "int16"))


def group_of(key, folds=3):
    """Faltung (0..folds-1) einer Quelle: sha1 des Schluessels; alle Ausschnitte eines Quell-Clips/Textes landen in derselben Faltung."""
    return int(hashlib.sha1(str(key).encode("utf-8")).hexdigest(), 16) % folds


def real_group(name):
    """Faltung eines echten Clips = Aufnahmeblock (clip_name: <geraet>_b<block>_...); Bloecke 1..3 -> 0..2."""
    m = R.NAME_RE.match(name)
    if not m: raise LeakError(f"echter Clip mit fremdem Namen: {name}")
    return (int(m.group(2)) - 1) % 3


# ---------- Stufe 1 und Merkmale (Modelle noetig) ----------
class Stage1:
    """Stufe-1-Kurve eines Streams (wie v8_measure.run_s1: 1 s Stille vor/nach, Zeit relativ zum Stream-Anfang)."""

    def __init__(self, model, oww_dir=OWW_DIR, ncpu=1):
        import onnxruntime as ort
        self.af = CM.make_features(oww_dir, ncpu)
        so = ort.SessionOptions(); so.intra_op_num_threads = 1
        self.sess = ort.InferenceSession(model, so, providers=["CPUExecutionProvider"])

    def curve(self, x):
        xp = np.concatenate([np.zeros(SR, "float32"), x, np.zeros(SR, "float32")])
        emb = CM.embed(self.af, [xp])[0]
        n = len(emb) - CM.WIN + 1
        if n <= 0: return np.zeros(0), np.zeros(0, "float32")
        w = np.stack([emb[j:j + CM.WIN] for j in range(n)]).astype("float32")
        t = (np.array([CM.window_end(j) for j in range(n)]) - SR) / SR
        return t, self.sess.run(None, {"input": w})[0][:, 0].astype("float32")

    def embed_segs(self, segs):
        """Normalisierte Ausschnitte (gleiche Laenge) -> (N,F,96)."""
        return CM.embed(self.af, [normalize(s) for s in segs]) if len(segs) else np.zeros((0, 0, 96), "float32")


def build_stream(rng, kind, clip, neg_pool, conf_train, quiet_p=0.25):
    """Stream aus Fuellmaterial mit Clip (kind pos/conf) bzw. nur Fuellmaterial (clip None) -> (Stream, Wortende in s oder None, Zusatzpegel dB).
    Wie Stufe-1-Training (common.build_clip + augment); zusaetzlich leise Varianten (-10..-20 dB) mit Wahrscheinlichkeit quiet_p."""
    x, e = CM.build_clip(rng, neg_pool, conf_train, clip)
    x = CM.augment(x, rng, neg_pool[:200])
    g = 0.0
    if rng.random() < quiet_p:
        g = -float(rng.uniform(10, 20)); x = (x * 10 ** (g / 20)).astype("float32")
    return x, (None if e is None else e / SR), g


def assert_clean_voices_txt(clean):
    """`<clean>/gen/voices.txt` (Stimmen der Clean-Daten, schreibt run_v8.sh) muss existieren, nicht leer sein und nur Stimmen des Stimmensets clean nennen."""
    f = os.path.join(clean, "gen", "voices.txt")
    try:
        names = [v[2:] if v.startswith("v-") else v for v in open(f, encoding="utf-8").read().split()]
    except OSError:
        raise LeakError(f"voices.txt der Clean-Daten fehlt: {f}")
    ok = allowed_voices()
    bad = [n for n in names if n not in ok]
    if not names or bad: raise LeakError(f"Stimmen in {f} nicht im Stimmenset clean: {bad or 'keine Stimme'}")
    return names


def check_sources(roots, real_dir, conf_dir, pos_dir, eval_dirs=(), clean=None, allow_missing=False):
    """Gesamtpruefung vor dem Merkmalslauf (fail-closed). clean: Wurzel der Clean-Daten (voices.txt wird geprueft)."""
    if clean: assert_clean_voices_txt(clean)
    check_roots(roots)
    if real_dir: assert_group_blocks(real_dir)
    if conf_dir: assert_conf_texts(conf_dir)
    if pos_dir and not os.path.isdir(pos_dir): raise LeakError(f"Positiv-Ordner fehlt: {pos_dir}")
    files = [f for _, (p, _) in roots.items() for f in glob.glob(os.path.join(p, "*.wav"))]
    assert_train_files(files, roots)
    if eval_dirs: assert_no_audio_overlap(files, eval_dirs, allow_missing)


def default_roots(clean=CLEAN, ver=VER):
    return {"pos": (f"{ver}/gen/pos", False), "conf": (f"{ver}/gen/conf", False), "neg_v8": (f"{clean}/gen/neg_v8", False),
            "fleurs_train": (f"{clean}/gen/real/train", True), "fleurs_dev": (f"{clean}/gen/real/dev", True)}


def default_eval_dirs():
    return [f"{KWS}/wp130/results/conf_say", f"{KWS}/wp111/work/fleurs/test", f"{KWS}/wp133/dl/mls_de_test/ex", f"{KWS}/data/neg"]


# ---------- Erzeugen (gen) ----------
def gen_clips(kind, n, seed, voices, out):
    """Piper-Clips mit Text-Sidecar (texts-s<seed>.json). kind = pos | conf (conf nur Trainings-Texte). Stimmen nur aus dem Stimmenset clean."""
    import gen_samples as G
    assert_clean_voices(voices)
    rng = np.random.default_rng(seed)
    dirs = sorted(glob.glob(os.path.join(voices, "v-*")))
    vs = [G.load_voice(d) for d in dirs]
    vw = voice_weights(); wts = np.array([vw.get(os.path.basename(d)[2:], 1.0) for d in dirs]); wts /= wts.sum()
    os.makedirs(out, exist_ok=True)
    texts, tot = {}, 0.0
    for i in range(n):
        vi = int(rng.choice(len(vs), p=wts)); v, sr, ns = vs[vi]
        if kind == "conf": (text, cut), word = draw_conf(rng, "train"), "conf"
        else: text, cut, word = draw_pos(rng)
        x = G.synth(v, sr, ns, text, rng, False, True)
        if x is not None and cut:
            x = G.cut_first_word(x)
            if kind == "conf" and x is not None: x = G.trim(x)
        if x is None or len(x) < 1600 or (kind == "pos" and len(x) > 1.8 * SR) or (kind == "conf" and len(x) > 2.4 * SR): continue
        name = f"{kind}{seed:02d}_{i:05d}.wav"
        sf.write(os.path.join(out, name), x, SR, subtype="PCM_16")
        texts[name] = dict(text=text, cut=cut, word=word, voice=os.path.basename(dirs[vi])[2:])
        tot += len(x) / SR
    _jdump(texts, os.path.join(out, f"texts-s{seed}.json"))
    print(f"{kind} seed {seed}: {len(texts)} Clips, {tot / 3600:.2f} h", flush=True)
    return texts


# ---------- Merkmale (features) ----------
def load_wavs(d, limit=None, max_s=None):
    fs = sorted(glob.glob(os.path.join(d, "*.wav")))[:limit]
    out = []
    for f in fs:
        x = sf.read(f, dtype="float32")[0]
        if max_s is None or len(x) <= max_s * SR: out.append((os.path.basename(f), x))
    return out


def build_features(s1, args, roots, real_dir, rng, log=print):
    """Beispielsatz aus Positiven (synthetisch, echt), Verwechslern und gemineten Negativ-Ereignissen. s1: Stage1 (curve, embed_segs)."""
    ver = args.ver
    pos = load_wavs(f"{ver}/gen/pos", args.limit, 1.8)
    conf = load_wavs(f"{ver}/gen/conf", args.limit, 2.4)
    real = load_wavs(real_dir, None, 2.2) if real_dir else []
    negs = load_wavs(roots["neg_v8"][0], args.limit) + sum((load_wavs(roots[k][0], args.limit) for k in ("fleurs_train", "fleurs_dev")), [])
    if not negs: raise LeakError("kein Negativ-Material")
    pool = [x for _, x in negs[:max(200, len(negs) // 10)]]
    conf_x = [x for _, x in conf]
    texts = load_texts(f"{ver}/gen/pos")
    parts, t0 = [], time.time()

    def add(kind, items, word_of, group_fn, n_total):
        kd = {"pos": KIND["pos_syn"], "real": KIND["pos_real"], "conf": KIND["conf"]}[kind]
        for k in range(n_total):
            name, clip = items[int(rng.integers(len(items)))]
            x, we, _g = build_stream(rng, kind, clip, pool, conf_x)
            ex = label_examples(x, stream_events(s1.curve, x), we, BAND[0] if kind != "conf" else 0.0, args.pre, args.tail)
            if not ex: continue
            emb = s1.embed_segs([e[0] for e in ex])
            for tgt in (True, False):
                sel = [j for j, e in enumerate(ex) if e[2] == tgt]
                if sel:
                    parts.append(Examples(**make_rows(emb[sel], [ex[j][1] for j in sel], kd if tgt else KIND["filler"],
                                                      word_of(name) if tgt and kind != "conf" else None, [group_fn(name)] * len(sel))))
            if k % 200 == 0: log(f"features {kind} {k}/{n_total} {time.time() - t0:.0f}s", flush=True)

    if pos: add("pos", pos, lambda n: texts[n]["word"], group_of, args.n_pos)
    if real: add("real", real, lambda n: "hey" if "_hey_" in n else "bare", real_group, args.n_real)
    if conf:
        ct = load_texts(f"{ver}/gen/conf")
        add("conf", conf, None, lambda n: group_of(norm_text(base_text(ct[n]["text"], ct[n].get("cut", False)))), args.n_conf)
    # Mining: lange Negativ-Streams (Fuellmaterial, kein Wort); mined = Ereignisse ab BAND[0] (wie die Pruefung), extra = optional Spitze [extra_neg_lo, BAND[0])
    hrs, need = 0.0, args.mine_hours
    order = rng.permutation(len(negs))
    buf, bl, k = [], 0.0, 0
    for i in order:
        if hrs >= need: break
        buf += [negs[i][1], np.zeros(int(rng.uniform(0.2, 0.8) * SR), "float32")]; bl += len(buf[-2]) / SR
        if bl < 60 and i != order[-1]: continue
        x = np.concatenate(buf); buf, bl = [], 0.0
        hrs += len(x) / SR / 3600
        for kd, evs in ((KIND["mined"], stream_events(s1.curve, x)), (KIND["extra"], extra_events(s1.curve, x, args.extra_neg_lo))):
            if evs:
                segs = [segment(x, te, args.pre, args.tail) for te, _ in evs]
                parts.append(Examples(**make_rows(s1.embed_segs(segs), [p for _, p in evs], kd, None, [group_of(f"m{k}")] * len(evs))))
        k += 1
    log(f"mining: {hrs:.2f} h, {sum(len(p) for p in parts if p.d['kind'][0] == KIND['mined'])} Ereignisse im Band, {sum(len(p) for p in parts if p.d['kind'][0] == KIND['extra'])} Zusatz-Negative", flush=True)
    return Examples.concat(parts)


def stamp_path(feat): return feat + ".leak.json"


def write_stamp(feat, roots, extra=None):
    """Nach bestandener Leckpruefung: Pruefsumme der Merkmalsdatei + geprueftes Wurzelverzeichnis-Set (Training und Eval verlangen den Stempel)."""
    _jdump(dict(ok=True, sha256=hashlib.sha256(_read(feat)).hexdigest(), roots=sorted(roots), **(extra or {})), stamp_path(feat))


def require_stamp(feat):
    """Fail-closed: Merkmalsdatei ohne gueltigen Leckpruefungs-Stempel (fehlt, nicht ok, Pruefsumme weicht ab) wird nicht verwendet."""
    try:
        st = _jload(stamp_path(feat))
        good = st.get("ok") is True and st.get("sha256") == hashlib.sha256(_read(feat)).hexdigest()
    except (OSError, ValueError, AttributeError):
        good = False
    if not good: raise LeakError(f"Merkmalsdatei ohne gueltige Leckpruefung: {feat}")


def feat_path(ver, tag, pre, tail): return f"{ver}/feat/{tag}/p{pre}-t{tail}.npz"


def feat_cut(feat):
    """(pre, tail) des Ausschnitts einer Merkmalsdatei aus dem Stempel (geschrieben beim Schneiden, nicht aus der CLI). Fail-closed: fehlt er, ist er
    kein Zahlenpaar oder widerspricht der Dateiname p<pre>-t<tail>.npz, Abbruch."""
    try:
        st = _jload(stamp_path(feat)); pre, tail = float(st["pre"]), float(st["tail"])
    except (OSError, ValueError, KeyError, TypeError):
        raise LeakError(f"Stempel ohne Ausschnitt (pre/tail): {feat}")
    m = re.search(r"p([0-9.]+)-t([0-9.]+)\.npz$", os.path.basename(feat))
    if m and (float(m.group(1)), float(m.group(2))) != (pre, tail):
        raise LeakError(f"Ausschnitt im Stempel ({pre}/{tail}) widerspricht dem Dateinamen: {feat}")
    return pre, tail


def model_tag(path):
    return f"{os.path.splitext(os.path.basename(path))[0]}-{hashlib.sha256(_read(path)).hexdigest()[:8]}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("phase", choices=["gen", "check", "features"])
    ap.add_argument("--probe", action="store_true", help="kleine Mengen, Ordner <VER>/probe")
    ap.add_argument("--kind", choices=["pos", "conf"]); ap.add_argument("--n", type=int); ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--voices", help="Ordner mit v-<name>-Stimmen (nur Stimmen des Stimmensets clean)")
    ap.add_argument("--model", help="Stufe-1-Modell (ONNX) fuer features"); ap.add_argument("--real-pos", help="Ordner echter Positive (real_split.py cut)")
    ap.add_argument("--oww", default=OWW_DIR); ap.add_argument("--clean", default=CLEAN)
    ap.add_argument("--pre", type=float, default=PRE); ap.add_argument("--tail", type=float, default=TAIL)
    ap.add_argument("--extra-neg-lo", type=float, default=EXTRA_LO,
                    help="Zusatz-Negative mit Spitze in [x, 0,98) als eigene KIND extra (Standard 0,9; 0 = aus). Ereignisse im Band entstehen immer ab 0,98 wie in der Pruefung")
    ap.add_argument("--n-pos", type=int, default=12000); ap.add_argument("--n-real", type=int, default=6000)
    ap.add_argument("--n-conf", type=int, default=10000); ap.add_argument("--mine-hours", type=float, default=12.0)
    a = ap.parse_args()
    a.ver = VER + ("/probe" if a.probe else "")
    a.limit = 60 if a.probe else None
    if a.probe: a.n_pos, a.n_real, a.n_conf, a.mine_hours = 40, 40, 40, 0.05
    roots = default_roots(a.clean, a.ver)
    if a.phase == "gen":
        n = a.n or (30 if a.probe else 6000)
        gen_clips(a.kind, n, a.seed, a.voices, f"{a.ver}/gen/{a.kind}")
    elif a.phase == "check":
        check_sources(roots, a.real_pos, roots["conf"][0], roots["pos"][0], default_eval_dirs(), a.clean, a.probe)
        print("Leckpruefung ok", flush=True)
    else:
        check_sources(roots, a.real_pos, roots["conf"][0], roots["pos"][0], default_eval_dirs(), a.clean, a.probe)
        s1 = Stage1(a.model, a.oww)
        ex = build_features(s1, a, roots, a.real_pos, np.random.default_rng(a.seed))
        p = feat_path(a.ver, model_tag(a.model), a.pre, a.tail)
        ex.save(p)
        write_stamp(p, roots, dict(model=a.model, probe=a.probe, pre=a.pre, tail=a.tail, extra_neg_lo=a.extra_neg_lo))
        print(f"{len(ex)} Beispiele -> {p}", flush=True)


if __name__ == "__main__":
    main()
