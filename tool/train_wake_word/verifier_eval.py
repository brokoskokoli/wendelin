#!/usr/bin/env python3
"""WP137 Teil 2, Prüfer B (Vorlagen-Vergleich zentriert), C (Fusion) und Vergleich gegen hw2 auf dem Prüf-Split.

B: Vorlagen = echte Huawei-Rufe Block 1 bis 3 (je Wort 5 bis 8, gleichmäßig über die Sortierung, ohne Stille-Polster, Spitze 0,5), als Embedding-Folge (m x 96).
   Zentrieren: Mittelwert mu aller Embedding-Frames der TRAININGS-Negativ-Ausschnitte (Verwechsler, Mining, Füllmaterial; nie Prüfdaten); Kosinus der zentrierten Frames,
   je Vorlage das Maximum über den Zeitversatz im Ausschnitt (Mittel über die Vorlagenlänge), Wert = Mittel der besten TOPK Vorlagen. Kopf W: Vorlagen „bare“, Kopf HW: „hey“.
   Auf der Trainingsseite wird ein echter Beispiel-Block aus den Vorlagen herausgelassen (Leave-Block-Out). Kein Training.
C: logistische Regression je Kopf auf (logit Spitzenwert Stufe 1, logit A, B) im Band; Gewichte und Schwelle aus out-of-fold-Werten der Trainingsseite (Faltung nach group).
Schwelle: dieselbe Regel wie A (niedrigste Schwelle mit Verwerfung >= REJECT_MIN der OOF-Negativen im Band).
Vergleich (run): Stufe 1 fest 0,98, Band [0,98; 0,999) wird geprüft (hw2 bzw. A/B/C), ab 0,999 direkt angenommen; Schwellen nur aus der Trainingsseite. Verwechsler getrennt nach
Text-Split (Test 30 % = Vergleichszahl, Training 70 % = Überanpassung); leise Rufe (Wort-Pegel < -35 dBFS im Label-Ausschnitt) getrennt; FA/h mit Poisson-Obergrenze;
CPU-Zeit je Prüfung einthreadig (process_time) inkl. Melspec+Embedding. Ausgabe lokal: <VER>/verifier_table.md. Selbsttest: test_verifier_eval.py."""
import argparse, json, os, platform, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np
import verifier_data as D
import verifier_train as T

SR = D.SR
TOPK = 3
N_TEMPL = 6
QUIET_DB = -35.0
DIRECT = D.BAND[1]
HEADS = ("Wendelin", "Hey Wendelin")


def logit(p):
    p = np.clip(np.asarray(p, "float64"), 1e-6, 1 - 1e-6)
    return np.log(p / (1 - p))


# ---------- B ----------
def pick_templates(names, n=N_TEMPL):
    """Gleichmäßig über die sortierte Namensliste gewählte Vorlagen (deterministisch); weniger Clips als n: alle."""
    names = sorted(names)
    if len(names) <= n: return names
    return [names[int(round(i * (len(names) - 1) / (n - 1)))] for i in range(n)]


def center_mu(ex):
    """Mittelwert aller Embedding-Frames der Trainings-Negativ-Ausschnitte (Zentrieren für B)."""
    m = np.isin(ex.d["kind"], D.NEG_KINDS)
    if not m.any(): raise SystemExit("keine Trainings-Negative für den Mittelwert von B")
    return ex.d["emb"][m].astype("float32").mean(axis=(0, 1))


def _unit(a):
    return a / (np.linalg.norm(a, axis=-1, keepdims=True) + 1e-9)


def b_score(emb, templ, mu, topk=TOPK):
    """emb (N,F,96); templ: Liste (m,96) zentrierter, normierter Vorlagen -> (N,) Wert in [-1,1]; Vorlagen länger als F werden ignoriert (kein Wert -> -1)."""
    E = _unit(emb.astype("float32") - mu)
    out = np.full(len(E), -1.0, "float32")
    per = []
    for Tm in templ:
        m = len(Tm)
        if m > E.shape[1]: continue
        M = np.einsum("md,nfd->nmf", Tm, E)                                  # (N, m, F) Kosinus aller Frame-Paare
        per.append(np.stack([np.mean([M[:, i, o + i] for i in range(m)], axis=0) for o in range(E.shape[1] - m + 1)], 1).max(1))
    if not per: return out
    per = np.sort(np.stack(per, 1), axis=1)[:, ::-1]
    return per[:, :topk].mean(1).astype("float32")


def prep_templates(embs, mu):
    return [_unit(e.astype("float32") - mu) for e in embs]


