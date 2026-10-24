#!/usr/bin/env python3
"""WP133 Teil A2: Ausschnitt fuer Stufe 2 (hw2) – Paritaet mit der App und Vor-/Nachlauf.

Die App entscheidet ein Ereignis mit dem Spitzenwert (WP141: Halten ab dem ersten Fenster im Band bis 0,8 s danach, einschliesslich;
candidate_wake_engine `_eventScore`, `holdDuration`) und schneidet [endSample - 2 s, endSample + 0,9 s] am Spitzenfenster; die Messung (words_measure.score_events) nimmt das erste Fenster >= Schwelle.
Hier werden beide Bezugszeiten („erst“, „app“) mit Vorlauf {1,2; 2,0; 2,5} s x Nachlauf {0,9; 1,3; 1,8} s verglichen (hw2 und hw2 auf
Spitze 0,5 normalisiert, je allein und mit Band 0,999), je Modell (Standard v8a), Segmente an Schwellen >= 0.95, eigener Cache s2p/ je Modell (Name+Hash der Modelldatei; Schluessel = seg_key der
Bezugszeit, je Vor-/Nachlauf/Normalisierung ein Ordner). Auswertung wie stage2_analysis: Kreuz-Auswahl mit Wilson, feste Schwelle, FA, Verwechsler.

Obergrenze des Haltens wie in der App (acceptFrom = directThreshold = Band der Stufe 2): Varianten mit Band 0,999 halten bis 0,999 und nehmen
ab dort direkt an; ohne Band prueft Stufe 2 alles, das Halten endet wie in der App bei 0,995 (APP_UPPER). Nur fuer den Ausschnitt der App
(2,0/0,9, Bezug app) gibt es zusaetzlich das heutige Band 0,995. Bezug erst: Spitzenwert = Maximum im Sperrfenster (1,5 s) ab dem ersten Fenster
(Definition der bisherigen Messung, schaut also bis zu 1,5 s voraus; die App entscheidet mit dem gehaltenen Wert).
Nicht nachgebildet (Grenzen der Kurven-Simulation): Pegel-Gate der Engine (mainGate), Sperre des Listeners waehrend der Pruefung (lockout),
Stopp-Regeln, Vorlagen-Regel.

Aufruf ueber stage2_analysis.py --cut-only (siehe dort). Ausgabe nur lokal: $RES/stage2_cut_table.md. Selbsttest: test_stage2_cut.py."""
import json, os, time

import words_measure as W
import station_measure as S
import v8_measure as V
import stage2_analysis as A

SR = W.SR
CUT_TAG = "v8a"                                 # Standardmodell (Dateiname/Cache wie bisher); weitere Modelle ueber den Parameter tag
CUT_THR_MIN = 0.95                              # Stufe-2-Segmente nur an Schwellen >= 0.95
REFS = ("erst", "app")                          # Bezugszeit: erstes Fenster >= Schwelle | Entscheidungsfenster der App (Halten)
PRES = (1.2, 2.0, 2.5)                          # Vorlauf in s
TAILS = (0.9, 1.3, 1.8)                         # Nachlauf in s
APP_PRE, APP_TAIL = 2.0, 0.9                    # Ausschnitt der App (wake_word_listener verifyWindow / verifyTail)
APP_UPPER, APP_HOLD_S = 0.995, 0.8              # WakeClassifierRules.acceptFrom (Stand Branch WP129) / holdWindow (WP141)
APP_HOLD = 11                                   # Alias (Fensterzahl, alte Schreibweise): 11 Fenster = 10 Abstaende = 0,8 s; hold=1 heisst roh
BANDS = (None, 0.999)                           # Band der Stufe 2: keins | 0,999; dazu fuer den App-Ausschnitt 0,995 (APP_UPPER)
NORM_PEAK = 0.5
FIXED_THR = 0.98


