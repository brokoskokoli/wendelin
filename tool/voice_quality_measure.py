#!/usr/bin/env python3
"""Misst STT- und TTS-Kandidaten mit sherpa-onnx (Python) auf dem Mac (WP102).

Nicht Teil der App und nicht des Gates. Python-Umgebung ausserhalb des Repos:

  python3 -m venv ~/wendelin-fixtures/venv
  ~/wendelin-fixtures/venv/bin/pip install sherpa-onnx numpy soundfile jiwer

Modelle liegen je Ordner unter --models (nie einchecken), Aufbau siehe
MODELS/VOICES unten. Aufrufe (immer nacheinander, ein Modell je Prozess, damit
die RAM-Spitze stimmt):

  voice_quality_measure.py stt  --models DIR [--only a,b] [--threads 4] [--out stt.json]
                                [--hotwords DIR]   # DIR: hotwords.txt + bpe.vocab, nur Parakeet
  voice_quality_measure.py tts  --models DIR --samples DIR [--only a,b] [--out tts.json]
  voice_quality_measure.py selftest
  voice_quality_measure.py table --stt stt.json [--tts tts.json]   # Markdown

STT-Eingabe: die Fixtures aus app/test/fixtures/stt (36 Befehle de/fr/en,
macOS `say`, 16 kHz) mit 300 ms Pre-Roll und 800 ms Endstille wie der Endpointer
der App, dazu je Sprache ein langer Satz (`say`, im Cache). Bedingungen:
clean, noisy (synthetisches Rauschen, 10 dB SNR), noisy+gtcrn. Die Messung ist
synthetisch; mit echten Stimmen sind andere Werte zu erwarten.
"""
import argparse
import json
import os
import re
import resource
import subprocess
import sys
import time
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FIX = REPO / "app/test/fixtures/stt"

# --- Kandidaten -------------------------------------------------------------
# kind: whisper | nemo_transducer | canary. Pfade relativ zu --models/<name>/.
STT = {
    "whisper-base": dict(kind="whisper", f=("base-encoder.int8.onnx", "base-decoder.int8.onnx", "base-tokens.txt")),
    "whisper-small": dict(kind="whisper", f=("small-encoder.int8.onnx", "small-decoder.int8.onnx", "small-tokens.txt")),
    "whisper-medium": dict(kind="whisper", f=("medium-encoder.int8.onnx", "medium-decoder.int8.onnx", "medium-tokens.txt")),
    "whisper-turbo": dict(kind="whisper", f=("turbo-encoder.int8.onnx", "turbo-decoder.int8.onnx", "turbo-tokens.txt")),
    "parakeet-v3": dict(kind="nemo_transducer", f=("encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt")),
    "canary-180m-flash": dict(kind="canary", d="sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8",
                              f=("encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt")),
}
GTCRN = "gtcrn_simple.onnx"
HOTWORDS_SCORE = 3.0

LONG = {
    "de": ("Anna", "Bitte lege morgen früh um halb acht einen Termin mit dem Zahnarzt in meinem Kalender an, erinnere mich "
                   "eine Stunde vorher daran und schreibe in meine Tagesnotiz, dass ich noch Milch, Brot und Äpfel "
                   "einkaufen muss, bevor die Geschäfte am Nachmittag schließen."),
    "fr": ("Thomas", "Crée demain matin à sept heures et demie un rendez-vous chez le dentiste dans mon agenda, rappelle-moi "
                     "une heure avant et note dans mon journal que je dois encore acheter du lait, du pain et des pommes "
                     "avant que les magasins ferment cet après-midi."),
    "en": ("Samantha", "Please create an appointment with the dentist tomorrow morning at half past seven in my calendar, "
                       "remind me an hour before and write in my daily note that I still have to buy milk, bread and "
                       "apples before the shops close this afternoon."),
}

NUM = {
    "de": "null eins zwei drei vier fünf sechs sieben acht neun zehn elf zwölf dreizehn vierzehn fünfzehn sechzehn siebzehn achtzehn neunzehn zwanzig".split(),
    "fr": "zéro un deux trois quatre cinq six sept huit neuf dix onze douze treize quatorze quinze seize dix-sept dix-huit dix-neuf vingt".split(),
    "en": "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty".split(),
}


