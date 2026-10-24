#!/usr/bin/env python3
"""WP134 Nachbesserung: (1) Zentrier-Mittel V2b auf ZURUECKGEHALTENEN Stroemen pruefen, (2) calibrateThreshold nachrechnen.

(1) Das feste Mittel V2b enthaelt die synthetischen Stroeme aus template_center_measure.sources()["synth"] (Seed 134: Stille, weiss 3/10/30,
rosa 10/100). Auf genau diesen wurde „Stille/Rauschen unter der Schwelle“ gemessen (Datenleck). Hier: andere Seeds, andere Pegel und Farben
(weiss 1/5/100/300, rosa 3/30/300, braun 10/50, blau 10, 50-Hz-Brummen, Dither-Stille) und echter Raumton (die leisesten 5-s-Stuecke der
Negativ-Aufnahmen, ohne Sprache), gemessen mit V2b (Ist), V2b-sep (Mittel aus getrennt erzeugtem Rauschen, anderer Seed/Pegel) und V2 (nur Sprache).
(2) calibrateThreshold (wake_calibration.dart) in Python: 14 Vorlagen (Rauschpolster, V2b), Hintergrund leiser Raum / Negativ-Aufnahmen / Fernseher
(FLEURS test, erste 0,5 h), Positive = Leave-one-out (+ „Antworten“ aus handy2 Block 1-3, nicht Teil der sauberen Pruefmenge); Treffer auf der sauberen Menge.

  nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/template_center_holdout.py --threads 2 [--out <ordner>]
"""
import argparse, os, sys, time, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import template_center_measure as m

SLOT = 24000          # 1,5 s wie WakeCalibrator._slot
EVENT_FLOOR, PROMPT_FLOOR, MAX_THR, MIN_THR, QUANTILE = 0.3, 0.4, 0.90, 0.40, 0.1
UNCONSTRAINED_MAX = 0.50  # wakeUnconstrainedMaxThreshold


def holdout_sources():
    """Zurueckgehaltene synthetische Stroeme (anderer Seed als sources()["synth"], andere Pegel und Farben)."""
    rng = np.random.default_rng(4242)
    n = 120 * m.SR
    d = {"dither": np.round(rng.uniform(-1, 1, n)).astype("int16")}
    for lvl in (1, 5, 100, 300):
        d[f"weiss{lvl}"] = m.to16(rng.normal(0, lvl, n) / 32767)
    for lvl in (3, 30, 300):
        d[f"rosa{lvl}"] = m.to16(m.colored(n, 1.0, rng) * lvl / 32767)
    for lvl in (10, 50):
        d[f"braun{lvl}"] = m.to16(m.colored(n, 2.0, rng) * lvl / 32767)
    d["blau10"] = m.to16(m.colored(n, -1.0, rng) * 10 / 32767)
    t = np.arange(n) / m.SR
    d["brummen20"] = m.to16((20 * (np.sin(2 * np.pi * 50 * t) + 0.5 * np.sin(2 * np.pi * 100 * t)) + rng.normal(0, 3, n)) / 32767)
    return d


def separate_noise_mean_sources():
    """Anderes Rauschen fuer ein getrennt gefittetes Mittel (Seed 777, Pegel 2/20/60, rosa 5/50)."""
    rng = np.random.default_rng(777)
    n = 120 * m.SR
    d = {"stille": np.zeros(n, "int16")}
    for lvl in (2, 20, 60):
        d[f"weiss{lvl}"] = m.to16(rng.normal(0, lvl, n) / 32767)
    for lvl in (5, 50):
        d[f"rosa{lvl}"] = m.to16(m.colored(n, 1.0, rng) * lvl / 32767)
    return d


def quiet_segments(dev, k=10, seg=5 * m.SR):
    """Die k leisesten 5-s-Stuecke der Negativ-Aufnahme (kleinster RMS; Sprache hebt den RMS) -> ({name: int16}, [rms])."""
    x = m.to16(m.load16(f"{m.WORK121}/neg_{dev}.wav"))
    n = len(x) // seg
    rms = np.array([np.sqrt(np.mean(x[i * seg:(i + 1) * seg].astype("float64") ** 2)) for i in range(n)])
    pick = np.argsort(rms)[:k]
    return {f"{dev}{i}": x[i * seg:(i + 1) * seg] for i in sorted(pick)}, [float(rms[i]) for i in sorted(pick)]


