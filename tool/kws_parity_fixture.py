#!/usr/bin/env python3
"""Paritaets-Fixture fuer den Klassifikator in der App (WP129).

Erzeugt ein kleines synthetisches Signal (keine Aufnahme) und die erwarteten
Fenster-Scores. Die Fensterbildung ist die von `tool/kws_measure.py`
(`two_stage_main.windows`): 1 s Stille davor und danach, Embeddings per
openWakeWord, Fenster aus 16 Embeddings (`common.WIN`), Klassifikator
`input` (N,16,96) -> `output` (N,1). Das Modell liegt lokal (nie im Repo).

  ~/wendelin-models/kws/wp58/venv/bin/python -I tool/kws_parity_fixture.py \
      --oww ~/wendelin-models/kws/wp58/dl/oww \
      --model ~/wendelin-models/kws/wp130/out/wendelin_wp130_a.onnx \
      --out app/test/fixtures/wake
"""
import argparse, json, os, sys, wave
import numpy as np

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, "train_wake_word"))
import common as C  # noqa: E402


def synth(seed=7, seconds=3.0):
    """Silbenartiges Signal: Grundton mit Formanten, Silben-Huellkurve, Rauschen."""
    rng = np.random.default_rng(seed)
    t = np.arange(int(C.SR * seconds)) / C.SR
    f0 = 110 + 25 * np.sin(2 * np.pi * 0.9 * t)
    phase = 2 * np.pi * np.cumsum(f0) / C.SR
    x = np.zeros_like(t)
    for k in range(1, 30):
        f = k * f0
        gain = sum(np.exp(-((f - c) / w) ** 2) for c, w in ((700, 150), (1200, 200), (2600, 300)))
        x += gain * np.sin(k * phase)
    env = np.clip(np.sin(2 * np.pi * 2.2 * t) + 0.2, 0, None) ** 0.7
    x = x * env
    x = 0.5 * x / np.abs(x).max()
    x = x + 0.004 * rng.standard_normal(len(t))   # Rauschboden, ca. -48 dBFS
    return (x * 32767).astype("int16")


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--oww", required=True); a.add_argument("--model", required=True)
    a.add_argument("--out", required=True)
    a.add_argument("--skip", type=int, default=160, help="Samples am Anfang, um die das Batch-Raster hinter dem der App liegt")
    a = a.parse_args()
    import onnxruntime as ort
    pcm = synth()
    x = pcm.astype("float32") / 32767
    # Die App rechnet im Strom: Mel-Chunks von 1280 Samples mit 480 Samples
    # Kontext, das Embedding-Raster liegt dadurch 7 Mel-Frames (1120 Samples)
    # hinter dem des Batch-Pfads (kws_measure: Raster ab Clipanfang). Fuer den
    # Paritaetstest steht deshalb PHASE Nullen mehr vor dem Clip; die Fenster
    # sind dann Embedding fuer Embedding dieselben wie die der App.
    # Zwei Unterschiede zur App, beide hier berücksichtigt:
    # 1. Raster: Die App rechnet im Strom (Mel-Chunks von 1280 Samples mit 480
    #    Samples Kontext); ihr k-tes Embedding beginnt bei 160 + 1280 k, das
    #    Batch-Raster von kws_measure bei 1280 k. Das Messskript rechnet daher
    #    auf x[SKIP:] (SKIP = 160), dann sind es dieselben Embeddings.
    # 2. Mel-Untergrenze: Das Mel-Modell begrenzt nach unten relativ zum
    #    Maximum des Eingangs (Batch: ganzer Clip, App: je Chunk). Digitale
    #    Stille (Nullen) ergibt deshalb verschiedene Werte; das Fixture hat
    #    durchgehend ein Rauschen (wie ein Mikrofon) und keine Null-Polster,
    #    der Unterschied bleibt unter 80 dB und fällt nicht an.
    af = C.make_features(a.oww, 1)
    emb = C.embed(af, [x[a.skip:]])[0]
    n = len(emb) - C.WIN + 1
    W = np.stack([emb[j:j + C.WIN] for j in range(n)]).astype("float32")
    so = ort.SessionOptions(); so.intra_op_num_threads = 1
    sess = ort.InferenceSession(a.model, so, providers=["CPUExecutionProvider"])
    scores = sess.run(None, {"input": W})[0][:, 0]
    os.makedirs(a.out, exist_ok=True)
    with wave.open(os.path.join(a.out, "parity.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(C.SR); w.writeframes(pcm.tobytes())
    # Fensterenden im Strom des gepolsterten Clips (1 s Stille davor).
    ends = [C.window_end(j) + a.skip for j in range(n)]
    json.dump({"ends": ends, "scores": [float(s) for s in scores],
               "windows": [[float(v) for v in W[j].ravel()[:8]] for j in range(n)]},
              open(os.path.join(a.out, "parity.json"), "w"), indent=0)
    print(n, "Fenster, max", scores.max(), "min", scores.min())


if __name__ == "__main__":
    main()
