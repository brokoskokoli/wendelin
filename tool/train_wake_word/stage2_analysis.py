#!/usr/bin/env python3
"""WP133 Teil A: Nutzen von Stufe 2 (Parakeet-Hotword hw2) am Stufe-1-Arbeitspunkt.

Baut auf v8_measure.py auf (gleicher Pruef-Split, gleiche Kurven- und Stufe-2-Caches, Kreuz-Auswahl 2 FA/h mit Wilson-Intervall).
Am Stufe-1-Arbeitspunkt (Kreuz-Auswahl, Kalibrierung echt, je Geraet/Wort/Fold) zaehlt es
  (1) echte Rufe, die Stufe 1 trifft und hw2 verwirft, nach Kategorie (leer / Schreibvariante / abgeschnitten / anderes Wort / Hey fehlt);
  (2) Ereignisse je Quelle (echt, syn, fleurs, conf), die hw2 herausfiltert.
Dazu Varianten der Stufe-2-Regel (austauschbar, siehe VARIANTS): app (heute), locker_d3 / locker_cp (toleranter Abgleich),
hey_opt (Hey Wendelin akzeptiert auch reines Wendelin), band (Stufe 2 nur unter einer Obergrenze des Stufe-1-Spitzenwerts) und
ausschnitt (laengerer Vor-/Nachlauf, neu dekodiert, nur Schwellen >= 0.9, eigener Cache s2x/),
norm (hw2 auf dem vorher auf Spitze 0,5 normalisierten Ausschnitt, Cache s2e/), hw3 (Hotword-Score 3) und blank1 / blank2 (hw2 mit sherpa-onnx blank_penalty 1,0 / 2,0)
sind drei weitere Quellen wie hw4 (eigener Cache s2e/ mit den Parametern im Pfad, nur v8a, Schwellen >= 0.95, je allein und mit Band),
whisper_de (Whisper small, language=de, ein Decode je Segment fuer beide Woerter, Cache s2w/) und hw4 (Parakeet-Hotword-Score 4, Cache s2h/),
beide gleicher Ausschnitt wie hw2, nur Modell v8a und Schwellen >= 0.95, je auch mit Band (_band999 / _band995). app_ge09 ist die Kontrolle fuer
ausschnitt (gleiche Schwellen, heutiger Ausschnitt).

Abschnitt 6 der Ausgabe zaehlt bei fester Stufe-1-Schwelle (--fixed-thr, Komma-Liste, Standard 0.98) je Modell (bei --split all ohne v8a) echte Rufe und Verwechsler je Spitzenwert-Band
sowie Treffer und durchkommende Ereignisse je Variante (keine, app, band999, band995, whisper_de, hw4, norm, hw3, blank1, blank2 je auch mit Band), nur aus den Caches.

Ausschnitt-Paritaet mit der App (Bezugszeit „app“ = Halten) und Vor-/Nachlauf: eigener Lauf mit --cut-only, Logik und Doku in stage2_cut.py (Ausgabe stage2_cut_table.md).
Ausgabe nur lokal (nie im Repo): $RES/stage2_table.md (Zahlen) und $RES/stage2_lost.local.md (Transkripte);
mit --split all (alle Bloecke 1..6, nur v7 und Modelle mit Sidecar real_pos=0, Abschnitt 6 je Modell ausser v8a) stage2_table_all.md / stage2_lost_all.local.md.
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
# Weitere Stufe-2-Quellen: Variante -> (Quelle, Cache-Name mit Parametern, make_rec-Name, Normalisierungs-Spitze oder None, blank_penalty)
EXTRA = {
    "norm": ("nm", "hw2-norm0.5", "parakeet-hw2", 0.5, 0.0),
    "hw3": ("h3", "parakeet-hw3.0", "parakeet-hw3", None, 0.0),
    "blank1": ("b1", "hw2-bp1.0", "parakeet-hw2", None, 1.0),
    "blank2": ("b2", "hw2-bp2.0", "parakeet-hw2", None, 2.0),
}
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
for _src, _name in (("wh", "whisper_de"), ("hw4", "hw4")) + tuple((v[0], k) for k, v in EXTRA.items()):
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


def extra_path(tag, vname, word):
    """Cache der EXTRA-Quellen; Parameter (Normalisierung, Score, blank_penalty) stehen im Namen, kein Wort-Teil kollidiert mit s2/ s2x/ s2h/."""
    label = EXTRA[vname][1]
    return f"{V.RES}/s2e/{V.ctag(tag)}-{label}/{label}@{W.key(word)}.json"


def normalize_peak(x, peak=0.5):
    """Ausschnitt auf Betrags-Spitze `peak` skalieren (Stille bleibt unveraendert)."""
    x = np.asarray(x, "float32")
    m = float(np.abs(x).max()) if x.size else 0.0
    return x if m <= 0 else (x * (peak / m)).astype("float32")


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


def _decode_into(rec, p, todo, have, norm=None):
    """Segmente `todo` (gleicher Ausschnitt wie hw2: words_measure.segment) mit rec dekodieren, regelmaessig in p sichern."""
    by_item = {}
    for k in todo:
        src, item, _ = k.split("|")
        by_item.setdefault((src, item), []).append(k)
    t_dump = time.time()
    for (src, item), ks in by_item.items():
        x = V.load_item(src, item)
        for k in ks:
            seg = W.segment(x, k).astype("float32")
            have[k] = S.decode(rec, seg if norm is None else normalize_peak(seg, norm))
        if time.time() - t_dump > 120: json.dump(have, open(p, "w")); t_dump = time.time()
    json.dump(have, open(p, "w"))


def run_extra(models, curves, threads):
    """Whisper (de), hw4 und die EXTRA-Quellen (norm, hw3, blank) fuer E_TAGS an Schwellen >= E_THR_MIN; vorhandene Caches bleiben, es werden nur fehlende Segmente ergaenzt."""
    for w in V.WORDS: S.WORDS.setdefault(W.key(w), {})["hot"] = W.SPEC[w]["hot"]
    S.WORK111 = f"{V.RES}/hw"
    os.makedirs(S.WORK111, exist_ok=True)
    for tag in models:
        if tag not in E_TAGS: continue
        cand = ausschnitt_keys(curves[tag], E_THR_MIN)
        jobs = [("whisper_de", wh_path(tag), WH_NAME, None, 0.0)] + [(f"hw4/{w}", hw4_path(tag, w), f"{HW4_NAME}@{W.key(w)}", None, 0.0) for w in V.WORDS]
        jobs += [(f"{vn}/{w}", extra_path(tag, vn, w), f"{e[2]}@{W.key(w)}", e[3], e[4]) for vn, e in EXTRA.items() for w in V.WORDS]
        for label, p, recname, norm, bp in jobs:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            have = json.load(open(p)) if os.path.exists(p) else {}
            todo = sorted(k for k in cand if k not in have)
            print(f"{label} {tag}: {len(todo)} neue Segmente (von {len(cand)})", flush=True)
            if not todo: continue
            t0 = time.time()
            rec = S.make_rec(recname, threads, blank_penalty=bp)
            _decode_into(rec, p, todo, have, norm)
            print(f"{label} {tag}: {time.time() - t0:.0f} s", flush=True)
            del rec


# ---------- Zeilen je Variante ----------
def rows_generic(tag, word, thr, vname, ev, passes, hr, labels):
    """Zeilen (je Geraet) wie v8_measure.rows_for_cfg fuer beliebiges passes(src, item, t) -> bool (KeyError, wenn ein Stufe-2-Text fehlt)."""
    fa = {s: sum(passes(s, i, t) for i, ts in ev[s].items() for t in ts) for s in W.NEG_SRC}
    rows = W.rows_for(word, tag, thr, vname, ev, passes, fa, hr, labels)
    cd = ev["conf"]
    ce = {i: sum(passes("conf", i, t) for t in ts) for i, ts in cd.items()}
    for r in rows:
        r.update(conf_n=len(cd), conf_hit=sum(v > 0 for v in ce.values()), conf_ev=sum(ce.values()), conf_h=hr["conf"])
    return rows


def variant_rows(tag, word, thr, vname, tx, ev, curves, hr, labels):
    """Zeilen (je Geraet) wie v8_measure.rows_for_cfg, aber mit Variantenregel. KeyError, wenn ein Stufe-2-Text fehlt.
    curves: {Quelle: {Item: (t, v)}} dieses Modells."""
    var = VARIANTS[vname]

    def passes(src, item, t):
        text = tx[W.seg_key(src, item, t)]
        pk = peak_at(*curves[src][item], t) if var["ceil"] is not None else 0.0
        return passes_rule(var, word, text, pk)

    return rows_generic(tag, word, thr, vname, ev, passes, hr, labels)


def load_tx(tag):
    """{"s2"/"s2x"/"wh"/"hw4"/EXTRA-Quellen: {Wort: {seg_key: Text} oder None}} aus den Caches (wh: ein Cache fuer beide Woerter)."""
    def ld(p): return json.load(open(p)) if os.path.exists(p) else None
    wh = ld(wh_path(tag))
    return {"s2": {w: ld(V.s2_path(tag, w)) for w in V.WORDS}, "s2x": {w: ld(s2x_path(tag, w)) for w in V.WORDS},
            "wh": {w: wh for w in V.WORDS}, "hw4": {w: ld(hw4_path(tag, w)) for w in V.WORDS},
            **{e[0]: {w: ld(extra_path(tag, vn, w)) for w in V.WORDS} for vn, e in EXTRA.items()}}


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


def analyse(models, curves, labels, rows, target, split="eval"):
    """{(Geraet, Wort, Modell): {"n1", "lost", "thrs", "filt"}} am Stufe-1-Arbeitspunkt (Kreuz-Auswahl, Kalibrierung echt)."""
    op = {}
    for tag in models:
        tx = load_tx(tag)
        for dev in V.DEVICES:
            for w in V.WORDS:
                tw = {src: m[w] or {} for src, m in tx.items()}
                basis = "Stufe 1"
                c = V.cv_cell(rows, dev, w, tag, ("-",), "real", target, split)
                if c is None or c[2] is None:                      # Stufe 1 haelt die FA-Grenze in einem Fold nie ein:
                    basis = "Wahl -/app"                           # Schwellen der Kreuz-Auswahl ueber Stufe 1 und App-Stufe-2
                    c = V.cv_cell(rows, dev, w, tag, ("-", "app"), "real", target, split)
                if c is None or c[2] is None: continue
                thrs = op_thresholds(tag, c[2])
                evs = {t: V.events_at(curves[tag], t) for t in set(thrs)}
                try:
                    n1, lost = lost_calls(dev, w, thrs, V.folds_for(dev, split), curves[tag], tw, labels, evs)
                    filt = {t: filtered_events(dev, w, t, curves[tag], tw, evs) for t in sorted(set(thrs))}
                except KeyError as e:
                    print(f"Stufe-2-Text fehlt fuer {tag}/{dev}/{w}: {e}", flush=True)
                    continue
                op[(dev, w, tag)] = {"basis": basis, "n1": n1, "lost": lost, "thrs": thrs, "filt": filt}
    return op


# ---------- Feste Stufe-1-Schwelle: Spitzenwert-Baender, Treffer und durchkommende Ereignisse ----------
FIXED_THR = 0.98
FIXED_VARIANTS = ("-", "app", "band999", "band995", "whisper_de", "hw4") + tuple(f"{v}{b}" for v in EXTRA for b in ("", "_band999", "_band995"))            # "-" = Stufe 1 allein
FIXED_SRC = ("neg_huawei", "neg_handy2", "syn", "fleurs", "conf")
BAND_EDGES = (0.995, 0.999)
BAND_NAMES = ("thr-0,995", "0,995-0,999", ">=0,999")


def band_of(peak):
    """Band des Spitzenwerts: 0 = [thr, 0.995), 1 = [0.995, 0.999), 2 = >= 0.999 (Stufe 1 ist ein Modell fuer beide Woerter)."""
    return sum(peak >= e for e in BAND_EDGES)


def fixed_pass(vn, word, tx, src, key, peak, thr):
    """Laesst die Variante das Ereignis durch? None, wenn die Schwelle unter dem Minimum liegt oder der Text fehlt."""
    if vn == "-": return True
    var = VARIANTS[vn]
    if thr < var["thr_min"]: return None
    t = tx[var["src"]][key] if vn == "app" else tx.get(var["src"], {}).get(key)           # hw2-Text muss da sein (KeyError), andere Quellen: None
    return None if t is None else passes_rule(var, word, t, peak)


def fixed_calls(dev, word, thr, curves, tx, labels, evs, vnames=FIXED_VARIANTS):
    """Echte Prueflabels eines Geraets/Wortes bei fester Schwelle (Ereignis im Labelfenster wie lost_calls).
    -> {"bands": [[Rufe, davon hw2 besteht] je Band] + "miss" (nicht erkannt), "hits": {Variante: Treffer oder None}, "n": Rufe}.
    Spitzenwert = Maximum ueber die Ereignisse im Fenster; hw2 besteht, wenn ein Ereignis im Fenster die App-Regel besteht."""
    src = f"pos_{dev}"
    res = {"bands": [[0, 0] for _ in BAND_NAMES], "miss": 0, "n": 0, "hits": {vn: 0 for vn in vnames}}
    for lb in labels:
        if lb["dev"] != dev or lb["word"] != word: continue
        lo, hi = W.label_window(lb["start"], lb["end"], lb["status"])
        inside = [t for t in evs[thr][src][src] if lo <= t <= hi]
        res["n"] += 1
        if not inside:
            res["miss"] += 1; continue
        pk = {t: peak_at(*curves[src][src], t) for t in inside}
        b = res["bands"][band_of(max(pk.values()))]
        b[0] += 1
        b[1] += any(fixed_pass("app", word, tx, src, W.seg_key(src, src, t), pk[t], thr) for t in inside)
        for vn in vnames:
            r = [fixed_pass(vn, word, tx, src, W.seg_key(src, src, t), pk[t], thr) for t in inside]
            res["hits"][vn] = None if res["hits"][vn] is None or None in r else res["hits"][vn] + any(r)
    return res


def fixed_events(word, thr, curves, tx, evs, vnames=FIXED_VARIANTS):
    """Ereignisse bei fester Schwelle je Quelle. -> {"conf_bands": [[Ereignisse, davon hw2 besteht] je Band],
    "pass": {Variante: {Quelle: durchkommende Ereignisse oder None}}, "n": {Quelle: Ereignisse}}."""
    out = {"conf_bands": [[0, 0] for _ in BAND_NAMES], "pass": {vn: {s: 0 for s in FIXED_SRC} for vn in vnames}, "n": {}}
    for s in FIXED_SRC:
        out["n"][s] = 0
        for item, ts in evs[thr][s].items():
            for t in ts:
                out["n"][s] += 1
                key, pk = W.seg_key(s, item, t), peak_at(*curves[s][item], t)
                if s == "conf":
                    b = out["conf_bands"][band_of(pk)]
                    b[0] += 1; b[1] += bool(fixed_pass("app", word, tx, s, key, pk, thr))
                for vn in vnames:
                    r = fixed_pass(vn, word, tx, s, key, pk, thr)
                    cur = out["pass"][vn][s]
                    out["pass"][vn][s] = None if cur is None or r is None else cur + r
    return out


def fixed_analysis(curves, tx_all, labels, thr):
    """{(Geraet, Wort): fixed_calls, Wort: fixed_events} fuer ein Modell aus Kurven und Caches. KeyError bei fehlendem hw2-Text."""
    evs = {thr: V.events_at(curves, thr)}
    out = {}
    for w in V.WORDS:
        tx = {src: m[w] or {} for src, m in tx_all.items()}
        for dev in V.DEVICES: out[(dev, w)] = fixed_calls(dev, w, thr, curves, tx, labels, evs)
        out[w] = fixed_events(w, thr, curves, tx, evs)
    return out


def render_fixed(fx, thr, tag="v8a"):
    """Abschnitt 6 (nur Zahlen) fuer ein Modell."""
    f = lambda v: "-" if v is None else str(v)
    out = ["", f"## 6. Feste Schwelle {W.fc(thr)} ({tag}, nur Zahlen aus den Caches)", "",
           "Ereignis = Stufe-1-Wert über der Schwelle, Spitzenwert = Maximum im Ereignis, Band wie bei Stufe 2 mit Obergrenze. Echte Rufe: Ereignis im Labelfenster; "
           "„hw2 besteht“ = ein Ereignis im Fenster besteht die App-Regel. „-“ = Text fehlt oder Schwelle unter dem Minimum der Variante.", "",
           "### 6a. Echte Prüf-Rufe je Spitzenwert-Band", "", "| Gerät | Wort | Rufe | " + " | ".join(f"{b} (davon hw2)" for b in BAND_NAMES) + " | nicht erkannt |", "|---|---|---|---|---|---|---|"]
    tot = [[0, 0] for _ in BAND_NAMES]; tn = tm = 0
    for dev in V.DEVICES:
        for w in V.WORDS:
            c = fx[(dev, w)]
            out.append(f"| {dev} | {w} | {c['n']} | " + " | ".join(f"{b[0]} ({b[1]})" for b in c["bands"]) + f" | {c['miss']} |")
            tn += c["n"]; tm += c["miss"]
            for t, b in zip(tot, c["bands"]): t[0] += b[0]; t[1] += b[1]
    out.append(f"| Summe | beide | {tn} | " + " | ".join(f"{b[0]} ({b[1]})" for b in tot) + f" | {tm} |")
    out += ["", "### 6b. Verwechsler-Ereignisse (conf) je Band", "", "| Band | Ereignisse | hw2 besteht " + V.WORDS[0] + " | hw2 besteht " + V.WORDS[1] + " |"]
    out.append("|---|---|---|---|")
    for i, b in enumerate(BAND_NAMES):
        out.append(f"| {b} | {fx[V.WORDS[0]]['conf_bands'][i][0]} | " + " | ".join(str(fx[w]["conf_bands"][i][1]) for w in V.WORDS) + " |")
    out += ["", "### 6c. Treffer je Variante (feste Schwelle, Rufe mit Ereignis im Labelfenster)", "",
            "| Variante | " + " | ".join(f"{d} {w}" for d in V.DEVICES for w in V.WORDS) + " |", "|---|" + "---|" * (len(V.DEVICES) * len(V.WORDS))]
    for vn in FIXED_VARIANTS:
        out.append(f"| {vn} | " + " | ".join(f"{f(fx[(d, w)]['hits'][vn])}/{fx[(d, w)]['n']}" for d in V.DEVICES for w in V.WORDS) + " |")
    out += ["", "### 6d. Ereignisse, die durchkommen, je Quelle (Wendelin / Hey Wendelin)", "",
            "| Variante | " + " | ".join(FIXED_SRC) + " |", "|---|" + "---|" * len(FIXED_SRC),
            "| Stufe-1-Ereignisse | " + " | ".join(str(fx[V.WORDS[0]]["n"][s]) for s in FIXED_SRC) + " |"]
    for vn in FIXED_VARIANTS:
        out.append(f"| {vn} | " + " | ".join(" / ".join(f(fx[w]["pass"][vn][s]) for w in V.WORDS) for s in FIXED_SRC) + " |")
    return "\n".join(out) + "\n"


OVERVIEW_VARIANTS = ("-", "app", "band999")


def render_fixed_overview(fxs):
    """6e: Modelle bei fester Schwelle. fxs = {(Modell, Schwelle): fixed_analysis}. Treffer = Summe ueber Geraete und Woerter, HW = nur Hey Wendelin;
    Verwechsler/syn/echt = durchkommende Ereignisse W/HW (gleiche Zahl: einmal); echt = neg_huawei + neg_handy2."""
    pair = lambda a, b: "-" if a is None or b is None else (str(a) if a == b else f"{a}/{b}")
    out = ["", "## 6e. Modelle bei fester Schwelle", "",
           "Treffer = echte Prüf-Rufe mit Ereignis im Labelfenster, durchgelassen von der Variante (Summe über Geräte und Wörter, davon Hey Wendelin). "
           "Verwechsler, syn, echt = durchkommende Ereignisse (Wendelin/Hey Wendelin, bei gleicher Zahl einmal); echt = beide Negativgeräte. „-“ = Text fehlt oder Schwelle unter dem Minimum.", "",
           "| Modell | Schwelle | Variante | Treffer | davon Hey Wendelin | Verwechsler | syn | echt |", "|---|---|---|---|---|---|---|---|"]
    for (tag, thr), fx in fxs.items():
        for vn in OVERVIEW_VARIANTS:
            hits = [fx[(d, w)]["hits"][vn] for d in V.DEVICES for w in V.WORDS]
            hw = [fx[(d, V.WORDS[1])]["hits"][vn] for d in V.DEVICES]
            n = sum(fx[(d, w)]["n"] for d in V.DEVICES for w in V.WORDS)
            tot = lambda xs: None if None in xs else sum(xs)
            ev = lambda srcs: pair(*[tot([fx[w]["pass"][vn][s] for s in srcs]) for w in V.WORDS])
            out.append(f"| {tag} | {W.fc(thr)} | {vn} | {'-' if tot(hits) is None else tot(hits)}/{n} | {'-' if tot(hw) is None else tot(hw)} | "
                       f"{ev(('conf',))} | {ev(('syn',))} | {ev(('neg_huawei', 'neg_handy2'))} |")
    return "\n".join(out) + "\n"


# ---------- Ausgabe ----------
def render(rows, models, target, op, skipped, split="eval"):
    """Zahlen-Tabellen (keine Transkripte)."""
    vn_all = list(VARIANTS)
    scope = ("alle Blöcke (Huawei und handy2 Block 1–6; nur Modelle ohne echte Positive und v7)" if split == "all" else "Prüfsplit")
    out = [f"# Stufe-2-Analyse (WP133 A): {scope}, Ziel {W.fc(target)} FA/h, Kalibrierung echt", "",
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
                        c = V.cv_cell(rows, dev, w, tag, st, "real", target, split)
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
                    c = V.cv_cell(rows, dev, w, tag, ("-", vn), "real", target, split)
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


def out_names(split):
    sfx = "_all" if split == "all" else ""
    return f"{V.RES}/stage2_table{sfx}.md", f"{V.RES}/stage2_lost{sfx}.local.md"


def parse_thrs(text):
    """'0.95,0.98' -> [0.95, 0.98] (Reihenfolge bleibt, Dubletten entfallen)."""
    try: v = [float(x) for x in text.split(",")]
    except ValueError: raise argparse.ArgumentTypeError(f"keine Zahlenliste: {text!r}")
    return list(dict.fromkeys(v))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", action="append", default=[], help="name=pfad (mehrfach); v7 ist immer dabei")
    ap.add_argument("--no-v7", action="store_true")
    ap.add_argument("--report-only", action="store_true", help="Ausschnitt nicht neu dekodieren")
    ap.add_argument("--target", type=float, default=2.0, help="FA/h")
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--cut-only", action="store_true", help="nur Ausschnitt-Paritaet/Vor-/Nachlauf (stage2_cut.py, v8a), Ausgabe stage2_cut_table.md")
    ap.add_argument("--split", choices=V.SPLITS, default="eval",
                    help="eval = Prüf-Split (Standard); all = alle Blöcke 1–6, nur v7 und Modelle mit Sidecar real_pos=0 (Abschnitt 6 je Modell ohne v8a, Ausgabe *_all)")
    ap.add_argument("--fixed-thr", type=parse_thrs, default=[FIXED_THR], help="feste Stufe-1-Schwellen fuer Abschnitt 6, Komma-Liste (Standard 0.98)")
    a = ap.parse_args()
    models = V.parse_models(a.model, not a.no_v7)
    if a.cut_only and a.split != "eval": sys.exit("--cut-only gibt es nur mit --split eval")
    V.check_split_models(a.split, models)
    if a.cut_only:
        import stage2_cut as C
        if C.CUT_TAG not in models: sys.exit("--cut-only braucht --model v8a=<pfad>")
        C.run_all(V.load_curves(C.CUT_TAG), V.filter_labels(W.read_labels()), {s: V.hours(s) for s in W.NEG_SRC + ["conf"]}, a.target, a.threads, a.report_only)
        return
    curves = {t: V.load_curves(t) for t in models}
    if not a.report_only: run_s2x(models, curves, a.threads); run_extra(models, curves, a.threads)
    labels = V.filter_labels(W.read_labels(), a.split)
    hr = {s: V.hours(s) for s in W.NEG_SRC + ["conf"]}
    rows, skipped = grid(models, curves, labels, hr)
    op = analyse(models, curves, labels, rows, a.target, a.split)
    md = render(rows, models, a.target, op, skipped, a.split)
    fxs = {}
    for tag in models:
        if tag == "v8a" and a.split == "all": continue      # v8a hat echte Positive (real_pos > 0): nicht auf allen Bloecken
        tx = load_tx(tag)
        for thr in a.fixed_thr:
            fxs[(tag, thr)] = fixed_analysis(curves[tag], tx, labels, thr)
            md += render_fixed(fxs[(tag, thr)], thr, tag)
    if len(fxs) > 1: md += render_fixed_overview(fxs)
    tbl, lost = out_names(a.split)
    open(tbl, "w").write(md)
    open(lost, "w").write(render_lost(op))
    print(f"{len(rows)} Zeilen -> {tbl}", flush=True)


if __name__ == "__main__":
    main()