class BStore:
    """Vorlagen je Kopf (bare/hey) mit Aufnahmeblock; Speicher/Laden als npz."""
    def __init__(self, mu, items): self.mu, self.items = mu, items       # items: [(wort, block, emb (m,96))]

    def templates(self, word, exclude_block=None):
        return prep_templates([e for w, b, e in self.items if w == word and b != exclude_block], self.mu)

    def scores(self, emb, blocks=None):
        """(N,2) Werte; blocks (N,) = auszulassender Block je Beispiel (0 = keiner)."""
        out = np.zeros((len(emb), 2), "float32")
        blocks = np.zeros(len(emb), int) if blocks is None else blocks
        for b in np.unique(blocks):
            sel = blocks == b
            for k, w in enumerate(("bare", "hey")):
                out[sel, k] = b_score(emb[sel], self.templates(w, int(b) if b else None), self.mu)
        return out

    def save(self, path):
        np.savez_compressed(path, mu=self.mu, words=np.array([w for w, _, _ in self.items]), blocks=np.array([b for _, b, _ in self.items]),
                            **{f"t{i}": e for i, (_, _, e) in enumerate(self.items)})

    @classmethod
    def load(cls, path):
        z = np.load(path)
        return cls(z["mu"], [(str(w), int(b), z[f"t{i}"]) for i, (w, b) in enumerate(zip(z["words"], z["blocks"]))])


def build_templates(clips, embed_one, mu):
    """clips {Name: Signal} (Trainings-Clips real_split) -> BStore. embed_one(x) -> (m,96) für den normalisierten, ungepolsterten Clip."""
    items = []
    for word, tag in (("bare", "_bare_"), ("hey", "_hey_")):
        for n in pick_templates([n for n in clips if tag in n]):
            e = embed_one(D.normalize(clips[n]))
            if len(e) >= 2: items.append((word, int(D.R.NAME_RE.match(n).group(2)), e))
    if not any(w == "bare" for w, _, _ in items) or not any(w == "hey" for w, _, _ in items): raise SystemExit("Vorlagen für ein Wort fehlen")
    return BStore(mu, items)


def train_blocks(ex):
    """Auszulassender Block je Trainings-Beispiel: echte Clips (group = Block-1) -> Block, sonst 0."""
    return np.where(ex.d["kind"] == D.KIND["pos_real"], ex.d["group"] % 3 + 1, 0)


# ---------- C ----------
def fuse_features(peak, a, b):
    return np.stack([logit(peak), logit(a), np.asarray(b, "float64")], 1)


def lr_fit(F, y, w=None, iters=400, lr=0.5, l2=1e-3):
    """Logistische Regression (Gradientenabstieg, klassenausgeglichen) -> (coef (d,), intercept). Merkmale werden mit festen Skalen geteilt (logit /5)."""
    s = np.array([5.0, 5.0, 1.0])
    X = F / s
    w = np.ones(len(y)) if w is None else w
    w = w * np.where(y == 1, 0.5 / max((y == 1).sum(), 1), 0.5 / max((y == 0).sum(), 1)) * len(y)
    c, b = np.zeros(X.shape[1]), 0.0
    for _ in range(iters):
        p = 1 / (1 + np.exp(-(X @ c + b)))
        g = (p - y) * w
        c -= lr * (X.T @ g / len(y) + l2 * c); b -= lr * g.mean()
    return c / s, float(b)


def lr_apply(coef, b, F):
    return 1 / (1 + np.exp(-(F @ np.asarray(coef) + b)))


def fit_fusion(ex, a_oof, b_sc, reject_min=T.REJECT_MIN, folds=3):
    """Je Kopf: OOF-Fusion (Gewichte aus den übrigen Gruppen), daraus Schwelle; Endgewichte auf allem im Band. -> {W|HW: {coef, intercept, thr, accept, reject}}."""
    out = {}
    g = ex.d["group"]
    for k, nm in enumerate(("W", "HW")):
        pos, neg = T.band_masks(ex, k)
        band = pos | neg
        y = (ex.d["yw"] if k == 0 else ex.d["yhw"]).astype(float)
        F = fuse_features(ex.d["peak"], a_oof[:, k], b_sc[:, k])
        oof = np.zeros(len(y))
        for f in range(folds):
            tr, te = np.where(band & (g % folds != f))[0], np.where(band & (g % folds == f))[0]
            if len(te) == 0 or len(tr) == 0: raise SystemExit(f"Fusion: Faltung {f} leer")
            c, b = lr_fit(F[tr], y[tr]); oof[te] = lr_apply(c, b, F[te])
        thr, acc, rej = T.choose_threshold(oof, pos, neg, reject_min)
        c, b = lr_fit(F[band], y[band])
        out[nm] = dict(coef=[float(v) for v in c], intercept=b, thr=thr, accept=acc, reject=rej)
    return out


