#!/usr/bin/env python3
"""WP121 Etappe 1: Labels fuer die Wake-Word-Aufnahmen (fuenf Woerter, sechs Bloecke), noch keine Messung.

Aufruf (ein Kommando je Schritt; Daten bleiben lokal, nie ins Repo; Venv wie bei real_measure.py):
  K=~/wendelin-models/kws; P="nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/words_labels.py"
  $P convert            # m4a/wav -> 16 kHz mono nach $K/wp121/work (afconvert)
  $P events             # Energie-VAD beider Geraete (ausgerichtet), Whisper medium je Ereignis -> work/events.json
  $P label              # Zuordnung nach Reihenfolge -> labels/labels.csv, Zaehlung Wort x Block je Geraet
  $P neg                # Negativ-Dateien: Whisper medium sucht die fuenf Woerter/Verwechsler -> labels/neg_hits.csv
Ablauf: Beide Handys liefen gleichzeitig (konstanter Versatz per Kreuzkorrelation der Energiehuellen). Die Ereignisse sind die
Vereinigung der VAD-Segmente beider Geraete. Whisper medium (unabhaengig, nicht der gemessene Erkenner) dient nur dazu, Ansagen
("Block n"), "Fehler"/Zwischenrufe und reine Geraeusche ([Musik], *hust* ...) zu erkennen; Wortlabels entstehen allein aus der
Reihenfolge laut ANLEITUNG (je Block 5 Runden Wendelin - Hey Wendelin - Alexa - Hey Octavia - Kobalos). Passt die Zahl der
Wortereignisse einer Region nicht auf 25 je Block, bricht `label` ab, ausser labels/manual.csv nennt die Abweichung von Hand.
manual.csv: start;aktion;wert;grund   (start = Ereignisbeginn in Sekunden der huawei-Zeit, aktion: drop | fehler | split)
"""
import argparse, csv, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))

SR = 16000
KWS = os.path.expanduser("~/wendelin-models/kws")
WORK = f"{KWS}/wp121/work"
FIX = os.path.expanduser("~/wendelin-fixtures/wake/words")
LABELS = f"{FIX}/labels"
DEVICES = {"huawei": 0.0, "handy2": -0.72}          # Zeitverschiebung ins huawei-Zeitraster (Kreuzkorrelation, konstant)
WORDS = ["Wendelin", "Hey Wendelin", "Alexa", "Hey Octavia", "Kobalos"]
ROUNDS = 5
PER_BLOCK = len(WORDS) * ROUNDS
LONG_S = 2.0                                          # laengere Aeusserungen: Grenzen unsicher (Hintergrund/zusammengezogen)


def fold(t):
    import unicodedata
    t = t.lower().replace("ß", "ss")
    t = "".join(c for c in unicodedata.normalize("NFD", t) if unicodedata.category(c) != "Mn")
    return " ".join("".join(c if c.isalnum() else " " for c in t).split())


def merge_intervals(iv, tol=0.2):
    """Vereinigung (start, ende)-Listen; Luecken <= tol werden geschlossen."""
    out = []
    for s, e in sorted(iv):
        if out and s <= out[-1][1] + tol: out[-1][1] = max(out[-1][1], e)
        else: out.append([s, e])
    return [tuple(x) for x in out]


def is_noise_text(t):
    """Whisper-Text nur Geraeuschtags ([Musik], *hust*, * Gelaechter *, (Stimmengewirr), auch abgeschnitten) oder leer?"""
    rest = re.sub(r"\[[^\]]*\]?|\([^)]*\)?|\*[^*]*\*?", " ", t)
    return not re.search(r"\w", rest)


def announce_no(texts):
    """Blocknummer, wenn ein Geraetetext eine Ansage 'Block n' enthaelt, sonst None."""
    for t in texts:
        m = re.search(r"\bblock\s*(\d)\b", fold(t))
        if m: return int(m.group(1))
    return None


def classify(ev):
    """ann (Ansage) | noise (beide Geraete nur Geraeusch) | speech."""
    t = [ev.get(d, "") for d in DEVICES]
    n = announce_no(t)
    if n is not None: return "ann", n
    if all(is_noise_text(x) for x in t): return "noise", None
    return "speech", None


def regions(events):
    """Zerlegt die Ereignisliste an den erkannten Ansagen: [(blocknummern, [ereignis, ...])]. Vor der ersten Ansage: Block 1.
    Fehlt eine Ansage (Whisper erkennt sie nicht), umfasst die Region mehrere Bloecke (Nummern bis zur naechsten Ansage)."""
    anns = [(i, classify(e)[1]) for i, e in enumerate(events) if classify(e)[0] == "ann"]
    cuts = [(-1, 1)] + anns
    out = []
    for k, (i, n) in enumerate(cuts):
        j, nn = (cuts[k + 1] if k + 1 < len(cuts) else (len(events), n + 1))
        out.append((list(range(n, nn)), [e for e in events[i + 1:j]]))
    return out


