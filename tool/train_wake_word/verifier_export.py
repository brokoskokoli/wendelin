#!/usr/bin/env python3
"""WP137: Export von Prüfer B für den Dart-Nachbau (WP143). Ohne echte Vorlagen (echte Stimme).

Liest <models>/<tag>/b_templates.npz (nur mu) und verifier.json (Ausschnitt, TOPK, Schwellen) und schreibt
  <out>/wake_verifier_b_mu.json     mu (96) mit Feature-Version und Ausschnitt
  <out>/verifier_b_parity.json      SYNTHETISCHE Embeddings, Vorlagen und erwartete b_score je Kopf (aus verifier_eval.b_score)
Aufruf: python verifier_export.py --models <ordner> --tag ca1 [--out tool/train_wake_word/testdata]
Selbsttest: test_verifier_export.py."""
import argparse, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np
import verifier_data as D
import verifier_eval as E
import real_split as R

FEATURE_VERSION = "oww-0.5.1-mel-emb-1"
DIMS = 96
SEED = 137
DECIMALS = 4            # Eingaben auf 4 Stellen gerundet gespeichert, erwartete Werte aus den gerundeten Eingaben
SOURCE = ("Mittelwert aller Embedding-Frames der Trainings-Negativ-Ausschnitte von Pruefer B "
          "(Verwechsler aus dem Stimmenset clean, Mining und Fuellmaterial aus synthetischen Negativen und FLEURS train/dev); "
          "keine Pruef- oder Einlern-Daten, keine Vorlagen")


def mu_json(mu, meta):
    mu = np.asarray(mu, "float32")
    if mu.shape != (DIMS,): raise SystemExit(f"mu hat Form {mu.shape}, erwartet ({DIMS},)")
    return {"name": "wake_verifier_b_mu", "feature_version": FEATURE_VERSION, "dims": DIMS, "source": SOURCE,
            "cut": {"pre_s": float(meta["pre"]), "tail_s": float(meta["tail"]), "norm_peak": 0.5},
            "mu": [round(float(v), 7) for v in mu]}


def _r(a): return np.round(np.asarray(a, "float32"), DECIMALS).astype("float32")


def _lst(a): return np.round(np.asarray(a, "float64"), DECIMALS).tolist()      # kurze Dezimalzahlen (float32.tolist() waere lang)


def parity(mu, meta, seed=SEED):
    """4 Ausschnitte (F=25) und 3 Vorlagen je Kopf (m=2..6), dazu ein kurzer Ausschnitt (F=4), bei dem lange Vorlagen ignoriert werden,
    und ein Kopf nur mit zu langen Vorlagen (Wert -1). Alles synthetisch (Rauschen um mu, eine Vorlage eingebettet)."""
    rng = np.random.default_rng(seed)
    mu = np.asarray(mu, "float32")
    scale = 8.0

    def rnd(*shape): return _r(mu + rng.standard_normal(shape) * scale)

    heads = {"W": [rnd(2, DIMS)[0:2], rnd(4, DIMS), rnd(6, DIMS)], "HW": [rnd(3, DIMS), rnd(5, DIMS), rnd(6, DIMS)]}
    q25 = rnd(4, 25, DIMS)
    q25[0, 6:10] = _r(heads["W"][1] + rng.standard_normal((4, DIMS)) * 1.0)      # Treffer W mit Versatz
    q25[1, 12:17] = _r(heads["HW"][1] + rng.standard_normal((5, DIMS)) * 1.0)    # Treffer HW
    q4 = rnd(2, 4, DIMS)
    cases = [
        {"name": "f25", "queries": q25, "heads": heads},
        {"name": "f4_lange_vorlagen_ignoriert", "queries": q4, "heads": heads},
        {"name": "nur_zu_lange_vorlagen", "queries": q4, "heads": {"W": [rnd(5, DIMS), rnd(6, DIMS)]}},
    ]
    out = []
    for c in cases:
        exp = {}
        for h, tl in c["heads"].items():
            t = E.prep_templates([np.asarray(x, "float32") for x in tl], mu)
            exp[h] = [round(float(v), 6) for v in E.b_score(c["queries"], t, mu, topk=int(meta["topk"]))]
        out.append({"name": c["name"], "queries": _lst(c["queries"]),
                    "templates": {h: [_lst(x) for x in tl] for h, tl in c["heads"].items()}, "expected": exp})
    return {"name": "verifier_b_parity", "feature_version": FEATURE_VERSION, "dims": DIMS, "seed": seed, "synthetic": True,
            "topk": int(meta["topk"]), "tolerance": 1e-4,
            "pcm": pcm_cases(),
            "rule": "emb-mu, Einheitsnorm je Frame, Kosinus je Frame-Paar, Mittel ueber Vorlagenlaenge, Max ueber Versatz, Top-k-Mittel ueber Vorlagen; Vorlage laenger als F ignoriert; keine Vorlage -> -1",
            "thresholds_trainingsseite": {"W": meta["thresholds"]["B"]["W"], "HW": meta["thresholds"]["B"]["HW"]},
            "cases": out}


