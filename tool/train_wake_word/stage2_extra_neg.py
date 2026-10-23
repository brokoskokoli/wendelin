#!/usr/bin/env python3
"""WP133 Teil A3: Fehlalarme des Bands (Stufe 2 nur unter 0,999) mit mehr oeffentlichen Negativdaten, nur v8a.

Zwei zusaetzliche Quellen, ohne bestehende Quellen/Caches zu aendern (neue Caches: s1x/, s2n/ unter $RES):
  fleurs_rest  FLEURS-de-Test ohne die bisher genutzte erste Stunde (words_measure.clip_list("fleurs"), sortiert nach Dateiname), wie fleurs auf Spitze 1 normiert
  mls_de       Multilingual LibriSpeech Deutsch, nur Test-Split (CC BY 4.0, Hoerbuecher), unnormiert, je Aeusserung ein Clip
Daten (lokal, nicht im Repo): $K/wp133/dl/mls_de_test/ex/*.flac (aus data/mls_german/test/audio/*.tar.gz des HF-Datasets facebook/multilingual_librispeech).
Messung: App-Bezugszeit mit Halten (stage2_cut.app_events), Ausschnitt 2,0/0,9, Schwellen 0,95/0,98/0,99, Varianten Stufe 1 allein, hw2, hw2+Band 0,999,
hw2+Band 0,995, hw2+norm+Band 0,999; Stufe 2 nur fuer Ereignisse. FA/h mit exakter Poisson-Obergrenze (95 % zweiseitig, also 97,5 % einseitig); Wilson 95 % fuer
den Anteil der Clips mit mindestens einem durchkommenden Ereignis. Zur Gegenprobe werden die bisherigen Quellen mit derselben Auswertung mitgefuehrt und
bei Schwelle 0,98 gegen stage2_cut.cut_fixed abgeglichen.

Lauf (Repo-Root, K=~/wendelin-models/kws):
  nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/stage2_extra_neg.py --model v8a=$K/wp130/out/wendelin_wp130_a.onnx --threads 2
Ausgabe nur lokal: $RES/stage2_extra_neg.md. Selbsttest: test_stage2_extra_neg.py."""
import argparse, functools, glob, json, math, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np
import soundfile as sf
import words_measure as W
import station_measure as S
import v8_measure as V
import stage2_analysis as A
import stage2_cut as C

SR = W.SR
TAG = C.CUT_TAG
NEW_SRC = ("fleurs_rest", "mls_de")
OLD_SRC = ("neg_huawei", "neg_handy2", "syn", "fleurs", "conf")
THRS = (0.95, 0.98, 0.99)
CUT = (C.APP_PRE, C.APP_TAIL)                                   # Ausschnitt der App
VARIANTS = ("-", "app-2.0-0.9", "app-2.0-0.9-b999", "app-2.0-0.9-b995", "app-2.0-0.9-nm-b999")
MLS_DIR = os.path.join(W.KWS, "wp133/dl/mls_de_test/ex")
FLEURS_DIR = f"{W.KWS}/wp111/work/fleurs/test"
FIRST_HOURS = 1.0                                               # words_measure.clip_list: FLEURS bis 1,0 h


# ---------- Reine Funktionen ----------
def split_first_hour(files, hours=FIRST_HOURS):
    """files: [(name, Dauer in s)] sortiert -> (erste, Rest). Nachbildung von words_measure.clip_list("fleurs"): Clips, solange die Summe vor dem Clip < hours ist."""
    first, rest, tot = [], [], 0.0
    for n, d in files:
        if tot >= hours * 3600:
            rest.append((n, d)); continue
        first.append((n, d)); tot += d
    return first, rest


def poisson_upper(k, hours, conf=0.95):
    """Obergrenze der Rate (Ereignisse/h): exakt, zweiseitig conf, also P(X <= k | lam) = (1 - conf) / 2 nach lam aufgeloest."""
    if hours <= 0: return float("inf")
    a = (1 - conf) / 2
    def cdf(lam):
        term = math.exp(-lam); s = term
        for i in range(1, k + 1):
            term *= lam / i; s += term
        return s
    lo, hi = 0.0, k + 10.0 + 10 * math.sqrt(k + 1)
    for _ in range(100):
        mid = (lo + hi) / 2
        if cdf(mid) > a: lo = mid
        else: hi = mid
    return hi / hours