def norm(text, lang):
    t = text.lower()
    t = re.sub(r"[.,;:!?¿¡«»\"„“”…]", " ", t)
    t = re.sub(r"[-'’]", " ", t)
    words = []
    for w in t.split():
        if w.isdigit() and int(w) <= 20:
            w = NUM[lang][int(w)].replace("-", " ")
        words.append(w)
    return " ".join(" ".join(words).split())


def wer_counts(ref, hyp):
    r, h = ref.split(), hyp.split()
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev = cur
    return d[len(h)], len(r)


def rss_mb():
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e6  # macOS: Bytes


def cur_rss_mb():
    out = subprocess.run(["ps", "-o", "rss=", "-p", str(os.getpid())], capture_output=True, text=True).stdout
    return int(out.strip()) / 1024


def read_wav(p):
    import numpy as np
    with wave.open(str(p), "rb") as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype("float32") / 32768


def write_wav(p, samples, sr):
    import numpy as np
    Path(p).parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(p), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())


def pad(s):
    import numpy as np
    return np.concatenate([np.zeros(4800, "float32"), s, np.zeros(12800, "float32")])


def long_fixture(lang, cache):
    wav = Path(cache) / f"long-{lang}.wav"
    if not wav.exists():
        voice, text = LONG[lang]
        Path(cache).mkdir(parents=True, exist_ok=True)
        aiff = wav.with_suffix(".aiff")
        subprocess.run(["say", "-v", voice, "-o", str(aiff), "--", text], check=True)
        subprocess.run(["afconvert", "--no-filler", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)], check=True)
        aiff.unlink()
    return wav


def fixtures(cache):
    rows = []
    for line in (FIX / "manifest.tsv").read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        id_, lang, _voice, text = line.split("\t")
        if not re.match(r"^(de|fr|en)-\d\d$", id_) and not id_.startswith("b6-"):
            continue
        kind = "b6" if id_.startswith("b6-") else "short"
        rows.append(dict(id=id_, lang=lang, text=text, kind=kind, wav=FIX / f"{id_}.wav"))
    for lang in LONG:
        rows.append(dict(id=f"long-{lang}", lang=lang, text=LONG[lang][1], kind="long", wav=long_fixture(lang, cache)))
    return rows


def make_noise(n, rng, rms):
    import numpy as np
    white = rng.standard_normal(n).astype("float32")
    # grob rosa: gleitender Mittelwert über weisses Rauschen + weisser Anteil
    k = np.ones(8, "float32") / 8
    pink = np.convolve(white, k, mode="same")
    x = 0.5 * white + 0.5 * pink * 2
    return x / (x.std() + 1e-9) * rms


def add_noise(sig, snr_db, seed):
    import numpy as np
    rng = np.random.default_rng(seed)
    speech = sig[4800:-12800] if len(sig) > 20000 else sig
    rms = float(np.sqrt(np.mean(speech ** 2)) + 1e-9)
    return np.clip(sig + make_noise(len(sig), rng, rms / (10 ** (snr_db / 20))), -1, 1).astype("float32")


def build_recognizer(name, models):
    import sherpa_onnx as so
    c = STT[name]
    d = Path(models) / c.get("d", name)
    f = [str(d / x) for x in c["f"]]
    return c, d, f, so


