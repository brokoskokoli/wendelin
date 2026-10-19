"""Gemeinsame Teile fuer Training und Messung des Wake-Word-Modells (WP58)."""
import glob, os
import numpy as np
import soundfile as sf

SR = 16000
CLIP = 5 * SR           # Laenge der Trainings-Clips
FRAME = 1280            # 80 ms je Embedding-Schritt
EMB_SPAN = 12640        # Samples, die ein Embedding ueberdeckt (76 Mel-Frames)
WIN = 16                # Embeddings je Klassifikator-Fenster


def window_end(j):
    """Letztes Sample, das Fenster j (Embeddings j..j+15) noch sieht."""
    return FRAME * (j + WIN - 1) + EMB_SPAN


def load_dir(d, limit=None, max_s=None, dtype="float32"):
    files = sorted(glob.glob(os.path.join(d, "*.wav")))[:limit]
    out = []
    for f in files:
        try:
            x = sf.read(f, dtype="float32")[0]
            if max_s is None or len(x) <= max_s * SR:
                out.append(x.astype(dtype))
        except Exception:      # abgebrochene Schreibvorgaenge ueberspringen
            pass
    return out


# ---------- Augmentierung ----------
def reverb(x, rt60, rng):
    t = np.arange(int(rt60 * SR)) / SR
    ir = rng.standard_normal(len(t)) * np.exp(-6.9 * t / rt60)
    ir[0] = 1.0
    y = np.convolve(x, ir.astype("float32"))[: len(x)]
    return (y * (np.abs(x).max() / (np.abs(y).max() + 1e-9))).astype("float32")