def wilson(k, n, z=1.96):
    return S.wilson(k, n, z)


def fa_count(curves, src, thr, upper, make_pass):
    """({Zahl durchkommender Ereignisse, Ereignisse, Clips mit Durchlass, Ereignisse mit Spitze >= 0,999}, Liste (item, t, peak) der Durchlaesse).
    make_pass(pk) -> pass_fn(src, item, t) (KeyError, wenn ein Text fehlt)."""
    ev, pk = C.events_cut({src: curves[src]}, thr, "app", upper)
    pass_fn = make_pass(pk)
    n_ev = n_pass = n_clip = n_top = 0
    passed = []
    for item, ts in ev[src].items():
        c = 0
        for t in ts:
            p = pk[(src, item, W.seg_key(src, item, t))]
            n_ev += 1
            n_top += p >= 0.999
            if pass_fn(src, item, t):
                n_pass += 1; c += 1; passed.append((item, t, p))
        n_clip += c > 0
    return dict(n_pass=n_pass, n_ev=n_ev, n_clip=n_clip, n_top=n_top), passed


def counts(curves, tx, word, src, thr, vn):
    """fa_count fuer eine Variante (vn = "-" Stufe 1 allein) -> (Zaehlwerte, Durchlaesse) oder None bei fehlendem Text."""
    if vn == "-": return fa_count(curves, src, thr, C.APP_UPPER, lambda pk: (lambda *_: True))
    var = C.VARS[vn]
    try:
        return fa_count(curves, src, thr, var["upper"], lambda pk: C._passes(var, word, tx, pk))
    except KeyError:
        return None


def merge_pool(rows):
    """Summe der Zaehlwerte ueber Quellen: [(dict, Stunden)] -> (dict, Stunden); None, wenn eine Quelle None ist."""
    if any(r is None for r in rows): return None
    tot = {k: sum(r[0][k] for r in rows) for k in rows[0][0]}
    return tot, sum(r[1] for r in rows)


def cell(c, hours):
    """Tabellenzelle: Zahl (FA/h, Obergrenze)."""
    if c is None: return "-"
    k = c["n_pass"]
    return f"{k} ({W.fc(f'{k / hours:.2f}')}/h, ≤{W.fc(f'{poisson_upper(k, hours):.2f}')})"


# ---------- Daten ----------
def fleurs_files():
    return [(os.path.basename(f), sf.info(f).duration) for f in sorted(glob.glob(f"{FLEURS_DIR}/*.wav"))]


@functools.lru_cache(maxsize=None)
def clip_paths_cached(src):
    return clip_paths_uncached(src)


def clip_paths(src): return dict(clip_paths_cached(src))


def clip_paths_uncached(src):
    if src == "fleurs_rest":
        _, rest = split_first_hour(fleurs_files())
        return tuple((n, f"{FLEURS_DIR}/{n}") for n, _ in rest)
    if src == "mls_de":
        return tuple((os.path.basename(f)[:-5], f) for f in sorted(glob.glob(f"{MLS_DIR}/*.flac")))
    raise ValueError(src)


def load_item(src, name):
    x = W.K.load(clip_paths(src)[name])
    return x / (np.abs(x).max() + 1e-9) if src == "fleurs_rest" else x          # wie fleurs: je Clip auf Spitze 1


def hours(src):
    if src in NEW_SRC:
        p = f"{V.RES}/s1x/hours.json"
        d = json.load(open(p)) if os.path.exists(p) else {}
        if src not in d:
            d[src] = round(sum(sf.info(f).duration for f in clip_paths(src).values()) / 3600, 4)
            os.makedirs(os.path.dirname(p), exist_ok=True); json.dump(d, open(p, "w"))
        return d[src]
    return V.hours(src)


