#!/usr/bin/env python3
"""WP130 Punkt 5: Messung der openWakeWord-Modelle (v7 und Kandidaten) fuer „Wendelin“ und „Hey Wendelin“ NUR auf dem Pruef-Split.

Pruef-Split (aus real_split.py, nie im Training): Huawei Block 4 bis 6 und das zweite Handy Block 4 bis 6. Huawei Block 1 bis 3
sind Trainingsdaten und werden nie gewertet; das zweite Handy hat in Block 1 bis 3 dieselben gesprochenen Rufe gleichzeitig aufgenommen
(Sitzung gepaart, real_split.paired_sessions) und faellt ebenfalls heraus. Alle bis 2026-10-24 gemeldeten WP137-Zahlen enthielten noch
das zweite Handy Block 1 bis 3 (Datenleck, hier behoben). Ausgabe wie words_measure.py: Treffer bei gleicher FA/h (Ziel 2/h, Kreuz-Auswahl nach
cv_pick, Wilson-Intervall), je Geraet, Stufe 1 („-“) und Stufe 2 (hw2). FA/h auf neg_huawei/neg_handy2 (echt), syn und fleurs.
Dazu synthetische Verwechsler: Seed-Satz aus gen_samples (conf_v8-Texte) mit den macOS-Stimmen aus gen_say_test.py. Disjunkt zum
Training sind nur die Stimmen (macOS nur in der Messung); die TEXTE stammen aus derselben CONF_V8-Liste wie im Training und
ueberdecken sie also. Die Rate je Clip misst daher Stimm-Verallgemeinerung, nicht unbekannte Woerter.
Reproduktion: Der Plan haengt nur von Seed und n ab; die Trainingsdaten dagegen von NJ (run_v8.sh, Seeds sb+1..sb+NJ, n/NJ
abgerundet): NJ gehoert zur Reproduktionsbedingung und steht im Ergebnis.

Venv wie words_measure.py (K=~/wendelin-models/kws):
  nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/v8_measure.py \\
      --model v8a=$K/wp130/out/wendelin_wp130_a.onnx [--model name=pfad ...] [--no-s2] [--report-only]
v7 ($K/wp58/out/wendelin_v7.onnx) ist immer dabei (--no-v7 schaltet ab). Cache und Ergebnis unter $K/wp130/results
(s1/, s2/, conf_say/, v8_grid.csv, v8_table.md); nie im Repo. Fehlt im Cache etwas, wird nur das nachgerechnet.
--split all (WP133): alle Bloecke beider Geraete, nur v7 und Modelle mit <modell>.meta.json real_pos=0 (run_v8.sh REAL_POS=0); Ausgabe
v8_table_all.md/v8_grid_all.csv, Caches gemeinsam (s1/s2 sind je Quelle ueber das ganze Band gerechnet: pos_<geraet> = ganze Aufnahme).
Selbsttest: test_v8_measure.py.
"""
import argparse, csv, hashlib, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np
import real_split as R
import words_measure as W
import station_measure as S

SR = W.SR
KWS = W.KWS
RES = os.environ.get("WENDELIN_WP130_RES") or f"{KWS}/wp130/results"
V7 = f"{KWS}/wp58/out/wendelin_v7.onnx"
WORDS = ["Wendelin", "Hey Wendelin"]                     # beide deckt dasselbe Modell ab; sie unterscheiden sich in Labels und Stufe 2
DEVICES = W.DEVICES
STAGES = ["-", "hw2"]
CONF_SEED = 9001                                         # Training: Seeds 200 + s (run_v8.sh); hier getrennt
CONF_N = 300
CONF_MAX_S = 2.4                                         # wie gen_samples (Ausreisser verwerfen)
SRCS = [f"pos_{d}" for d in DEVICES] + W.NEG_SRC + ["conf"]
NEG_SRC_ALL = W.NEG_SRC + ["conf"]                       # Quellen, deren Ereignisse in Stufe 2 geprueft werden


# ---------- Split (Pruef-Split aus real_split.py, nichts duplizieren) ----------
SPLITS = ("eval", "all")      # „all“ (WP133): alle Bloecke 1..6 beider Geraete, nur fuer Modelle ohne echte Positive (check_split_models)


