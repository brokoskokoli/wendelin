#!/usr/bin/env python3
"""Erzeugt synthetische Trainingsclips (Piper, deutsche Stimmen) fuer das Wake Word (WP58).

  python gen_samples.py --kind pos|conf|neg|pos_v8|conf_v8|neg_v8 --out <ordner> --n 1000 --seed 1 \
      --voices <ordner-mit-v-*-Stimmen> [--text deu.tsv.bz2]

Ausgabe: 16-kHz-Mono-WAVs. Stimmen/Daten liegen ausserhalb des Repos
(~/wendelin-models/kws/wp58/dl). Single-thread (ORT), damit mehrere Prozesse
parallel laufen koennen.
"""
import argparse, bz2, glob, json, os, random
import numpy as np
import onnxruntime as ort
import soundfile as sf
from piper import PiperVoice, SynthesisConfig
from piper.config import PiperConfig
from pathlib import Path
from piper.voice import ESPEAK_DATA_DIR

SR = 16000
POS = ["Wendelin", "Wendelin.", "Wendelin!", "Wendelin?", "Hey Wendelin", "Hey, Wendelin", "Hey Wendelin."]
# WP111: je Wort eigene Trainingsmengen (--kind bare = nur „Wendelin“, hey = „Hey Wendelin“, conf2 = Verwechsler fuer „Hey Wendelin“)
BARE = ["Wendelin", "Wendelin.", "Wendelin!", "Wendelin?", "Wendelin,"]
HEY = ["Hey Wendelin", "Hey, Wendelin", "Hey Wendelin.", "Hey Wendelin!", "Hey, Wendelin.", "Hey Wendelin?"]
CONF2 = ["Hey Wendel", "Hey Berlin", "Hey Wenzel", "Hey Wendelstein", "hey, wenn der Wind", "hey, wenn die Linie", "Hey Windel",
         "Hey Gwendolin", "Gwendolin", "Wendolin", "wenn die Linie", "Hey Wendy", "Hey Mandolin", "Hey Vendetta", "Hey Madeleine",
         "Hey Wendehals", "Hey Kendall", "Hey Merlin", "Hey Marlin", "Hey Vanille", "Hey Wende", "Hey Handel", "Hey Wenden",
         "Hey Heidelin", "Hey Pendel", "Hey Wandern", "Hey Wetter", "Hey Mandy", "Hey Mama"]
# WP121: weitere Woerter, gleiche Pipeline wie v7. oct/kob = Positive (wie hey bzw. bare), conf_oct/conf_kob = Verwechsler (wie conf2)
OCT = ["Hey Octavia", "Hey, Octavia", "Hey Octavia.", "Hey Octavia!", "Hey, Octavia.", "Hey Octavia?"]
KOB = ["Kobalos", "Kobalos.", "Kobalos!", "Kobalos?", "Kobalos,"]
CONF_OCT = ["Hey Olivia", "Hey Octavian", "Hey Ottavio", "Hey Tavia", "Hey Oktave", "Hey Ophelia", "Hey Octopus", "Hey Lavia", "Hey Mafia",
            "Hey Octavio", "Hey Ottavia", "Octavia", "Oktavia", "Hey Tabea", "Hey Otto", "Hey Oktober", "Hey Opa", "Hey Oma",
            "Hey Ottilie", "Hey Aktie", "Hey Octave", "Hey Olga", "Hey Mama", "Hey Mandy", "Hey Eva", "Hey Sophia", "Hey Victoria",
            "Hey Ocatvia", "Hey Hortensia", "Hey Tavita", "Hey Ocean", "hey, oh Tavia"]
CONF_KOB = ["Kobold", "Kobolde", "Kobalt", "Cobalt", "Kolibri", "Carlos", "Karlos", "Kolonos", "Kokolores", "Kobra", "Kolossos", "Koloss",
            "Kolumbus", "Kabalos", "Gobelin", "Koboldos", "Kobaltos", "Kobel", "Kobold Alos", "Bolos", "Kolonie", "Kopalos", "Kolos",
            "Hey Kobalos", "Kobalus", "Kollos", "Kobolos", "Kolobos", "Kolokos", "Kopallos", "Kobalo", "Gobalos"]
# aehnlich klingende Woerter/Phrasen (Negative)
CONF = ["Wendel", "Wendeltreppe", "Wendelstein", "Vanille", "Berlin", "Wenden", "Wende", "Windel",
        "Mandolin", "Vendetta", "Wendy", "Hey Wendy", "Handelin", "Kendall", "Wenig", "Verwendet",
        "Wandern", "Wendehals", "Pendelin", "Wendelinus", "Hey Wende", "Hey Mandy",
        "Venedig", "Wandelin", "Vendel", "Heidelin", "Marlin", "Madeleine", "Wendungen", "Hallo",
        "Hey Google", "Alexa", "Hey Siri", "Okay", "Wetter", "Timer", "Hey Wenzel", "Wenzel", "Wanderlin"]


