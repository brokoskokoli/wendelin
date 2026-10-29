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
  voice_quality_measure.py hotword-bias --models DIR --bpe-vocab FILE [--cache DIR] [--out hb.json] [--md note.md]
                                # WP146: Einfluss der Hotwords auf Einfügungen (nur Parakeet, de)
  voice_quality_measure.py hotword-bias-wake --models DIR --bpe-vocab FILE   # dito, Wake-Pfad („Hey Wendelin, …“)
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
HOTWORDS_SCORE = 1.0                             # = defaultHotwordsScore (WP146)

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
        id_, lang, _voice, text = line.split("\t")[:4]
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



# --- WP146: Hotword-Bias ------------------------------------------------------
# Frage: erfindet Parakeet mit Hotwords (modified_beam_search, Bonus) Kontaktnamen,
# wenn das Audio schlecht ist? Alle Namen sind erfunden (Silben, feste Seed).
SYL_ON = "b d f g h k l m n p r s t v w z br gr kr tr fr st sch kl pl".split()
SYL_NU = "a e i o u au ei".split()
SYL_CO = ["", "", "n", "r", "l", "s", "t", "k", "nd", "rn", "lk"]
LIST_NAMES = ["Baumarktliste", "Geschenkideen", "Wochenplan", "Urlaubsplanung", "Buecherwunsch"]
NAME_CMDS = [  # {n}: erfundener Name, der auch in der Hotword-Liste steht
    "Ruf {n} an.", "Schick eine Nachricht an {n}.", "Wann hat {n} Geburtstag?", "Schreib {n}, dass ich später komme.",
    "Wie ist die Nummer von {n}?", "Erinnere mich daran, {n} zu besuchen.", "Lade {n} zum Essen ein.",
    "Sag {n} bitte Bescheid.", "Wo wohnt {n} eigentlich?", "Trag ein Treffen mit {n} für morgen ein.",
]
NAME_VOICES = ["Anna", "Flo (German (Germany))", "Reed (German (Germany))"]
SCORES = (1.0, 1.5, 2.0, 3.0)


def gen_names(count, seed=146):
    import random
    rng = random.Random(seed)

    def word(k):
        return "".join(rng.choice(SYL_ON) + rng.choice(SYL_NU) + rng.choice(SYL_CO) for _ in range(k)).capitalize()
    seen, out = set(), []
    while len(out) < count:
        first, last = word(2), word(rng.choice((2, 3)))
        if first.lower() in seen or last.lower() in seen or first.lower() == last.lower():
            continue
        seen |= {first.lower(), last.lower()}
        out.append(f"{first} {last}")
    return out


def say_wav(text, voice, wav):
    if not wav.exists():
        wav.parent.mkdir(parents=True, exist_ok=True)
        aiff = wav.with_suffix(".aiff")
        subprocess.run(["say", "-v", voice, "-o", str(aiff), "--", text], check=True)
        subprocess.run(["afconvert", "--no-filler", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)], check=True)
        aiff.unlink()
    return wav


def first_word_span(sig, sr=16000):
    """Grobe Lage des ersten Wortes (Start, Ende in Samples) über die Energie in 10-ms-Rahmen."""
    import numpy as np
    fr = 160
    n = len(sig) // fr
    e = np.sqrt((sig[:n * fr].reshape(n, fr) ** 2).mean(axis=1))
    thr = max(0.1 * e.max(), 1e-4)
    on = int(np.argmax(e > thr))
    end = None
    for i in range(on + 6, n - 6):  # Lücke >= 60 ms unter der Schwelle = Wortende
        if (e[i:i + 6] < thr).all():
            end = i
            break
    if end is None or (end - on) * 10 < 150:
        end = min(on + 40, n)  # Notanker: 400 ms
    return on * fr, end * fr


def handoff_hole(sig):
    import numpy as np
    a, b = first_word_span(sig)
    mid = (a + b) // 2
    out = sig.copy()
    out[max(0, mid - 4800):mid + 4800] = 0  # 600 ms, mittig im ersten Wort
    return out