def random_eq(x, rng, db=8.0):
    """Zufaellige glatte Klangfarbe (Stimm-/Mikrofonvariation): 8 Stuetzpunkte, +-db dB."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    pts = np.linspace(0, SR / 2, 8)
    g = np.interp(f, pts, rng.uniform(-db, db, 8))
    return np.fft.irfft(X * 10 ** (g / 20), len(x)).astype("float32")


def bandlimit(x, rng):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X[f > rng.uniform(3500, 7500)] = 0
    X[f < rng.uniform(40, 300)] = 0
    return np.fft.irfft(X, len(x)).astype("float32")


def _colored(n, power, rng):
    X = np.fft.rfft(rng.standard_normal(n))
    f = np.maximum(np.fft.rfftfreq(n, 1 / SR), 20.0)
    return np.fft.irfft(X / f ** (power / 2), n).astype("float32")


def make_noise(n, kind, rng, pool=None):
    if kind == "white":
        return rng.standard_normal(n).astype("float32")
    if kind == "pink":
        return _colored(n, 1.0, rng)
    if kind == "brown":
        return _colored(n, 2.0, rng)
    if kind == "hum":
        t = np.arange(n) / SR
        f0 = rng.choice([50.0, 100.0, 120.0])
        y = sum(np.sin(2 * np.pi * f0 * k * t + rng.uniform(0, 6)) / k for k in range(1, 6))
        return (y + 0.2 * _colored(n, 1.0, rng) / (_colored(n, 1.0, rng).std() + 1e-9)).astype("float32")
    if kind == "music":
        y = np.zeros(n, "float32")
        t = np.arange(n) / SR
        for _ in range(rng.integers(3, 9)):
            f = 110 * 2 ** (rng.integers(0, 36) / 12)
            env = np.clip(np.sin(np.pi * ((t * rng.uniform(0.2, 1.5) + rng.uniform()) % 1.0)), 0, 1)
            y += (np.sin(2 * np.pi * f * t) * env).astype("float32")
        return y
    if kind == "babble" and pool:
        y = np.zeros(n, "float32")
        for _ in range(rng.integers(3, 7)):
            c = pool[int(rng.integers(len(pool)))]
            c = np.tile(c, n // len(c) + 1)
            o = int(rng.integers(len(c) - n + 1)) if len(c) > n else 0
            y += c[o:o + n]
        return y
    return rng.standard_normal(n).astype("float32")


NOISE_KINDS = ["white", "pink", "brown", "hum", "music", "babble", "babble"]


def augment(x, rng, pool):
    if rng.random() < 0.4:
        x = reverb(x, rng.uniform(0.2, 0.9), rng)
    if rng.random() < 0.3:
        x = bandlimit(x, rng)
    if rng.random() < 0.75:
        nz = make_noise(len(x), NOISE_KINDS[int(rng.integers(len(NOISE_KINDS)))], rng, pool)
        p = (x ** 2).mean() + 1e-9
        nz *= np.sqrt(p / 10 ** (rng.uniform(4, 35) / 10) / ((nz ** 2).mean() + 1e-12))
        x = x + nz
    pk = np.abs(x).max() + 1e-9
    return (x * (rng.uniform(0.08, 0.9) / pk)).astype("float32")


def crop_end(c, n):
    return c[-n:] if len(c) > n else c


def build_clip(rng, neg, conf, word=None):
    """Baut einen 4-s-Clip. Mit `word`: Wake Word, Rueckgabe (clip, E) mit Wortende E in Samples."""
    def filler(target):
        parts, tot = [], 0
        while tot < target:
            src = conf if (conf and rng.random() < 0.15) else neg
            c = src[int(rng.integers(len(src)))]
            parts += [c, np.zeros(int(rng.uniform(0.05, 0.6) * SR), "float32")]
            tot += len(parts[-1]) + len(c)
        return np.concatenate(parts)

    if word is None:
        return filler(CLIP)[:CLIP].astype("float32"), None
    lead_len = int(rng.uniform(1.4, 3.2) * SR)   # erstes Fenster endet erst bei 2,0 s
    lead = crop_end(filler(lead_len), lead_len) if rng.random() < 0.85 else np.zeros(lead_len, "float32")
    gap = np.zeros(int(rng.uniform(0.05, 0.4) * SR), "float32")
    f = rng.uniform(0.8, 1.25)              # Tonhoehe/Tempo des Wortes zusaetzlich variieren
    w = np.interp(np.linspace(0, len(word) - 1, int(len(word) / f)), np.arange(len(word)), word)
    w = (w * 10 ** (rng.uniform(-6, 2) / 20)).astype("float32")
    if rng.random() < 0.7:
        w = random_eq(w, rng)
    pre = np.concatenate([lead, gap, w]).astype("float32")
    e = len(pre)
    if rng.random() < 0.5:
        tail = np.concatenate([np.zeros(int(rng.uniform(0.1, 0.5) * SR), "float32"), filler(2 * SR)])
    else:
        tail = np.zeros(0, "float32")
    x = np.concatenate([pre, tail])
    if len(x) > CLIP:                      # von vorn kuerzen, Wortende mitschieben
        cut = len(x) - CLIP
        if cut > e - len(w) - 0.1 * SR:    # Wort darf nicht angeschnitten werden
            cut = int(max(0, e - len(w) - 0.1 * SR))
        x = x[cut:]; e -= cut
    x = x[:CLIP]
    x = np.concatenate([x, np.zeros(CLIP - len(x), "float32")])
    return x, e


def embed(af, clips, ncpu=1):
    """clips: Liste gleich langer float32-Clips (-1..1) -> (N, Frames, 96)."""
    n = len(clips)
    clips = [c[: len(c) // 160 * 160] for c in clips]   # openWakeWord erwartet Vielfache von 10 ms
    if n == 1:                             # openWakeWord squeezt Batch 1 falsch
        clips = clips * 2
    a = (np.stack(clips) * 32767).astype("int16")
    return af.embed_clips(a, batch_size=64, ncpu=ncpu)[:n]


def make_features(models_dir, ncpu=1):
    from openwakeword.utils import AudioFeatures
    return AudioFeatures(melspec_model_path=os.path.join(models_dir, "melspectrogram.onnx"),
                         embedding_model_path=os.path.join(models_dir, "embedding_model.onnx"),
                         ncpu=ncpu, inference_framework="onnx")
