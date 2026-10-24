#!/usr/bin/env python3
"""WP137: Export von Prüfer B für den Dart-Nachbau (WP143). Ohne echte Vorlagen (echte Stimme).

Liest <models>/<tag>/b_templates.npz (nur mu) und verifier.json (Ausschnitt, TOPK, Schwellen) und schreibt
  <out>/wake_verifier_b_mu.json     mu (96) mit Feature-Version und Ausschnitt
  <out>/verifier_b_parity.json      SYNTHETISCHE Embeddings, Vorlagen und erwartete b_score je Kopf (aus verifier_eval.b_score)
  <out>/verifier_b_chain_parity.json  Kettenfall: Signale -> Zuschnitt -> echte oww-Embeddings -> Kopfwerte (nur mit lokalen oww-Modellen)
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


def _r(a, dec=DECIMALS): return np.round(np.asarray(a, "float32"), dec).astype("float32")


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
                     "template": "a = trunc((start - 0.12)*16000), b = trunc((ende + 0.20)*16000) in double, begrenzt auf [0, len]; trim -40 dB (160er Frames, Rand 800); Annahme, wenn die oww-Kette mindestens 2 Embedding-Frames liefert (Clip ab 13920 Samples = 0,87 s; verifier_eval.build_templates len(e) >= 2; real_split.cut_clips selbst nimmt ab 4000 Samples, Vorlagen darunter kommen nie in den Pruefer)",
                     "frames": "k = n//160; M = k - 3; F = (M - 76)//8 + 1; M < 76: ungueltig"},
            "oww_frames_checked": [{"samples": n, "F": f} for n, f in OWW_CHECKED],
            "live": live_cases(), "template": template_cases()}


# ---------- Kettenfall: Signal -> Zuschnitt -> normalize -> echte oww-Embeddings -> Kopfwerte ----------
CHAIN_LIVE_N, CHAIN_LIVE_END = 64000, 40000                       # 4 s, Entscheidungsende 2,5 s -> Ausschnitt 44000 Samples, F = 25
CHAIN_ENROLL_N = 96000                                             # Einlern-Signal 6 s
CHAIN_WORDS = ((0.5, 1.4, 37), (2.2, 3.2, 53), (4.0, 4.9, 71))      # Start/Ende (s) und Schrittweite der 3 Vorlagen-Clips
CHAIN_BG = 0.001
CHAIN_HEADS = {"W": [0, 1, 2], "HW": [1, 2]}                       # Vorlagen je Kopf (Index in CHAIN_WORDS): getrennt, HW nutzt nur 2 Vorlagen (Top-k mit weniger als k)
CHAIN_TOL = {"embeddings": 1e-3, "scores": 1e-4}
CHAIN_FORMULA = ("Live: x[i] = 0.4 * ((i*37 % 2001) - 1000) / 2000, i < 64000; Ausschnitt verifier_data.segment(x, 40000/16000), normalize (Spitze 0,5), "
                 "Embeddings F x 96. Einlernen: y[i] = ((i*k % 2001) - 1000) / 2000 * (0.4 im Wort [int(start*16000), int(ende*16000)) mit Schritt k = 37, 53, 71 je Wort, sonst 0.001 mit k = 37), i < 96000; "
                 "Clips real_split.cut_clips (a = int((start - 0.12)*16000), b = int((ende + 0.20)*16000), trim -40 dB), normalize, Embeddings m x 96. "
                 "Embeddings: openWakeWord-Kette (Melspec + Embedding, Vielfache von 160 Samples, int16), Werte auf 6 Stellen")


def chain_enroll_signal(n=CHAIN_ENROLL_N, words=CHAIN_WORDS, bg=CHAIN_BG):
    idx = np.arange(n)
    x, amp = ((idx * 37) % 2001 - 1000) / 2000, np.full(n, bg)
    for s, e, k in words:
        m = (idx >= int(s * SR)) & (idx < int(e * SR)); x[m] = ((idx[m] * k) % 2001 - 1000) / 2000; amp[m] = 0.4
    return (x * amp).astype("float32")


def chain_parity(mu, meta, oww):
    """Erwartete Embedding-Folgen aus der echten Messkette und Kopfwerte. mu: exportiertes (gerundetes) mu."""
    import common as CM
    af = CM.make_features(oww)
    mu = np.asarray(mu, "float32")
    live = live_signal(CHAIN_LIVE_N)
    seg = D.normalize(D.segment(live, CHAIN_LIVE_END / SR))
    q = _r(CM.embed(af, [seg])[0], 6)
    enroll = chain_enroll_signal()
    rows = [{"geraet": R.TRAIN_DEVICE, "block": "1", "runde": "1", "wort": "Wendelin", "status": "ok", "start": str(s), "ende": str(e)} for s, e, _ in CHAIN_WORDS]
    clips = [R.cut_clips([r], enroll) for r in rows]
    assert all(len(c) == 1 for c in clips), "Vorlagen-Clip abgelehnt"
    clips = [c[0][1] for c in clips]
    tmpl = [_r(CM.embed(af, [D.normalize(c)])[0], 6) for c in clips]
    assert len(q) == oww_frames(len(seg)) and all(len(t) == oww_frames(len(c)) >= 2 for t, c in zip(tmpl, clips))
    heads = {h: chain_scores(q, [tmpl[i] for i in idx], mu, int(meta["topk"])) for h, idx in CHAIN_HEADS.items()}
    return {"name": "verifier_b_chain_parity", "feature_version": FEATURE_VERSION, "dims": DIMS, "synthetic": True,
            "formula": CHAIN_FORMULA, "tolerance": CHAIN_TOL, "topk": int(meta["topk"]),
            "live": {"signal_len": CHAIN_LIVE_N, "decision_end_sample": CHAIN_LIVE_END, "segment_len": len(seg), "frames_F": len(q), "embeddings": _lst6(q)},
            "templates": [{"start_s": s, "end_s": e, "step": k, "clip_len": len(c), "frames_m": len(t), "embeddings": _lst6(t)}
                          for (s, e, k), c, t in zip(CHAIN_WORDS, clips, tmpl)],
            "heads": {h: {"templates": CHAIN_HEADS[h], **v} for h, v in heads.items()}}


def chain_scores(q, tl, mu, topk):
    """Score je Vorlage (E.b_score mit einer Vorlage, ohne Top-k-Mittel) und Kopfwert, gerechnet aus den gespeicherten (gerundeten) Embeddings."""
    q = np.asarray(q, "float32")[None]
    per = [round(float(E.b_score(q, E.prep_templates([np.asarray(t, "float32")], mu), mu, topk=1)[0]), 6) for t in tl]
    return {"template_scores": per, "head_score": round(float(E.b_score(q, E.prep_templates([np.asarray(t, "float32") for t in tl], mu), mu, topk=topk)[0]), 6)}


def _lst6(a): return np.round(np.asarray(a, "float64"), 6).tolist()


def export(models, tag, out, oww=D.OWW_DIR):
    d = os.path.join(models, tag)
    meta = json.load(open(os.path.join(d, "verifier.json")))
    meta = {"pre": meta["pre"], "tail": meta["tail"], "topk": meta["topk"], "thresholds": meta["thresholds"]}
    mu = np.load(os.path.join(d, "b_templates.npz"))["mu"]          # nur mu lesen, Vorlagen bleiben lokal
    os.makedirs(out, exist_ok=True)
    mj = mu_json(mu, meta)
    mu = np.array(mj["mu"], "float32")                               # die Paritaet rechnet mit dem exportierten (gerundeten) mu, wie die App
    for name, obj in (("wake_verifier_b_mu.json", mj), ("verifier_b_parity.json", parity(mu, meta))):
        with open(os.path.join(out, name), "w") as f: json.dump(obj, f, separators=(",", ":") if "parity" in name else None, indent=None if "parity" in name else 1); f.write("\n")
    if oww and os.path.isfile(os.path.join(oww, "embedding_model.onnx")):
        with open(os.path.join(out, "verifier_b_chain_parity.json"), "w") as f:
            json.dump(chain_parity(mu, meta, oww), f, separators=(",", ":")); f.write("\n")
    else:
        print("oww-Modelle fehlen: verifier_b_chain_parity.json nicht erzeugt", file=sys.stderr)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", required=True); ap.add_argument("--tag", required=True)
    ap.add_argument("--out", default=os.path.join(HERE, "testdata"))
    a = ap.parse_args(); export(a.models, a.tag, a.out)
