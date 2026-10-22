#!/usr/bin/env python3
"""WP133 Teil A: Nutzen von Stufe 2 (Parakeet-Hotword hw2) am Stufe-1-Arbeitspunkt.

Baut auf v8_measure.py auf (gleicher Pruef-Split, gleiche Kurven- und Stufe-2-Caches, Kreuz-Auswahl 2 FA/h mit Wilson-Intervall).
Am Stufe-1-Arbeitspunkt (Kreuz-Auswahl, Kalibrierung echt, je Geraet/Wort/Fold) zaehlt es
  (1) echte Rufe, die Stufe 1 trifft und hw2 verwirft, nach Kategorie (leer / Schreibvariante / abgeschnitten / anderes Wort / Hey fehlt);
  (2) Ereignisse je Quelle (echt, syn, fleurs, conf), die hw2 herausfiltert.
Dazu Varianten der Stufe-2-Regel (austauschbar, siehe VARIANTS): app (heute), locker_d3 / locker_cp (toleranter Abgleich),
hey_opt (Hey Wendelin akzeptiert auch reines Wendelin), band (Stufe 2 nur unter einer Obergrenze des Stufe-1-Spitzenwerts) und
ausschnitt (laengerer Vor-/Nachlauf, neu dekodiert, nur Schwellen >= 0.9, eigener Cache s2x/),
whisper_de (Whisper small, language=de, ein Decode je Segment fuer beide Woerter, Cache s2w/) und hw4 (Parakeet-Hotword-Score 4, Cache s2h/),
beide gleicher Ausschnitt wie hw2, nur Modell v8a und Schwellen >= 0.95, je auch mit Band (_band999 / _band995). app_ge09 ist die Kontrolle fuer
ausschnitt (gleiche Schwellen, heutiger Ausschnitt).

Ausgabe nur lokal (nie im Repo): $RES/stage2_table.md (Zahlen) und $RES/stage2_lost.local.md (Transkripte).
Lauf (K=~/wendelin-models/kws, vorher `memory_pressure | tail -1`: frei >= 30 %):
  nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/stage2_analysis.py --model v8a=$K/wp130/out/wendelin_wp130_a.onnx --threads 2
Selbsttest: test_stage2_analysis.py.
"""
import argparse, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np
import kws_measure as K
import words_measure as W
import station_measure as S
import v8_measure as V

SR = W.SR
CATS = ["leer", "Schreibvariante", "abgeschnitten", "anderes Wort", "Hey fehlt"]
PRE_X, TAIL_X = 3.0, 1.8                       # Ausschnitt-Variante: Vorlauf/Nachlauf in s (heute 2,0 / 0,9)
X_THR_MIN = 0.9                                # nur Segmente an Schwellen >= 0.9 werden neu dekodiert
E_THR_MIN = 0.95                               # whisper_de / hw4: nur Segmente an Schwellen >= 0.95
E_TAGS = ("v8a",)                              # whisper_de / hw4 nur fuer dieses Modell
WH_NAME, HW4_NAME = "whisper-small", "parakeet-hw4.0"          # station_measure.make_rec (Whisper mit language="de"; Hotword-Score 4)


# ---------- Reine Regeln ----------
def cp_near(s):
    """Koelner-Praefix: Wort mit w/v/f, >= 5 Zeichen, dessen Koelner Code (>= 4 Stellen) Anfang des Codes von „wendelin“ ist."""
    c = K.cologne(s)
    return len(s) >= 5 and s[0] in "wvf" and len(c) >= 4 and K.WAKE_KEY.startswith(c)


def d3_near(s):
    """Editierabstand <= 3 zu „wendelin“ (ab 7 Zeichen, w/v/f vorn)."""
    return len(s) >= 7 and s[0] in "wvf" and K.dist(s, "wendelin") <= 3


def no_extra(s): return False