# ---------- Zählen (rein) ----------
def make_pass(stage, word_idx, scores, thr, hw2=None):
    """pass(ev) für eine Stufe; ev = dict(src, item, t, peak, key). Spitzenwert >= DIRECT: direkte Annahme. Band: A/B/C nach Schwelle thr (Kopf word_idx), hw2 über hw2(ev).
    Fehlt der Wert zu einem Ereignis im Band: KeyError (kein stilles Durchlassen)."""
    def p(ev):
        if ev["peak"] >= DIRECT or stage == "s1": return True
        if stage == "hw2": return bool(hw2(ev))
        return bool(scores[ev["key"]][stage][word_idx] >= thr)
    return p


def hit_counts(events, labels, passes, quiet_db=QUIET_DB):
    """{(Gerät, Wort): {"alle": (Treffer, n), "leise": ..., "laut": ...}}; Treffer = Ereignis im Label-Fenster, das die Stufe durchlässt.
    events: {Quelle: [ev]} (Quelle pos_<gerät>); labels: dict(dev, word, start, end, status, level)."""
    import words_measure as W
    out = {}
    for lb in labels:
        lo, hi = W.label_window(lb["start"], lb["end"], lb["status"])
        src = f"pos_{lb['dev']}"
        hit = any(lo <= ev["t"] <= hi and passes(ev) for ev in events.get(src, []))
        d = out.setdefault((lb["dev"], lb["word"]), {"alle": [0, 0], "leise": [0, 0], "laut": [0, 0]})
        for k in ("alle", "leise" if lb["level"] < quiet_db else "laut"):
            d[k][0] += hit; d[k][1] += 1
    return {c: {k: tuple(v) for k, v in d.items()} for c, d in out.items()}


def conf_counts(events, passes, info):
    """{Split: (Clips mit Durchlass, Clips)} für die Pruef-Verwechsler; info {Dateiname: (Basistext, Split)}. Clips ohne Ereignis zählen als Clip ohne Durchlass."""
    out = {"test": [0, 0], "train": [0, 0]}
    by = {}
    for ev in events.get("conf", []): by.setdefault(ev["item"], []).append(ev)
    for name, (_, sp) in info.items():
        out[sp][1] += 1
        out[sp][0] += any(passes(e) for e in by.get(name, []))
    return {k: tuple(v) for k, v in out.items()}


def hw2_available(tx, probe=False):
    """Fail-closed: fehlen die hw2-Transkripte (s2p/s2n fuer das Modell-Tag), bricht die Messung ab statt die hw2-Spalte still wegzulassen; Probe: False (Spalte entfaellt)."""
    ok = bool(tx) and all(tx.get(w) is not None for w in HEADS)
    if not ok and not probe:
        raise SystemExit("hw2-Transkripte fehlen (s2p/s2n fuer dieses Modell-Tag): zuerst stage2_analysis.py --cut-only und stage2_extra_neg.py fuer das Tag laufen lassen; "
                         "ohne sie fehlt die Vergleichsspalte hw2 + Band")
    return ok


def assert_conf_plan(items, info, probe=False):
    """Fail-closed: die Clips der Verwechsler-Kurven muessen der Plan-Liste `info` (conf_say_info) entsprechen. Weicht der Cache ab (andere --conf-n/--conf-seed),
    zaehlte conf_counts sonst Clips ohne Ereignis still als verworfen (0 %). Probe: Kurven sind gekuerzt, es genuegt Teilmenge."""
    items, plan = set(items), set(info)
    if not items <= plan or (not probe and items != plan):
        raise SystemExit(f"Verwechsler-Plan passt nicht zum Cache: {len(items - plan)} Clips nicht im Plan, {len(plan - items)} Plan-Clips ohne Kurve (andere conf-n/conf-seed?)")


def head_positive(label_word, word_idx):
    """Wie im Training (verifier_data.make_rows): W-Kopf (0) = „Wendelin“ und „Hey Wendelin“ positiv, HW-Kopf (1) nur „Hey Wendelin“."""
    return label_word == HEADS[1] or (word_idx == 0 and label_word == HEADS[0])


