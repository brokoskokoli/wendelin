#!/usr/bin/env python3
"""WP130: echte Positive (Wendelin / Hey Wendelin) fuer das Training, fest verdrahteter Split.

Training: NUR Geraet huawei, Bloecke 1 bis 3, Woerter Wendelin und Hey Wendelin, Status ungleich fehler (unsichere nur bis
MAX_S Sekunden). Pruefung (nie im Training): huawei Block 4 bis 6, das gesamte zweite Geraet, alle Negativ-Aufnahmen
(raw-neg), alle anderen Woerter. Die Audioquelle ist fest die huawei-Aufnahme; fuer andere Geraete gibt es keinen Pfad.

  python real_split.py cut --fix <ordner-mit-labels/ und raw/> --work <arbeitsordner> --out <clip-ordner>

Aufnahmen und Labels bleiben lokal (nie ins Repo). Selbsttest: test_real_split.py.
"""
import argparse, csv, os, re, subprocess
import numpy as np
import soundfile as sf

SR = 16000
TRAIN_DEVICE = "huawei"
TRAIN_BLOCKS = (1, 2, 3)
TRAIN_WORDS = ("Wendelin", "Hey Wendelin")
MAX_S = 2.0                      # laengere Ereignisse haben unsichere Grenzen (Hintergrund/zusammengezogen)
SOURCES = {"huawei": "raw/all_huawei.m4a"}      # bewusst nur diese eine Quelle
PRE, POST = 0.12, 0.20           # Rand um das Label in Sekunden


def is_train_clip(row):
    """row: Dict mit geraet, block, wort, start, ende, status (Strings wie in labels.csv)."""
    try:
        return (row["geraet"] == TRAIN_DEVICE and int(row["block"]) in TRAIN_BLOCKS and row["wort"] in TRAIN_WORDS
                and row["status"] != "fehler" and row["status"] in ("ok", "unsicher")
                and 0 < float(row["ende"]) - float(row["start"]) <= MAX_S)
    except (KeyError, ValueError, TypeError):
        return False             # fail-closed: unlesbare Zeile wird nie Trainingsclip


def select(rows):
    return [r for r in rows if is_train_clip(r)]


def source_for(geraet):
    if geraet not in SOURCES:
        raise ValueError(f"keine Trainingsquelle fuer Geraet {geraet!r}")
    return SOURCES[geraet]


def clip_name(r):
    w = "hey" if r["wort"].startswith("Hey") else "bare"
    return f"{r['geraet']}_b{int(r['block'])}_r{int(r['runde']):02d}_{w}_{int(round(float(r['start']) * 100)):06d}.wav"


def trim(x, db=-40.0, pad=0.05):
    f = 160
    n = len(x) // f
    if n == 0:
        return x
    rms = np.sqrt((x[: n * f].reshape(n, f) ** 2).mean(axis=1) + 1e-12)
    idx = np.where(20 * np.log10(rms / (rms.max() + 1e-9) + 1e-12) > db)[0]
    if len(idx) == 0:
        return x
    return x[max(0, idx[0] * f - int(pad * SR)): min(len(x), (idx[-1] + 1) * f + int(pad * SR))]


def cut_clips(rows, x):
    out = []
    for r in select(rows):
        a = max(0, int((float(r["start"]) - PRE) * SR)); b = min(len(x), int((float(r["ende"]) + POST) * SR))
        c = trim(x[a:b])
        if len(c) >= SR // 4:
            out.append((clip_name(r), c))
    return out


NAME_RE = re.compile(r"^([a-z0-9]+)_b(\d+)_r(\d{2,})_(hey|bare)_(\d{6})\.wav$")     # Muster von clip_name()


def check_dir(d, require_nonempty=False):
    """Alle Clips im Ordner muessen Trainingsnamen sein (huawei, Block 1 bis 3, clip_name-Muster); sonst Abbruch.
    Fail-closed: fremdes Namensschema, fehlender Ordner und (mit require_nonempty) leerer Ordner brechen ab."""
    if not os.path.isdir(d):
        raise SystemExit(f"Ordner der echten Positive fehlt: {d}")
    n = 0
    for f in sorted(os.listdir(d)):
        if not f.endswith(".wav"):
            continue
        m = NAME_RE.match(f)
        if not m or m.group(1) != TRAIN_DEVICE or int(m.group(2)) not in TRAIN_BLOCKS:
            raise SystemExit(f"Pruef-Clip oder fremder Name im Trainingsordner: {f}")
        n += 1
    if require_nonempty and n == 0:
        raise SystemExit(f"keine echten Positive im Ordner: {d}")


def pos_for_split(pos, real_pos, rep, split):
    """Positiv-Liste je Split fuer train.py: Train = 90 % synthetisch + echte Positive x rep; Val = restliche 10 % synthetisch (nie echt)."""
    cut = int(len(pos) * .9)
    return pos[:cut] + list(real_pos) * rep if split == "train" else pos[cut:]


def main():
    a = argparse.ArgumentParser(); a.add_argument("cmd", choices=["cut"])
    a.add_argument("--fix", required=True); a.add_argument("--work", required=True); a.add_argument("--out", required=True)
    a = a.parse_args()
    rows = list(csv.DictReader(open(os.path.join(a.fix, "labels", "labels.csv"), encoding="utf-8")))
    os.makedirs(a.work, exist_ok=True); os.makedirs(a.out, exist_ok=True)
    wav = os.path.join(a.work, "train_huawei.wav")
    if not os.path.exists(wav):
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
                        os.path.join(a.fix, source_for(TRAIN_DEVICE)), wav], check=True)
    x = sf.read(wav, dtype="float32")[0]
    skipped = [r for r in rows if r["geraet"] == TRAIN_DEVICE and int(r["block"]) in TRAIN_BLOCKS
               and r["wort"] in TRAIN_WORDS and not is_train_clip(r)]
    n = 0
    for name, c in cut_clips(rows, x):
        sf.write(os.path.join(a.out, name), c, SR, subtype="PCM_16"); n += 1
    check_dir(a.out)
    print(f"echte Positive (Training): {n} Clips, ausgeschlossen im Trainingsbereich: {len(skipped)}")


if __name__ == "__main__":
    main()