def make_rec(name, models, threads, lang, hotwords=None):
    c, d, f, so = build_recognizer(name, models)
    R = so.OfflineRecognizer
    if c["kind"] == "whisper":
        return R.from_whisper(f[0], f[1], f[2], language=lang, task="transcribe", num_threads=threads, tail_paddings=-1)
    if c["kind"] == "canary":
        return R.from_nemo_canary(f[0], f[1], f[2], src_lang=lang, tgt_lang=lang, num_threads=threads)
    if hotwords:
        # Parakeet (BPE): modified_beam_search + Hotwords-Datei, bpe_vocab = SentencePiece-Vocab
        # des Tokenizers (steckt in der .nemo-Datei des Originals, nicht im sherpa-Paket).
        hw = Path(hotwords)
        return R.from_transducer(f[0], f[1], f[2], f[3], num_threads=threads, model_type="nemo_transducer",
                                 decoding_method="modified_beam_search", hotwords_file=str(hw / "hotwords.txt"),
                                 hotwords_score=HOTWORDS_SCORE, modeling_unit="bpe", bpe_vocab=str(hw / "bpe.vocab"))
    return R.from_transducer(f[0], f[1], f[2], f[3], num_threads=threads, model_type="nemo_transducer")


def decode(rec, samples):
    st = rec.create_stream()
    st.accept_waveform(16000, samples)
    t = time.perf_counter()
    rec.decode_stream(st)
    return st.result.text, time.perf_counter() - t


def zero():
    return dict(e=0, n=0, t=0.0, d=0.0, c=0, term=0)


def cmd_stt_one(a):
    """Ein Modell, eine Sprache, ein Prozess (saubere RAM-Spitze)."""
    import numpy as np
    import sherpa_onnx as so
    name, lang = a.one, a.lang
    rows = [r for r in fixtures(a.cache) if r["lang"] == lang]
    audio = {r["id"]: pad(read_wav(r["wav"])) for r in rows}
    base_mb = cur_rss_mb()
    t0 = time.perf_counter()
    rec = make_rec(name, a.models, a.threads, lang, a.hotwords)
    load = time.perf_counter() - t0
    after_load = cur_rss_mb()
    den = so.OfflineSpeechDenoiser(so.OfflineSpeechDenoiserConfig(
        model=so.OfflineSpeechDenoiserModelConfig(gtcrn=so.OfflineSpeechDenoiserGtcrnModelConfig(model=str(Path(a.models) / GTCRN)),
                                                  num_threads=a.threads)))
    decode(rec, audio[f"{lang}-01"])  # Warmup
    res = dict(model=name, lang=lang, load_s=load, base_mb=base_mb, after_load_mb=after_load, conds={}, hyps={})
    for cond in ("clean", "noisy", "noisy+gtcrn"):
        agg = {"short": zero(), "long": zero(), "b6": zero()}
        hyps = []
        for r in rows:
            s = audio[r["id"]]
            if cond != "clean":
                s = add_noise(s, 10, sum(map(ord, r["id"])))
            if cond == "noisy+gtcrn":
                s = np.asarray(den.run(s, 16000).samples, "float32")
            text, dt = decode(rec, s)
            e, n_ = wer_counts(norm(r["text"], lang), norm(text, lang))
            g = agg[r["kind"]]
            g["e"] += e; g["n"] += n_; g["t"] += dt; g["d"] += len(s) / 16000; g["c"] += 1
            if r["kind"] == "b6":
                g["term"] += int("wendelin" in norm(text, lang))
            hyps.append(dict(id=r["id"], ref=r["text"], hyp=text))
        res["conds"][cond] = agg
        res["hyps"][cond] = hyps
    res["peak_mb"] = rss_mb()
    print(json.dumps(res))


def merge_stt(name, parts):
    """Fasst die drei Sprachläufe eines Modells zusammen."""
    out = dict(model=name, load_s=round(sum(p["load_s"] for p in parts) / len(parts), 2),
               peak_mb=round(max(p["peak_mb"] for p in parts)),
               load_mb=round(max(p["after_load_mb"] - p["base_mb"] for p in parts)), conds={})
    for cond in parts[0]["conds"]:
        tot = {k: zero() for k in ("short", "long", "b6")}
        wer = {}
        for p in parts:
            c = p["conds"][cond]
            wer[p["lang"]] = round(100 * c["short"]["e"] / max(c["short"]["n"], 1), 1)
            for k in tot:
                for f in tot[k]:
                    tot[k][f] += c[k][f]
        t = tot
        out["conds"][cond] = dict(
            wer=wer, wer_all=round(100 * t["short"]["e"] / max(t["short"]["n"], 1), 1),
            wer_long=round(100 * t["long"]["e"] / max(t["long"]["n"], 1), 1),
            wer_b6=round(100 * t["b6"]["e"] / max(t["b6"]["n"], 1), 1),
            b6_term_hits=f'{t["b6"]["term"]}/{t["b6"]["c"]}',
            lat_short_ms=round(1000 * t["short"]["t"] / t["short"]["c"]),
            lat_long_ms=round(1000 * t["long"]["t"] / t["long"]["c"]),
            rtf_short=round(t["short"]["t"] / t["short"]["d"], 3),
            rtf_long=round(t["long"]["t"] / t["long"]["d"], 3))
    out["hyps"] = {p["lang"]: p["hyps"]["clean"] for p in parts}
    return out