def cross_select_hits(events, labels, scores, word_idx, passes_direct=DIRECT, reject_min=T.REJECT_MIN, quiet_db=QUIET_DB):
    """Vergleichszeile „C per Kreuzauswahl ueber Pruef-Bloecke“ (NICHT der Arbeitspunkt): die Schwelle fuer jeden Pruef-Block (Geraet, Block) wird mit der
    Trainings-Regel (T.choose_threshold) auf den Band-Ereignissen der UEBRIGEN Pruef-Bloecke gewaehlt (Positive = Ereignis im Label-Fenster eines Rufs, dessen Wort
    fuer diesen Kopf positiv ist (head_positive, wie im Training), Negative = uebrige Band-Ereignisse), dann auf diesem Block gezaehlt. labels: ALLE Ruf-Labels
    (beide Woerter; gezaehlt werden nur die des Kopfes). Block ohne Negative oder Positive in den uebrigen Bloecken: Schwelle None (n/a), der Block zaehlt nicht mit.
    -> ({(Geraet, Wort): {"alle": (Treffer, n)}}, {Block: Schwelle|None}, {Block: Zahl Negative in den uebrigen Bloecken}). labels: Ausgabe von hit_counts (mit block, word)."""
    import words_measure as W
    evs = []          # (Block, Ereignis ist Positiv, C-Wert)
    for dev in {lb["dev"] for lb in labels}:
        ls = [lb for lb in labels if lb["dev"] == dev]
        for e in events.get(f"pos_{dev}", []):
            if e["peak"] >= passes_direct: continue
            near = min(ls, key=lambda lb: abs(e["t"] - (lb["start"] + lb["end"]) / 2))
            lo, hi = W.label_window(near["start"], near["end"], near["status"])
            pos = lo <= e["t"] <= hi and head_positive(near["word"], word_idx)
            evs.append(((dev, near["block"]), pos, float(scores[e["key"]]["c"][word_idx]), e))
    blocks = sorted({b for b, *_ in evs} | {(lb["dev"], lb["block"]) for lb in labels})
    thr, nneg = {}, {}
    for b in blocks:
        rest = [(p, c) for bb, p, c, _ in evs if bb != b]
        sc, po = np.array([c for _, c in rest]), np.array([p for p, _ in rest], bool)
        nneg[b] = int((~po).sum())
        thr[b] = T.choose_threshold(sc, po, ~po, reject_min)[0] if po.any() and (~po).any() else None
    out = {}
    for lb in labels:
        if lb["word"] != HEADS[word_idx]: continue
        b = (lb["dev"], lb["block"])
        if thr[b] is None: continue
        lo, hi = W.label_window(lb["start"], lb["end"], lb["status"])
        hit = any(lo <= e["t"] <= hi and (e["peak"] >= passes_direct or scores[e["key"]]["c"][word_idx] >= thr[b]) for e in events.get(f"pos_{lb['dev']}", []))
        d = out.setdefault((lb["dev"], lb["word"]), {"alle": [0, 0]})["alle"]
        d[0] += hit; d[1] += 1
    return {c: {k: tuple(v) for k, v in d.items()} for c, d in out.items()}, thr, nneg


def fa_count(events, srcs, passes):
    return sum(passes(ev) for s in srcs for ev in events.get(s, []))


def flat_events(pk):
    """{(Quelle, Item, seg_key): Spitzenwert} (stage2_cut.events_cut) -> {Quelle: [ev]}; Zeit aus dem seg_key (10-ms-Raster)."""
    ev = {}
    for (src, item, key), peak in pk.items():
        ev.setdefault(src, []).append(dict(src=src, item=item, t=int(key.rsplit("|", 1)[1]) * 160 / SR, peak=peak, key=key))
    return ev


def level_of(x, start, end):
    return D.level_db(x[int(start * SR):int(end * SR)])


# ---------- Messung: Merkmale und Bench ----------
class Scorer:
    """A + B (+C) auf Ausschnitten; ncpu=1, ein Thread. segs: Rohausschnitte (feste Länge, nicht normalisiert)."""
    def __init__(self, a_onnx, store, fusion, af):
        import onnxruntime as ort
        so = ort.SessionOptions(); so.intra_op_num_threads = 1
        self.sess = ort.InferenceSession(a_onnx, so, providers=["CPUExecutionProvider"])
        self.store, self.fusion, self.af = store, fusion, af

    def score(self, segs, peaks, parts=("a", "b", "c")):
        """-> {"a": (N,2), "b": (N,2), "c": (N,2)} (nur die gewünschten Teile; c braucht a und b)."""
        import common as CM
        emb = CM.embed(self.af, [D.normalize(s) for s in segs])
        out = {}
        if "a" in parts or "c" in parts: out["a"] = self.sess.run(None, {"input": emb.astype("float32")})[0]
        if "b" in parts or "c" in parts: out["b"] = self.store.scores(emb)
        if "c" in parts:
            c = np.zeros_like(out["a"])
            for k, nm in enumerate(("W", "HW")):
                f = self.fusion[nm]
                c[:, k] = lr_apply(f["coef"], f["intercept"], fuse_features(np.asarray(peaks), out["a"][:, k], out["b"][:, k]))
            out["c"] = c
        return out