def match_name(text, hey, extra=no_extra):
    """Spiegel von kws_measure.matches_wake_word (hey=False) bzw. matches_hey_wake_word (hey=True) mit max_dist 2;
    `extra(token)` ist eine zusaetzliche, tolerantere Namens-Regel (ODER). Mit no_extra identisch zur App-Regel."""
    w = K.fold(text).split()
    near = lambda s, single: K.near_wake_word(s, 2, single) or extra(s)
    for i in range(len(w)):
        if not hey:
            if near(w[i], True): return True
            if i + 1 < len(w) and w[i + 1] not in K.NOT_SPLIT_TAIL and near(w[i] + w[i + 1], False): return True
        else:
            if w[i] in K.HEY_WORDS and i + 1 < len(w):
                if near(w[i + 1], True): return True
                if i + 2 < len(w) and w[i + 2] not in K.NOT_SPLIT_TAIL and near(w[i + 1] + w[i + 2], False): return True
            for h in ("hey", "hei"):
                if w[i].startswith(h) and len(w[i]) > len(h) + 4 and near(w[i][len(h):], True): return True
    return False


def rule_app(word, text): return match_name(text, word == "Hey Wendelin")


def rule_loose(extra):
    return lambda word, text: match_name(text, word == "Hey Wendelin", extra)


def rule_hey_opt(word, text):
    """„Hey Wendelin“ akzeptiert auch einen reinen Wendelin-Treffer (Hey fehlt oder wurde nicht erkannt)."""
    return match_name(text, False) or (word == "Hey Wendelin" and match_name(text, True))


# Variante -> rule(word, text), ceil (Stufe 2 nur wenn Stufe-1-Spitzenwert < ceil, sonst Treffer), Schwellen-Minimum, Cache ("s2"/"s2x")
VARIANTS = {
    "app": dict(rule=rule_app, ceil=None, thr_min=0.0, src="s2"),
    "app_ge09": dict(rule=rule_app, ceil=None, thr_min=X_THR_MIN, src="s2"),
    "locker_d3": dict(rule=rule_loose(d3_near), ceil=None, thr_min=0.0, src="s2"),
    "locker_cp": dict(rule=rule_loose(cp_near), ceil=None, thr_min=0.0, src="s2"),
    "hey_opt": dict(rule=rule_hey_opt, ceil=None, thr_min=0.0, src="s2"),
    "band995": dict(rule=rule_app, ceil=0.995, thr_min=0.0, src="s2"),
    "band999": dict(rule=rule_app, ceil=0.999, thr_min=0.0, src="s2"),
    "ausschnitt": dict(rule=rule_app, ceil=None, thr_min=X_THR_MIN, src="s2x"),
}
# Weitere Stufe-2-Erkenner (eigene Text-Quelle, eigener Cache), je allein und mit Band
for _src, _name in (("wh", "whisper_de"), ("hw4", "hw4")):
    VARIANTS[_name] = dict(rule=rule_app, ceil=None, thr_min=E_THR_MIN, src=_src)
    for _b in (999, 995):
        VARIANTS[f"{_name}_band{_b}"] = dict(rule=rule_app, ceil=_b / 1000, thr_min=E_THR_MIN, src=_src)


def passes_rule(var, word, text, peak):
    """Stufe 2 laesst durch: Band (Spitzenwert >= Obergrenze: Stufe 1 genuegt) oder Regel auf dem Transkript."""
    return (var["ceil"] is not None and peak >= var["ceil"]) or var["rule"](word, text)


def peak_at(t, v, te, refr=W.REFR):
    """Stufe-1-Spitzenwert im Ereignis: Maximum der Kurve im Sperrfenster ab der Ereigniszeit."""
    t, v = np.asarray(t), np.asarray(v)
    m = (t >= te) & (t < te + refr)
    return float(v[m].max()) if m.any() else 0.0


# ---------- Kategorien verworfener Rufe ----------
def _tokens(text):
    w = K.fold(text).split()
    return w + [a + b for a, b in zip(w, w[1:])]


def _cut(s):
    """Anfang oder Ende von „wendelin“ (mind. 3 Zeichen, kuerzer als das Wort)."""
    return 3 <= len(s) < 8 and ("wendelin".startswith(s) or "wendelin".endswith(s))