# ---------- Reine Funktionen ----------
def app_events(t, v, lower, upper=APP_UPPER, hold_s=APP_HOLD_S, refr=W.REFR, hold=None, flush=True):
    """Nachbildung von CandidateWakeEngine (WP141) auf der Stufe-1-Kurve: [(Spitzenzeit, Spitzenwert)].
    Ab dem ersten Fenster im Band [lower, upper) wird gehalten, bis (Fensterende - erstes Fensterende) >= hold_s (einschliesslich: das
    Fenster bei +hold_s zaehlt noch mit und entscheidet; Vergleich in Samples bei 16 kHz). Abfaelle unter die Spitze oder unter das Band
    und NaN beenden das Halten nicht. Ein Wert >= upper entscheidet sofort mit diesem Wert (direkt). Sonst entscheidet am Ende die
    Spitze (bei gleichen Werten das spaetere Fenster); die Trefferzeit ist das Spitzenfenster. hold_s <= 0 (Alias hold=1): das erste Fenster im Band
    entscheidet. Sperrzeit `refr` von Trefferzeit zu Trefferzeit.
    flush=True (Standard): ein am Kurvenende noch offenes Halten entscheidet mit der Spitze (Spitzenzeit, Spitze), die Sperrzeit gilt wie
    sonst. Das entspricht einem weiterlaufenden Strom mit leisen Fenstern (die App sieht solche Ereignisse, die Kurve eines kurzen Clips
    endet nur frueher). flush=False: unvollstaendiges Halten am Stromende gibt kein Ereignis (so entscheidet die Dart-Engine, Paritaetstest).
    Gleiche Regel wie Dart, Paritaetsfixture packages/wendelin_voice/test/fixtures/wake_hold_parity.json (test_stage2_cut.py)."""
    if hold is not None: hold_s = (hold - 1) * 0.08          # Alias: Fensterzahl inkl. erstem Fenster
    hold_n, refr_n = round(hold_s * SR), round(refr * SR)
    out, last = [], None
    start = pk = pk_t = pk_n = None
    for ti, vi in zip(t, v):
        n = round(float(ti) * SR)
        s = None if vi is None or vi != vi else float(vi)      # NaN/None ist kein Wert
        ev = None                                              # (Zeit, Samples, Wert)
        if start is None:
            if s is None or s < lower: continue
            if s >= upper or hold_n <= 0:
                ev = (float(ti), n, s)
            else:
                start, pk, pk_t, pk_n = n, s, float(ti), n
        elif s is not None and s >= upper:
            ev, start = (float(ti), n, s), None
        else:
            if s is not None and s >= pk: pk, pk_t, pk_n = s, float(ti), n
            if n - start >= hold_n:
                ev, start = (pk_t, pk_n, pk), None
        if ev is None: continue
        if last is not None and ev[1] - last < refr_n: continue
        last = ev[1]
        out.append((ev[0], ev[2]))
    if flush and start is not None and (last is None or pk_n - last >= refr_n):
        out.append((pk_t, pk))
    return out


def events_cut(curves, thr, ref, upper=APP_UPPER):
    """({Quelle: {Item: [Zeit]}}, {(Quelle, Item, seg_key): Spitzenwert}) bei Schwelle thr fuer die Bezugszeit ref (erst | app; upper nur fuer app)."""
    ev, pk = {}, {}
    for src, d in curves.items():
        ev[src] = {}
        for item, (t, v) in d.items():
            if ref == "erst":
                pairs = [(te, A.peak_at(t, v, te)) for te in W.score_events(t, v, thr)]
            elif ref == "app":
                pairs = app_events(t, v, thr, upper)
            else:
                raise ValueError(ref)
            ev[src][item] = [te for te, _ in pairs]
            for te, p in pairs: pk[(src, item, W.seg_key(src, item, te))] = p
    return ev, pk


def vname(ref, pre, tail, norm, band):
    return f"{ref}-{pre}-{tail}" + ("-nm" if norm else "") + (f"-b{round(band * 1000)}" if band else "")