def apply_manual(cands, manual):
    """manual: [{'start': float, 'aktion': 'drop'|'fehler'|'split', 'wert': str, 'grund': str}]. Liefert (Liste, Fehlerslots)."""
    by = {round(m["start"], 2): m for m in manual}
    out, used = [], set()
    for e in cands:
        m = by.get(round(e["s"], 2))
        if m: used.add(round(e["s"], 2))
        if m and m["aktion"] == "drop": continue
        if m and m["aktion"] == "fehler":
            out.append(dict(e, status="fehler", note=m["grund"])); continue
        if m and m["aktion"] == "split":
            k = int(m["wert"] or 2)
            for part in split_event(e, k): out.append(dict(part, note=m["grund"]))
            continue
        out.append(e)
    missing = sorted(set(by) - used)
    if missing: raise SystemExit(f"manual.csv: kein Ereignis bei start={missing}")
    return out


def split_event(e, k):
    """Teilt ein zusammengezogenes Ereignis in k gleich lange Teile (Grenzen unsicher)."""
    w = (e["e"] - e["s"]) / k
    return [dict(e, s=round(e["s"] + i * w, 2), e=round(e["s"] + (i + 1) * w, 2), status="unsicher", split=True) for i in range(k)]


def assign(events, manual=()):
    """-> Zeilen (block, runde, wort, s, e, status, note) in huawei-Zeit. Bricht ab, wenn Zahl der Wortereignisse nicht passt."""
    rows = []
    starts = {round(e["s"], 2) for e in events if classify(e)[0] == "speech"}
    bad = sorted(m["start"] for m in manual if round(m["start"], 2) not in starts)
    if bad: raise SystemExit(f"manual.csv: kein Wortereignis bei start={bad}")
    for blocks, evs in regions(events):
        cands = [e for e in evs if classify(e)[0] == "speech"]
        cands = apply_manual(cands, [m for m in manual if any(e["s"] == m["start"] or round(e["s"], 2) == round(m["start"], 2) for e in cands)])
        errs = [e for e in cands if e.get("status") == "fehler"]
        cands = [e for e in cands if e.get("status") != "fehler"]
        need = PER_BLOCK * len(blocks)
        if len(cands) != need:
            raise SystemExit(f"Block {blocks}: {len(cands)} Wortereignisse statt {need} "
                             f"(Starts: {[round(c['s'], 1) for c in cands]}); manual.csv ergaenzen")
        for k, e in enumerate(cands):
            b = blocks[k // PER_BLOCK]; j = k % PER_BLOCK
            st = e.get("status") or ("unsicher" if e["e"] - e["s"] > LONG_S else "ok")
            note = e.get("note") or ("Dauer %.1f s" % (e["e"] - e["s"]) if st == "unsicher" else "")
            rows.append((b, j // len(WORDS) + 1, WORDS[j % len(WORDS)], max(0.0, e["s"]), e["e"], st, note))
        for e in errs:       # Versprecher: eigener Blockbezug ueber die Zeit (kein Wortslot)
            b = next((bb for bb, i0 in zip(blocks, range(len(blocks))) if cands and e["s"] < cands[min((i0 + 1) * PER_BLOCK, len(cands)) - 1]["s"]), blocks[-1])
            rows.append((b, 0, "(Fehler)", max(0.0, e["s"]), e["e"], "fehler", e["note"]))
    return rows


def count_table(rows, stati=("ok",)):
    """Zaehlung Wort x Block (nur die genannten Stati) -> {(wort, block): n}."""
    t = {}
    for r in rows:
        if r[5] in stati: t[(r[2], r[0])] = t.get((r[2], r[0]), 0) + 1
    return t


def read_manual(path):
    if not os.path.exists(path): return []
    return [dict(start=float(r["start"]), aktion=r["aktion"], wert=r.get("wert", ""), grund=r.get("grund", ""))
            for r in csv.DictReader(open(path), delimiter=";")]


# ---------- Schritte mit Audio/Modellen ----------
def cmd_convert(_):
    import subprocess
    os.makedirs(WORK, exist_ok=True)
    for src, dst in [("raw/all_huawei.m4a", "all_huawei"), ("raw/all_handy2.wav", "all_handy2"),
                     ("raw-neg/neg_huawei.m4a", "neg_huawei"), ("raw-neg/neg_handy2.wav", "neg_handy2")]:
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", f"{FIX}/{src}", f"{WORK}/{dst}.wav"], check=True)


def whisper():
    import sherpa_onnx as so
    import station_measure as S
    Md = f"{S.MODELS}/whisper-medium"
    rec = so.OfflineRecognizer.from_whisper(encoder=f"{Md}/medium-encoder.int8.onnx", decoder=f"{Md}/medium-decoder.int8.onnx",
                                            tokens=f"{Md}/medium-tokens.txt", language="de", num_threads=4)
    # Whisper stuerzt bei Audio > 30 s ab (Segfault): hoechstens 24 s je Aufruf
    return lambda x: " | ".join(S.decode(rec, x[a:a + 24 * SR]) for a in range(0, max(len(x), 1), 24 * SR))


def cmd_events(a):
    import real_measure as R
    dec = whisper(); X, iv = {}, []
    for d, sh in DEVICES.items():
        X[d] = R.load(f"{WORK}/all_{d}.wav"); r = R.level_db(X[d])
        iv += [(s / R.FPS + sh, (p + 1) / R.FPS + sh) for s, p in R.segment(r, r, 12, 0.35, 0.12)]
    out = []
    for s, e in merge_intervals([(float(a), float(b)) for a, b in iv]):
        t = {}
        for d, sh in DEVICES.items():
            lo = max(0, int((s - 0.3 - sh) * SR)); hi = min(len(X[d]), int((e + 0.4 - sh) * SR))
            t[d] = dec(X[d][lo:hi])
        out.append(dict(s=round(s, 2), e=round(e, 2), **t))
        if len(out) % 20 == 0: print(len(out), flush=True)
    json.dump(out, open(f"{WORK}/events.json", "w"), ensure_ascii=False)


def cmd_label(a):
    events = json.load(open(f"{WORK}/events.json")); os.makedirs(LABELS, exist_ok=True)
    rows = assign(events, read_manual(f"{LABELS}/manual.csv"))
    with open(f"{LABELS}/labels.csv", "w", newline="") as f:
        w = csv.writer(f); w.writerow(["geraet", "block", "runde", "wort", "start", "ende", "status", "bemerkung"])
        for d, sh in DEVICES.items():
            for b, r, wd, s, e, st, note in rows:
                w.writerow([d, b, r, wd, round(max(0.0, s - sh), 2), round(e - sh, 2), st, note])
    for titel, stati in (("nur status ok", ("ok",)), ("ok + unsicher (Grenzen/Zusammenziehung unsicher)", ("ok", "unsicher"))):
        t = count_table(rows, stati)
        print(f"Zaehlung Wort x Block, {titel} (je Geraet gleich: Ereignisse sind geraeteuebergreifend)")
        print("%-13s" % "wort", *["B%d" % b for b in range(1, 7)], "Summe")
        for wd in WORDS:
            c = [t.get((wd, b), 0) for b in range(1, 7)]
            print("%-13s" % wd, *["%2d" % x for x in c], "%3d" % sum(c))
    print("fehler:", [(r[0], round(r[3], 1)) for r in rows if r[5] == "fehler"])
    print("unsicher:", [(r[0], round(r[3], 1), r[6]) for r in rows if r[5] == "unsicher"])


NEG_RX = {
    "wendelin": r"w[eiu]nd[eao]l[iyu]n|wendeline|vendelin|gwendolin|bandolin|pendelin",
    "alexa": r"\balex(a|ah|o|e|el|em|i)?\b|alexander",
    "octavia": r"[oa]kt?av|opt?avi|octav|ocavi|aptavi",
    "kobalos": r"[kc][oua]b?[ao]l[ou]s|kuba ?l|koma los|kommandos|kobalt",
}
NEG_CONF = r"wendel|windel|berlin|vanill|linie|octob|oktob|oktav|kobold|kobra|kabel"


def neg_classes(text):
    f = fold(text)
    return [k for k, rx in NEG_RX.items() if re.search(rx, f)] or (["verwechsler"] if re.search(NEG_CONF, f) else [])


def cmd_neg(a):
    """Zeitstempel (Sekunden der jeweiligen Datei) der Fundstellen; Fenster 24 s, Hop 20 s, dann 8-s-Teilfenster (Hop 4 s)."""
    import real_measure as R
    dec = whisper(); os.makedirs(LABELS, exist_ok=True); hits = []
    for d in DEVICES:
        x = R.load(f"{WORK}/neg_{d}.wav"); act = R.level_db(x) > 10
        for t in range(0, max(1, int(len(x) / SR - 2)), 20):
            if act[t * R.FPS:(t + 24) * R.FPS].mean() < 0.03: continue
            if not neg_classes(dec(x[t * SR:(t + 24) * SR])): continue
            for u in range(t, t + 24, 4):
                cl = neg_classes(dec(x[u * SR:(u + 8) * SR]))
                for c in cl: hits.append((d, u, c))
        print(d, len(hits), flush=True)
    with open(f"{LABELS}/neg_hits.csv", "w", newline="") as f:
        w = csv.writer(f); w.writerow(["geraet", "zeit_s", "klasse"])
        w.writerows(sorted(set(hits)))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("cmd", choices=["convert", "events", "label", "neg"])
    a = ap.parse_args(); {"convert": cmd_convert, "events": cmd_events, "label": cmd_label, "neg": cmd_neg}[a.cmd](a)