def cpu_stats(times):
    t = np.asarray(times, "float64")
    return float(np.median(t)), float(np.quantile(t, 0.95))


def bench(fn, items, warm=3):
    """CPU-Zeit (process_time) je Aufruf fn(item); die ersten `warm` Aufrufe zählen nicht. -> (Median, 95 %-Quantil) in s."""
    for it in items[:warm]: fn(it)
    ts = []
    for it in items[warm:]:
        t0 = time.process_time(); fn(it); ts.append(time.process_time() - t0)
    return cpu_stats(ts)


def rss_mb():
    return int(subprocess.run(["ps", "-o", "rss=", "-p", str(os.getpid())], capture_output=True, text=True).stdout.strip() or 0) / 1024


def hardware():
    try:
        cpu = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip()
    except OSError:
        cpu = ""
    return f"{cpu or platform.processor()}, {platform.system()} {platform.release()}"


# ---------- Ausgabe ----------
def pct(h, n):
    import words_measure as W
    return "-" if not n else W.fmt_hit(h, n)


def render(res, notes):
    """res {Stufe: {"hits": ..., "conf": ..., "fa": {Quelle: (k, h)}}}; Markdown mit Zahlen (keine Transkripte)."""
    import stage2_extra_neg as E
    stages = list(res)
    cells = [(d, w) for d in ("huawei", "handy2") for w in HEADS]
    out = ["# Wortspezifischer Prüfer (WP137 Teil 2): Vergleich", "", *notes, "",
           "## Treffer (feste Schwelle, Stufe 1 bei 0,98; Wilson 95 %)", "",
           "| Stufe | " + " | ".join(f"{d} {w}" for d, w in cells) + " | Prüf-Split gesamt |", "|---|" + "---|" * (len(cells) + 1)]
    for s in stages:
        h = res[s]["hits"]
        tot = lambda k: (sum(h.get(c, {}).get(k, (0, 0))[0] for c in cells), sum(h.get(c, {}).get(k, (0, 0))[1] for c in cells))
        out.append(f"| {s} | " + " | ".join(pct(*h[c]["alle"]) if c in h else "-" for c in cells) + f" | {pct(*tot('alle'))} |")
    out += ["", "## Leise Rufe getrennt (Wort-Pegel < -35 dBFS) / laute", "", "| Stufe | leise | laut |", "|---|---|---|"]
    for s in stages:
        h = res[s]["hits"]
        tot = lambda k: (sum(v[k][0] for v in h.values()), sum(v[k][1] for v in h.values()))
        out.append(f"| {s} | {pct(*tot('leise'))} | {pct(*tot('laut'))} |")
    out += ["", "## Verwechsler (Clips mit Ereignis, das die Stufe durchlässt, je Kopf)", "", "| Stufe | Wort | Test-Texte 30 % (Vergleichszahl) | Trainings-Texte 70 % |", "|---|---|---|---|"]
    for s in stages:
        for w in HEADS:
            c = res[s]["conf"][w]
            out.append(f"| {s} | {w} | {pct(*c['test'])} | {pct(*c['train'])} |")
    srcs = [k for k in res[stages[0]]["fa"]]
    out += ["", "## Fehlalarme pro Stunde (Anzahl, FA/h, Poisson-Obergrenze 95 %)", "", "| Stufe | Wort | " + " | ".join(srcs) + " |", "|---|---|" + "---|" * len(srcs)]
    for s in stages:
        for w in HEADS:
            row = []
            for sr in srcs:
                k, hrs = res[s]["fa"][sr][w]
                row.append("-" if not hrs else f"{k} ({k / hrs:.2f}/h, ≤{E.poisson_upper(k, hrs):.2f})".replace(".", ","))
            out.append(f"| {s} | {w} | " + " | ".join(row) + " |")
    return "\n".join(out) + "\n"


# ---------- Phase fit: B-Vorlagen, C-Fusion, Schwellen (nur Trainingsseite) ----------
def cut_of(a, meta):
    """(pre, tail) aus Stempel der Merkmalsdatei und meta des Trainings; sie muessen uebereinstimmen, eine ausdrueckliche CLI-Angabe darf nicht abweichen."""
    cut = D.feat_cut(a.feat)
    if (meta.get("pre"), meta.get("tail")) != cut: raise SystemExit(f"Ausschnitt in meta ({meta.get('pre')}/{meta.get('tail')}) widerspricht der Merkmalsdatei {cut}")
    for v, c, nm in ((a.pre, cut[0], "--pre"), (a.tail, cut[1], "--tail")):
        if v is not None and v != c: raise SystemExit(f"{nm} {v} widerspricht dem Ausschnitt der Merkmalsdatei {c}")
    return cut