def eval_blocks(dev, split="eval"):
    """Bloecke 1..6, die nicht zu den Trainingsdaten gehoeren (real_split.TRAIN_DEVICE/TRAIN_BLOCKS); split="all": alle Bloecke 1..6."""
    if split not in SPLITS: raise SystemExit(f"unbekannter Split: {split!r}")
    return tuple(b for b in range(1, 7) if split == "all" or not (dev == R.TRAIN_DEVICE and b in R.TRAIN_BLOCKS))


def filter_labels(labels, split="eval"):
    """Nur Pruef-Labels der beiden Woerter (labels im Format von words_measure.read_labels). Aufnahmen, die dieselbe Sitzung wie eine
    Trainingsaufnahme sind (real_split.paired_sessions, z. B. das zweite Handy bei Block 1 bis 3), fallen heraus."""
    pairs = {} if split == "all" else R.paired_sessions(labels)
    out = [lb for lb in labels if lb["word"] in WORDS and lb["dev"] in DEVICES and lb["block"] in eval_blocks(lb["dev"], split)
           and (lb["dev"], lb["block"]) not in pairs]
    assert_eval_only(out, split, labels)
    return out


def assert_eval_only(labels, split="eval", ref=None):
    """Fail-closed: ein Trainings-Label in der Messung bricht ab (nur split="all" erlaubt sie), ebenso ein Label, dessen Aufnahme laut ref
    (alle Labels, Standard: labels selbst) dieselbe Sitzung wie eine Trainingsaufnahme ist."""
    if split == "all": return
    pairs = R.paired_sessions(labels if ref is None else ref)
    for lb in labels:
        if lb["dev"] == R.TRAIN_DEVICE and lb["block"] in R.TRAIN_BLOCKS:
            raise SystemExit(f"Trainings-Label in der Messung: {lb['dev']} Block {lb['block']}")
        if (lb["dev"], lb["block"]) in pairs:
            raise SystemExit(f"Label in der Messung ist dieselbe Sitzung wie eine Trainingsaufnahme: {lb['dev']} Block {lb['block']} (= {pairs[(lb['dev'], lb['block'])]})")


def check_split_models(split, models):
    """--split all nur fuer v7 (Pfad = V7) und Modelle, deren Sidecar <modell>.meta.json real_pos == 0 sagt; sonst Abbruch (fail-closed)."""
    if split == "eval": return
    for name, path in models.items():
        if os.path.realpath(path) == os.path.realpath(V7): continue
        try:
            rp = json.load(open(path + ".meta.json")).get("real_pos")
        except (OSError, ValueError, AttributeError):
            raise SystemExit(f"--split all: Sidecar {path}.meta.json fehlt oder ist unlesbar ({name})")
        if not (type(rp) is int and rp == 0):
            raise SystemExit(f"--split all: Modell {name} ist nicht ohne echte Positive trainiert (real_pos={rp!r})")


def folds_for(dev, split="eval"):
    """Kreuz-Auswahl innerhalb des Pruef-Splits: je Block auswaehlen auf den uebrigen, zaehlen auf diesem Block (Leave-one-block-out)."""
    bl = eval_blocks(dev, split)
    return [(tuple(b for b in bl if b != t), (t,)) for t in bl]


# ---------- Verwechsler-Satz (macOS-Stimmen, seed-getrennt) ----------
def conf_plan(n, seed):
    """[(text, cut, stimme, tempo)]: Texte aus gen_samples (conf_v8), Stimmen/Tempi aus gen_say_test; reproduzierbar je Seed."""
    import gen_samples as G
    import gen_say_test as T
    rng = np.random.default_rng(seed)
    out = []
    for _ in range(n):
        text, cut = G.v8_text("conf_v8", rng)
        out.append((text, cut, T.VOICES[int(rng.integers(len(T.VOICES)))], T.RATES[int(rng.integers(len(T.RATES)))]))
    return out


