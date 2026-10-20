#!/usr/bin/env python3
"""microWakeWord (Apache-2.0, kahrendt/microWakeWord) fuer „Wendelin“ bzw. „Hey Wendelin“ mit den Daten des Projekts (WP106, WP111).

Aufruf mit dem Spezial-venv (Python 3.11, TF 2.18, microwakeword-Quellen per PYTHONPATH):
  K=~/wendelin-models/kws; PYTHONPATH=$K/wp106/mww-src $K/wp111/mww-venv/bin/python mww_train.py prep|feats|train --word wendelin|hey [--steps ..]
WP111: --word waehlt die Positivmenge (wendelin = nur „Wendelin“ plus ein Teil „Hey Wendelin“, hey = nur „Hey Wendelin“; fuer hey ist das
nackte „Wendelin“ zusaetzlich Negativ). Alle Negativmengen (Sprache, Verwechsler, Hintergrund, Hall) sind fuer beide Woerter gleich.
Ohne --word (WP106) bleibt der alte Pfad wp106/mww.
Ohne Fremddaten-Zwang: Hintergrund/Hall sind synthetisch (wie v7/v9), Negative = Piper-Saetze (CC0/CC-BY) + FLEURS train (CC-BY 4.0).
Alles unter $M/mww; Quell-WAVs aus $K/wp58/gen (Symlinks).
"""
import argparse, glob, os, sys, runpy
import numpy as np

K = os.path.expanduser("~/wendelin-models/kws")
M = f"{K}/wp106/mww"
G = f"{K}/wp58/gen"
G2 = f"{K}/wp111/gen"          # WP111: bare/hey/conf2 (gen_samples.py --kind bare|hey|conf2)
M111 = f"{K}/wp111/mww"
CONF_PHRASES_NOTE = "conf = wp58 conf* + wp111 conf2 (gleich fuer beide Woerter)"
HERE = os.path.dirname(os.path.abspath(__file__))


def link(srcs, dst, pat="*.wav"):
    os.makedirs(dst, exist_ok=True)
    for s in srcs:
        for f in glob.glob(os.path.join(s, pat)):
            d = os.path.join(dst, os.path.basename(f))
            if not os.path.lexists(d): os.symlink(f, d)


def prep():
    import soundfile as sf
    sys.path.insert(0, HERE)
    import common as C
    rng = np.random.default_rng(3)
    os.makedirs(f"{M}/rirs", exist_ok=True); os.makedirs(f"{M}/bg", exist_ok=True)
    for i in range(150):
        rt = rng.uniform(0.15, 1.0); t = np.arange(int(rt * 16000)) / 16000
        ir = rng.standard_normal(len(t)) * np.exp(-6.9 * t / rt); ir[int(rng.integers(0, 40))] += 3
        sf.write(f"{M}/rirs/ir{i:03d}.wav", (ir / np.abs(ir).max() * .9).astype("float32"), 16000, subtype="PCM_16")
    pool = C.load_dir(f"{G}/real/dev")[:200] + C.load_dir(f"{G}/neg")[:200]      # Babble aus Sprache
    for i in range(240):
        kind = C.NOISE_KINDS[i % len(C.NOISE_KINDS)]
        y = C.make_noise(15 * 16000, kind, rng, pool)
        sf.write(f"{M}/bg/bg{i:03d}_{kind}.wav", (y / (np.abs(y).max() + 1e-9) * .8).astype("float32"), 16000, subtype="PCM_16")
    link([f"{G}/pos", f"{G}/pos2", f"{G}/pos3"], f"{M}/src/pos")
    link([f"{G}/conf", f"{G}/conf2", f"{G}/conf3"], f"{M}/src/conf")
    link([f"{G}/neg", f"{G}/neg3", f"{G}/real/train"], f"{M}/src/speech")
    link([f"{G}/real/dev"], f"{M}/src/ambient")
    for n in ("pos", "conf", "speech", "ambient"): print(n, len(os.listdir(f"{M}/src/{n}")))


