#!/usr/bin/env python3
"""WP129 kleine Messung Stufe 2 mit Whisper (App-Regel) auf Band-Ereignissen des Pruef-Splits.

Aufbau: Band-Ereignisse aus den Stufe-1-Kurven von v8a (Cache wp130/results/s1) mit dem Katalogband des Handys (0,98 bis 0,999)
und dem Spitzenwert-Halten der Engine (hoechstens 5 Fenster, Ende nach 2 Fenstern unter der Spitze); Ausschnitt wie die App:
2,0 s vor und 0,9 s nach dem Ende des Haltens, optional auf Spitze 0,5 normalisiert (Mindestspitze 164, wie `normalizePeak`).
Quellen: echte Rufe (Labels Pruef-Split, Ereignis im Label-Fenster), Negativ-Aufnahmen Huawei/Handy 2, Verwechsler-Clips (macOS-Stimmen).
Pruefregel: `matchesWakeWord` (maxDistance 2) auf dem Whisper-Text (`TranscriptWakeVerifier`), Sprache de, ohne Prompt/Hotwords.
Whisper: sherpa-onnx, int8, Modelle `~/wendelin-models/whisper-<base|small>`. Last: Aufruf mit nice, hoechstens 2 Threads.
Ausgabe nur Zaehlungen und Laufzeiten; Texte stehen nur im Cache (--cache, lokal, nie im Repo), nie in der Ausgabe ausser als Kategorie.

  nice -n 10 ~/wendelin-models/kws/wp58/venv/bin/python -I tool/wake_stage2_whisper.py --cache <ordner> [--models base small] [--list]
"""
import argparse, collections, json, math, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "train_wake_word")); sys.path.insert(0, HERE)
import numpy as np
import words_measure as W
import v8_measure as V
import kws_measure as K

SR = 16000
LO, HI = 0.98, 0.999
HOLD, DROPS = 5, 2
PRE, TAIL = 2.0, 0.9
PEAK, MINPEAK = 0.5, 164
MODELS = os.path.expanduser("~/wendelin-models")
CACHE_V8A = f"{V.RES}/s1/v8a-bfeb939d"
EXTRA_LO = 0.9
LOCK = 1.5                                       # s Sperre nach einem Ereignis (wie words_measure)


def engine_events(t, v, LO=LO):
    """[(Ende des Haltens in s, Spitze)] wie CandidateWakeEngine: ab erstem Fenster >= LO halten (HOLD Fenster oder DROPS in Folge unter der Spitze)."""
    out, i, last = [], 0, -1e9
    n = len(v)
    while i < n:
        if v[i] >= LO and t[i] - last >= LOCK:
            peak, k, below, j = v[i], 1, 0, i
            if peak < HI:
                while k < HOLD and j + 1 < n:
                    j += 1; k += 1
                    if v[j] > peak: peak, below = v[j], 0
                    else:
                        below += 1
                        if below >= DROPS: break
                    if peak >= HI: break
            out.append((float(t[j]), float(peak)))
            last = t[j]; i = j + 1
        else:
            i += 1
    return out


def clip(x, t_end):
    e = int(round(t_end * SR))
    return x[max(0, e - int(PRE * SR)): e + int(TAIL * SR)]


def norm16(x):
    """x float32 in [-1,1]; wie normalizePeak (Int16)."""
    pk = float(np.abs(x).max()) * 32768 if len(x) else 0.0
    if pk < MINPEAK: return x
    return np.clip(x * (PEAK * 32768 / pk), -1.0, 32767 / 32768).astype("float32")