def make_variants():
    """{Name: {ref, pre, tail, norm, band, ceil, upper, app, rule}}; app markiert die Werte der App (2,0/0,9 mit Bezugszeit app);
    upper = Obergrenze des Haltens (nur Bezug app; None bei erst)."""
    out = {}
    for ref in REFS:
        for pre in PRES:
            for tail in TAILS:
                is_app = ref == "app" and (pre, tail) == (APP_PRE, APP_TAIL)
                for norm in (False, True):
                    for band in BANDS + ((APP_UPPER,) if is_app else ()):
                        out[vname(ref, pre, tail, norm, band)] = dict(
                            ref=ref, pre=pre, tail=tail, norm=norm, band=band is not None, ceil=band, app=is_app, rule=A.rule_app,
                            upper=None if ref == "erst" else (band or APP_UPPER))
    return out


VARS = make_variants()


def seg_bounds(k, pre, tail):
    """(von, bis) Abtastwerte des Ausschnitts zum seg_key k (Ende = Fenster-Ende)."""
    e = int(k.rsplit("|", 1)[1]) * 160
    return max(0, e - int(round(pre * SR))), e + int(round(tail * SR))


def cut_path(tag, word, pre, tail, norm):
    nm = f"-nm{NORM_PEAK}" if norm else ""
    return f"{V.RES}/s2p/{V.ctag(tag)}-p{pre}-t{tail}{nm}/hw2@{W.key(word)}.json"


def combos():
    """(pre, tail, norm) in der Reihenfolge: App-Ausschnitt zuerst, dann ohne Normalisierung."""
    cs = [(p, t, n) for n in (False, True) for p in PRES for t in TAILS]
    cs.sort(key=lambda c: (c[:2] != (APP_PRE, APP_TAIL), c[2]))
    return cs


def groups():
    """Ereignismengen der Varianten: (Bezug, Obergrenze des Haltens)."""
    return sorted({(v["ref"], v["upper"]) for v in VARS.values()}, key=lambda g: (g[0], g[1] or 0))


def cut_candidates(curves):
    """seg_keys aller Ereignisse (alle Bezugszeiten/Obergrenzen) an Schwellen >= CUT_THR_MIN; Konfigurationen mit zu vielen Negativ-Kandidaten uebersprungen."""
    cand = set()
    for ref, upper in groups():
        for thr in W.OWW_THR:
            if thr < CUT_THR_MIN: continue
            ev, pk = events_cut(curves, thr, ref, upper or APP_UPPER)
            if sum(len(ts) for s in V.NEG_SRC_ALL for ts in ev[s].values()) > W.MAX_CAND: continue
            cand.update(k[2] for k in pk)
    return cand


def run_cut(curves, threads, tag=CUT_TAG):
    """hw2 je Wort und (Vor-, Nachlauf, Normalisierung) auf allen Kandidaten dekodieren; vorhandene Caches bleiben, nur fehlende Segmente."""
    for w in V.WORDS: S.WORDS.setdefault(W.key(w), {})["hot"] = W.SPEC[w]["hot"]
    S.WORK111 = f"{V.RES}/hw"
    os.makedirs(S.WORK111, exist_ok=True)
    cand = cut_candidates(curves)
    for w in V.WORDS:
        rec = None
        for pre, tail, norm in combos():
            p = cut_path(tag, w, pre, tail, norm)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            have = json.load(open(p)) if os.path.exists(p) else {}
            todo = sorted(k for k in cand if k not in have)
            print(f"s2p {w} p{pre} t{tail} norm={norm}: {len(todo)} neue Segmente (von {len(cand)})", flush=True)
            if not todo: continue
            if rec is None: rec = S.make_rec(f"parakeet-hw2@{W.key(w)}", threads)
            by_item = {}
            for k in todo:
                src, item, _ = k.split("|")
                by_item.setdefault((src, item), []).append(k)
            t0 = t_dump = time.time()
            for (src, item), ks in by_item.items():
                x = V.load_item(src, item)
                for k in ks:
                    a, b = seg_bounds(k, pre, tail)
                    seg = x[a:b].astype("float32")
                    have[k] = S.decode(rec, A.normalize_peak(seg, NORM_PEAK) if norm else seg)
                if time.time() - t_dump > 120: json.dump(have, open(p, "w")); t_dump = time.time()
            json.dump(have, open(p, "w"))
            print(f"s2p {w} p{pre} t{tail} norm={norm}: {time.time() - t0:.0f} s", flush=True)
        del rec