def handoff_cut(sig):
    a, b = first_word_span(sig)
    return sig[(a + b) // 2:].copy()  # beginnt hart mitten im ersten Wort


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * ((p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5) / d
    return (max(0.0, c - h), min(1.0, c + h))


def boot_wer(pairs, iters=1000):
    import random
    if not pairs:
        return (0.0, 0.0, 0.0)
    rng = random.Random(1)
    tot = lambda ps: 100 * sum(e for e, _ in ps) / max(sum(n for _, n in ps), 1)
    xs = sorted(tot([rng.choice(pairs) for _ in pairs]) for _ in range(iters))
    return (tot(pairs), xs[int(0.025 * iters)], xs[int(0.975 * iters)])


def hb_audio(a):
    """Liste (id, art, ref, samples): art = plain (de-Befehle ohne Namen) | named (mit Namen) | silence | noise."""
    import numpy as np
    names = gen_names(300)
    items = []
    for r in fixtures(a.cache):
        if r["lang"] == "de" and r["kind"] == "short":
            items.append(dict(id=r["id"], kind="plain", ref=r["text"], sig=pad(read_wav(r["wav"])), spoken=[]))
    for i, tpl in enumerate(NAME_CMDS):
        nm = names[i]
        txt = tpl.format(n=nm)
        wav = say_wav(txt, NAME_VOICES[i % 3], Path(a.cache) / f"hb-name-{i:02d}.wav")
        items.append(dict(id=f"name-{i:02d}", kind="named", ref=txt, sig=pad(read_wav(wav)),
                          spoken=[w.lower() for w in nm.split()]))
    return names, items


def hb_conditions(items, rng_seeds=3):
    """(bedingung, art, ref, spoken, samples)-Liste; Rausch-/Stille-Bedingungen ohne Referenz."""
    import numpy as np
    out = []
    for it in items:
        s = it["sig"]
        out.append(("clean", it, s))
        for k in range(rng_seeds):
            out.append(("noisy10", it, add_noise(s, 10, sum(map(ord, it["id"])) + 1000 * k)))
        out.append(("hole", it, handoff_hole(s)))
        out.append(("cut", it, handoff_cut(s)))
    empty = dict(id="-", kind="none", ref="", spoken=[])
    out.append(("silence", dict(empty, id="silence"), np.zeros(16000 * 3, "float32")))
    for level, rms in (("noise-40dB", 0.01), ("noise-26dB", 0.05)):
        for k in range(20):
            rng = np.random.default_rng(7000 + k)
            out.append((level, dict(empty, id=f"{level}-{k}"), make_noise(16000 * 3, rng, rms).astype("float32")))
    return out


def hb_config_list():
    cfgs = [("greedy", dict(method="greedy", n=0, score=0.0)), ("beam", dict(method="beam", n=0, score=0.0))]
    cfgs += [(f"hw300 s{sc}", dict(method="hw", n=300, score=sc)) for sc in SCORES]
    for sc in (1.5, 3.0):
        cfgs += [(f"hw0 s{sc}", dict(method="hw", n=0, score=sc)), (f"hw50 s{sc}", dict(method="hw", n=50, score=sc))]
    return cfgs


def hb_recognizer(cfg, names, models, bpe_vocab, threads, scratch):
    import sherpa_onnx as so
    c = STT["parakeet-v3"]
    d = Path(models) / "parakeet-v3"
    f = [str(d / x) for x in c["f"]]
    R = so.OfflineRecognizer
    kw = dict(num_threads=threads, model_type="nemo_transducer")
    if cfg["method"] == "greedy":
        return R.from_transducer(*f, **kw)
    if cfg["method"] == "beam":
        return R.from_transducer(*f, decoding_method="modified_beam_search", **kw)
    # Wie die App: Wendelin + Listennamen immer, dazu die ersten n erfundenen Kontakte.
    terms = ["Wendelin"] + LIST_NAMES + names[:cfg["n"]]
    hw = Path(scratch) / f"hotwords-{cfg['n']}.txt"
    hw.parent.mkdir(parents=True, exist_ok=True)
    hw.write_text("\n".join(terms) + "\n")
    return R.from_transducer(*f, decoding_method="modified_beam_search", hotwords_file=str(hw),
                             hotwords_score=cfg["score"], modeling_unit="bpe", bpe_vocab=str(bpe_vocab), **kw)


def hb_score(conds, hyps, names):
    """Aggregiert je Bedingung: WER (plain/named), Einfügungsrate, Recall, Nichtleer-Rate."""
    hot = {w.lower() for n in names for w in n.split()} | {"wendelin"} | {x.lower() for x in LIST_NAMES}
    res = {}
    for (cond, it, _), hyp in zip(conds, hyps):
        g = res.setdefault(cond, dict(plain=[], named=[], ins=0, n=0, nonempty=0, nm_hit=0, nm_all=0))
        h = norm(hyp, "de")
        hw = set(h.split())
        g["n"] += 1
        g["nonempty"] += int(bool(h))
        ref_words = set(norm(it["ref"], "de").split())
        g["ins"] += int(bool((hw & hot) - ref_words))
        if it["kind"] in ("plain", "named"):
            g[it["kind"]].append(wer_counts(norm(it["ref"], "de"), h))
        if it["kind"] == "named":
            g["nm_all"] += len(it["spoken"])
            g["nm_hit"] += sum(1 for w in it["spoken"] if w in hw)
    out = {}
    for cond, g in res.items():
        lo, hi = wilson(g["ins"], g["n"])
        out[cond] = dict(n=g["n"], ins=g["ins"], ins_ci=[lo, hi], nonempty=g["nonempty"],
                         wer_plain=boot_wer(g["plain"]) if g["plain"] else None,
                         wer_named=boot_wer(g["named"]) if g["named"] else None,
                         recall=[g["nm_hit"], g["nm_all"]])
    return out


def cmd_hotword_bias(a):
    import sherpa_onnx  # noqa: F401 (früh scheitern)
    names, items = hb_audio(a)
    conds = hb_conditions(items)
    print(f"[hb] {len(items)} Äußerungen, {len(conds)} Audios, {len(names)} Namen", file=sys.stderr, flush=True)
    out = dict(cfgs={}, hyps={}, n_items=len(items), n_audio=len(conds))
    for label, cfg in hb_config_list():
        t0 = time.perf_counter()
        rec = hb_recognizer(cfg, names, a.models, a.bpe_vocab, a.threads, a.cache)
        hyps = [decode(rec, s)[0] for _, _, s in conds]
        out["cfgs"][label] = hb_score(conds, hyps, names)
        out["hyps"][label] = [dict(c=c, id=it["id"], ref=it["ref"], hyp=h) for (c, it, _), h in zip(conds, hyps)]
        Path(a.out).write_text(json.dumps(out, ensure_ascii=False, indent=1))
        print(f"[hb] {label} {time.perf_counter() - t0:.0f}s", file=sys.stderr, flush=True)
    print(hb_markdown(out))


def hb_markdown(out):
    pct = lambda c: f'{100 * c["ins"] / c["n"]:.0f}% ({c["ins"]}/{c["n"]}; {100 * c["ins_ci"][0]:.0f}-{100 * c["ins_ci"][1]:.0f})'
    wer = lambda w: "-" if not w else f"{w[0]:.1f} ({w[1]:.0f}-{w[2]:.0f})"
    L = []
    for cond, title in (("clean", "clean"), ("noisy10", "noisy 10 dB (3 Seeds)"), ("hole", "Handoff-Loch 600 ms"),
                        ("cut", "Handoff-Schnitt")):
        L += [f"\n**{title}**: WER ohne Namen / mit Namen (95%-Bootstrap), Einfügungsrate erfundener Namen, Recall gesagter Namen\n",
              "| Konfiguration | WER ohne Namen | WER mit Namen | Namen eingefügt | Recall |", "|---|--:|--:|--:|--:|"]
        for label, cs in out["cfgs"].items():
            c = cs[cond]
            L.append(f'| {label} | {wer(c["wer_plain"])} | {wer(c["wer_named"])} | {pct(c)} | {c["recall"][0]}/{c["recall"][1]} |')
    L += ["\n**Nur Stille / nur Rauschen** (3 s): Anteil Läufe mit nicht leerem Transkript / mit eingefügtem Namen\n",
          "| Konfiguration | Stille | Rauschen -40 dB | Rauschen -26 dB |", "|---|--:|--:|--:|"]
    for label, cs in out["cfgs"].items():
        f = lambda c: f'{c["nonempty"]}/{c["n"]} / {c["ins"]}/{c["n"]}'
        L.append(f'| {label} | {f(cs["silence"])} | {f(cs["noise-40dB"])} | {f(cs["noise-26dB"])} |')
    return "\n".join(L)


# --- WP146: Hotword-Bias im Wake-Pfad -------------------------------------------
WAKE_OFFSETS = (-400, -200, 0, 200)  # ms gegenüber dem echten Ende von „Wendelin“


def active_span(sig, frames=160, rel=0.05):
    """(erster, letzter) aktiver Rahmen als Samples."""
    import numpy as np
    n = len(sig) // frames
    e = np.sqrt((sig[:n * frames].reshape(n, frames) ** 2).mean(axis=1))
    idx = np.nonzero(e > max(rel * e.max(), 1e-4))[0]
    return int(idx[0]) * frames, (int(idx[-1]) + 1) * frames


def first_gap(sig, min_ms=350, frames=160, rel=0.05):
    """(Start, Ende) der ersten Pause >= min_ms nach dem Sprechbeginn, sonst None."""
    import numpy as np
    n = len(sig) // frames
    e = np.sqrt((sig[:n * frames].reshape(n, frames) ** 2).mean(axis=1))
    act = e > max(rel * e.max(), 1e-4)
    i = int(np.argmax(act))
    need = min_ms // 10
    while i < n:
        if not act[i]:
            j = i
            while j < n and not act[j]:
                j += 1
            if j - i >= need and j < n:
                return i * frames, j * frames
            i = j
        else:
            i += 1
    return None


def wake_audio(a):
    """Je Befehl: Weckwort+Befehl mit/ohne Pause, dazu der Befehl allein (Tipp-Pfad)."""
    names = gen_names(300)
    cmds = [(r["id"], r["text"], []) for r in fixtures(a.cache) if r["lang"] == "de" and r["id"] in {f"de-{i:02d}" for i in range(1, 11)}]
    cmds += [(f"name-{i:02d}", tpl.format(n=names[i]), [w.lower() for w in names[i].split()]) for i, tpl in enumerate(NAME_CMDS)]
    out = []
    for k, (cid, text, spoken) in enumerate(cmds):
        voice = NAME_VOICES[k % 3]
        c = Path(a.cache)
        tip = pad(read_wav(say_wav(text, voice, c / f"hbw-tip-{k:02d}.wav")))
        pre = read_wav(say_wav("Hey Wendelin,", voice, c / f"hbw-pre-{k:02d}.wav"))
        np_sig = pad(read_wav(say_wav(f"Hey Wendelin, {text}", voice, c / f"hbw-np-{k:02d}.wav")))
        p_sig = pad(read_wav(say_wav(f"Hey Wendelin. [[slnc 500]] {text}", voice, c / f"hbw-p-{k:02d}.wav")))
        on_p, end_p = active_span(pre)
        gap = first_gap(p_sig)
        if gap is None:
            raise SystemExit(f"keine Pause erkannt: {cid}")
        out.append(dict(id=cid, text=text, spoken=spoken, tip=tip, np=np_sig, p=p_sig,
                        wake_end_np=4800 + end_p, gap=gap))
    return names, out


def wake_variants(it, seed):
    """(szenario, [segmente]); Szenario = pfad/offset/behandlung/rauschen."""
    import numpy as np
    out = []
    for noisy in (False, True):
        tag = "noisy" if noisy else "clean"
        nz = (lambda s: add_noise(s, 10, seed)) if noisy else (lambda s: s)
        out.append((f"tip/-/-/{tag}", [nz(it["tip"])]))
        for off in WAKE_OFFSETS:
            sh = off * 16
            # ohne Pause: ein Segment ab dem Schnitt
            s = nz(it["np"]); cut = max(0, it["wake_end_np"] + sh)
            seg = s[cut:].copy()
            out.append((f"np/{off}/plain/{tag}", [seg]))
            h = seg.copy(); h[:9600] = 0
            out.append((f"np/{off}/hole/{tag}", [h]))
            # mit Pause: erstes Segment bis zur Pause, dann der Rest, getrennt
            s = nz(it["p"]); g0, g1 = it["gap"]; cut = max(0, g0 + sh)
            for beh in ("plain", "mute", "hole"):
                t = s[cut:].copy()
                if beh == "mute":
                    t[:3200] = 0
                if beh == "hole":
                    t[:9600] = 0
                seg1 = t[:max(0, g0 - cut)]
                seg2 = t[max(0, g1 - cut):]
                out.append((f"p/{off}/{beh}/{tag}", [x for x in (seg1, seg2) if len(x) > 1600]))
    return out


def cmd_hotword_bias_wake(a):
    names, items = wake_audio(a)
    hot = {w.lower() for n in names for w in n.split()} | {x.lower() for x in LIST_NAMES}
    print(f"[hbw] {len(items)} Befehle", file=sys.stderr, flush=True)
    jobs = []
    for k, it in enumerate(items):
        for scen, segs in wake_variants(it, 31 + k):
            jobs.append((scen, it, segs))
    cfgs = [("beam", dict(method="beam", n=0, score=0.0))]
    for n in [int(x) for x in a.counts.split(",")]:
        for sc in [float(x) for x in a.scores.split(",")]:
            cfgs.append((f"hw{n} s{sc}", dict(method="hw", n=n, score=sc)))
    out = dict(rows={}, hyps={}, n_cmds=len(items))
    for label, cfg in cfgs:
        rec = hb_recognizer(cfg, names, a.models, a.bpe_vocab, a.threads, a.cache)
        t0 = time.perf_counter()
        rows, hy = {}, []
        for scen, it, segs in jobs:
            text = " ".join(decode(rec, pad(x))[0] for x in segs)
            h = set(norm(text, "de").split())
            ref = set(norm("hey wendelin " + it["text"], "de").split())
            r = rows.setdefault(scen, dict(n=0, ins=0, nonempty=0, wend=0, hit=0, all=0))
            r["n"] += 1; r["ins"] += int(bool((h & hot) - ref)); r["nonempty"] += int(bool(h)); r["wend"] += int("wendelin" in h)
            r["hit"] += sum(w in h for w in it["spoken"]); r["all"] += len(it["spoken"])
            hy.append(dict(s=scen, id=it["id"], hyp=text))
        out["rows"][label] = rows
        out["hyps"][label] = hy
        Path(a.out).write_text(json.dumps(out, ensure_ascii=False, indent=1))
        print(f"[hbw] {label} {time.perf_counter() - t0:.0f}s", file=sys.stderr, flush=True)
    print(hbw_markdown(out))


def hbw_markdown(out):
    def agg(rows, pred):
        ks = [k for k in rows if pred(k.split("/"))]
        n = sum(rows[k]["n"] for k in ks); i = sum(rows[k]["ins"] for k in ks)
        lo, hi = wilson(i, n)
        return f"{100 * i / max(n, 1):.0f}% ({i}/{n}; {100 * lo:.0f}-{100 * hi:.0f})"
    cols = [("Tipp-Pfad clean", lambda p: p[0] == "tip" and p[3] == "clean"),
            ("Tipp-Pfad noisy", lambda p: p[0] == "tip" and p[3] == "noisy"),
            ("Wake ohne Pause, Schnitt, clean", lambda p: p[0] == "np" and p[2] == "plain" and p[3] == "clean"),
            ("Wake ohne Pause, Schnitt, noisy", lambda p: p[0] == "np" and p[2] == "plain" and p[3] == "noisy"),
            ("Wake mit Pause, Schnitt, clean", lambda p: p[0] == "p" and p[2] == "plain" and p[3] == "clean"),
            ("Wake mit Pause, Schnitt, noisy", lambda p: p[0] == "p" and p[2] == "plain" and p[3] == "noisy"),
            ("Pause + Mute", lambda p: p[0] == "p" and p[2] == "mute"),
            ("Loch 600 ms (beide Pfade)", lambda p: p[2] == "hole")]
    L = ["| Konfiguration | " + " | ".join(c for c, _ in cols) + " |", "|---|" + "--:|" * len(cols)]
    for label, rows in out["rows"].items():
        L.append(f"| {label} | " + " | ".join(agg(rows, f) for _, f in cols) + " |")
    L += ["", "Je Schnittversatz (Wake mit Pause bzw. ohne Pause, plain, clean+noisy), nur hw300 s3.0 und beam:", "",
          "| Konfiguration | Pfad | -400 | -200 | 0 | +200 |", "|---|---|--:|--:|--:|--:|"]
    for label in ("beam", "hw300 s3.0"):
        if label in out["rows"]:
            for path in ("np", "p"):
                L.append(f"| {label} | {path} | " + " | ".join(
                    agg(out["rows"][label], lambda p, o=o, path=path: p[0] == path and p[1] == str(o) and p[2] == "plain") for o in WAKE_OFFSETS) + " |")
    L += ["", "Weckwort „Wendelin“ im Transkript erkannt (Wake mit Schnitt, plain, clean+noisy; Trefferrate je Schnittversatz):", "",
          "| Konfiguration | Pfad | -400 | -200 | 0 | +200 |", "|---|---|--:|--:|--:|--:|"]
    def wend(rows, pred):
        ks = [k for k in rows if pred(k.split("/"))]
        n = sum(rows[k]["n"] for k in ks); i = sum(rows[k]["wend"] for k in ks)
        lo, hi = wilson(i, n)
        return f"{100 * i / max(n, 1):.0f}% ({i}/{n}; {100 * lo:.0f}-{100 * hi:.0f})"
    for label, rows in out["rows"].items():
        for path in ("np", "p"):
            L.append(f"| {label} | {path} | " + " | ".join(
                wend(rows, lambda p, o=o, path=path: p[0] == path and p[1] == str(o) and p[2] == "plain") for o in WAKE_OFFSETS) + " |")
    return "\n".join(L)


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
    h = sub.add_parser("hotword-bias")
    h.add_argument("--models", required=True)
    h.add_argument("--bpe-vocab", required=True)
    h.add_argument("--threads", type=int, default=4)
    h.add_argument("--cache", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "wp146-hb"))
    h.add_argument("--out", default="hotword-bias.json")
    w = sub.add_parser("hotword-bias-wake")
    w.add_argument("--models", required=True)
    w.add_argument("--bpe-vocab", required=True)
    w.add_argument("--threads", type=int, default=4)
    w.add_argument("--cache", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "wp146-hb"))
    w.add_argument("--out", default="hotword-bias-wake.json")
    w.add_argument("--counts", default="0,50,300", help="Anzahl erfundener Kontakte, kommagetrennt")
    w.add_argument("--scores", default="1.5,3.0", help="Hotword-Boni, kommagetrennt")
    t = sub.add_parser("table")
    t.add_argument("--stt"); t.add_argument("--tts")
    a = ap.parse_args()
    {"stt": cmd_stt, "stt-one": cmd_stt_one, "tts": cmd_tts, "tts-one": cmd_tts_one, "table": cmd_table, "hotword-bias": cmd_hotword_bias, "hotword-bias-wake": cmd_hotword_bias_wake}[a.cmd](a)


if __name__ == "__main__":
    main()