def slot_events(t, v):
    """Spitze je 1,5-s-Slot ab EVENT_FLOOR (wie WakeCalibrator._closeSlot)."""
    best = {}
    for ti, vi in zip(t, v):
        s = int(round(ti * m.SR)) // SLOT
        if vi > best.get(s, -1): best[s] = float(vi)
    return [b for b in best.values() if b >= EVENT_FLOOR]


def calibrate(pos, neg, hours, target=1.0):
    """calibrateThreshold + Deckelung auf MAX_THR wie WakeCalibrator._conclude -> (thr, recall, fa/h)."""
    pos, neg = sorted(pos), sorted(neg)
    allowed = int(np.floor(target * hours))
    if len(neg) <= allowed:
        thr = pos[int(np.floor((len(pos) - 1) * QUANTILE))]
        thr = min(thr, UNCONSTRAINED_MAX)  # WP134: kein Ereignis erzwingt mehr -> nie ueber die vorlaeufige Schwelle
    else:
        thr = neg[len(neg) - allowed - 1] + 1e-6
        if pos: thr = max(thr, min(pos[int(np.floor((len(pos) - 1) * QUANTILE))], UNCONSTRAINED_MAX))  # Review R2/B: schwaches Ereignis senkt nicht unter min(Quantil, 0,50)
    thr = min(max(thr, MIN_THR), MAX_THR)
    return thr, sum(p >= thr for p in pos) / len(pos), sum(n >= thr for n in neg) / hours