def load_cut_tx(tag=CUT_TAG):
    """{(pre, tail, norm): {Wort: {seg_key: Text} oder None}}."""
    def ld(p): return json.load(open(p)) if os.path.exists(p) else None
    return {c: {w: ld(cut_path(tag, w, *c)) for w in V.WORDS} for c in combos()}


def _passes(var, word, tx, pk):
    """passes(src, item, t) fuer eine Variante; KeyError, wenn ein Text fehlt."""
    txw = tx[(var["pre"], var["tail"], var["norm"])][word]

    def passes(src, item, t):
        k = W.seg_key(src, item, t)
        if txw is None: raise KeyError(k)
        return A.passes_rule(var, word, txw[k], pk[(src, item, k)])
    return passes


# ---------- Zeilen (Kreuz-Auswahl, FA, Verwechsler) ----------
def cut_rows(curves, labels, hr, tx, tag=CUT_TAG):
    """({ref: Zeilen}, uebersprungen): je Bezugszeit Stufe 1 („-“, alle Schwellen) und jede Variante (Schwellen >= CUT_THR_MIN)."""
    rows, skipped = {r: [] for r in REFS}, {}
    for ref in REFS:
        for thr in W.OWW_THR:
            ev, _ = events_cut(curves, thr, ref)                         # Stufe 1 allein: Halten bis 0,995 wie die App
            for w in V.WORDS:
                rows[ref] += A.rows_generic(tag, w, thr, "-", ev, lambda *_: True, hr, labels)
        for upper in sorted({v["upper"] for v in VARS.values() if v["ref"] == ref}, key=lambda u: u or 0):
            for thr in (x for x in W.OWW_THR if x >= CUT_THR_MIN):
                ev, pk = events_cut(curves, thr, ref, upper or APP_UPPER)
                for w in V.WORDS:
                    for n, var in VARS.items():
                        if var["ref"] != ref or var["upper"] != upper: continue
                        try:
                            rows[ref] += A.rows_generic(tag, w, thr, n, ev, _passes(var, w, tx, pk), hr, labels)
                        except KeyError:
                            skipped[n] = skipped.get(n, 0) + 1
    return rows, skipped


# ---------- Feste Schwelle ----------
def cut_fixed(curves, labels, tx, thr=FIXED_THR, refs=REFS, only=None):
    """{(ref, Variante oder "-"): {"hits": {(Geraet, Wort): (Treffer, n) oder None}, "pass": {Wort: {Quelle: Zahl oder None}}, "n": {Wort: {Quelle: Ereignisse}}}}.
    Treffer = Ruf mit einem Ereignis im Labelfenster, das die Variante durchlaesst. refs/only beschraenken Bezugszeiten bzw. Variantennamen ("-" = Stufe 1)."""
    out = {}
    for ref in refs:
        for n in ["-"] + [n for n, v in VARS.items() if v["ref"] == ref]:
            if only is not None and n not in only: continue
            var = None if n == "-" else VARS[n]
            ev, pk = events_cut(curves, thr, ref, APP_UPPER if var is None else (var["upper"] or APP_UPPER))
            res = {"hits": {}, "pass": {}, "n": {}}
            for w in V.WORDS:
                try:
                    ps = (lambda *_: True) if var is None else _passes(var, w, tx, pk)
                    res["pass"][w] = {s: sum(bool(ps(s, i, t)) for i, ts in ev[s].items() for t in ts) for s in A.FIXED_SRC}
                    for dev in V.DEVICES:
                        src = f"pos_{dev}"
                        hit = nn = 0
                        for lb in labels:
                            if lb["dev"] != dev or lb["word"] != w: continue
                            lo, hi = W.label_window(lb["start"], lb["end"], lb["status"])
                            nn += 1
                            hit += any(ps(src, src, t) for t in ev[src][src] if lo <= t <= hi)
                        res["hits"][(dev, w)] = (hit, nn)
                except KeyError:
                    res["pass"][w] = {s: None for s in A.FIXED_SRC}
                    for dev in V.DEVICES: res["hits"][(dev, w)] = None
                res["n"][w] = {s: sum(len(ts) for ts in ev[s].values()) for s in A.FIXED_SRC}
            out[(ref, n)] = res
    return out