def s1x_path(tag, src): return f"{V.RES}/s1x/{V.ctag(tag)}/{src}.npz"


def s2n_path(word, norm):
    nm = f"-nm{C.NORM_PEAK}" if norm else ""
    return f"{V.RES}/s2n/{V.ctag(TAG)}-p{CUT[0]}-t{CUT[1]}{nm}/hw2@{W.key(word)}.json"


# ---------- Laeufe ----------
def run_s1x(model, threads):
    """Wertekurven von v8a je Fenster fuer die neuen Quellen (gleiche Verarbeitung wie v8_measure.run_s1) -> s1x/<tag>/<src>.npz."""
    import onnxruntime as ort
    pad = lambda x: np.concatenate([np.zeros(SR, "float32"), x, np.zeros(SR, "float32")])
    af = sess = None
    for src in NEW_SRC:
        p = s1x_path(TAG, src)
        if os.path.exists(p): continue
        if af is None:
            af = S.Oww(model).af
            so_ = ort.SessionOptions(); so_.intra_op_num_threads = 1
            sess = ort.InferenceSession(model, so_, providers=["CPUExecutionProvider"])
        d, t0, names = {}, time.time(), list(clip_paths(src))
        for i, name in enumerate(names):
            emb = S.C.embed(af, [pad(load_item(src, name))])[0]
            n = len(emb) - S.C.WIN + 1
            if n <= 0: continue
            Wn = np.stack([emb[j:j + S.C.WIN] for j in range(n)]).astype("float32")
            d[f"{name}|t"] = ((np.array([S.C.window_end(j) for j in range(n)]) - SR) / SR).astype("float32")
            d[f"{name}|s"] = sess.run(None, {"input": Wn})[0][:, 0].astype("float32")
            if i % 200 == 0: print(f"s1x {src}: {i}/{len(names)} {time.time() - t0:.0f} s", flush=True)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        np.savez_compressed(p, **d)
        print(f"s1x {src}: {len(names)} Clips, {time.time() - t0:.0f} s", flush=True)


def load_new_curves():
    out = {}
    for src in NEW_SRC:
        z = np.load(s1x_path(TAG, src))
        out[src] = {k[:-2]: (z[k], z[k[:-2] + "|s"]) for k in z.files if k.endswith("|t")}
    return out


def candidates(curves):
    """seg_keys der Ereignisse der neuen Quellen (Obergrenzen 0,995 und 0,999, Schwellen THRS)."""
    cand = set()
    for upper in (C.APP_UPPER, 0.999):
        for thr in THRS:
            ev, pk = C.events_cut({s: curves[s] for s in NEW_SRC}, thr, "app", upper)
            cand.update(k[2] for k in pk)
    return cand


def run_s2n(curves, threads):
    """hw2 je Wort, ohne und mit Normalisierung, auf den Ereignissen der neuen Quellen -> s2n/..."""
    for w in V.WORDS: S.WORDS.setdefault(W.key(w), {})["hot"] = W.SPEC[w]["hot"]
    S.WORK111 = f"{V.RES}/hw"
    os.makedirs(S.WORK111, exist_ok=True)
    cand = candidates(curves)
    for w in V.WORDS:
        rec = None
        for norm in (False, True):
            p = s2n_path(w, norm)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            have = json.load(open(p)) if os.path.exists(p) else {}
            todo = sorted(k for k in cand if k not in have)
            print(f"s2n {w} norm={norm}: {len(todo)} neue Segmente (von {len(cand)})", flush=True)
            if not todo: continue
            if rec is None: rec = S.make_rec(f"parakeet-hw2@{W.key(w)}", threads)
            by_item = {}
            for k in todo:
                src, item, _ = k.split("|")
                by_item.setdefault((src, item), []).append(k)
            t0 = t_dump = time.time()
            for (src, item), ks in by_item.items():
                x = load_item(src, item)
                for k in ks:
                    a, b = C.seg_bounds(k, *CUT)
                    seg = x[a:b].astype("float32")
                    have[k] = S.decode(rec, A.normalize_peak(seg, C.NORM_PEAK) if norm else seg)
                if time.time() - t_dump > 120: json.dump(have, open(p, "w")); t_dump = time.time()
            json.dump(have, open(p, "w"))
            print(f"s2n {w} norm={norm}: {time.time() - t0:.0f} s", flush=True)
        del rec