def cmd_stt(a):
    names = a.only.split(",") if a.only else list(STT)
    out = []
    for n in names:
        d = Path(a.models) / STT[n].get("d", n)
        if not d.exists():
            print(f"[skip] {n}: {d} fehlt", file=sys.stderr); continue
        parts = []
        for lang in ("de", "fr", "en"):
            print(f"[stt] {n} {lang}", file=sys.stderr, flush=True)
            p = subprocess.run([sys.executable, "-I", __file__, "stt-one", "--one", n, "--lang", lang, "--models", a.models,
                                "--threads", str(a.threads), "--cache", a.cache]
                               + (["--hotwords", a.hotwords] if a.hotwords else []), capture_output=True, text=True)
            if p.returncode != 0:
                print(p.stderr[-1500:], file=sys.stderr); parts = []; break
            parts.append(json.loads(p.stdout.strip().splitlines()[-1]))
        if not parts:
            continue
        r = merge_stt(n, parts)
        r["size_mb"] = round(sum(f.stat().st_size for f in d.glob("*") if f.is_file()) / 1e6)
        out.append(r)
        Path(a.out).write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f"-> {a.out}", file=sys.stderr)


# --- TTS --------------------------------------------------------------------
TEXT = {
    "de": "Guten Morgen! Heute ist ein schöner Tag. Um zehn Uhr hast du einen Termin beim Zahnarzt, danach kaufst du Milch und Brot ein.",
    "fr": "Bonjour ! Aujourd'hui, c'est une belle journée. À dix heures, tu as rendez-vous chez le dentiste, puis tu achètes du lait et du pain.",
    "en": "Good morning! Today is a lovely day. At ten o'clock you have an appointment at the dentist, and afterwards you buy milk and bread.",
}
SHORT = {"de": "Okay, erledigt.", "fr": "D'accord, c'est fait.", "en": "Okay, done."}

# name -> (verzeichnis, sprache, art, sid, kokoro-lang)
VOICES = {
    "piper-de-thorsten-medium": ("vits-piper-de_DE-thorsten-medium-int8", "de", "vits"),
    "piper-de-thorsten-high": ("vits-piper-de_DE-thorsten-high-int8", "de", "vits"),
    "piper-de-thorsten-high-fp32": ("vits-piper-de_DE-thorsten-high", "de", "vits"),
    "piper-de-kerstin-low": ("vits-piper-de_DE-kerstin-low-int8", "de", "vits"),
    "piper-de-miro-high": ("vits-piper-de_DE-miro-high-int8", "de", "vits"),
    "piper-fr-siwis-medium": ("vits-piper-fr_FR-siwis-medium-int8", "fr", "vits"),
    "piper-fr-miro-high": ("vits-piper-fr_FR-miro-high-int8", "fr", "vits"),
    "piper-en-ljspeech-medium": ("vits-piper-en_US-ljspeech-medium-int8", "en", "vits"),
    "piper-en-lessac-high": ("vits-piper-en_US-lessac-high-int8", "en", "vits"),
    "kokoro-fr-siwis": ("kokoro-int8-multi-lang-v1_0", "fr", "kokoro"),
    "kokoro-en-heart": ("kokoro-int8-multi-lang-v1_0", "en", "kokoro"),
    "kokoro-en-emma": ("kokoro-int8-multi-lang-v1_0", "en", "kokoro"),
}
# Sprecher-IDs von kokoro-multi-lang-v1_0 (54 Stimmen, IDs 0-52 laut README des Modells,
# gegen speaker2id der Modell-Metadaten geprueft) und Sprachcode je Stimme.
KOKORO_SID = {"kokoro-fr-siwis": 30, "kokoro-en-heart": 3, "kokoro-en-emma": 21}  # ff_siwis, af_heart, bf_emma
KOKORO_LANG = {"kokoro-fr-siwis": "fr", "kokoro-en-heart": "en-us", "kokoro-en-emma": "en"}  # britisch; "en-gb" kennt die espeak-Datei des Modells nicht