def phase_fit(a):
    import common as CM
    D.require_stamp(a.feat)
    ex = D.Examples.load(a.feat)
    meta = json.load(open(os.path.join(a.verifier, "verifier_a.onnx.meta.json")))
    oof = np.load(os.path.join(a.verifier, "oof.npz"))["oof"]
    if len(oof) != len(ex) or meta["feat"] != os.path.basename(a.feat): raise SystemExit("OOF-Datei gehört nicht zu dieser Merkmalsdatei")
    pre, tail = cut_of(a, meta)
    D.assert_group_blocks(a.real_pos)
    af = CM.make_features(a.oww, 1)
    mu = center_mu(ex)
    store = build_templates(dict(D.load_wavs(a.real_pos, None, 2.2)), lambda x: CM.embed(af, [x])[0], mu)
    b_sc = store.scores(ex.d["emb"], train_blocks(ex))
    fus = fit_fusion(ex, oof, b_sc)
    thr = {"A": meta["thresholds"], "B": {}, "C": {k: fus[k]["thr"] for k in ("W", "HW")}}
    for k, nm in enumerate(("W", "HW")): thr["B"][nm] = T.choose_threshold(b_sc[:, k], *T.band_masks(ex, k))[0]
    store.save(os.path.join(a.verifier, "b_templates.npz"))
    json.dump(dict(thresholds=thr, fusion=fus, topk=TOPK, n_templates=len(store.items), feat=meta["feat"], pre=pre, tail=tail),
              open(os.path.join(a.verifier, "verifier.json"), "w"), indent=1)
    with open(os.path.join(a.verifier, "sweep.md"), "a") as fh:
        for k, nm in enumerate(("Wendelin", "Hey Wendelin")):
            fh.write(f"## Sweep B (Trainingsseite, Leave-Block-Out) Kopf {nm}\n\n" + "\n".join(T.sweep_table(b_sc[:, k], ex, k)) + "\n\n")
    print(f"B: {len(store.items)} Vorlagen; Schwellen {thr}", flush=True)


def make_scorer(a):
    import common as CM
    return Scorer(os.path.join(a.verifier, "verifier_a.onnx"), BStore.load(os.path.join(a.verifier, "b_templates.npz")),
                  json.load(open(os.path.join(a.verifier, "verifier.json")))["fusion"], CM.make_features(a.oww, 1))