def categorize(word, text):
    """Kategorie, warum Stufe 2 einen Ruf verwirft (text = Transkript, das die App-Regel NICHT akzeptiert hat):
    leer | Hey fehlt (Name da, Hey nicht; nur „Hey Wendelin“) | Schreibvariante (Name nah, aber ausserhalb der App-Regel)
    | abgeschnitten (Anfang/Ende des Namens, bei „Hey Wendelin“ auch nur Hey) | anderes Wort."""
    if not K.fold(text).split(): return "leer"
    if word == "Hey Wendelin" and match_name(text, False): return "Hey fehlt"
    if match_name(text, word == "Hey Wendelin", lambda s: d3_near(s) or cp_near(s)): return "Schreibvariante"
    if any(_cut(s) for s in _tokens(text)): return "abgeschnitten"
    if word == "Hey Wendelin" and K.fold(text).split()[-1] in K.HEY_WORDS: return "abgeschnitten"      # Name fehlt ganz: Ende abgeschnitten
    return "anderes Wort"


def categorize_all(word, texts):
    """Mehrere Transkripte zu einem Ruf: die aussagekraeftigste Kategorie (Reihenfolge Hey fehlt, Schreibvariante, abgeschnitten, anderes Wort, leer)."""
    cats = {categorize(word, t) for t in texts} or {"leer"}
    for c in ("Hey fehlt", "Schreibvariante", "abgeschnitten", "anderes Wort", "leer"):
        if c in cats: return c


# ---------- Ausschnitt (laengerer Vor-/Nachlauf) ----------
def segment_x(x, k, pre=PRE_X, tail=TAIL_X):
    e = int(k.rsplit("|", 1)[1]) * 160
    return x[max(0, e - int(pre * SR)): e + int(tail * SR)]


def s2x_path(tag, word): return f"{V.RES}/s2x/{V.ctag(tag)}-p{PRE_X}-t{TAIL_X}/hw2@{W.key(word)}.json"


def wh_path(tag):
    """Whisper (de): ein Decode je Segment fuer beide Woerter, daher ein Cache ohne Wort im Dateinamen."""
    return f"{V.RES}/s2w/{V.ctag(tag)}-{WH_NAME}-de/texts.json"


def hw4_path(tag, word): return f"{V.RES}/s2h/{V.ctag(tag)}-{HW4_NAME}/{HW4_NAME}@{W.key(word)}.json"


def ausschnitt_keys(curves, thr_min=X_THR_MIN):
    """seg_keys der Ereignisse an Schwellen >= thr_min (Konfigurationen mit zu vielen Negativ-Kandidaten wie in v8_measure uebersprungen)."""
    cand = set()
    for thr in W.OWW_THR:
        if thr < thr_min: continue
        ev = V.events_at(curves, thr)
        if sum(len(ts) for s in V.NEG_SRC_ALL for ts in ev[s].values()) > W.MAX_CAND: continue
        cand.update(W.seg_key(s, i, t) for s, d in ev.items() for i, ts in d.items() for t in ts)
    return cand


def run_s2x(models, curves, threads):
    for w in V.WORDS: S.WORDS.setdefault(W.key(w), {})["hot"] = W.SPEC[w]["hot"]
    S.WORK111 = f"{V.RES}/hw"
    os.makedirs(S.WORK111, exist_ok=True)
    for tag in models:
        cand = ausschnitt_keys(curves[tag])
        for w in V.WORDS:
            p = s2x_path(tag, w)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            have = json.load(open(p)) if os.path.exists(p) else {}
            todo = sorted(k for k in cand if k not in have)
            print(f"s2x {tag}/{w}: {len(todo)} neue Segmente (von {len(cand)})", flush=True)
            if not todo: continue
            rec = S.make_rec(f"parakeet-hw2@{W.key(w)}", threads)
            by_item = {}
            for k in todo:
                src, item, _ = k.split("|")
                by_item.setdefault((src, item), []).append(k)
            t_dump, t0 = time.time(), time.time()
            for (src, item), ks in by_item.items():
                x = V.load_item(src, item)
                for k in ks: have[k] = S.decode(rec, segment_x(x, k).astype("float32"))
                if time.time() - t_dump > 120: json.dump(have, open(p, "w")); t_dump = time.time()
            json.dump(have, open(p, "w"))
            print(f"s2x {tag}/{w}: {time.time() - t0:.0f} s", flush=True)
            del rec