# ---------- Ausgabe ----------
def label_of(n):
    if n == "-": return "Stufe 1 allein"
    v = VARS[n]
    return (f"{v['pre']} / {v['tail']}, hw2{'+norm' if v['norm'] else ''}{f" + Band {W.fc(v['ceil'])}" if v['band'] else ''}"
            + (" **(App)**" if v["app"] else ""))


def render_cut(rows, fixed, skipped, target, tag=CUT_TAG):
    """Zahlen-Tabellen (keine Transkripte)."""
    out = [f"# Ausschnitt-Parität und Vor-/Nachlauf (WP133 A2): {tag}, Prüfsplit, Ziel {W.fc(target)} FA/h, Kalibrierung echt", "",
           "Bezug: erst = erstes Fenster ≥ Schwelle (Messung bisher), app = Entscheidungsfenster der App (Halten bis 5 Fenster, Spitzenwert; Obergrenze 0,995). "
           "Variante = Vorlauf / Nachlauf in s. Kreuz-Auswahl (Schwellen 0,95/0,98/0,99) und Wilson 95 % wie stage2_analysis; Stufe 1 allein (alle Schwellen) je Bezug als Referenz. "
           "Nicht nachgebildet: Pegel-Gate, Sperre während der Prüfung, Stopp-Regeln.", ""]
    names = {r: ["-"] + [n for n, v in VARS.items() if v["ref"] == r] for r in REFS}
    cols = [(d, w) for d in V.DEVICES for w in V.WORDS]

    def cell(r, d, w, st):
        c = V.cv_cell(r, d, w, tag, st, "real", target)
        return "keine Konf. ≤ Ziel" if c is None or c[0] is None else W.fmt_hit(c[0], c[1]) if c[1] else "-"

    out += ["## 7a. Treffer (Kreuz-Auswahl, Kalibrierung echt)", "",
            "Je Gerät/Wort: erst die Variante allein, dann beste Wahl Stufe 1 oder Variante („-/V“).", "",
            "| Bezug | Variante | " + " | ".join(f"{d} {w}" for d, w in cols) + " | " + " | ".join(f"{d} {w} (-/V)" for d, w in cols) + " |",
            "|---|---|" + "---|" * (2 * len(cols))]
    for ref in REFS:
        for n in names[ref]:
            alone = [cell(rows[ref], d, w, (n,)) for d, w in cols]
            best = ["-"] * len(cols) if n == "-" else [cell(rows[ref], d, w, ("-", n)) for d, w in cols]
            out.append(f"| {ref} | {label_of(n)} | " + " | ".join(alone) + " | " + " | ".join(best) + " |")
    out += ["", "## 7b. Arbeitspunkte (beste Wahl -/V): FA/h echt, syn, fleurs, Verwechsler-Clips mit Ereignis", "",
            "| Bezug | Variante | Gerät | Wort | Konfiguration | FA/h echt | FA/h syn | FA/h fleurs | Verwechsler-Clips mit Ereignis |", "|---|---|---|---|---|---|---|---|---|"]
    for ref in REFS:
        by = {(r["dev"], r["word"], V.cfg_key(r)): r for r in rows[ref]}
        for n in names[ref][1:]:
            for d in V.DEVICES:
                for w in V.WORDS:
                    c = V.cv_cell(rows[ref], d, w, tag, ("-", n), "real", target)
                    for k in dict.fromkeys(c[2] if c and c[2] else []):
                        r = by.get((d, w, k))
                        if r is None: continue
                        out.append(f"| {ref} | {label_of(n)} | {d} | {w} | {k[len(tag):]} | {V.rate(r['fa_real'], r['h_real'])} | {V.rate(r['fa_syn'], r['h_syn'])} | "
                                   f"{V.rate(r['fa_fleurs'], r['h_fleurs'])} | {W.fmt_hit(r['conf_hit'], r['conf_n'])} |")
    f = lambda x: "-" if x is None else str(x)
    out += ["", f"## 7c. Feste Schwelle {W.fc(FIXED_THR)}: Treffer und durchkommende Ereignisse (Wendelin / Hey Wendelin)", "",
            "„-“: Text fehlt. Treffer = Rufe mit einem Ereignis im Labelfenster, das die Variante durchlässt.", "",
            "| Bezug | Variante | " + " | ".join(f"{d} {w}" for d, w in cols) + " | " + " | ".join(A.FIXED_SRC) + " |", "|---|---|" + "---|" * (len(cols) + len(A.FIXED_SRC))]
    for ref in REFS:
        for n in names[ref]:
            r = fixed[(ref, n)]
            out.append(f"| {ref} | {label_of(n)} | " + " | ".join("-" if r["hits"][c] is None else f"{r['hits'][c][0]}/{r['hits'][c][1]}" for c in cols) + " | "
                       + " | ".join(" / ".join(f(r["pass"][w][s]) for w in V.WORDS) for s in A.FIXED_SRC) + " |")
    if skipped:
        out += ["", "Übersprungene Konfigurationen (Texte fehlen): " + ", ".join(f"{n}: {c}" for n, c in sorted(skipped.items()))]
    return "\n".join(out) + "\n"


