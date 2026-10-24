#!/usr/bin/env python3
"""WP130: echte Positive (Wendelin / Hey Wendelin) fuer das Training, fest verdrahteter Split.

Training: NUR Geraet huawei, Bloecke 1 bis 3, Woerter Wendelin und Hey Wendelin, Status ungleich fehler (unsichere nur bis
MAX_S Sekunden). Pruefung (nie im Training): huawei Block 4 bis 6, das gesamte zweite Geraet, alle Negativ-Aufnahmen
(raw-neg), alle anderen Woerter. Die Audioquelle ist fest die huawei-Aufnahme; fuer andere Geraete gibt es keinen Pfad.

  python real_split.py cut --fix <ordner-mit-labels/ und raw/> --work <arbeitsordner> --out <clip-ordner> [--speakers <speakers.csv>]

Weitere Sprecher (WP137, nur mit --speakers; ohne die Option bleibt alles wie bisher): Ablage je Sprecher-Kuerzel
<fix>/speakers/<kuerzel>/labels/labels.csv (Spalte geraet = Kuerzel, sonst wie labels.csv) und <fix>/speakers/<kuerzel>/raw/all_<kuerzel>.m4a.
Konfig speakers.csv (Spalten kuerzel, rolle, train_blocks; Kuerzel nur [a-z0-9]+, "huawei" und "handy2" sind fest und stehen nicht darin):
  rolle train: alle Bloecke Training | eval: nur Pruefung (nichts davon wird je gelesen) | split: train_blocks (z. B. "1 2 3") Training, Rest Pruefung.
Mindestens ein Sprecher mit rolle eval ist Pflicht. Alles, was nicht ausdruecklich Training ist, ist Pruefung (fail-closed).

Aufnahmen und Labels bleiben lokal (nie ins Repo). Selbsttest: test_real_split.py.
"""
import argparse, csv, os, re, subprocess
import numpy as np
import soundfile as sf

SR = 16000
TRAIN_DEVICE = "huawei"
TRAIN_BLOCKS = (1, 2, 3)
TRAIN_WORDS = ("Wendelin", "Hey Wendelin")
MAX_S = 2.0                      # laengere Ereignisse haben unsichere Grenzen (Hintergrund/zusammengezogen)
SOURCES = {"huawei": "raw/all_huawei.m4a"}      # bewusst nur diese eine Quelle
PRE, POST = 0.12, 0.20           # Rand um das Label in Sekunden


FIXED_SPEAKERS = {"huawei": (1, 2, 3), "handy2": ()}   # Sprecher/Geraete mit festem Split (huawei: Block 1-3 Training; handy2: nur Pruefung)
ROLES = ("train", "eval", "split")
KUERZEL_RE = re.compile(r"^[a-z0-9]+$")


def default_speakers():
    """Nur die festen Sprecher: Wert = Trainingsbloecke (leer: nur Pruefung, None: alle Bloecke Training)."""
    return dict(FIXED_SPEAKERS)


