#!/usr/bin/env python3
"""WP137 Teil 2, Prüfer A: kleines Faltungsnetz auf openWakeWord-Embeddings (F x 96) des Ausschnitts um den Entscheidungszeitpunkt.

Netz: LayerNorm je Frame, 3 Faltungen (k=3, 64 Kanäle), mittelnde Bündelung auf 5 Zeitabschnitte, Linear 64, zwei Köpfe (Ausgabe p = [P(„Wendelin“), P(„Hey Wendelin“)]).
Begründung zwei Köpfe: ein Rumpf, aber „Hey Wendelin“ muss „Hey + X“ trennen, „Wendelin“ allein darf „Hey Wendelin“ annehmen; die Köpfe haben
verschiedene Positive (Kopf W: bare + hey, Kopf HW: nur hey; „bare“ ist für HW ein Negativ). Gewicht: Verwechsler und Mining x2, Ereignisse im Band [0,98; 0,999) x3.
Faltungen: Ausschnitte werden nach `group` in 3 Gruppen geteilt (echte Clips = Aufnahmeblock, synthetisch = Clip-Hash, Verwechsler = Text-Hash); out-of-fold-Werte
(OOF) dienen der Wahl von Ausschnitt und Schwellen und später der Fusion C. Das Endmodell trainiert auf allem, ONNX < 1,5 MB, <= 300 k Parameter.
Schwellenregel (vorher festgelegt): je Kopf die niedrigste Schwelle, bei der >= REJECT_MIN der OOF-Negativen im Band verworfen werden (Positive im Band so
viele wie möglich); dazu Sweep-Tabelle. Aufruf:
  python verifier_train.py --feat <feat.npz> [--feat weitere ...] --out <ordner> [--probe]
Mehrere --feat = Ausschnitt-Kandidaten, Wahl nach OOF-Annahme bei Regel. Selbsttest: test_verifier_train.py."""
import argparse, hashlib, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np
import torch
from torch import nn
import verifier_data as D

REJECT_MIN = 0.90
MAX_PARAMS = 300_000
MAX_BYTES = 1_500_000
SWEEP = (0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.98)
BANDS = 5
CH = 64


class Net(nn.Module):
    def __init__(self, frames, drop=0.2):
        super().__init__()
        self.frames = frames
        self.norm = nn.LayerNorm(96)
        self.conv = nn.Sequential(nn.Conv1d(96, CH, 3, padding=1), nn.ReLU(), nn.Conv1d(CH, CH, 3, padding=1), nn.ReLU(), nn.Conv1d(CH, CH, 3, padding=1), nn.ReLU())
        self.pad = (-frames) % BANDS
        self.head = nn.Sequential(nn.Flatten(), nn.Linear(CH * BANDS, 64), nn.ReLU(), nn.Dropout(drop), nn.Linear(64, 2), nn.Sigmoid())

    def forward(self, x):
        h = self.conv(self.norm(x).transpose(1, 2))
        if self.pad: h = torch.nn.functional.pad(h, (0, self.pad), mode="replicate")
        return self.head(h.reshape(h.shape[0], CH, BANDS, -1).mean(-1))


def n_params(net): return sum(p.numel() for p in net.parameters())


def weights(kind, peak):
    w = np.ones(len(kind), "float32")
    w[np.isin(kind, [D.KIND["conf"], D.KIND["mined"], D.KIND["extra"]])] *= 2.0
    w[(peak >= D.BAND[0]) & (peak < D.BAND[1])] *= 3.0           # Band: genau dort entscheidet der Pruefer
    return w


