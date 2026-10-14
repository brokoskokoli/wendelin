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
"""
import argparse, glob, os, time
import numpy as np
import soundfile as sf
import sherpa_onnx

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


if __name__ == "__main__":
    main()