# WP130 (v8): Kontexte und harte Verwechsler. Positive stehen allein (BARE/HEY) oder im Befehlssatz und werden am ersten
# Atemzug nach dem Wort abgeschnitten (cut_first_word), damit das Wortende bekannt ist.
CMD_V8 = ["mach das Licht an", "wie spät ist es", "wie wird das Wetter morgen", "stell einen Timer auf fünf Minuten", "spiel etwas Musik",
          "was steht heute im Kalender", "schreib eine Nachricht", "erinnere mich an den Termin", "sag mir die Nachrichten",
          "kannst du mir helfen", "wie geht es dir", "stopp", "hör zu", "mach bitte leiser", "such mir ein Rezept"]
CONF_V8 = [c for c in CONF + CONF2 if "wendelin" not in c.lower()] + [   # nie das Wake Word selbst als Negativ
    "Wendels", "Wendezeit", "Wendepunkt", "Wendekreis", "Windeln", "Berliner", "Berlinale",
    "Wenn der Lin", "wenn der Linus", "wenn der Linie", "wenn der Lindwurm", "wenn der Wind", "wenn den Lin", "wenn die Linde",
    "Hey Wendel", "Hey Wendeltreppe", "Hey Wendelstein", "Hey Windel", "Hey Berlin", "Hey Wenden",
    "Wendell", "Gwendolyn", "Mendelin", "Mendel", "Bandelin", "Wendling", "Wedeln", "Wenzeslaus",
    "Wendelsheim", "Wendlingen", "Wandelin", "Hey Mendel", "Hey Hendrik", "Hey Wende",
    "Kendelin", "Endlich", "Wenn ich", "Wenn er", "Wendungen", "Verwenden", "Handel", "Hey Handel"]
POS_V8_SHARE = (0.35, 0.35, 0.30)       # allein / Hey allein / im Befehlssatz (abgeschnitten)


def cut_first_word(x, min_speech=0.25, min_gap=0.08, db=-38.0):
    """Schneidet den Anfang bis zur ersten Sprechpause (Komma) ab; None, wenn keine Pause gefunden wird."""
    f = 160
    n = len(x) // f
    if n == 0:
        return None
    rms = np.sqrt((x[: n * f].reshape(n, f) ** 2).mean(axis=1) + 1e-12)
    loud = 20 * np.log10(rms / (rms.max() + 1e-9) + 1e-12) > db
    on = np.where(loud)[0]
    if len(on) == 0:
        return None
    i = on[0]
    speech = 0
    while i < n:
        if loud[i]:
            speech += 1; i += 1
            continue
        j = i
        while j < n and not loud[j]:
            j += 1
        if speech >= int(min_speech * 100) and (j - i) >= int(min_gap * 100) and j < n:
            return x[: i * f]
        i = j
    return None


def v8_text(kind, rng):
    """-> (text, cut). cut=True: Satz synthetisieren und nach dem ersten Wort abschneiden."""
    if kind == "pos_v8":
        r = rng.random()
        if r < POS_V8_SHARE[0]:
            return BARE[int(rng.integers(len(BARE)))], False
        if r < POS_V8_SHARE[0] + POS_V8_SHARE[1]:
            return HEY[int(rng.integers(len(HEY)))], False
        head = ["Wendelin", "Hey Wendelin", "Hey, Wendelin"][int(rng.integers(3))]
        return f"{head}, {CMD_V8[int(rng.integers(len(CMD_V8)))]}", True
    w = CONF_V8[int(rng.integers(len(CONF_V8)))]
    if " " not in w.strip() and rng.random() < 0.25:
        return f"{w}, {CMD_V8[int(rng.integers(len(CMD_V8)))]}", True
    return w, False


def load_voice(d):
    cfg = json.load(open(os.path.join(d, "m.onnx.json")))
    so = ort.SessionOptions(); so.intra_op_num_threads = 1; so.inter_op_num_threads = 1
    sess = ort.InferenceSession(os.path.join(d, "m.onnx"), sess_options=so, providers=["CPUExecutionProvider"])
    v = PiperVoice(config=PiperConfig.from_dict(cfg), session=sess, espeak_data_dir=Path(ESPEAK_DATA_DIR),
                   download_dir=Path(d))
    return v, cfg["audio"]["sample_rate"], int(cfg["num_speakers"])


def resample(x, sr_in, sr_out, factor=1.0):
    """Lineares Resampling; factor != 1 aendert Tonhoehe und Tempo."""
    n = int(len(x) * sr_out / sr_in / factor)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype("float32")