def _decode_into(rec, p, todo, have):
    """Segmente `todo` (gleicher Ausschnitt wie hw2: words_measure.segment) mit rec dekodieren, regelmaessig in p sichern."""
    by_item = {}
    for k in todo:
        src, item, _ = k.split("|")
        by_item.setdefault((src, item), []).append(k)
    t_dump = time.time()
    for (src, item), ks in by_item.items():
        x = V.load_item(src, item)
        for k in ks: have[k] = S.decode(rec, W.segment(x, k).astype("float32"))
        if time.time() - t_dump > 120: json.dump(have, open(p, "w")); t_dump = time.time()
    json.dump(have, open(p, "w"))


def run_extra(models, curves, threads):
    """Whisper (de) und hw4 fuer E_TAGS an Schwellen >= E_THR_MIN; vorhandene Caches bleiben, es werden nur fehlende Segmente ergaenzt."""
    for w in V.WORDS: S.WORDS.setdefault(W.key(w), {})["hot"] = W.SPEC[w]["hot"]
    S.WORK111 = f"{V.RES}/hw"
    os.makedirs(S.WORK111, exist_ok=True)
    for tag in models:
        if tag not in E_TAGS: continue
        cand = ausschnitt_keys(curves[tag], E_THR_MIN)
        jobs = [("whisper_de", wh_path(tag), WH_NAME)] + [(f"hw4/{w}", hw4_path(tag, w), f"{HW4_NAME}@{W.key(w)}") for w in V.WORDS]
        for label, p, recname in jobs:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            have = json.load(open(p)) if os.path.exists(p) else {}
            todo = sorted(k for k in cand if k not in have)
            print(f"{label} {tag}: {len(todo)} neue Segmente (von {len(cand)})", flush=True)
            if not todo: continue
            t0 = time.time()
            rec = S.make_rec(recname, threads)
            _decode_into(rec, p, todo, have)
            print(f"{label} {tag}: {time.time() - t0:.0f} s", flush=True)
            del rec


# ---------- Zeilen je Variante ----------
def variant_rows(tag, word, thr, vname, tx, ev, curves, hr, labels):
    """Zeilen (je Geraet) wie v8_measure.rows_for_cfg, aber mit Variantenregel. KeyError, wenn ein Stufe-2-Text fehlt.
    curves: {Quelle: {Item: (t, v)}} dieses Modells."""
    var = VARIANTS[vname]

    def passes(src, item, t):
        text = tx[W.seg_key(src, item, t)]
        pk = peak_at(*curves[src][item], t) if var["ceil"] is not None else 0.0
        return passes_rule(var, word, text, pk)

    fa = {s: sum(passes(s, i, t) for i, ts in ev[s].items() for t in ts) for s in W.NEG_SRC}
    rows = W.rows_for(word, tag, thr, vname, ev, passes, fa, hr, labels)
    cd = ev["conf"]
    ce = {i: sum(passes("conf", i, t) for t in ts) for i, ts in cd.items()}
    for r in rows:
        r.update(conf_n=len(cd), conf_hit=sum(v > 0 for v in ce.values()), conf_ev=sum(ce.values()), conf_h=hr["conf"])
    return rows


def load_tx(tag):
    """{"s2"/"s2x"/"wh"/"hw4": {Wort: {seg_key: Text} oder None}} aus den Caches (wh: ein Cache fuer beide Woerter)."""
    def ld(p): return json.load(open(p)) if os.path.exists(p) else None
    wh = ld(wh_path(tag))
    return {"s2": {w: ld(V.s2_path(tag, w)) for w in V.WORDS}, "s2x": {w: ld(s2x_path(tag, w)) for w in V.WORDS},
            "wh": {w: wh for w in V.WORDS}, "hw4": {w: ld(hw4_path(tag, w)) for w in V.WORDS}}


def grid(models, curves, labels, hr):
    """Zeilen aller Konfigurationen: Stufe 1 („-“) und jede Variante; dazu Zaehler uebersprungener Konfigurationen."""
    rows, skipped = [], {}
    for tag in models:
        txs = load_tx(tag)
        for thr in W.OWW_THR:
            ev = V.events_at(curves[tag], thr)
            for w in V.WORDS:
                rows += V.rows_for_cfg(tag, w, thr, "-", ev, {}, hr, labels)
                for vn, var in VARIANTS.items():
                    if thr < var["thr_min"]: continue
                    tx = txs[var["src"]][w]
                    if tx is None:
                        skipped[(tag, vn)] = skipped.get((tag, vn), 0) + 1; continue
                    try:
                        rows += variant_rows(tag, w, thr, vn, tx, ev, curves[tag], hr, labels)
                    except KeyError:
                        skipped[(tag, vn)] = skipped.get((tag, vn), 0) + 1
    return rows, skipped