def gen_conf(out, n=CONF_N, seed=CONF_SEED):
    import subprocess, tempfile
    import soundfile as sf
    import gen_samples as G
    import gen_say_test as T
    os.makedirs(out, exist_ok=True)
    meta = {"seed": seed, "n_plan": n, "voices": T.VOICES, "rates": T.RATES}
    total, kept = 0.0, 0
    with tempfile.TemporaryDirectory() as td:
        for i, (text, cut, voice, rate) in enumerate(conf_plan(n, seed)):
            tmp = os.path.join(td, "c.wav")
            T.say(voice, rate, text, tmp)
            x = sf.read(tmp, dtype="float32")[0]
            if cut:
                x = G.cut_first_word(x)
                x = G.trim(x) if x is not None else None
            if x is None or len(x) < 1600 or len(x) > CONF_MAX_S * SR:
                continue
            sf.write(os.path.join(out, f"conf{seed}_{i:04d}.wav"), x, SR, subtype="PCM_16")
            total += len(x) / SR; kept += 1
    meta.update(n=kept, hours=round(total / 3600, 4))
    json.dump(meta, open(os.path.join(out, "meta.json"), "w"))
    return meta


def conf_dir(): return f"{RES}/conf_say"


def conf_names():
    return sorted(f for f in os.listdir(conf_dir()) if f.endswith(".wav")) if os.path.isdir(conf_dir()) else []


# ---------- Daten ----------
def item_names(src): return conf_names() if src == "conf" else W.item_names(src)


def load_item(src, name):
    return W.K.load(f"{conf_dir()}/{name}") if src == "conf" else W.load_item(src, name)


def hours(src):
    if src == "conf":
        return json.load(open(f"{conf_dir()}/meta.json"))["hours"]
    return W.src_hours(src)


def sha8(path): return hashlib.sha256(open(path, "rb").read()).hexdigest()[:8]


# ---------- Stufe 1 ----------
CACHE_TAG = {}                                           # Modellname -> Cache-Ordner (Name + Pruefsumme: neues Modell = neuer Cache)


def ctag(tag): return CACHE_TAG.get(tag, tag)


def s1_path(tag, src): return f"{RES}/s1/{ctag(tag)}/{src}.npz"


def seed_v7(tag, path, src):
    """v7-Kurven aus dem WP121-Cache uebernehmen (gleiche Fenster, gleiche Quellen), statt neu zu rechnen."""
    old = f"{W.OUT}/s1/oww/{src}.npz"
    if src == "conf" or os.path.realpath(path) != os.path.realpath(V7) or not os.path.exists(old):
        return
    z = np.load(old)
    d = {}
    for k in z.files:
        if k.endswith("|t"): d[k] = z[k]
        elif k.endswith("|v7"): d[k[:-3] + "|s"] = z[k]
    os.makedirs(os.path.dirname(s1_path(tag, src)), exist_ok=True)
    np.savez_compressed(s1_path(tag, src), **d)


def run_s1(models):
    """models: {tag: pfad}. Wertekurven je Fenster -> s1/<tag>/<src>.npz (Schluessel „<item>|t“ und „<item>|s“)."""
    import onnxruntime as ort
    pad = lambda x: np.concatenate([np.zeros(SR, "float32"), x, np.zeros(SR, "float32")])
    af, sess = None, {}
    for src in SRCS:
        for tag, path in models.items():
            if not os.path.exists(s1_path(tag, src)): seed_v7(tag, path, src)
        todo = [t for t in models if not os.path.exists(s1_path(t, src))]
        if not todo: continue
        if af is None: af = S.Oww(next(iter(models.values()))).af
        for t in todo:
            if t not in sess:
                so_ = ort.SessionOptions(); so_.intra_op_num_threads = 1
                sess[t] = ort.InferenceSession(models[t], so_, providers=["CPUExecutionProvider"])
        d, t0 = {t: {} for t in todo}, time.time()
        for name in item_names(src):
            emb = S.C.embed(af, [pad(load_item(src, name))])[0]
            n = len(emb) - S.C.WIN + 1
            if n <= 0: continue
            Wn = np.stack([emb[j:j + S.C.WIN] for j in range(n)]).astype("float32")
            tt = ((np.array([S.C.window_end(j) for j in range(n)]) - SR) / SR).astype("float32")
            for t in todo:
                d[t][f"{name}|t"] = tt
                d[t][f"{name}|s"] = sess[t].run(None, {"input": Wn})[0][:, 0].astype("float32")
        for t in todo:
            os.makedirs(os.path.dirname(s1_path(t, src)), exist_ok=True)
            np.savez_compressed(s1_path(t, src), **d[t])
        print(f"s1 {src}: {', '.join(todo)}, {time.time() - t0:.0f} s", flush=True)