def load_tx():
    """{(pre, tail, norm): {Wort: {seg_key: Text} oder None}}: bisherige s2p-Caches (nur lesen) plus die neuen s2n-Caches, nur Ausschnitt der App."""
    def ld(p): return json.load(open(p)) if os.path.exists(p) else None
    tx = {}
    for norm in (False, True):
        tx[(*CUT, norm)] = {}
        for w in V.WORDS:
            old, new = ld(C.cut_path(TAG, w, *CUT, norm)), ld(s2n_path(w, norm))
            tx[(*CUT, norm)][w] = None if old is None or new is None else {**old, **new}
    return tx


# ---------- Auswertung ----------
def evaluate(curves, tx):
    """{(Quelle, Wort, Variante, Schwelle): (Zaehlwerte, Durchlaesse) oder None}."""
    out = {}
    for src in NEW_SRC + OLD_SRC:
        for w in V.WORDS:
            for vn in VARIANTS:
                for thr in THRS:
                    out[(src, w, vn, thr)] = counts(curves, tx, w, src, thr, vn)
    return out


def check_parity(res, curves, tx, labels):
    """Gegenprobe: bisherige Quellen bei 0,98 gegen stage2_cut.cut_fixed (Zahl durchkommender Ereignisse). -> Liste der Abweichungen."""
    fx = C.cut_fixed(curves, labels, tx)
    bad = []
    for vn in VARIANTS:
        r = fx[("app", vn)]
        for w in V.WORDS:
            for src in OLD_SRC:
                a = res[(src, w, vn, 0.98)]
                a = None if a is None else a[0]["n_pass"]
                b = r["pass"][w][src]
                if a != b: bad.append((vn, w, src, a, b))
    return bad


def render(res, target_note=""):
    lab = {"-": "Stufe 1 allein", "app-2.0-0.9": "hw2", "app-2.0-0.9-b999": "hw2 + Band 0,999", "app-2.0-0.9-b995": "hw2 + Band 0,995",
           "app-2.0-0.9-nm-b999": "hw2 + norm + Band 0,999"}
    pools = {"neu (fleurs_rest + mls_de)": NEW_SRC, "alle ohne conf": tuple(s for s in NEW_SRC + OLD_SRC if s != "conf")}
    hs = {s: hours(s) for s in NEW_SRC + OLD_SRC}
    out = ["# Fehlalarme des Bands mit mehr öffentlichen Negativdaten (WP133 A3): v8a, App-Bezug mit Halten, Ausschnitt 2,0/0,9", "",
           "Zelle = durchkommende Ereignisse (FA/h, Poisson-95-%-Obergrenze, zweiseitig/exakt). Ereignisse werden nur gezählt, nicht auf Treffer der Wortsilben geprüft. "
           "Poisson setzt unabhängige Ereignisse voraus; Clips derselben Sprecher/Kapitel sind korreliert, die Obergrenze ist daher eher zu knapp. "
           "conf = synthetische Verwechsler (kein Alltagssprecher, nicht in den Pools).", "",
           "## Stunden und Ereignisse je Quelle", "", "| Quelle | Stunden | Ereignisse Stufe 1 (0,95 / 0,98 / 0,99) | davon Spitze ≥ 0,999 (direkt angenommen) |", "|---|---|---|---|"]
    for s in NEW_SRC + OLD_SRC:
        e = [res[(s, V.WORDS[0], "app-2.0-0.9-b999", t)] for t in THRS]
        out.append(f"| {s} | {W.fc(f'{hs[s]:.2f}')} | " + " / ".join("-" if x is None else str(x[0]["n_ev"]) for x in e) + " | "
                   + " / ".join("-" if x is None else str(x[0]["n_top"]) for x in e) + " |")
    for w in V.WORDS:
        out += ["", f"## {w}", "", "| Quelle | Variante | " + " | ".join(f"Schwelle {W.fc(t)}" for t in THRS) + " |", "|---|---|---|---|---|"]
        for name, srcs in list(pools.items()) + [(s, (s,)) for s in NEW_SRC + OLD_SRC]:
            for vn in VARIANTS:
                cells = []
                for thr in THRS:
                    m = merge_pool([(res[(s, w, vn, thr)][0], hs[s]) if res[(s, w, vn, thr)] else None for s in srcs])
                    cells.append("-" if m is None else cell(m[0], m[1]))
                out.append(f"| {name} | {lab[vn]} | " + " | ".join(cells) + " |")
    out += ["", "## Clips mit mindestens einem Durchlass (Wilson 95 %)", "", "| Quelle | Wort | Variante | Schwelle | Clips mit Durchlass / Clips | Wilson |", "|---|---|---|---|---|---|"]
    for s in NEW_SRC:
        n = len(clip_paths(s))
        for w in V.WORDS:
            for vn in VARIANTS[1:]:
                for thr in THRS:
                    r = res[(s, w, vn, thr)]
                    if r is None: continue
                    lo, hi = wilson(r[0]["n_clip"], n)
                    out.append(f"| {s} | {w} | {lab[vn]} | {W.fc(thr)} | {r[0]['n_clip']} / {n} | {W.fc(f'{lo * 100:.1f}')}–{W.fc(f'{hi * 100:.1f}')} % |")
    return "\n".join(out) + "\n"