def table_path(tag=CUT_TAG):
    """v8a wie bisher stage2_cut_table.md, jedes andere Modell eigene Datei."""
    return f"{V.RES}/stage2_cut_table.md" if tag == CUT_TAG else f"{V.RES}/stage2_cut_table_{tag}.md"


def run_all(curves, labels, hr, target, threads, report_only=False, tag=CUT_TAG, seed_thrs=()):
    """Dekodieren (ausser report_only), auswerten, Tabelle schreiben (table_path). Mit seed_thrs: zusaetzlich
    {thr: cut_fixed(...)} fuer Stufe 1 und App-Ausschnitt mit Band 0,999 (fuer seed_summary), sonst {}."""
    if not report_only: run_cut(curves, threads, tag)
    tx = load_cut_tx(tag)
    rows, skipped = cut_rows(curves, labels, hr, tx, tag)
    fixed = cut_fixed(curves, labels, tx)
    md = render_cut(rows, fixed, skipped, target, tag)
    open(table_path(tag), "w").write(md)
    print(f"-> {table_path(tag)}", flush=True)
    return {thr: cut_fixed(curves, labels, tx, thr, refs=("app",), only=SEED_STAGES) for thr in seed_thrs}


# ---------- Seed-Zusammenfassung ----------
SEED_THRS = (0.95, 0.98, 0.99)
SEED_BAND = vname("app", APP_PRE, APP_TAIL, False, 0.999)       # App-Ausschnitt, hw2 + Band 0,999
SEED_STAGES = ("-", SEED_BAND)


def parse_seed_group(text):
    """'v8a=v8a,a-s2' -> ('v8a', ['v8a', 'a-s2']); Fehler bei fehlendem Namen, leerer Liste und Dubletten."""
    name, sep, tags = text.partition("=")
    ts = [t for t in tags.split(",") if t]
    if not sep or not name or not ts or len(set(ts)) != len(ts): raise ValueError(f"--seed-group name=tag1,tag2 erwartet: {text!r}")
    return name, ts