def load_curves(tag):
    out = {}
    for src in SRCS:
        z = np.load(s1_path(tag, src))
        out[src] = {k[:-2]: (z[k], z[k[:-2] + "|s"]) for k in z.files if k.endswith("|t")}
    return out


def events_at(curves, thr):
    """{src: {item: [Zeit]}} fuer eine Schwelle (words_measure.score_events, Sperrzeit 1,5 s)."""
    return {src: {i: W.score_events(t, v, thr) for i, (t, v) in d.items()} for src, d in curves.items()}


# ---------- Stufe 2 (hw2) ----------
def s2_path(tag, word): return f"{RES}/s2/{ctag(tag)}/hw2@{W.key(word)}.json"


def candidates(curves):
    """seg_keys aller Ereignisse ueber alle Schwellen (Konfigurationen mit zu vielen Negativ-Kandidaten wie in words_measure uebersprungen)."""
    cand = set()
    for thr in W.OWW_THR:
        ev = events_at(curves, thr)
        if sum(len(ts) for s in NEG_SRC_ALL for ts in ev[s].values()) > W.MAX_CAND: continue
        cand.update(W.seg_key(s, i, t) for s, d in ev.items() for i, ts in d.items() for t in ts)
    return cand


def run_s2(models, curves, threads):
    for w in WORDS: S.WORDS.setdefault(W.key(w), {})["hot"] = W.SPEC[w]["hot"]
    S.WORK111 = f"{RES}/hw"
    os.makedirs(S.WORK111, exist_ok=True)
    for tag, path in models.items():
        cand = candidates(curves[tag])
        for w in WORDS:
            p = s2_path(tag, w)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            have = json.load(open(p)) if os.path.exists(p) else {}
            old = f"{W.OUT}/s2/hw2@{W.key(w)}.json"
            if not have and os.path.realpath(path) == os.path.realpath(V7) and os.path.exists(old):
                have = {k: v for k, v in json.load(open(old)).items() if k in cand}      # gleiche Segmente, gleicher Erkenner
            todo = sorted(k for k in cand if k not in have)
            print(f"s2 {tag}/{w}: {len(todo)} neue Segmente (von {len(cand)})", flush=True)
            if not todo: json.dump(have, open(p, "w")); continue
            rec = S.make_rec(f"parakeet-hw2@{W.key(w)}", threads)
            by_item = {}
            for k in todo:
                src, item, _ = k.split("|")
                by_item.setdefault((src, item), []).append(k)
            t_dump = time.time()
            for (src, item), ks in by_item.items():
                x = load_item(src, item)
                for k in ks: have[k] = S.decode(rec, W.segment(x, k).astype("float32"))
                if time.time() - t_dump > 120: json.dump(have, open(p, "w")); t_dump = time.time()
            json.dump(have, open(p, "w"))
            del rec


# ---------- Auswertung ----------
def rows_for_cfg(tag, word, thr, stage, ev, tx, hr, labels):
    """Zeilen (je Geraet) fuer ein Modell x Wort x Schwelle x Stufe; words_measure.rows_for plus Verwechsler-Zahlen.
    ev: {src: {item: [Zeit]}}, tx: seg_key -> Stufe-2-Text (fehlender Schluessel = KeyError)."""
    def passes(src, item, t):
        return True if stage == "-" else W.MATCH[word](tx[W.seg_key(src, item, t)], 2)

    fa = {s: sum(passes(s, i, t) for i, ts in ev[s].items() for t in ts) for s in W.NEG_SRC}
    rows = W.rows_for(word, tag, thr, stage, ev, passes, fa, hr, labels)
    cd = ev["conf"]
    ce = {i: sum(passes("conf", i, t) for t in ts) for i, ts in cd.items()}
    for r in rows:
        r.update(conf_n=len(cd), conf_hit=sum(v > 0 for v in ce.values()), conf_ev=sum(ce.values()), conf_h=hr["conf"])
    return rows


