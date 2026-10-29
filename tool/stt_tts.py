#!/usr/bin/env python3
"""Spricht einen Text mit einem sherpa-onnx-VITS-Piper-Modell und schreibt ein WAV
(Modellrate, mono, 16 bit). Aufruf: stt_tts.py MODELLORDNER AUSGABE.wav [SPEED] < text
(SPEED: 1.0 = Standard, kleiner = langsamer; Manifest-Spalte 5)
Wird von tool/make_stt_fixtures.sh benutzt."""
import glob
import os
import sys
import wave

import numpy as np
import sherpa_onnx

model_dir, out = sys.argv[1], sys.argv[2]
speed = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
cfg = sherpa_onnx.OfflineTtsConfig(
    model=sherpa_onnx.OfflineTtsModelConfig(
        vits=sherpa_onnx.OfflineTtsVitsModelConfig(
            model=glob.glob(os.path.join(model_dir, "*.onnx"))[0],
            tokens=os.path.join(model_dir, "tokens.txt"),
            data_dir=os.path.join(model_dir, "espeak-ng-data"),
        ),
        num_threads=2,
    )
)
audio = sherpa_onnx.OfflineTts(cfg).generate(sys.stdin.read().strip(), sid=0, speed=speed)
pcm = (np.clip(np.array(audio.samples), -1, 1) * 32767).astype("<i2")
with wave.open(out, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(audio.sample_rate)
    w.writeframes(pcm.tobytes())