def prep111():
    """WP111: Quellordner (Symlinks) fuer beide Woerter; Hall/Hintergrund werden von WP106 wiederverwendet."""
    for n in ("rirs", "bg"):
        os.makedirs(M111, exist_ok=True)
        if not os.path.lexists(f"{M111}/{n}"): os.symlink(f"{K}/wp106/mww/{n}", f"{M111}/{n}")
    link([f"{G2}/bare"], f"{M111}/src/pos_wendelin")
    heys = sorted(glob.glob(f"{G2}/hey/*.wav"))
    nb = len(glob.glob(f"{G2}/bare/*.wav"))
    for f in heys[: int(0.4 * nb)]:                     # „Hey Wendelin“ ist fuer das Wort Wendelin ebenfalls ein Treffer
        d = f"{M111}/src/pos_wendelin/{os.path.basename(f)}"
        if not os.path.lexists(d): os.symlink(f, d)
    link([f"{G2}/hey"], f"{M111}/src/pos_hey")
    link([f"{G2}/bare"], f"{M111}/src/conf_bare")       # nur fuer hey: nacktes Wendelin ist Negativ
    link([f"{G}/conf", f"{G}/conf2", f"{G}/conf3", f"{G2}/conf2"], f"{M111}/src/conf")
    link([f"{G}/neg", f"{G}/neg3", f"{G}/real/train"], f"{M111}/src/speech")
    link([f"{G}/real/dev"], f"{M111}/src/ambient")
    for n in sorted(os.listdir(f"{M111}/src")): print(n, len(os.listdir(f"{M111}/src/{n}")))


def feats(a):
    from mmap_ninja.ragged import RaggedMmap
    from microwakeword.audio.augmentation import Augmentation
    from microwakeword.audio.clips import Clips
    from microwakeword.audio.spectrograms import SpectrogramGeneration
    probs = {"SevenBandParametricEQ": 0.15, "TanhDistortion": 0.05, "PitchShift": 0.2, "BandStopFilter": 0.1,
             "AddColorNoise": 0.2, "AddBackgroundNoise": 0.75, "Gain": 1.0, "RIR": 0.5}
    kw = dict(augmentation_probabilities=probs, impulse_paths=[f"{M}/rirs"], background_paths=[f"{M}/bg"],
              background_min_snr_db=-2, background_max_snr_db=20)
    aug_w = Augmentation(augmentation_duration_s=3.2, min_jitter_s=0.195, max_jitter_s=0.205, **kw)
    aug_s = Augmentation(augmentation_duration_s=None, truncate_randomly=True, **kw)
    def dump(clips, aug, outdir, split, rep, slide=None, split_dur=None, step=10):
        os.makedirs(os.path.dirname(outdir), exist_ok=True)
        sg = SpectrogramGeneration(clips=clips, augmenter=aug, slide_frames=slide, split_spectrogram_duration_s=split_dur, step_ms=step)
        RaggedMmap.from_generator(out_dir=outdir, sample_generator=sg.spectrogram_generator(split=split, repeat=rep), batch_size=100, verbose=False)
        print("fertig", outdir, flush=True)
    F = f"{M}/feat"
    todo = (("wake", "pos", aug_w, dict(max_clip_duration_s=1.5), a.pos_rep, "pos"),
            ("conf", "conf", aug_w, dict(max_clip_duration_s=1.5), a.conf_rep, "conf"),
            ("speech", "speech", aug_s, {}, 1, "speech"))
    if a.word:      # WP111: gemeinsame Negativmengen nur einmal, Positivmenge je Wort
        todo = (("wake", f"pos_{a.word}", aug_w, dict(max_clip_duration_s=1.5), a.pos_rep, f"pos_{a.word}"),
                ("conf", "conf", aug_w, dict(max_clip_duration_s=1.5), a.conf_rep, "conf"),
                ("conf_bare", "conf_bare", aug_w, dict(max_clip_duration_s=1.5), a.conf_rep, "conf_bare"),
                ("speech", "speech", aug_s, {}, 1, "speech"))
    for name, d, aug, kwc, reps, tag in todo:
        if a.only_ambient: break
        if a.word and tag != f"pos_{a.word}" and os.path.isdir(f"{F}/{tag}/testing/wakeword_mmap"): continue   # schon berechnet
        cl = Clips(input_directory=f"{M}/src/{d}", file_pattern="*.wav", random_split_seed=10, split_count=0.1, **kwc)
        for sp, sub, rep, slide in (("train", "training", reps, 10 if name != "speech" else None),
                                    ("validation", "validation", 1, 10 if name != "speech" else None),
                                    ("test", "testing", 1, 1 if name != "speech" else None)):
            dump(cl, aug, f"{F}/{tag}/{sub}/wakeword_mmap", sp, rep, slide)
    # Ambient: FLEURS dev (sprecherfremd), in 3,2-s-Stuecken gesplittet, Haelfte Validierung, Haelfte Test
    if a.word and os.path.isdir(f"{F}/ambient/testing_ambient/wakeword_mmap"): return
    cl = Clips(input_directory=f"{M}/src/ambient", file_pattern="*.wav", random_split_seed=10, split_count=0.45)
    for sp, sub in (("validation", "validation_ambient"), ("test", "testing_ambient")):
        dump(cl, None, f"{F}/ambient/{sub}/wakeword_mmap", sp, 1, None)   # ungesplittet: das Training teilt selbst (truncation_strategy split)