def trim(x, db=-45.0, pad=0.05):
    f = 160
    n = len(x) // f
    if n == 0:
        return x
    rms = np.sqrt((x[: n * f].reshape(n, f) ** 2).mean(axis=1) + 1e-12)
    idx = np.where(20 * np.log10(rms / (np.abs(x).max() + 1e-9) + 1e-12) > db)[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] * f - int(pad * SR)); b = min(len(x), (idx[-1] + 1) * f + int(pad * SR))
    return x[a:b]


def synth(voice, sr, ns, text, rng, wide=False, v8=False):
    lo, hi = (0.75, 1.5) if v8 else ((0.7, 1.5) if wide else (0.8, 1.3))       # --wide (v9) / v8: mehr Tempo-/Tonhoehenvielfalt
    nlo = 0.3 if v8 else 0.4
    cfg = SynthesisConfig(speaker_id=int(rng.integers(ns)) if ns > 1 else None,
                          length_scale=float(rng.uniform(lo, hi)),
                          noise_scale=float(rng.uniform(nlo, 1.0)),
                          noise_w_scale=float(rng.uniform(nlo, 1.0)))
    parts = [c.audio_float_array for c in voice.synthesize(text, cfg)]
    if not parts:
        return None
    x = np.concatenate(parts).astype("float32")
    pf = rng.uniform(0.88, 1.14) if v8 else (rng.uniform(0.85, 1.18) if wide else rng.uniform(0.92, 1.08))
    x = resample(x, sr, SR, float(pf))
    return trim(x)


def sentences(path, rng, n):
    with bz2.open(path, "rt", encoding="utf-8") as f:
        rows = [l.split("\t")[2].strip() for l in f if l.count("\t") >= 2]
    rows = [r for r in rows if 15 <= len(r) <= 160 and "wendelin" not in r.lower()]
    rng.shuffle(rows)
    return rows[:n]


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--kind", required=True, choices=["pos", "conf", "neg", "bare", "hey", "conf2", "oct", "conf_oct", "kob", "conf_kob",
                                                       "pos_v8", "conf_v8", "neg_v8"])
    a.add_argument("--out", required=True)
    a.add_argument("--n", type=int, default=100)
    a.add_argument("--seed", type=int, default=1)
    a.add_argument("--voices", required=True)
    a.add_argument("--text")
    a.add_argument("--wide", action="store_true", help="v9: breiteres Tempo/Tonhoehe, MLS-Sprecher dreifach gewichtet")
    a.add_argument("--max-seconds", type=float, default=0, help="Abbruch nach so viel Audio (neg)")
    a = a.parse_args()
    rng = np.random.default_rng(a.seed)
    random.seed(a.seed)
    os.makedirs(a.out, exist_ok=True)
    voices = [load_voice(d) for d in sorted(glob.glob(os.path.join(a.voices, "v-*")))]
    v8 = a.kind.endswith("_v8")
    wts = np.array([(4.0 if v8 else 3.0) if d.endswith("v-mls") else 1.0
                    for d in sorted(glob.glob(os.path.join(a.voices, "v-*")))])
    wts = wts / wts.sum() if (a.wide or v8) else None
    texts = None
    if a.kind in ("neg", "neg_v8"):
        texts = sentences(a.text, np.random.default_rng(a.seed), a.n)
    total = 0.0
    for i in range(a.n):
        cut = False
        v, sr, ns = voices[int(rng.choice(len(voices), p=wts))]
        if a.kind == "pos":
            t = POS[int(rng.integers(len(POS)))]
        elif a.kind == "conf":
            t = CONF[int(rng.integers(len(CONF)))]
        elif a.kind in ("bare", "hey", "conf2", "oct", "conf_oct", "kob", "conf_kob"):
            L = {"bare": BARE, "hey": HEY, "conf2": CONF2, "oct": OCT, "conf_oct": CONF_OCT, "kob": KOB, "conf_kob": CONF_KOB}[a.kind]
            t = L[int(rng.integers(len(L)))]
        elif v8 and a.kind != "neg_v8":
            t, cut = v8_text(a.kind, rng)
        else:
            t = texts[i]
        x = synth(v, sr, ns, t, rng, a.wide, v8)
        if x is not None and v8 and a.kind != "neg_v8" and cut:
            x = cut_first_word(x)
            if a.kind == "conf_v8" and x is not None:
                x = trim(x)
        if x is None or len(x) < 1600 or (a.kind not in ("neg", "neg_v8") and len(x) > 1.8 * SR) or (a.kind.startswith("conf") and a.kind != "conf" and len(x) > 2.4 * SR):
            continue   # Ausreisser (lange Pausen/Artefakte) verwerfen
        sf.write(os.path.join(a.out, f"{a.kind}{a.seed:02d}_{i:05d}.wav"), x, SR, subtype="PCM_16")
        total += len(x) / SR
        if a.max_seconds and total >= a.max_seconds:
            break
    print(f"{a.kind} seed {a.seed}: {total/3600:.2f} h")


if __name__ == "__main__":
    main()