# ---------- PCM-Zuschnitt (ohne Embeddings): sample-genaue Grenzen und Frame-Anzahl ----------
SR = D.SR
HOP = 160                                   # 10 ms
WIN_MEL, STRIDE_MEL, MEL_LAG = 76, 8, 3     # Embedding-Fenster in Melspec-Frames, Schritt, Melspec-Frames = n//160 - 3 (an oww gemessen)
# an echtem oww (Melspec+Embedding, Python-Kette CM.embed) gemessene Paare (Samples -> F), Teil der Paritaet
OWW_CHECKED = [(16000, 3), (16480, 4), (17760, 5), (19040, 6), (24000, 9), (32000, 16), (40000, 22), (44000, 25), (44160, 25)]


def zig(i): return ((i * 37) % 2001 - 1000) / 2000            # deterministisches Testsignal in [-0,5; 0,5], in Dart leicht nachbaubar


def live_signal(n): return (0.4 * np.array([zig(i) for i in range(n)])).astype("float32")      # Spitze 0,2


def oww_frames(n):
    """F nach der oww-Kette fuer n Samples: auf Vielfache von 160 gekuerzt, Melspec-Frames M = n//160 - 3, F = (M - 76)//8 + 1; M < 76: Python wirft (None)."""
    m = n // HOP - MEL_LAG
    return None if m < WIN_MEL else (m - WIN_MEL) // STRIDE_MEL + 1


def segment_bounds(sig_len, end_sample, pre=D.PRE, tail=D.TAIL):
    """Wie verifier_data.segment: e = round(end/160)*160 (Python round = Halbe zur geraden Zahl!), a = e - round(pre*SR), b = e + round(tail*SR);
    kopiert wird [max(a,0), min(b,len)) nach Position max(a,0)-a, Rest Nullen."""
    e = int(round(end_sample / HOP)) * HOP
    a, b = e - int(round(pre * SR)), e + int(round(tail * SR))
    lo, hi = max(a, 0), min(b, sig_len)
    return {"e": e, "a": a, "b": b, "seg_len": b - a, "copy_lo": lo, "copy_hi": max(hi, lo), "zeros_front": lo - a, "zeros_back": b - a - (max(hi, lo) - a)}