def load_speakers(path):
    """speakers.csv (kuerzel, rolle, train_blocks) -> {kuerzel: Trainingsbloecke}, inkl. fester Sprecher. Fail-closed: Fehler brechen ab
    (unbekannte Rolle, ungueltiges/doppeltes/festes Kuerzel, Bloecke passen nicht zur Rolle, kein reiner Pruef-Sprecher in der Datei)."""
    sp, roles = default_speakers(), []
    with open(path, encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            k, role, tb = (r.get("kuerzel") or "").strip(), (r.get("rolle") or "").strip(), (r.get("train_blocks") or "").strip()
            if not KUERZEL_RE.match(k) or k in sp: raise SystemExit(f"speakers.csv: ungueltiges, doppeltes oder festes Kuerzel {k!r}")
            if role not in ROLES: raise SystemExit(f"speakers.csv: unbekannte Rolle {role!r} bei {k}")
            try: blocks = tuple(sorted({int(x) for x in tb.split()}))
            except ValueError: raise SystemExit(f"speakers.csv: train_blocks bei {k} nicht lesbar: {tb!r}")
            if role == "split" and not blocks or role != "split" and blocks: raise SystemExit(f"speakers.csv: train_blocks passt nicht zur Rolle {role} bei {k}")
            sp[k] = None if role == "train" else blocks
            roles.append(role)
    if "eval" not in roles: raise SystemExit("speakers.csv: mindestens ein Sprecher nur zur Pruefung (rolle eval) ist Pflicht")
    return sp


def is_train_block(speakers, k, block):
    """Training nur, wenn der Sprecher bekannt ist und der Block ausdruecklich Training ist."""
    if k not in speakers: return False
    tb = speakers[k]
    return tb is None or block in tb


SESSION_TOL = 0.2                # s: Streuung des Geraeteversatzes zwischen zwei Aufnahmen derselben Sitzung
SESSION_MIN = 3                  # mindestens so viele Rufe mit gemeinsamem Versatz


def _call(r):
    """(geraet, block, runde, wort, start) aus einer Zeile im Format von labels.csv (geraet/wort/runde) oder words_measure.read_labels (dev/word/round)."""
    return (r["geraet"] if "geraet" in r else r["dev"], int(r["block"]), int(r["runde"] if "runde" in r else r["round"]),
            r["wort"] if "wort" in r else r["word"], float(r["start"]))


def paired_sessions(rows, speakers=None):
    """Pruef-Aufnahmen (geraet, block), die dieselbe Sitzung wie eine Trainingsaufnahme sind: zwei Geraete haben dieselben gesprochenen Rufe
    gleichzeitig aufgenommen (gleicher Block, Runde, Wort; Start bis auf einen festen Geraeteversatz gleich). Erkannt wird das nur ueber die Labels:
    Die Aufnahme (geraet, block) zaehlt als gepaart, wenn mindestens SESSION_MIN Rufe und mehr als die Haelfte ihrer Labels zu Trainings-Rufen mit
    EINEM gemeinsamen Versatz (Toleranz SESSION_TOL) passen. Ein weiteres Geraet derselben Sitzung wird so automatisch erfasst.
    rows: alle Labels (beide Formate, auch Nicht-Trainings-Woerter). -> {(geraet, block): Trainings-Geraet}. Ganze Aufnahme, nicht nur einzelne Rufe (fail-closed)."""
    sp = {TRAIN_DEVICE: TRAIN_BLOCKS} if speakers is None else speakers
    calls = []
    for r in rows:
        try: calls.append(_call(r))
        except (KeyError, ValueError, TypeError): continue          # unlesbare Zeile kann nichts paaren (Trainingsbloecke prueft assert_eval_only getrennt)
    train = {}
    groups = {}
    for dev, b, rd, w, st in calls:
        if is_train_block(sp, dev, b): train.setdefault((b, rd, w), []).append((dev, st))
        else: groups.setdefault((dev, b), []).append((b, rd, w, st))
    out = {}
    for g, items in groups.items():
        diffs = [[(st - ts, td) for td, ts in train.get((b, rd, w), [])] for b, rd, w, st in items]
        best = (0, None)
        for cand in sorted({round(d, 3) for ds in diffs for d, _ in ds}):
            hit = [next((td for d, td in ds if abs(d - cand) <= SESSION_TOL), None) for ds in diffs]
            n = sum(h is not None for h in hit)
            if n > best[0]: best = (n, next(h for h in hit if h is not None))
        if best[0] >= SESSION_MIN and 2 * best[0] > len(items): out[g] = best[1]
    return out


def speaker_source(speakers, k):
    """Audioquelle (relativ zu fix) eines Sprechers mit Trainingsbloecken; Pruef-Sprecher haben keinen Pfad."""
    if k == TRAIN_DEVICE: return source_for(k)
    if k not in speakers or speakers[k] == (): raise ValueError(f"keine Trainingsquelle fuer Sprecher {k!r}")
    return f"speakers/{k}/raw/all_{k}.m4a"


def is_train_clip(row, speakers=None):
    """row: Dict mit geraet, block, wort, start, ende, status (Strings wie in labels.csv). speakers=None: nur huawei Block 1-3 (wie bisher)."""
    try:
        sp = {TRAIN_DEVICE: TRAIN_BLOCKS} if speakers is None else speakers
        return (is_train_block(sp, row["geraet"], int(row["block"])) and row["wort"] in TRAIN_WORDS
                and row["status"] != "fehler" and row["status"] in ("ok", "unsicher")
                and 0 < float(row["ende"]) - float(row["start"]) <= MAX_S)
    except (KeyError, ValueError, TypeError):
        return False             # fail-closed: unlesbare Zeile wird nie Trainingsclip


def select(rows, speakers=None):
    return [r for r in rows if is_train_clip(r, speakers)]


def source_for(geraet):
    if geraet not in SOURCES:
        raise ValueError(f"keine Trainingsquelle fuer Geraet {geraet!r}")
    return SOURCES[geraet]


def clip_name(r):
    w = "hey" if r["wort"].startswith("Hey") else "bare"
    return f"{r['geraet']}_b{int(r['block'])}_r{int(r['runde']):02d}_{w}_{int(round(float(r['start']) * 100)):06d}.wav"


def trim(x, db=-40.0, pad=0.05):
    f = 160
    n = len(x) // f
    if n == 0:
        return x
    rms = np.sqrt((x[: n * f].reshape(n, f) ** 2).mean(axis=1) + 1e-12)
    idx = np.where(20 * np.log10(rms / (rms.max() + 1e-9) + 1e-12) > db)[0]
    if len(idx) == 0:
        return x
    return x[max(0, idx[0] * f - int(pad * SR)): min(len(x), (idx[-1] + 1) * f + int(pad * SR))]


def cut_clips(rows, x, speakers=None):
    out = []
    for r in select(rows, speakers):
        a = max(0, int((float(r["start"]) - PRE) * SR)); b = min(len(x), int((float(r["ende"]) + POST) * SR))
        c = trim(x[a:b])
        if len(c) >= SR // 4:
            out.append((clip_name(r), c))
    return out


NAME_RE = re.compile(r"^([a-z0-9]+)_b(\d+)_r(\d{2,})_(hey|bare)_(\d{6})\.wav$")     # Muster von clip_name()


def check_dir(d, require_nonempty=False, speakers=None):
    """Alle Clips im Ordner muessen Trainingsnamen sein (Trainingssprecher und -block, clip_name-Muster; Standard huawei Block 1 bis 3); sonst Abbruch.
    Clips von Pruef-Sprechern (rolle eval, handy2) und Pruef-Bloecken werden abgewiesen.
    Fail-closed: fremdes Namensschema, fehlender Ordner und (mit require_nonempty) leerer Ordner brechen ab."""
    if not os.path.isdir(d):
        raise SystemExit(f"Ordner der echten Positive fehlt: {d}")
    n = 0
    for f in sorted(os.listdir(d)):
        if not f.endswith(".wav"):
            continue
        m = NAME_RE.match(f)
        if not m or not is_train_block({TRAIN_DEVICE: TRAIN_BLOCKS} if speakers is None else speakers, m.group(1), int(m.group(2))):
            raise SystemExit(f"Pruef-Clip oder fremder Name im Trainingsordner: {f}")
        n += 1
    if require_nonempty and n == 0:
        raise SystemExit(f"keine echten Positive im Ordner: {d}")


def pos_for_split(pos, real_pos, rep, split):
    """Positiv-Liste je Split fuer train.py: Train = 90 % synthetisch + echte Positive x rep; Val = restliche 10 % synthetisch (nie echt)."""
    cut = int(len(pos) * .9)
    return pos[:cut] + list(real_pos) * rep if split == "train" else pos[cut:]


def assert_syn_only(ps, pos, split):
    """Fail-closed fuer --no-real-pos: die Positiv-Liste des Splits darf nur die synthetischen Clips enthalten (Train 90 %, Val 10 %)."""
    cut = int(len(pos) * .9)
    exp = pos[:cut] if split == "train" else pos[cut:]
    if len(ps) != len(exp) or any(a is not b for a, b in zip(ps, exp)):
        raise SystemExit("echte Positive im Lauf ohne echte Positive")


def cut_speaker(fix, work, out, k, speakers):
    """Trainingsclips eines Sprechers nach out; huawei wie bisher (labels/labels.csv, raw/all_huawei.m4a), andere unter speakers/<k>/.
    -> (Zahl Clips, Zahl ausgeschlossener Zeilen im Trainingsbereich)."""
    base = fix if k == TRAIN_DEVICE else os.path.join(fix, "speakers", k)
    rows = list(csv.DictReader(open(os.path.join(base, "labels", "labels.csv"), encoding="utf-8")))
    rows = [r for r in rows if r.get("geraet") == k]                    # nur Zeilen dieses Sprechers
    wav = os.path.join(work, f"train_{k}.wav")
    if not os.path.exists(wav):
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
                        os.path.join(fix, speaker_source(speakers, k)), wav], check=True)
    x = sf.read(wav, dtype="float32")[0]
    sp = {k: speakers[k]}
    skipped = [r for r in rows if is_train_block(sp, k, int(r["block"])) and r["wort"] in TRAIN_WORDS and not is_train_clip(r, sp)]
    n = 0
    for name, c in cut_clips(rows, x, sp):
        sf.write(os.path.join(out, name), c, SR, subtype="PCM_16"); n += 1
    return n, len(skipped)


def main():
    a = argparse.ArgumentParser(); a.add_argument("cmd", choices=["cut"])
    a.add_argument("--fix", required=True); a.add_argument("--work", required=True); a.add_argument("--out", required=True)
    a.add_argument("--speakers", help="speakers.csv mit weiteren Sprechern (siehe Modul-Doku); ohne: nur huawei")
    a = a.parse_args()
    speakers = load_speakers(a.speakers) if a.speakers else None
    sp = default_speakers() if speakers is None else speakers
    sp = {k: v for k, v in sp.items() if k == TRAIN_DEVICE or v != ()}
    os.makedirs(a.work, exist_ok=True); os.makedirs(a.out, exist_ok=True)
    for k in sorted(sp, key=lambda x: (x != TRAIN_DEVICE, x)):          # huawei zuerst; Pruef-Sprecher werden nie gelesen
        n, sk = cut_speaker(a.fix, a.work, a.out, k, sp)
        print(f"echte Positive (Training){'' if k == TRAIN_DEVICE else ' ' + k}: {n} Clips, ausgeschlossen im Trainingsbereich: {sk}")
    check_dir(a.out, speakers=None if speakers is None else sp)


if __name__ == "__main__":
    main()