def grid(models, curves, labels, hr):
    rows = []
    for tag in models:
        tx = {w: (json.load(open(s2_path(tag, w))) if os.path.exists(s2_path(tag, w)) else None) for w in WORDS}
        for thr in W.OWW_THR:
            ev = events_at(curves[tag], thr)
            for w in WORDS:
                for stage in STAGES:
                    if stage != "-" and tx[w] is None: continue
                    try:
                        rows += rows_for_cfg(tag, w, thr, stage, ev, tx[w], hr, labels)
                    except KeyError:
                        continue                         # Stufe 2 fuer diese Konfiguration unvollstaendig (zu viele Kandidaten)
    return rows


def cv_cell(rows, dev, word, tag, stages, calib, target, split="eval"):
    """-> (hit, n, [Konfiguration je Fold]) mit Kreuz-Auswahl im Pruef-Split; None, wenn keine Zeile oder FA-Grenze nie eingehalten."""
    pts = sorted((W.calib_point(r, calib) for r in rows
                  if r["dev"] == dev and r["word"] == word and r["prog"] == tag and r["stage2"] in stages),
                 key=lambda p: (p["stage2"] == "-", -p["ord"]))
    if not pts: return None
    folds = folds_for(dev, split)
    if split != "all": folds = [f for f in folds if any(pts[0][f"n_b{b}"] for b in f[1])]     # Bloecke ohne Pruef-Labels (gepaarte Sitzung) zaehlen nicht als Fold
    return W.cv_pick(pts, pts[0]["hours"], target, folds)


def cfg_key(r): return f"{r['prog']}{r['thr']}+{r['stage2']}"


def rate(a, b): return W.fc(f"{a / b:.1f}") if b else "-"


def render(rows, models, target, hr, split="eval"):
    stage_sets = [("Stufe 1 (-)", ("-",)), ("Stufe 2 (hw2)", ("hw2",)), ("beste Wahl (-/hw2)", ("-", "hw2"))]
    scope = ("Alle Blöcke: Huawei Block 1–6, handy2 Block 1–6 (nur Modelle ohne echte Positive und v7). " if split == "all" else
             "Prüf-Split: Huawei Block 4–6, handy2 Block 1–6 (Huawei Block 1–3 sind Training und werden nicht gewertet). ")
    out = [f"# Wake-Word v8: Messung auf {'allen Blöcken' if split == 'all' else 'dem Prüf-Split'} (Ziel {W.fc(target)} FA/h)", "",
           scope + "Auswahl der "
           "Schwelle (und Stufe) je Block auf den übrigen Prüf-Blöcken, Zählung auf dem ausgelassenen Block; Wilson 95 %. "
           f"Modelle: {', '.join(models)}. Negativstunden: "
           + ", ".join(f"{s} {W.fc(hr[s])} h" for s in W.NEG_SRC) + f"; Verwechsler {W.fc(hr['conf'])} h. "
           "„keine Konfiguration ≤ Ziel“: keine Schwelle hält die FA-Grenze (Ziel × Negativstunden, abgerundet) ein.", ""]
    by_cfg = {(r["dev"], r["word"], cfg_key(r)): r for r in rows}
    for calib, title in (("real", "Kalibrierung echte Negativ-Aufnahme des Geräts"), ("syn", "Kalibrierung syn + fleurs")):
        out += [f"## Treffer, {title}", "", "| Gerät | Wort | Modell | " + " | ".join(n for n, _ in stage_sets) + " |", "|---|---|---|---|---|---|"]
        for dev in DEVICES:
            for w in WORDS:
                for tag in models:
                    cells = []
                    for _, st in stage_sets:
                        c = cv_cell(rows, dev, w, tag, st, calib, target, split)
                        cells.append("keine Konfiguration ≤ Ziel" if c is None or c[0] is None else W.fmt_hit(c[0], c[1]))
                    out.append(f"| {dev} | {w} | {tag} | " + " | ".join(cells) + " |")
        out.append("")
    out += ["## Arbeitspunkte (Kalibrierung echt) und Verwechsler", "",
            "| Gerät | Wort | Modell | Stufe | Konfiguration | FA/h echt | FA/h syn | FA/h fleurs | Verwechsler-Clips mit Ereignis | Ereignisse/h Verwechsler |",
            "|---|---|---|---|---|---|---|---|---|---|"]
    for dev in DEVICES:
        for w in WORDS:
            for tag in models:
                for sname, st in stage_sets[:2]:
                    c = cv_cell(rows, dev, w, tag, st, "real", target, split)
                    for k in dict.fromkeys(c[2] if c and c[2] else []):
                        r = by_cfg.get((dev, w, k))
                        if r is None: continue
                        out.append(f"| {dev} | {w} | {tag} | {sname} | {k[len(tag):]} | {rate(r['fa_real'], r['h_real'])} | {rate(r['fa_syn'], r['h_syn'])} | "
                                   f"{rate(r['fa_fleurs'], r['h_fleurs'])} | {W.fmt_hit(r['conf_hit'], r['conf_n'])} | {rate(r['conf_ev'], r['conf_h'])} |")
    return "\n".join(out) + "\n"