# ---------- Phase run: Messung auf dem Prüf-Split ----------
def phase_run(a):
    import words_measure as W
    import station_measure as S
    import v8_measure as V
    import stage2_cut as C
    import stage2_analysis as A
    import stage2_extra_neg as E
    D.require_stamp(a.feat)
    vj = json.load(open(os.path.join(a.verifier, "verifier.json")))
    meta = json.load(open(os.path.join(a.verifier, "verifier_a.onnx.meta.json")))
    if vj["feat"] != os.path.basename(a.feat) or meta["feat"] != vj["feat"]: raise SystemExit("verifier.json und Merkmalsdatei passen nicht zusammen")
    name = a.model.partition("=")[0]
    models = V.parse_models([a.model], with_v7=False)
    E.TAG = name
    if not a.probe and not a.report_only:
        V.run_s1(models); E.run_s1x(models[name], a.threads)
    curves = V.load_curves(name)
    try: curves.update(E.load_new_curves())
    except OSError: print("Hinweis: keine Kurven für MLS/FLEURS-Rest (s1x fehlt)", flush=True)
    if a.probe: curves = {s: dict(list(d.items())[:25]) for s, d in curves.items()}
    pre, tail = cut_of(a, meta)
    if (vj.get("pre"), vj.get("tail")) != (pre, tail): raise SystemExit("verifier.json: Ausschnitt weicht von Merkmalsdatei/meta ab")
    ev1 = flat_events(C.events_cut(curves, 0.98, "app", C.APP_UPPER)[1])      # Stufe 1 allein: Halten bis 0,995 (App ohne Band)
    ev = flat_events(C.events_cut(curves, 0.98, "app", DIRECT)[1])            # mit Prüfer: Halten bis zur Direktannahme 0,999 (acceptFrom)
    load = lambda src, item: E.load_item(src, item) if src in E.NEW_SRC else V.load_item(src, item)
    r_rss = rss_mb()
    f1 = make_scorer(a)
    f1.score([np.zeros(int((pre + tail) * SR), "float32")], [0.99])                  # Sitzungen und Merkmalsmodelle laden
    rss_abc = rss_mb() - r_rss
    scores, by = {}, {}
    for es in ev.values():
        for e in es:
            if e["peak"] < DIRECT: by.setdefault((e["src"], e["item"]), []).append(e)
    for (src, item), es in by.items():
        x = load(src, item)
        sc = f1.score([D.segment(x, e["t"], pre, tail) for e in es], [e["peak"] for e in es])
        for i, e in enumerate(es): scores[e["key"]] = {k: sc[k][i] for k in sc}
    labels = V.filter_labels(W.read_labels(), "eval")
    full = {d: V.load_item(f"pos_{d}", f"pos_{d}") for d in V.DEVICES}
    for lb in labels: lb["level"] = level_of(full[lb["dev"]], lb["start"], lb["end"])
    del full
    tx = E.load_tx().get((*E.CUT, False), {})
    info = D.conf_say_info()
    assert_conf_plan(curves.get("conf", {}), info, a.probe)
    var = C.VARS[C.SEED_BAND]
    hours = {s: (E.hours(s) if s in E.NEW_SRC else V.hours(s)) for s in curves if not s.startswith("pos_")}
    fa_src = {"syn": ["syn"], "fleurs": ["fleurs"], "echt": ["neg_huawei", "neg_handy2"], "mls_de": ["mls_de"], "fleurs_rest": ["fleurs_rest"]}
    thr = vj["thresholds"]
    def cross_side(k, t):
        p = make_pass("c", k, scores, t)
        cf = conf_counts(ev, p, info).get("test", (0, 0))
        fa = {sn: (fa_count(ev, [x for x in ss if x in curves], p), sum(hours.get(x, 0) for x in ss if x in curves)) for sn, ss in fa_src.items()}
        return f"Verwechsler Test {cf[0]}/{cf[1]}; FA " + ", ".join(f"{sn} {n}/{h:.1f} h" for sn, (n, h) in fa.items())
    names = {"s1": "Stufe 1 (0,98)", "hw2": "hw2 + Band", "A": "A Klassifikator", "B": "B Vorlagen", "C": "C Fusion"}
    res = {}
    hw2_ok = hw2_available(tx, a.probe)
    for st in names:
        if st == "hw2" and not hw2_ok: print("Hinweis (Probe): hw2-Transkripte fehlen, Spalte entfaellt", flush=True); continue
        r = dict(hits={}, conf={}, fa={s: {} for s in fa_src})
        for k, w in enumerate(HEADS):
            if st == "hw2":
                p = make_pass("hw2", k, scores, 0, hw2=lambda e, txw=tx[w], w=w: A.passes_rule(var, w, txw[e["key"]], e["peak"]))
            else:
                p = make_pass("s1" if st == "s1" else st.lower(), k, scores, 0 if st == "s1" else thr[st]["W" if k == 0 else "HW"])
            evs = ev1 if st == "s1" else ev
            r["hits"].update(hit_counts(evs, [lb for lb in labels if lb["word"] == w], p))
            r["conf"][w] = conf_counts(evs, p, info)
            for sn, ss in fa_src.items():
                r["fa"][sn][w] = (fa_count(evs, [x for x in ss if x in curves], p), sum(hours.get(x, 0) for x in ss if x in curves))
        res[names[st]] = r
    notes = [f"Stufe-1-Modell {name}, Prüfer {meta['sha256'][:12]}, Ausschnitt {pre} s vor / {tail} s nach der Entscheidung, Schwellen aus der Trainingsseite: {thr}.",
             "Prüf-Split: Huawei Block 4–6, handy2 Block 1–6; Verwechsler: macOS-say, nach Text-Split (30 % Test / 70 % Training).",
             f"Rechner: {hardware()}.", *cross_notes(ev, labels, scores, cross_side), f"RSS-Zuwachs A/B/C (Sitzungen, Merkmalsmodelle, Vorlagen laden): {rss_abc:.0f} MB",
             *bench_notes(a, f1, ev, load, pre, tail, meta, S, W, V)]
    p = os.path.join(a.out or D.VER, "verifier_table.md")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(render(res, notes))
    print(f"-> {p}", flush=True)