def seed_values(fixed, hr):
    """Kennzahlen eines Seeds aus cut_fixed-Ergebnis (Bezug app, ein Variantenname): {Kennzahl: Zahl oder None}.
    Treffer je Wort = Rufe mit Treffer / Rufe ueber beide Geraete (in %); Verwechsler = durchkommende conf-Ereignisse (beide Woerter);
    FA/h syn = syn-Ereignisse (beide Woerter) / Stunden; FA/h echt = neg_huawei+neg_handy2 (beide Woerter) / Stunden."""
    out = {}
    for w in V.WORDS:
        hs = [fixed["hits"][(d, w)] for d in V.DEVICES]
        out[f"Treffer {w} [%]"] = None if any(h is None for h in hs) or not sum(h[1] for h in hs) else 100 * sum(h[0] for h in hs) / sum(h[1] for h in hs)
    ps = [fixed["pass"][w] for w in V.WORDS]
    if any(p[s] is None for p in ps for s in A.FIXED_SRC):
        out.update({"Verwechsler (Ereignisse)": None, "FA/h syn": None, "FA/h echt": None})
    else:
        real_h = hr["neg_huawei"] + hr["neg_handy2"]
        out["Verwechsler (Ereignisse)"] = sum(p["conf"] for p in ps)
        out["FA/h syn"] = sum(p["syn"] for p in ps) / hr["syn"]
        out["FA/h echt"] = sum(p["neg_huawei"] + p["neg_handy2"] for p in ps) / real_h
    return out


SEED_METRICS = [f"Treffer {w} [%]" for w in V.WORDS] + ["Verwechsler (Ereignisse)", "FA/h syn", "FA/h echt"]


def seed_summary(groups, per_tag, hr):
    """Markdown-Abschnitt. groups = [(Name, [Tags])], per_tag = {Tag: {thr: cut_fixed-Ergebnis}}. Je Gruppe, Schwelle und Stufe
    (Stufe 1 | + Band 0,999): Mittel ueber die Seeds und Min–Max; fehlt ein Wert bei einem Seed, steht „-“ (kein stilles Weglassen)."""
    f = lambda x: W.fc(f"{x:.1f}") if abs(x - round(x)) > 1e-9 else str(int(round(x)))
    out = ["## 8. Seed-Zusammenfassung (App-Ausschnitt 2,0 / 0,9, Bezug app, feste Schwelle)", "",
           "Mittel [Min–Max] über die Seeds der Gruppe; Treffer = Rufe über beide Geräte im Prüf-Split, Verwechsler = durchkommende Ereignisse (Clips „conf“), "
           "FA/h über beide Wörter. „Band“ = Stufe 1 + hw2 mit Band 0,999. Mit nur wenigen Seeds ist Min–Max grob, kein Konfidenzintervall.", "",
           "| Gruppe | Seeds | Schwelle | Stufe | " + " | ".join(SEED_METRICS) + " |", "|---|---|---|---|" + "---|" * len(SEED_METRICS)]
    for name, tags in groups:
        for thr in SEED_THRS:
            for st, lab in (("-", "Stufe 1"), (SEED_BAND, "Band 0,999")):
                vals = []
                for t in tags:
                    r = per_tag.get(t, {}).get(thr)
                    vals.append(seed_values(r[("app", st)], hr) if r is not None else dict.fromkeys(SEED_METRICS))
                cells = []
                for m in SEED_METRICS:
                    xs = [v[m] for v in vals]
                    cells.append("-" if any(x is None for x in xs) else f"{f(sum(xs) / len(xs))} [{f(min(xs))}–{f(max(xs))}]")
                out.append(f"| {name} | {len(tags)} | {W.fc(thr)} | {lab} | " + " | ".join(cells) + " |")
    return "\n".join(out) + "\n"