def collect(curves):
    """[(quelle, name, t_end, spitze, label_id|None)] nur Band-Ereignisse (Spitze < HI)."""
    labels = [lb for lb in V.filter_labels(W.read_labels())]
    items = []
    for src in ("pos_huawei", "pos_handy2"):
        dev = src[4:]
        t, v = curves[src][src]
        for te, pk in engine_events(t, v):
            if pk >= HI: continue
            hit = [i for i, lb in enumerate(labels) if lb["dev"] == dev and
                   (lambda w: w[0] <= te <= w[1])(W.label_window(lb["start"], lb["end"], lb["status"]))]
            if hit: items.append((src, src, te, pk, f"{dev}:{hit[0]}"))
    for src in ("neg_huawei", "neg_handy2"):
        t, v = curves[src][src]
        items += [(src, src, te, pk, None) for te, pk in engine_events(t, v) if pk < HI]
    for name, (t, v) in sorted(curves["conf"].items()):
        items += [("conf", name, te, pk, None) for te, pk in engine_events(t, v) if pk < HI]
    # Zusatz: Ereignisse knapp unter dem Band (EXTRA_LO bis LO), nur Negativ und Verwechsler: mehr Stichprobe fuer „lehnt Whisper Nicht-Rufe ab“
    for src in ("neg_huawei", "neg_handy2"):
        t, v = curves[src][src]
        items += [("unter_" + src, src, te, pk, None) for te, pk in engine_events(t, v, EXTRA_LO) if pk < LO]
    for name, (t, v) in sorted(curves["conf"].items()):
        items += [("unter_conf", name, te, pk, None) for te, pk in engine_events(t, v, EXTRA_LO) if pk < LO]
    return items, labels


def wilson(k, n, z=1.96):
    if n == 0: return (0.0, 0.0)
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (c - h, c + h)


def fmt(k, n):
    lo, hi = wilson(k, n)
    return f"{k}/{n} ({100 * max(lo, 0):.0f}-{100 * hi:.0f} %)"


def make_rec(model, threads=2):
    import sherpa_onnx as so
    d = f"{MODELS}/whisper-{model}"
    return so.OfflineRecognizer.from_whisper(encoder=f"{d}/{model}-encoder.int8.onnx", decoder=f"{d}/{model}-decoder.int8.onnx",
                                             tokens=f"{d}/{model}-tokens.txt", language="de", num_threads=threads)


def transcribe(rec, x):
    s = rec.create_stream(); s.accept_waveform(SR, x.astype("float32")); rec.decode_stream(s)
    return s.result.text


def category(text):
    if not text.strip(): return "leer"
    if K.matches_wake_word(text, 2): return "bestaetigt"
    return "anderes Wort"


def report_clips(peaks):
    """Plausibilitaet des Ausschnitts: Spitze (Vollausschlag 1) und Laenge je Gruppe; Spitze > 0,5 wird durch die Normalisierung leiser."""
    for g in sorted({p[0] for p in peaks}):
        pk = [p[1] for p in peaks if p[0] == g]; ln = [p[2] for p in peaks if p[0] == g]
        print(f"Ausschnitt {g}: n={len(pk)}, Spitze Median {np.median(pk):.2f} (min {min(pk):.3f}, max {max(pk):.2f}), "
              f"{sum(x > PEAK for x in pk)} ueber 0,5 (wuerden leiser), Laenge Median {np.median(ln):.2f} s")


def bins(curves, labels):
    """Ereignisse (Engine-Halten, Sperre) je Spitzen-Grenze: echte Rufe (je Label hoechstens einmal), Negativ (je Stunde), Verwechsler-Clips mit Ereignis."""
    hrs = {s: V.hours(s) for s in ("neg_huawei", "neg_handy2")}
    global LO
    print("Grenze | echte Rufe (von %d Labels) | Negativ Ereignisse (FA/h, %.2f h) | Verwechsler-Clips mit Ereignis (von %d)" %
          (len(labels), sum(hrs.values()), len(curves["conf"])))
    for thr in (0.90, 0.95, 0.97, 0.98, 0.99, 0.995, 0.999):
        LO = thr
        calls = set()
        for src in ("pos_huawei", "pos_handy2"):
            dev = src[4:]; t, v = curves[src][src]
            for te, pk in engine_events(t, v, thr):
                for i, lb in enumerate(labels):
                    w = W.label_window(lb["start"], lb["end"], lb["status"])
                    if lb["dev"] == dev and w[0] <= te <= w[1]: calls.add((dev, i))
        neg = sum(len(engine_events(*curves[s][s], thr)) for s in hrs)
        conf = sum(1 for _, (t, v) in curves["conf"].items() if engine_events(t, v, thr))
        print(f"{thr} | {len(calls)} | {neg} ({neg / sum(hrs.values()):.1f}/h) | {conf}")
    LO = 0.98