def render_passed(res, tx, thr=0.98):
    """Lokale Liste der durchkommenden Ereignisse der neuen Quellen (Text aus hw2) fuer die Plausibilitaet."""
    out = [f"# Durchlaesse der neuen Quellen bei Schwelle {W.fc(thr)} (lokal, nicht committen)", ""]
    for s in NEW_SRC:
        for w in V.WORDS:
            for vn in VARIANTS[1:]:
                r = res[(s, w, vn, thr)]
                if r is None or not r[1]: continue
                var = C.VARS[vn]
                txw = tx[(var["pre"], var["tail"], var["norm"])][w]
                out.append(f"## {s} / {w} / {vn}: {len(r[1])} Durchlaesse")
                for item, t, p in r[1]:
                    out.append(f"- {item} t={t:.1f} Spitze={p:.4f} Text={txw.get(W.seg_key(s, item, t), '')!r}")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", action="append", default=[], help="v8a=<pfad>")
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--report-only", action="store_true")
    a = ap.parse_args()
    models = V.parse_models(a.model, False)
    if TAG not in models: sys.exit("braucht --model v8a=<pfad>")
    if not a.report_only:
        run_s1x(models[TAG], a.threads)
    first, _ = split_first_hour(fleurs_files())
    assert [n for n, _ in first] == [n for n, _ in W.clip_list("fleurs")], "erste Stunde weicht von words_measure.clip_list ab"
    curves = {**V.load_curves(TAG), **load_new_curves()}
    if not a.report_only: run_s2n(curves, a.threads)
    tx = load_tx()
    res = evaluate(curves, tx)
    labels = V.filter_labels(W.read_labels())
    bad = check_parity(res, curves, tx, labels)
    print("Paritaet mit cut_fixed (bisherige Quellen, 0,98):", "OK" if not bad else f"ABWEICHUNGEN {bad}", flush=True)
    md = render(res) + ("" if not bad else f"\n**Achtung: Abweichungen zur Gegenprobe {bad}**\n")
    open(f"{V.RES}/stage2_extra_neg.md", "w").write(md)
    open(f"{V.RES}/stage2_extra_neg_passed.local.md", "w").write(render_passed(res, tx))
    print(f"-> {V.RES}/stage2_extra_neg.md", flush=True)


if __name__ == "__main__":
    main()