def make_tts(name, models, threads):
    import sherpa_onnx as so
    d, lang, kind = VOICES[name][:3]
    p = Path(models) / d
    if kind == "vits":
        onnx = next(x for x in p.glob("*.onnx"))
        lex = p / "lexicon.txt"
        mc = so.OfflineTtsModelConfig(vits=so.OfflineTtsVitsModelConfig(
            model=str(onnx), tokens=str(p / "tokens.txt"), data_dir=str(p / "espeak-ng-data"),
            lexicon=str(lex) if lex.exists() else ""), num_threads=threads)
        sid = 0
    else:
        mc = so.OfflineTtsModelConfig(kokoro=so.OfflineTtsKokoroModelConfig(
            model=str(p / "model.int8.onnx") if (p / "model.int8.onnx").exists() else str(p / "model.onnx"),
            voices=str(p / "voices.bin"), tokens=str(p / "tokens.txt"), data_dir=str(p / "espeak-ng-data"),
            dict_dir=str(p / "dict"), lexicon=",".join(str(x) for x in sorted(p.glob("lexicon-*.txt"))),
            lang=KOKORO_LANG[name]), num_threads=threads)
        sid = KOKORO_SID[name]
    cfg = so.OfflineTtsConfig(model=mc, max_num_sentences=1)
    return so.OfflineTts(cfg), sid


def cmd_tts_one(a):
    name = a.one
    d, lang, kind = VOICES[name][:3]
    base = cur_rss_mb()
    t0 = time.perf_counter()
    tts, sid = make_tts(name, a.models, a.threads)
    load = time.perf_counter() - t0
    tts.generate(SHORT[lang], sid=sid)  # Warmup
    res = dict(voice=name, lang=lang, load_s=round(load, 2), base_mb=round(base), after_load_mb=round(cur_rss_mb()), runs={})
    for key, text in (("short", SHORT[lang]), ("long", TEXT[lang])):
        first = []
        t = time.perf_counter()

        def cb(samples, progress, first=first, t=t):
            if not first:
                first.append(time.perf_counter() - t)
            return 1
        audio = tts.generate(text, sid=sid, speed=1.0, callback=cb)
        dt = time.perf_counter() - t
        dur = len(audio.samples) / audio.sample_rate
        res["runs"][key] = dict(first_audio_ms=round(1000 * (first[0] if first else dt)), total_ms=round(1000 * dt),
                                audio_s=round(dur, 1), rtf=round(dt / dur, 3))
        if key == "long":
            import numpy as np
            write_wav(Path(a.samples) / name / f"{name}-{lang}.wav", np.asarray(audio.samples, "float32"), audio.sample_rate)
    res["peak_mb"] = round(rss_mb())
    print(json.dumps(res))


def cmd_tts(a):
    names = a.only.split(",") if a.only else list(VOICES)
    out = []
    for n in names:
        d = Path(a.models) / VOICES[n][0]
        if not d.exists():
            print(f"[skip] {n}: {d} fehlt", file=sys.stderr); continue
        print(f"[tts] {n}", file=sys.stderr, flush=True)
        p = subprocess.run([sys.executable, "-I", __file__, "tts-one", "--one", n, "--models", a.models,
                            "--threads", str(a.threads), "--samples", a.samples], capture_output=True, text=True)
        if p.returncode != 0:
            print(p.stderr[-1500:], file=sys.stderr); continue
        r = json.loads(p.stdout.strip().splitlines()[-1])
        r["size_mb"] = round(sum(f.stat().st_size for f in d.rglob("*") if f.is_file()) / 1e6)
        out.append(r)
        Path(a.out).write_text(json.dumps(out, ensure_ascii=False, indent=1))