# ---------- Arbeitspunkt: verlorene Rufe und herausgefilterte Ereignisse ----------
def op_thresholds(tag, cfgs):
    """Schwellen je Fold aus den Konfigurationsnamen von cv_pick („<tag><thr>+<stufe>“)."""
    return [float(c[len(tag):].rsplit("+", 1)[0]) for c in cfgs]


def lost_calls(dev, word, thrs, folds, curves, tx, labels, evs):
    """Je Fold: Stufe-1-Treffer auf den Test-Bloecken und davon die von hw2 (App-Regel) verworfenen.
    -> (Zahl Stufe-1-Treffer, [{"block", "thr", "texts", "cat", "rec": {Variante: bool|None}}])
    Verworfen = Stufe 1 trifft im Labelfenster, aber kein Ereignis im Fenster besteht die App-Regel. Fehlt ein Text: KeyError."""
    n1, lost = 0, []
    src = f"pos_{dev}"
    key = lambda t: W.seg_key(src, src, t)
    for thr, (_, test) in zip(thrs, folds):
        dets = evs[thr][src][src]
        for lb in labels:
            if lb["dev"] != dev or lb["word"] != word or lb["block"] not in test: continue
            lo, hi = W.label_window(lb["start"], lb["end"], lb["status"])
            inside = [t for t in dets if lo <= t <= hi]
            if not inside: continue
            n1 += 1
            texts = [tx["s2"][key(t)] for t in inside]
            if any(VARIANTS["app"]["rule"](word, x) for x in texts): continue
            rec = {}
            for vn, var in VARIANTS.items():
                if vn == "app" or thr < var["thr_min"]: continue
                try:
                    rec[vn] = any(passes_rule(var, word, tx[var["src"]][key(t)], peak_at(*curves[src][src], t)) for t in inside)
                except KeyError:
                    rec[vn] = None                                  # Text fehlt
            lost.append({"block": lb["block"], "thr": thr, "texts": texts, "cat": categorize_all(word, texts), "rec": rec})
    return n1, lost


def filtered_events(dev, word, thr, curves, tx, evs):
    """Ereignisse je Quelle bei einer Schwelle: {Quelle: (Stufe 1, von hw2 verworfen, {Variante: davon wieder durchgelassen oder None})}."""
    out = {}
    for src in (f"neg_{dev}", "syn", "fleurs", "conf"):
        n1 = fl = 0
        back = {vn: (None if thr < var["thr_min"] else 0) for vn, var in VARIANTS.items() if vn != "app"}
        for item, ts in evs[thr][src].items():
            for t in ts:
                n1 += 1
                k = W.seg_key(src, item, t)
                if VARIANTS["app"]["rule"](word, tx["s2"][k]): continue
                fl += 1
                for vn, var in VARIANTS.items():
                    if vn == "app" or back[vn] is None: continue
                    try:
                        pk = peak_at(*curves[src][item], t) if var["ceil"] is not None else 0.0
                        back[vn] += passes_rule(var, word, tx[var["src"]][k], pk)
                    except KeyError:
                        back[vn] = None
        out[src] = (n1, fl, back)
    return out