def live_cases():
    out = []
    for name, n, end in (("mitte", 160000, 80000), ("rand_anfang", 160000, 20000), ("rand_ende", 160000, 158000),
                         ("halbe_abgerundet", 160000, 80080), ("halbe_aufgerundet", 160000, 80240)):
        x = live_signal(n)
        d = segment_bounds(n, end)
        seg = D.segment(x, end / SR)                      # Referenz aus dem echten Code
        assert len(seg) == d["seg_len"]
        pk = float(np.abs(seg).max())
        nrm = D.normalize(seg)
        out.append({"name": name, "signal": {"len": n, "sr": SR, "formula": "x[i] = 0.4 * ((i*37 % 2001) - 1000) / 2000"},
                    "decision_end_sample": end, **d, "peak_in": round(pk, 6), "peak_out": round(float(np.abs(nrm).max()), 6),
                    "used_samples": d["seg_len"] // HOP * HOP, "frames_F": oww_frames(d["seg_len"])})
    return out


def trim_bounds(x, db=-40.0, pad=0.05):
    """Grenzen von real_split.trim als (lo, hi) in x; ohne Treffer oder x kuerzer als 160: ganz."""
    n = len(x) // HOP
    if n == 0: return 0, len(x)
    rms = np.sqrt((x[: n * HOP].reshape(n, HOP) ** 2).mean(axis=1) + 1e-12)
    idx = np.where(20 * np.log10(rms / (rms.max() + 1e-9) + 1e-12) > db)[0]
    if len(idx) == 0: return 0, len(x)
    return int(max(0, idx[0] * HOP - int(pad * SR))), int(min(len(x), (idx[-1] + 1) * HOP + int(pad * SR)))


def template_signal(n, start, end, bg=0.001):
    """Wort (Spitze 0,2) in [int(start*SR), int(end*SR)), sonst Hintergrund mit Spitze 0,0005 (-52 dB)."""
    x = np.array([zig(i) for i in range(n)]); w0, w1 = int(start * SR), int(end * SR)
    amp = np.where((np.arange(n) >= w0) & (np.arange(n) < w1), 0.4, bg)
    return (x * amp).astype("float32")


def template_cut(n, start, end, bg=0.001):
    """Zuschnitt exakt wie real_split.cut_clips: a = int((start - PRE)*SR), b = int((ende + POST)*SR) (Gleitkomma, Abschneiden), dann trim -40 dB Rand 50 ms."""
    x = template_signal(n, start, end, bg)
    a, b = max(0, int((start - R.PRE) * SR)), min(n, int((end + R.POST) * SR))
    lo, hi = trim_bounds(x[a:b])
    row = {"geraet": R.TRAIN_DEVICE, "block": "1", "runde": "1", "wort": "Wendelin", "status": "ok", "start": str(start), "ende": str(end)}
    ref = R.cut_clips([row], x)                           # Referenz aus dem echten Code
    c = ref[0][1] if ref else None
    res = {"signal": {"len": n, "sr": SR, "formula": "x[i] = ((i*37 % 2001) - 1000) / 2000 * (0.4 im Wort [int(start*SR), int(ende*SR)), sonst bg)", "bg": bg},
           "start_s": start, "end_s": end, "label_a": a, "label_b": b, "trim_lo": lo, "trim_hi": hi,
           "clip_a": a + lo, "clip_b": a + hi, "clip_len": hi - lo, "accepted": c is not None and len(c) >= SR // 4}
    if c is not None:
        assert len(c) == hi - lo
        res["peak_in"] = round(float(np.abs(c).max()), 6); res["peak_out"] = round(float(np.abs(D.normalize(c)).max()), 6)
        k = len(c) // HOP
        res["used_samples"] = k * HOP
        res["m"] = oww_frames(len(c))                      # None: Python wirft (< 76 Melspec-Frames); App lehnt die Vorlage ab; m < 2 wird verworfen
    return res


def template_cases():
    out = []
    for name, start, end, bg in (("normal", 1.0, 1.9, 0.001), ("rundung_start", 1.13, 2.03, 0.001), ("rundung_ende", 0.23, 1.13, 0.001),
                                 ("rand_anfang", 0.05, 0.95, 0.001), ("trim_greift_nicht", 1.0, 1.9, 0.4), ("zu_kurz", 1.0, 1.2, 0.001)):
        out.append({"name": name, **template_cut(48000, start, end, bg)})
    return out


def pcm_cases():
    return {"rule": {"segment": "e = pythonRound(end/160)*160 (Halbe -> gerade Zahl); a = e - 30400; b = e + 13600; Rand mit Nullen; Spitze auf 0,5 (nur wenn max > 1e-6)",
                     "template": "a = trunc((start - 0.12)*16000), b = trunc((ende + 0.20)*16000) in double, begrenzt auf [0, len]; trim -40 dB (160er Frames, Rand 800); Annahme nur bei Laenge >= 4000",
                     "frames": "k = n//160; M = k - 3; F = (M - 76)//8 + 1; M < 76: ungueltig"},
            "oww_frames_checked": [{"samples": n, "F": f} for n, f in OWW_CHECKED],
            "live": live_cases(), "template": template_cases()}


def export(models, tag, out):
    d = os.path.join(models, tag)
    meta = json.load(open(os.path.join(d, "verifier.json")))
    meta = {"pre": meta["pre"], "tail": meta["tail"], "topk": meta["topk"], "thresholds": meta["thresholds"]}
    mu = np.load(os.path.join(d, "b_templates.npz"))["mu"]          # nur mu lesen, Vorlagen bleiben lokal
    os.makedirs(out, exist_ok=True)
    mj = mu_json(mu, meta)
    mu = np.array(mj["mu"], "float32")                               # die Paritaet rechnet mit dem exportierten (gerundeten) mu, wie die App
    for name, obj in (("wake_verifier_b_mu.json", mj), ("verifier_b_parity.json", parity(mu, meta))):
        with open(os.path.join(out, name), "w") as f: json.dump(obj, f, separators=(",", ":") if "parity" in name else None, indent=None if "parity" in name else 1); f.write("\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", required=True); ap.add_argument("--tag", required=True)
    ap.add_argument("--out", default=os.path.join(HERE, "testdata"))
    a = ap.parse_args(); export(a.models, a.tag, a.out)