def cmd_table(a):
    if a.stt:
        print("| Modell | MB | Laden s | RAM-Spitze MB | WER de | fr | en | gesamt | lang | Satz ms | RTF kurz | RTF lang | lang ms |")
        print("|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|")
        for r in json.load(open(a.stt)):
            c = r["conds"]["clean"]
            print(f'| {r["model"]} | {r["size_mb"]} | {r["load_s"]} | {r["peak_mb"]} | {c["wer"]["de"]} | {c["wer"]["fr"]} | {c["wer"]["en"]} | '
                  f'{c["wer_all"]} | {c["wer_long"]} | {c["lat_short_ms"]} | {c["rtf_short"]} | {c["rtf_long"]} | {c["lat_long_ms"]} |')
        print("\n| Modell | WER clean | WER noisy | WER noisy+GTCRN | Wendelin-Treffer clean/noisy/GTCRN |\n|---|--:|--:|--:|--:|")
        for r in json.load(open(a.stt)):
            c = r["conds"]
            print(f'| {r["model"]} | {c["clean"]["wer_all"]} | {c["noisy"]["wer_all"]} | {c["noisy+gtcrn"]["wer_all"]} | '
                  f'{c["clean"]["b6_term_hits"]} / {c["noisy"]["b6_term_hits"]} / {c["noisy+gtcrn"]["b6_term_hits"]} |')
    if a.tts:
        print("\n| Stimme | Spr. | MB | Laden s | RAM-Spitze MB | RTF kurz | RTF lang | erstes Audio kurz ms | erstes Audio lang ms |\n|---|---|--:|--:|--:|--:|--:|--:|--:|")
        for r in json.load(open(a.tts)):
            s, l = r["runs"]["short"], r["runs"]["long"]
            print(f'| {r["voice"]} | {r["lang"]} | {r["size_mb"]} | {r["load_s"]} | {r["peak_mb"]} | {s["rtf"]} | {l["rtf"]} | {s["first_audio_ms"]} | {l["first_audio_ms"]} |')


def selftest():
    """Prüft Normalisierung und Wortfehlerrate (python3 voice_quality_measure.py selftest)."""
    assert norm("Trag mir um 10 Uhr, Tauchen ein!", "de") == "trag mir um zehn uhr tauchen ein"
    assert norm("Qu'est-ce que 7 ?", "fr") == "qu est ce que sept"
    assert norm("20 Minuten", "de") == "zwanzig minuten" and norm("21", "de") == "21"
    assert wer_counts("a b c d", "a x c") == (2, 4)
    assert wer_counts("a b", "a b") == (0, 2)
    assert wer_counts("a", "") == (1, 1)
    print("ok")


def main():
    if sys.argv[1:] == ["selftest"]:
        return selftest()
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for n in ("stt", "stt-one", "tts", "tts-one"):
        p = sub.add_parser(n)
        p.add_argument("--models", required=True)
        p.add_argument("--only")
        p.add_argument("--one")
        p.add_argument("--hotwords", help="Ordner mit hotwords.txt und bpe.vocab (nur Parakeet)")
        p.add_argument("--lang")
        p.add_argument("--threads", type=int, default=4)
        p.add_argument("--cache", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "wp102-long"))
        p.add_argument("--samples", default="wp102-samples")
        p.add_argument("--out", default=f"{n.split('-')[0]}.json")
    t = sub.add_parser("table")
    t.add_argument("--stt"); t.add_argument("--tts")
    a = ap.parse_args()
    {"stt": cmd_stt, "stt-one": cmd_stt_one, "tts": cmd_tts, "tts-one": cmd_tts_one, "table": cmd_table}[a.cmd](a)


if __name__ == "__main__":
    main()