def out_names(split):
    sfx = "_all" if split == "all" else ""
    return f"{RES}/v8_grid{sfx}.csv", f"{RES}/v8_table{sfx}.md"


def write_outputs(rows, models, target, hr, split="eval"):
    os.makedirs(RES, exist_ok=True)
    keys = sorted({k for r in rows for k in r})
    csv_p, md_p = out_names(split)
    with open(csv_p, "w", newline="") as fh:
        wr = csv.DictWriter(fh, fieldnames=keys); wr.writeheader(); wr.writerows(rows)
    open(md_p, "w").write(render(rows, models, target, hr, split))


def parse_models(specs, with_v7=True):
    models = {"v7": V7} if with_v7 else {}
    for s in specs:
        name, sep, path = s.partition("=")
        if not sep or not name or any(c in name for c in " +|/"): raise SystemExit(f"--model name=pfad erwartet: {s!r}")
        models[name] = os.path.expanduser(path)
    for n, p in models.items():
        if not os.path.exists(p): raise SystemExit(f"Modell {n} fehlt: {p}")
        CACHE_TAG[n] = f"{n}-{sha8(p)}"
    return models


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", action="append", default=[], help="name=pfad (mehrfach)")
    ap.add_argument("--no-v7", action="store_true"); ap.add_argument("--no-s2", action="store_true")
    ap.add_argument("--report-only", action="store_true", help="nur aus dem Cache auswerten")
    ap.add_argument("--target", type=float, default=2.0, help="FA/h")
    ap.add_argument("--conf-n", type=int, default=CONF_N); ap.add_argument("--conf-seed", type=int, default=CONF_SEED)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--split", choices=SPLITS, default="eval",
                    help="eval = Prüf-Split (Standard); all = alle Blöcke, nur v7 und Modelle mit Sidecar real_pos=0")
    a = ap.parse_args()
    models = parse_models(a.model, not a.no_v7)
    check_split_models(a.split, models)
    if not conf_names():
        print("Verwechsler:", gen_conf(conf_dir(), a.conf_n, a.conf_seed), flush=True)
    if not a.report_only:
        run_s1(models)
    curves = {t: load_curves(t) for t in models}
    if not a.report_only and not a.no_s2:
        run_s2(models, curves, a.threads)
    labels = filter_labels(W.read_labels(), a.split)
    hr = {s: hours(s) for s in W.NEG_SRC + ["conf"]}
    rows = grid(models, curves, labels, hr)
    write_outputs(rows, models, a.target, hr, a.split)
    print(f"{len(rows)} Zeilen -> {out_names(a.split)[1]}")


if __name__ == "__main__":
    main()