def analyse(models, curves, labels, rows, target):
    """{(Geraet, Wort, Modell): {"n1", "lost", "thrs", "filt"}} am Stufe-1-Arbeitspunkt (Kreuz-Auswahl, Kalibrierung echt)."""
    op = {}
    for tag in models:
        tx = load_tx(tag)
        for dev in V.DEVICES:
            for w in V.WORDS:
                tw = {src: m[w] or {} for src, m in tx.items()}
                basis = "Stufe 1"
                c = V.cv_cell(rows, dev, w, tag, ("-",), "real", target)
                if c is None or c[2] is None:                      # Stufe 1 haelt die FA-Grenze in einem Fold nie ein:
                    basis = "Wahl -/app"                           # Schwellen der Kreuz-Auswahl ueber Stufe 1 und App-Stufe-2
                    c = V.cv_cell(rows, dev, w, tag, ("-", "app"), "real", target)
                if c is None or c[2] is None: continue
                thrs = op_thresholds(tag, c[2])
                evs = {t: V.events_at(curves[tag], t) for t in set(thrs)}
                try:
                    n1, lost = lost_calls(dev, w, thrs, V.folds_for(dev), curves[tag], tw, labels, evs)
                    filt = {t: filtered_events(dev, w, t, curves[tag], tw, evs) for t in sorted(set(thrs))}
                except KeyError as e:
                    print(f"Stufe-2-Text fehlt fuer {tag}/{dev}/{w}: {e}", flush=True)
                    continue
                op[(dev, w, tag)] = {"basis": basis, "n1": n1, "lost": lost, "thrs": thrs, "filt": filt}
    return op


# ---------- Ausgabe ----------
def render(rows, models, target, op, skipped):
    """Zahlen-Tabellen (keine Transkripte)."""
    vn_all = list(VARIANTS)
    out = [f"# Stufe-2-Analyse (WP133 A): Prüfsplit, Ziel {W.fc(target)} FA/h, Kalibrierung echt", "",
           "Auswahl der Schwelle je Block auf den übrigen Prüf-Blöcken, Zählung auf dem ausgelassenen Block (Leave-one-block-out), Wilson 95 %. "
           "Stufe-1-Arbeitspunkt = Kreuz-Auswahl nur über Stufe 1. Modelle: " + ", ".join(models) + ".", ""]
    out += ["## 1. Echte Rufe: Stufe 1 trifft, hw2 (App-Regel) verwirft", "",
            "| Gerät | Wort | Modell | Schwellen aus | Stufe-1-Treffer | von hw2 verworfen | " + " | ".join(CATS) + " |", "|---|---|---|---|---|---|" + "---|" * len(CATS)]
    for (dev, w, tag), o in op.items():
        cnt = {c: sum(x["cat"] == c for x in o["lost"]) for c in CATS}
        out.append(f"| {dev} | {w} | {tag} | {o['basis']} | {o['n1']} | {len(o['lost'])} | " + " | ".join(str(cnt[c]) for c in CATS) + " |")
    out += ["", "## 2. Ereignisse, die hw2 herausfiltert (bei den Schwellen der Folds)", "",
            "| Gerät | Wort | Modell | Schwelle | Quelle | Stufe-1-Ereignisse | von hw2 verworfen |", "|---|---|---|---|---|---|---|"]
    for (dev, w, tag), o in op.items():
        for thr, f in o["filt"].items():
            for src, (n1, fl, _) in f.items():
                out.append(f"| {dev} | {w} | {tag} | {W.fc(thr)} | {src} | {n1} | {fl} |")
    out += ["", "## 3. Varianten am Arbeitspunkt: zurückgeholte Rufe und wieder durchgelassene Ereignisse", "",
            "Zurück = verworfene echte Rufe, die die Variante annimmt. Wieder = von hw2 (App) verworfene Ereignisse, die die Variante durchlässt "
            "(Summe über die Schwellen der Folds, je Quelle). „-“: Texte fehlen oder Schwelle unter dem Minimum der Variante.", "",
            "| Gerät | Wort | Modell | Variante | zurück | wieder echt-neg | wieder syn | wieder fleurs | wieder conf |", "|---|---|---|---|---|---|---|---|---|"]
    for (dev, w, tag), o in op.items():
        for vn in vn_all:
            if vn == "app": continue
            rec = [x["rec"].get(vn) for x in o["lost"]]
            back = "-" if any(r is None for r in rec) else f"{sum(rec)}/{len(rec)}"
            cols = []
            for src in (f"neg_{dev}", "syn", "fleurs", "conf"):
                vals = [f[src][2][vn] for f in o["filt"].values()]
                cols.append("-" if any(v is None for v in vals) else str(sum(vals)))
            out.append(f"| {dev} | {w} | {tag} | {vn} | {back} | " + " | ".join(cols) + " |")
    alone = [("Stufe 1", ("-",))] + [(f"{vn} allein", (vn,)) for vn in vn_all]
    best = [(f"beste Wahl -/{vn}", ("-", vn)) for vn in vn_all]
    out += ["", "## 4. Treffer je Variante (Kreuz-Auswahl, Kalibrierung echt)", ""]
    for part, ss in (("Stufe 1 und Stufe 2 allein", alone), ("beste Wahl Stufe 1 oder Variante", best)):
        out += [f"### {part}", "", "| Gerät | Wort | Modell | " + " | ".join(n for n, _ in ss) + " |", "|---|---|---|" + "---|" * len(ss)]
        for dev in V.DEVICES:
            for w in V.WORDS:
                for tag in models:
                    cells = []
                    for _, st in ss:
                        c = V.cv_cell(rows, dev, w, tag, st, "real", target)
                        cells.append("keine Konfiguration ≤ Ziel" if c is None or c[0] is None else W.fmt_hit(c[0], c[1]))
                    out.append(f"| {dev} | {w} | {tag} | " + " | ".join(cells) + " |")
        out.append("")
    out += ["## 5. Arbeitspunkte (beste Wahl -/Variante): FA/h echt, syn, fleurs, Verwechsler-Clips", "",
            "| Gerät | Wort | Modell | Variante | Konfiguration | FA/h echt | FA/h syn | FA/h fleurs | Verwechsler-Clips mit Ereignis |", "|---|---|---|---|---|---|---|---|---|"]
    by_cfg = {(r["dev"], r["word"], V.cfg_key(r)): r for r in rows}
    for dev in V.DEVICES:
        for w in V.WORDS:
            for tag in models:
                for vn in vn_all:
                    c = V.cv_cell(rows, dev, w, tag, ("-", vn), "real", target)
                    for k in dict.fromkeys(c[2] if c and c[2] else []):
                        r = by_cfg.get((dev, w, k))
                        if r is None: continue
                        out.append(f"| {dev} | {w} | {tag} | {vn} | {k[len(tag):]} | {V.rate(r['fa_real'], r['h_real'])} | {V.rate(r['fa_syn'], r['h_syn'])} | "
                                   f"{V.rate(r['fa_fleurs'], r['h_fleurs'])} | {W.fmt_hit(r['conf_hit'], r['conf_n'])} |")
    if skipped:
        out += ["", "Übersprungene Konfigurationen (Stufe-2-Texte fehlen oder zu viele Kandidaten): " +
                ", ".join(f"{t}/{v}: {n}" for (t, v), n in sorted(skipped.items()))]
    return "\n".join(out) + "\n"