def pct(a, q): return float(np.percentile(a, q)) if len(a) else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", required=True); ap.add_argument("--models", nargs="*", default=["base", "small"])
    ap.add_argument("--list", action="store_true"); ap.add_argument("--bins", action="store_true"); ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--max-conf", type=int, default=0, help="hoechstens so viele Verwechsler-Ereignisse (0 = alle)")
    a = ap.parse_args()
    os.makedirs(a.cache, exist_ok=True)
    V.CACHE_TAG["v8a"] = "v8a-bfeb939d"
    curves = V.load_curves("v8a")
    items, labels = collect(curves)
    if a.max_conf:
        keep, c = [], 0
        for it in items:
            if it[0] in ("conf", "unter_conf"):
                c += 1
                if c > a.max_conf: continue
            keep.append(it)
        items = keep
    by = collections.Counter(it[0] for it in items)
    if a.bins: bins(curves, labels); return
    print("Band-Ereignisse je Quelle:", dict(by), "Labels mit Ereignis:", len({it[4] for it in items if it[4]}), "von", len(labels))
    if a.list: return
    audio = {}
    for model in a.models:
        rec = make_rec(model, a.threads)
        tx = {}
        for norm in (False, True):
            texts, times = [], []
            if not norm: peaks = []
            for src, name, te, pk, lab in items:
                rs = src.removeprefix("unter_")
                if (rs, name) not in audio: audio[(rs, name)] = V.load_item(rs, name)
                x = clip(audio[(rs, name)], te)
                if not norm: peaks.append((src, float(np.abs(x).max()) if len(x) else 0.0, len(x) / SR))
                x = norm16(x) if norm else x
                t0 = time.perf_counter(); txt = transcribe(rec, x); times.append(time.perf_counter() - t0)
                texts.append(txt)
            tx[norm] = (texts, times)
            json.dump(texts, open(f"{a.cache}/{model}_{'norm' if norm else 'raw'}.json", "w"))
            report(model, norm, items, texts, times)
            if not norm and model == a.models[0]: report_clips(peaks)
        del rec


def report(model, norm, items, texts, times):
    tag = f"{model} {'norm' if norm else 'roh '}"
    rows = {}
    for (src, name, te, pk, lab), txt in zip(items, texts):
        grp = "echt" if src.startswith("pos_") else ("verwechsler" if src == "conf" else src)
        if src.startswith("unter_"): grp = src
        rows.setdefault(grp, []).append((category(txt), lab, txt))
    for grp, rs in rows.items():
        ok = sum(r[0] == "bestaetigt" for r in rs)
        extra = ""
        if grp == "echt":
            labs = {}
            for c, lab, _ in rs: labs[lab] = labs.get(lab, False) or c == "bestaetigt"
            extra = f"; je Ruf (>=1 bestaetigt) {fmt(sum(labs.values()), len(labs))}"
        cats = collections.Counter(r[0] for r in rs)
        print(f"{tag} {grp}: bestaetigt {fmt(ok, len(rs))}{extra}; Kategorien {dict(cats)}")
        if grp != "echt" or True:
            rej = collections.Counter(r[2].strip().lower()[:30] for r in rs if r[0] != "bestaetigt")
            if grp == "verwechsler" or grp.startswith("neg"):
                pass
    print(f"{tag} Laufzeit je Pruefung (Mac, Threads s.o.): Median {pct(times, 50) * 1000:.0f} ms, p95 {pct(times, 95) * 1000:.0f} ms, n={len(times)}")


if __name__ == "__main__":
    main()
