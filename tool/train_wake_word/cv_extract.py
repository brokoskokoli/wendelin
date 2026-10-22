#!/usr/bin/env python3
"""WP130: Common Voice de (CC0) als echte Negativ-Sprache. Liest einen Trainings-Shard (tar mit mp3) im Strom und
schreibt jeden --every-ten Clip als 16-kHz-Mono-WAV (hoechstens --max Clips). Nutzt nur Trainings-Shards, keine eigenen Aufnahmen.

  python cv_extract.py --tar <de_train_0.tar> --out <ordner> [--every 3] [--max 4000] [--allow-truncated]
"""
import argparse, io, os, tarfile
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

SR = 16000


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--tar", required=True); a.add_argument("--out", required=True)
    a.add_argument("--every", type=int, default=3); a.add_argument("--max", type=int, default=4000)
    a.add_argument("--allow-truncated", action="store_true", help="abgeschnittenes Archiv tolerieren (nur Probelauf)")
    a = a.parse_args()
    os.makedirs(a.out, exist_ok=True)
    try:
        _read(a, tf_open=tarfile.open(a.tar, "r|"))
    except (tarfile.TarError, EOFError) as e:
        if not a.allow_truncated:
            raise SystemExit(f"Archiv unvollstaendig oder defekt: {e}")      # fail-closed im Volllauf
        print("Archiv abgeschnitten (--allow-truncated): bisherige Clips bleiben")
    print(f"common voice: {len(os.listdir(a.out))} Clips")


def _read(a, tf_open):
    n = k = 0
    with tf_open as tf:
        for m in tf:
            if not m.isfile() or not m.name.lower().endswith(".mp3"):
                continue
            k += 1
            if k % a.every:
                continue
            try:
                x, sr = sf.read(io.BytesIO(tf.extractfile(m).read()), dtype="float32")
            except Exception:
                continue
            if x.ndim > 1:
                x = x.mean(axis=1)
            if sr != SR:
                g = np.gcd(sr, SR); x = resample_poly(x, SR // g, sr // g).astype("float32")
            if len(x) < SR or len(x) > 12 * SR:
                continue
            sf.write(os.path.join(a.out, f"cv_{n:05d}.wav"), x, SR, subtype="PCM_16")
            n += 1
            if n >= a.max:
                break


if __name__ == "__main__":
    main()