def render_lost(op):
    """Lokale Datei mit Transkripten (nie ins Repo, nie zitieren)."""
    out = ["# Verlorene Rufe mit Transkript (nur lokal, nie ins Repo, nie zitieren)", ""]
    for (dev, w, tag), o in op.items():
        out += [f"## {dev} / {w} / {tag}", ""]
        for x in o["lost"]:
            out.append(f"- Block {x['block']}, Schwelle {x['thr']}, {x['cat']}: " + " | ".join(repr(t) for t in x["texts"]))
        out.append("")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", action="append", default=[], help="name=pfad (mehrfach); v7 ist immer dabei")
    ap.add_argument("--no-v7", action="store_true")
    ap.add_argument("--report-only", action="store_true", help="Ausschnitt nicht neu dekodieren")
    ap.add_argument("--target", type=float, default=2.0, help="FA/h")
    ap.add_argument("--threads", type=int, default=2)
    a = ap.parse_args()
    models = V.parse_models(a.model, not a.no_v7)
    curves = {t: V.load_curves(t) for t in models}
    if not a.report_only: run_s2x(models, curves, a.threads); run_extra(models, curves, a.threads)
    labels = V.filter_labels(W.read_labels())
    hr = {s: V.hours(s) for s in W.NEG_SRC + ["conf"]}
    rows, skipped = grid(models, curves, labels, hr)
    op = analyse(models, curves, labels, rows, a.target)
    open(f"{V.RES}/stage2_table.md", "w").write(render(rows, models, a.target, op, skipped))
    open(f"{V.RES}/stage2_lost.local.md", "w").write(render_lost(op))
    print(f"{len(rows)} Zeilen -> {V.RES}/stage2_table.md", flush=True)


if __name__ == "__main__":
    main()