def fit(ex, idx, epochs, seed=1, threads=2, batch=256, lr=2e-3, log=None):
    """Netz auf den Beispielen idx trainieren (gewichteter BCE, Klassenausgleich je Kopf)."""
    torch.set_num_threads(threads); torch.manual_seed(seed)
    rng = np.random.default_rng(seed)
    d = ex.d
    X = torch.from_numpy(d["emb"][idx].astype("float32"))
    Y = torch.from_numpy(np.stack([d["yw"][idx], d["yhw"][idx]], 1).astype("float32"))
    w = torch.from_numpy(weights(d["kind"][idx], d["peak"][idx]))[:, None].repeat(1, 2)
    for k in range(2):                                  # Klassenausgleich: Gesamtgewicht Positive = Negative
        pos = Y[:, k] == 1
        if pos.any() and (~pos).any(): w[pos, k] *= float(w[~pos, k].sum() / w[pos, k].sum())
    net = Net(X.shape[1])
    opt = torch.optim.Adam(net.parameters(), lr, weight_decay=1e-4)
    steps = epochs * max(1, -(-len(idx) // batch))
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, lr, total_steps=max(steps, 2))
    bce = nn.BCELoss(reduction="none")
    for s in range(steps):
        b = rng.integers(len(idx), size=batch)
        net.train()
        loss = (bce(net(X[b]), Y[b]) * w[b]).sum() / w[b].sum()
        opt.zero_grad(); loss.backward(); opt.step(); sched.step()
        if log and (s % 500 == 499 or s == steps - 1): log(f"step {s + 1}/{steps} loss {loss.item():.4f}")
    return net.eval()


def predict(net, emb, batch=2048):
    with torch.no_grad():
        return np.concatenate([net(torch.from_numpy(emb[i:i + batch].astype("float32"))).numpy() for i in range(0, len(emb), batch)]) if len(emb) else np.zeros((0, 2), "float32")


def oof_scores(ex, epochs, folds=3, **kw):
    """Out-of-fold-Werte (N,2): Netz je Faltung auf den übrigen Gruppen trainiert, auf dieser Gruppe bewertet. Fehlt eine Gruppe, bricht es ab (kein stilles Leck)."""
    g = ex.d["group"]
    out = np.zeros((len(g), 2), "float32")
    for k in range(folds):
        te, tr = np.where(g % folds == k)[0], np.where(g % folds != k)[0]
        if len(te) == 0 or len(tr) == 0: raise SystemExit(f"Faltung {k} leer")
        out[te] = predict(fit(ex, tr, epochs, **kw), ex.d["emb"][te])
    return out


def band_masks(ex, head):
    """(Positive, Negative) im Band [0,98; 0,999) für den Kopf (0 = W, 1 = HW)."""
    y = ex.d["yw"] if head == 0 else ex.d["yhw"]
    inb = (ex.d["peak"] >= D.BAND[0]) & (ex.d["peak"] < D.BAND[1])
    return inb & (y == 1), inb & (y == 0)


def choose_threshold(score, pos, neg, reject_min=REJECT_MIN):
    """Niedrigste Schwelle mit Verwerfungsrate der Negativen >= reject_min (dann Annahme der Positiven maximal). -> (Schwelle, Annahme, Verwerfung);
    ohne Positive/Negative oder wenn keine Schwelle reicht: (1.0, 0, 1) (verwirft alles, fail-closed)."""
    if not pos.any() or not neg.any(): return 1.0, 0.0, 1.0
    cands = np.unique(np.concatenate([score[neg], [1.0]]))                        # Schwellen sind Negativ-Werte: score >= thr nimmt an
    best = None
    for t in cands:
        rej = float((score[neg] < t).mean())
        if rej >= reject_min:
            best = (float(t), float((score[pos] >= t).mean()), rej); break
    return best or (1.0, 0.0, 1.0)


def sweep_table(score, ex, head):
    pos, neg = band_masks(ex, head)
    kinds = ex.d["kind"]
    rows = ["| Schwelle | Positive angenommen | Negative verworfen | davon Verwechsler | davon Mining |", "|---|---|---|---|---|"]
    f = lambda m, v: "-" if not m.any() else f"{100 * v[m].mean():.0f} %"
    for t in SWEEP:
        rj = score < t
        rows.append(f"| {t} | {f(pos, ~rj)} | {f(neg, rj)} | {f(neg & (kinds == D.KIND['conf']), rj)} | {f(neg & (kinds == D.KIND['mined']), rj)} |")
    return rows


def export_onnx(net, path):
    net.eval()
    torch.onnx.export(net, torch.zeros(1, net.frames, 96), path, input_names=["input"], output_names=["p"],
                      dynamic_axes={"input": {0: "batch"}, "p": {0: "batch"}}, opset_version=13, dynamo=False)
    if n_params(net) > MAX_PARAMS or os.path.getsize(path) > MAX_BYTES:
        raise SystemExit(f"Modell zu gross: {n_params(net)} Parameter, {os.path.getsize(path)} Bytes")
    import onnxruntime as ort
    so = ort.SessionOptions(); so.intra_op_num_threads = 1
    x = np.random.default_rng(0).standard_normal((4, net.frames, 96)).astype("float32")
    y = ort.InferenceSession(path, so, providers=["CPUExecutionProvider"]).run(None, {"input": x})[0]
    if np.abs(y - predict(net, x)).max() > 1e-4: raise SystemExit("ONNX weicht von PyTorch ab")
    return hashlib.sha256(D._read(path)).hexdigest()


def run(feats, out, epochs, probe=False, reject_min=REJECT_MIN, seed=1, threads=2, log=print):
    """Je Kandidat OOF; bester Ausschnitt nach mittlerer OOF-Annahme bei der Regel; Endmodell, ONNX, Meta, OOF-Datei."""
    os.makedirs(out, exist_ok=True)
    best = None
    for f in feats:
        D.require_stamp(f)
        cut = D.feat_cut(f)
        ex = D.Examples.load(f)
        oof = oof_scores(ex, epochs, seed=seed, threads=threads)
        res = [choose_threshold(oof[:, k], *band_masks(ex, k), reject_min) for k in range(2)]
        m = float(np.mean([r[1] for r in res]))
        log(f"{os.path.basename(f)}: OOF-Annahme bei Verwerfung >= {reject_min:.0%}: W {res[0][1]:.2f}, HW {res[1][1]:.2f}")
        if best is None or m > best[0]: best = (m, f, ex, oof, res, cut)
    _, f, ex, oof, res, cut = best
    net = fit(ex, np.arange(len(ex)), epochs, seed=seed, threads=threads, log=log)
    onnx_p = os.path.join(out, "verifier_a.onnx")
    sha = export_onnx(net, onnx_p)
    meta = dict(feat=os.path.basename(f), pre=cut[0], tail=cut[1], frames=int(ex.d["emb"].shape[1]), params=n_params(net), bytes=os.path.getsize(onnx_p), sha256=sha,
                thresholds=dict(W=res[0][0], HW=res[1][0]), oof_accept=dict(W=res[0][1], HW=res[1][1]), oof_reject=dict(W=res[0][2], HW=res[1][2]),
                reject_min=reject_min, norm=f"Spitze {D.NORM_PEAK}", epochs=epochs, seed=seed, probe=probe, heads=["Wendelin", "Hey Wendelin"])
    D._jdump(meta, onnx_p + ".meta.json")
    np.savez_compressed(os.path.join(out, "oof.npz"), oof=oof)
    with open(os.path.join(out, "sweep.md"), "w") as fh:
        for k, nm in enumerate(("Wendelin", "Hey Wendelin")):
            fh.write(f"## Sweep OOF Kopf {nm} (Schwelle gewählt: {res[k][0]:.4f})\n\n" + "\n".join(sweep_table(oof[:, k], ex, k)) + "\n\n")
    log(f"-> {onnx_p} ({meta['bytes']} Bytes, {meta['params']} Parameter) {sha[:12]}")
    return meta


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--feat", action="append", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--epochs", type=int, default=25); ap.add_argument("--probe", action="store_true")
    ap.add_argument("--reject-min", type=float, default=REJECT_MIN); ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--threads", type=int, default=2)
    a = ap.parse_args()
    run(a.feat, a.out, 2 if a.probe else a.epochs, a.probe, a.reject_min, a.seed, a.threads)


if __name__ == "__main__":
    main()