def outlier_report(x, train_rows, info, G, loo):
    """Schwaechste Vorlage (kleinstes zentriertes LOO): Label, Nullanteil, Pegel, beste Nachbarn. Nur Ausgabe, keine Datenaenderung."""
    i = int(np.argmin(loo))
    inf = info[i]
    cand = [r for r in train_rows if int(r["block"]) == inf["block"] and int(r["runde"]) == inf["runde"]]
    r = cand[0] if len(cand) == 1 else None
    log = print
    log(f"Ausreisser-Vorlage #{i}: LOO {loo[i]:.2f}, naechste Nachbarn {np.sort(G[i])[-3:][::-1].round(2).tolist()}, info {inf}; Zeilen mit Block/Runde: {len(cand)}")
    if r is not None:
        a, b, _ = m.capture_bounds(x, float(r["start"]), float(r["ende"]))
        seg = m.to16(x[a:b]).astype("float64")
        lead = seg[:3200]
        # Pegel Wort / erste 200 ms (Raumton) in LSB, Sprachanteil der Dauer
        log(f"  Label: {dict((k, r[k]) for k in r if k not in ('datei',))}; Dauer {float(r['ende']) - float(r['start']):.2f} s; "
            f"RMS Ausschnitt {np.sqrt((seg**2).mean()):.0f} LSB, erste 200 ms {np.sqrt((lead**2).mean()):.0f} LSB, Spitze {np.abs(seg).max():.0f}; "
            f"Rand: Ende liegt {len(x) / m.SR - float(r['ende']):.2f} s vor Dateiende")
    dur = [float(rr["ende"]) - float(rr["start"]) for rr in train_rows]
    rms = []
    for rr in train_rows:
        a, b, _ = m.capture_bounds(x, float(rr["start"]), float(rr["ende"]))
        rms.append(float(np.sqrt((m.to16(x[a:b]).astype("float64") ** 2).mean())))
    log(f"  Vergleich alle Vorlagen: Dauer {min(dur):.2f}..{max(dur):.2f} s (Median {np.median(dur):.2f}), RMS {min(rms):.0f}..{max(rms):.0f} (Median {np.median(rms):.0f})")
    st = {}
    for rr in train_rows: st[rr["status"]] = st.get(rr["status"], 0) + 1
    log(f"  Status der Vorlagen: {st}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--out", default=m.WORKDIR)
    a = ap.parse_args()
    t0 = time.time()
    log = lambda *s: print(f"[{time.time() - t0:5.0f}s]", *s, flush=True)
    chain = m.Chain(a.threads)
    cache = m.Cache(chain, a.out)
    srcs = m.sources()
    labels = m.read_labels()
    train_rows = [r for r in labels if m.is_train_row(r)]
    eval_rows = m.pruef_rows(labels)
    x = m.load16(f"{m.WORK121}/all_{m.TRAIN_DEVICE}.wav")
    T, _, info = m.enroll(chain, x, train_rows, "noise")
    mus, _ = m.neutral_means(chain, cache, srcs)
    sp = m.windows_from_emb(np.concatenate(list(cache.get("fleurs_dev", srcs["fleurs_dev"]).values())))
    sep = {k: m.windows_from_emb(v) for k, v in cache.get("synth_sep", separate_noise_mean_sources).items()}
    mu_sep = (sp.mean(axis=0) + np.concatenate([w for k, w in sep.items() if k != "stille"]).mean(axis=0) + sep["stille"].mean(axis=0)) / 3
    mu = {"V2b": mus["V2b"], "V2b-sep": mu_sep.astype("float32"), "V2": mus["V2"]}
    log(f"Vorlagen {len(T)}; Abstand der Mittel V2b - V2b-sep (Norm): {np.linalg.norm(mus['V2b'] - mu_sep):.2f} (V2b {np.linalg.norm(mus['V2b']):.2f})")

    # ---- (1) zurueckgehaltene Stroeme ----
    hold = cache.get("holdout_synth", holdout_sources)
    quiet = {}
    for dev in m.DEVICES:
        q, rms = quiet_segments(dev)
        quiet.update(q)
        log(f"leiseste Stuecke {dev}: RMS {min(rms):.1f}..{max(rms):.1f} LSB")
    qe = cache.get("room_quiet", lambda: quiet)
    rows = []
    for name, E in {**hold, **qe}.items():
        W = m.windows_from_emb(E)
        if not len(W): continue
        rows.append((name, {k: float(m.best_sim(W, T, v).max()) for k, v in mu.items()}))
    L = ["| Strom (zurückgehalten) | V2b (Ist) | V2b-sep (Rauschen getrennt) | V2 (nur Sprache) |", "|---|---|---|---|"]
    for name, d in rows:
        L.append(f"| {name} | " + " | ".join(f"{d[k]:.2f}".replace(".", ",") for k in mu) + " |")
    syn = [d for n, d in rows if not n.startswith(tuple(m.DEVICES))]
    room = [d for n, d in rows if n.startswith(tuple(m.DEVICES))]
    for lbl, grp in (("Maximum synthetisch (zurückgehalten)", syn), ("Maximum echter Raumton", room)):
        L.append(f"| **{lbl}** | " + " | ".join(f"**{max(d[k] for d in grp):.2f}**".replace(".", ",") for k in mu) + " |")
    print("\n".join(L), flush=True)

    # ---- (2) Kalibrierung ----
    mv = mu["V2b"]
    Tn = m.prep(T, mv)
    G = Tn @ Tn.T
    np.fill_diagonal(G, -1)
    loo = [float(v) for v in G.max(axis=1)]
    log(f"Leave-one-out zentriert: min {min(loo):.2f} Median {np.median(loo):.2f} max {max(loo):.2f} (roh: siehe V0-Diagnose)")
    pk = {d: m.hit_rows(m.sims_of(cache.get("pos_" + d, srcs["pos_" + d]), T, mv, m.SR), eval_rows, d) for d in m.DEVICES}
    answers = [p["peak"] for p in pk["handy2"] if p["word"] == "Wendelin" and p["block"] <= 3]
    answers = [v for v in answers if v >= PROMPT_FLOOR]
    clean = {w: [p["peak"] for d in m.DEVICES for p in pk[d] if p["word"] == w and (d != "handy2" or p["block"] >= 4)] for w in m.WORDS}
    log(f"Antworten (handy2 B1-3, >= {PROMPT_FLOOR}): {len(answers)}; saubere Menge: " + ", ".join(f"{w} {len(v)}" for w, v in clean.items()))
    outlier_report(x, train_rows, info, G, loo)
    repeat = max(1, int(np.ceil(len(loo) / max(len(answers), 1))))
    pos_both = loo + answers * repeat
    bg = {}
    hold = {}  # zurueckgehaltener Rest je Hintergrund: (Events, Stunden), nur Bericht der FA/h
    bg["leiser Raum (10 leiseste 5-s-Stücke je Gerät)"] = ([], sum(len(m.windows_from_emb(E)) for E in qe.values()) and 0)
    qE = qe
    qh = sum(max(0, len(E) + m.FIRST_EMB) * m.CHUNK for E in qE.values()) / m.SR / 3600
    qev = []
    for E in qE.values():
        W = m.windows_from_emb(E)
        if len(W): qev += slot_events(m.win_times(len(W)), m.best_sim(W, T, mv))
    bg["leiser Raum (leiseste Stücke)"] = (qev, qh)
    del bg["leiser Raum (10 leiseste 5-s-Stücke je Gerät)"]
    for dev in m.DEVICES:
        Ed = cache.get("neg_" + dev, srcs["neg_" + dev])
        S = m.sims_of(Ed, T, mv)
        t, v = m.one(S)
        keep = t < 1800
        bg[f"Negativ-Aufnahme {dev} (erste 30 min)"] = (slot_events(t[keep], v[keep]), 0.5)
        rest = ~keep
        hold[f"Negativ-Aufnahme {dev} (erste 30 min)"] = (slot_events(t[rest], v[rest]), m.hours_of(Ed) - 0.5)
        bg[f"Negativ-Aufnahme {dev} (ganz)"] = (slot_events(t, v), m.hours_of(Ed))
    tvE = cache.get("fleurs_test", srcs["fleurs_test"])
    acc, ev, tot = {}, [], 0.0
    for k in sorted(tvE):
        if tot >= 0.5: break
        acc[k] = tvE[k]; tot = m.hours_of(acc)
    for k, E in acc.items():
        W = m.windows_from_emb(E)
        if len(W): ev += slot_events(m.win_times(len(W)), m.best_sim(W, T, mv))
    bg["Fernseher (FLEURS test, erste 0,5 h)"] = (ev, tot)
    rev, rtot = [], 0.0
    for k in sorted(tvE):
        if k in acc: continue
        W = m.windows_from_emb({k: tvE[k]})
        if len(W): rev += slot_events(m.win_times(len(W)), m.best_sim(W, T, mv))
        rtot += m.hours_of({k: tvE[k]})
    hold["Fernseher (FLEURS test, erste 0,5 h)"] = (rev, rtot)
    def held(name, thr):
        if name not in hold: return "-"
        e, h = hold[name]
        n = sum(x >= thr for x in e)
        return f"{n / h:.1f} ({n} / {h:.2f} h)"
    C = ["| Hintergrund | Events (Slots ≥0,3) / h | Positive | Schwelle | Recall eigene Positive | FA/h | Wendelin sauber | Hey Wendelin sauber | FA/h zurückgehalten (Events / h) |", "|---|---|---|---|---|---|---|---|---|"]
    for name, (neg, hrs) in bg.items():
        for pname, pos in (("LOO", loo), ("LOO+Antworten", pos_both)):
            thr, rec, fa = calibrate(pos, neg, hrs)
            hit = lambda w: f"{sum(p >= thr for p in clean[w])}/{len(clean[w])}"
            C.append(f"| {name} | {len(neg)} / {hrs:.2f} h | {pname} | {thr:.2f} | {rec:.2f} | {fa:.1f} | {hit('Wendelin')} | {hit('Hey Wendelin')} | {held(name, thr)} |".replace(".", ","))
    print("\n" + "\n".join(C), flush=True)
    json.dump({"hold": rows, "loo": loo, "answers": answers}, open(f"{a.out}/holdout.json", "w"), indent=1)
    open(f"{a.out}/holdout.md", "w").write("\n".join(L) + "\n\n" + "\n".join(C) + "\n")
    log("fertig")


if __name__ == "__main__":
    main()