def cross_notes(ev, labels, scores, side=None):
    """Vergleichszeile C per Kreuzauswahl ueber Pruef-Bloecke (Schwelle aus den uebrigen Pruef-Bloecken; nur zum Vergleich, nicht der Arbeitspunkt). Zeigt je Block die Zahl
    der Negativen (Schwellenbasis; 0 -> „n/a“) und, wenn `side(k, thr)` -> Text gegeben ist, Verwechsler/FA bei dieser Schwelle (sonst nur die Trefferseite)."""
    out = []
    for k, w in enumerate(HEADS):
        h, thr, nneg = cross_select_hits(ev, labels, scores, k)
        cells = "; ".join(f"{d}: {pct(*v['alle'])}" for (d, _), v in sorted(h.items())) or "n/a"
        ts = ", ".join(f"{d}{b}={'n/a' if t is None else format(t, '.3f')} (Neg. {nneg[(d, b)]}" + (f"; {side(k, t)}" if side and t is not None else "") + ")" for (d, b), t in sorted(thr.items()))
        out.append(f"C per Kreuzauswahl über Prüf-Blöcke (nur Vergleichszeile, nur Trefferseite {'' if side else 'ohne Verwechsler/FA '}— Schwellen: {ts}) {w}: {cells}")
    return out


def bench_notes(a, f1, ev, load, pre, tail, meta, S, W, V):
    """CPU-Zeit je Prüfung (einthreadig, Median / 95 %-Quantil), Speicher; hw2 auf denselben Ausschnitten."""
    pool = [e for es in ev.values() for e in es if e["peak"] < DIRECT]
    if len(pool) < 5: return ["Bench: zu wenige Ereignisse im Band."]
    pick = [pool[i] for i in np.random.default_rng(1).permutation(len(pool))[:min(a.bench_n, len(pool))]]
    audio = [load(e["src"], e["item"]) for e in pick]
    segs = [(D.segment(x, e["t"], pre, tail), e["peak"]) for x, e in zip(audio, pick)]
    notes = []
    for nm, parts in (("A", ("a",)), ("B", ("b",)), ("C", ("c",))):
        m, q = bench(lambda it, parts=parts: f1.score([it[0]], [it[1]], parts), segs)
        notes.append(f"CPU-Zeit {nm} (Melspec+Embedding+Prüfung, 1 Thread): Median {m * 1000:.0f} ms, 95 %-Quantil {q * 1000:.0f} ms ({len(segs) - 3} Ausschnitte)")
    r0 = rss_mb()
    for w in V.WORDS: S.WORDS.setdefault(W.key(w), {})["hot"] = W.SPEC[w]["hot"]
    S.WORK111 = f"{V.RES}/hw"
    rec = S.make_rec("parakeet-hw2@wendelin", 1)
    h2 = [(D.segment(x, e["t"], 2.0, 0.9),) for x, e in zip(audio, pick)]
    m, q = bench(lambda it: S.decode(rec, it[0]), h2)
    notes.append(f"CPU-Zeit hw2 (sherpa-onnx Parakeet, 1 Thread, Ausschnitt 2,0/0,9 s): Median {m * 1000:.0f} ms, 95 %-Quantil {q * 1000:.0f} ms; RSS-Zuwachs durch hw2 {rss_mb() - r0:.0f} MB")
    notes.append(f"Speicher A: ONNX {meta['bytes'] / 1e6:.2f} MB, {meta['params']} Parameter; B: {len(f1.store.items)} Vorlagen. Einzelmessung auf dem Mac, Übertragung aufs Handy nur Abschätzung.")
    return notes


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("phase", choices=["fit", "run"])
    ap.add_argument("--verifier", required=True, help="Ordner mit verifier_a.onnx (verifier_train.py --out)")
    ap.add_argument("--feat", required=True, help="Merkmalsdatei des Trainings (mit Leckpruefungs-Stempel)")
    ap.add_argument("--real-pos", help="fit: Ordner echter Positive"); ap.add_argument("--model", help="run: name=pfad Stufe-1-Modell")
    ap.add_argument("--oww", default=D.OWW_DIR); ap.add_argument("--pre", type=float); ap.add_argument("--tail", type=float)       # nur Gegenprobe; der Ausschnitt kommt aus der Merkmalsdatei
    ap.add_argument("--probe", action="store_true"); ap.add_argument("--report-only", action="store_true"); ap.add_argument("--out")
    ap.add_argument("--threads", type=int, default=2); ap.add_argument("--bench-n", type=int, default=60)
    a = ap.parse_args()
    if a.phase == "fit" and not a.real_pos: ap.error("fit braucht --real-pos")
    if a.phase == "run" and not a.model: ap.error("run braucht --model")
    (phase_fit if a.phase == "fit" else phase_run)(a)


if __name__ == "__main__":
    main()