def train(a):
    import yaml
    F = f"{M}/feat"
    f = lambda d, w, truth, trunc, pen=1.0: {"features_dir": f"{F}/{d}", "sampling_weight": w, "penalty_weight": pen,
                                            "truth": truth, "truncation_strategy": trunc, "type": "mmap"}
    cfg = {"window_step_ms": 10, "train_dir": f"{M}/trained_{a.name}",
           "features": [f(f"pos_{a.word}" if a.word else "pos", a.w_pos, True, "truncate_start"), f("speech", a.w_speech, False, "random"),
                        f("conf", a.w_conf, False, "truncate_start", a.pen_conf)]
           + ([f("conf_bare", a.w_conf, False, "truncate_start", a.pen_conf)] if a.word == "hey" else [])
           + [f("ambient" if a.word else "ambient2", 0.0, False, "split")],
           "training_steps": [a.steps, a.steps // 2], "positive_class_weight": [1, 1], "negative_class_weight": [20, a.neg_w2],
           "learning_rates": [0.001, 0.0003], "batch_size": 128,
           "time_mask_max_size": [0, 5], "time_mask_count": [0, 2], "freq_mask_max_size": [0, 3], "freq_mask_count": [0, 2],
           "eval_step_interval": 500, "clip_duration_ms": 1500, "target_minimization": 0.9, "minimization_metric": None,
           "maximization_metric": "average_viable_recall"}
    os.makedirs(f"{M}/cfg", exist_ok=True)
    cp = f"{M}/cfg/{a.name}.yaml"; yaml.dump(cfg, open(cp, "w"))
    import tensorflow as tf
    tf.config.threading.set_intra_op_parallelism_threads(a.threads); tf.config.threading.set_inter_op_parallelism_threads(2)
    sys.argv = ["model_train_eval", f"--training_config={cp}", "--train", "1", "--restore_checkpoint", "1",
                "--test_tf_nonstreaming", "0", "--test_tflite_nonstreaming", "0", "--test_tflite_nonstreaming_quantized", "0",
                "--test_tflite_streaming", "0", "--test_tflite_streaming_quantized", "1", "--use_weights", "best_weights",
                "mixednet", "--pointwise_filters", "64,64,64,64", "--repeat_in_block", "1, 1, 1, 1",
                "--mixconv_kernel_sizes", "[5], [7,11], [9,15], [23]", "--residual_connection", "0,0,0,0",
                "--first_conv_filters", "32", "--first_conv_kernel_size", "5", "--stride", "3"]
    runpy.run_module("microwakeword.model_train_eval", run_name="__main__")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("stage", choices=["prep", "feats", "train"]); p.add_argument("--name", default="m1")
    p.add_argument("--word", choices=["wendelin", "hey"], help="WP111: Wort (Positivmenge); setzt den Arbeitsordner wp111/mww")
    p.add_argument("--pos-rep", type=int, default=2); p.add_argument("--conf-rep", type=int, default=2)
    p.add_argument("--steps", type=int, default=10000); p.add_argument("--threads", type=int, default=4)
    p.add_argument("--w-pos", type=float, default=2.0); p.add_argument("--w-speech", type=float, default=10.0)
    p.add_argument("--w-conf", type=float, default=4.0); p.add_argument("--pen-conf", type=float, default=2.0)
    p.add_argument("--only-ambient", action="store_true")
    p.add_argument("--neg-w2", type=float, default=30.0)
    a = p.parse_args()
    if a.word:
        M = M111
    {"prep": lambda: prep111() if a.word else prep(), "feats": lambda: feats(a), "train": lambda: train(a)}[a.stage]()
