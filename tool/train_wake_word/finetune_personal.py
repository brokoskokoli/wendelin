#!/usr/bin/env python3
"""WP106 Teil 3A: persoenliches Feintuning (Stufe 1) von wendelin_v7/v9 mit den Einlern-Segmenten 1-5 (Messung, kein App-Code).

Aufruf (ein Kommando; Daten bleiben lokal, nie ins Repo):
  K=~/wendelin-models/kws; nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/finetune_personal.py [--out $K/wp106/finetune] [--bases v7,v9]
Danach je Modell: nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/real_measure.py --model $K/wp106/finetune/ft_v7.onnx \
  --model-thr 0.5,0.7,0.9 --thr 0.95 --s2-thr M0.5 --variants parakeet-hw2 --out $K/wp106/finetune/real_v7

Positive: nur die Einlern-Segmente 1-5 beider Geraete (10 Woerter, Wortgrenzen aus real_measure.segment), je Clip mit
build_clip/augment aus common (Pegel, Hall, Rauschen, Tonhoehe/Tempo 0,8-1,25, EQ) neu gemischt; die Fuellsprache kommt aus den
synthetischen Negativ-Clips (gen/neg). Negative: vorhandene WP58-Features (work5, ohne Positive-Anteil neu) - NIE die
Negativ-Datei und nie Testsegmente. Optimiert werden alle Gewichte, wenige Schritte, kleine Lernrate; der Positiv-Anteil im
Batch ist zur Haelfte persoenlich, zur Haelfte synthetisch (gegen Vergessen).
"""
import argparse, os, sys, time
import numpy as np
import torch
from torch import nn
import onnx
from onnx import numpy_helper

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C                      # noqa: E402
import real_measure as R                # noqa: E402
from train import make_net, windows     # noqa: E402

KWS = os.path.expanduser("~/wendelin-models/kws")
DEV = ["station", "mobile"]


def enroll_words():
    pos = {d: R.load(f"{R.DIR}/pos/{d}/pos_{d}.wav") for d in DEV}
    lag, _ = R.lag_samples(pos["station"], pos["mobile"])
    n = min(len(pos["station"]), len(pos["mobile"]) + lag)
    mob = np.zeros(len(pos["station"]), "float32")
    src = pos["mobile"][max(0, -lag):]; dst = max(0, lag)
    mob[dst:dst + len(src)] = src[:len(mob) - dst]
    ra, rb = R.level_db(pos["station"][:n]), R.level_db(mob[:n])
    segs = R.segment(ra, rb)
    assert len(segs) == R.EXPECT_SEGS, len(segs)
    aud = {"station": pos["station"], "mobile": mob}
    m = int(0.08 * C.SR)
    # Segmente > 2 s sind keine Einzelwoerter (Segment 1 ist ein langer Satz): ausgelassen
    return [aud[d][max(0, s * R.FR - m):(p + 1) * R.FR + m].copy() for d in DEV for s, p in (segs[i - 1] for i in R.ENROLL)
            if (p - s) / R.FPS <= 2.0]


def load_net(path):
    net = make_net(128)
    m = onnx.load(path)
    sd = {i.name: torch.tensor(numpy_helper.to_array(i).copy()) for i in m.graph.initializer}
    net.load_state_dict(sd)
    return net


def personal_features(words, n, af, seed, ncpu):
    rng = np.random.default_rng(seed)
    fill = C.load_dir(f"{KWS}/wp58/gen/neg", limit=600, dtype="float32")
    pool = fill[:200]
    embs, ends, done = [], [], 0
    while done < n:
        m = min(64, n - done)
        clips, es = [], []
        for _ in range(m):
            x, e = C.build_clip(rng, fill, None, words[int(rng.integers(len(words)))])
            clips.append(C.augment(x, rng, pool)); es.append(e)
        embs.append(C.embed(af, clips, ncpu)); ends += es; done += m
    return np.concatenate(embs), np.array(ends)


def gather(emb, idx):
    return np.stack([emb[c, j:j + C.WIN] for c, j in idx]).astype("float32")


def finetune(base, a, words, pe, pend, d):
    torch.set_num_threads(a.threads); torch.manual_seed(a.seed); rng = np.random.default_rng(a.seed)
    net = load_net(f"{KWS}/wp58/out/wendelin_{base}.onnx")
    emb, end = d["emb"], d["end"]
    idx, y = windows(emb, end)
    pidx, py = windows(pe, pend)
    ineg = np.where(y == 0)[0]; isyn = np.where(y == 1)[0]; ipers = np.where(py == 1)[0]; pneg = np.where(py == 0)[0]
    print(f"{base}: neg {len(ineg)}, syn pos {len(isyn)}, personal pos {len(ipers)}, personal-clip neg {len(pneg)}", flush=True)
    sub = rng.choice(ineg, min(len(ineg), a.neg_sub), replace=False)
    Xn = torch.tensor(gather(emb, idx[sub]))
    Xp = torch.tensor(gather(pe, pidx[ipers])); Xs = torch.tensor(gather(emb, idx[isyn]))
    Xpn = torch.tensor(gather(pe, pidx[pneg]))
    Xn = torch.cat([Xn, Xpn]); w = np.ones(len(Xn))
    opt = torch.optim.Adam(net.parameters(), a.lr, weight_decay=1e-5)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, a.steps)
    bce = nn.BCELoss()
    t0 = time.time()
    for step in range(a.steps):
        if step and step % 250 == 0:
            net.eval()
            with torch.no_grad():
                s = torch.cat([net(Xn[i:i + 20000]).squeeze(1) for i in range(0, len(Xn), 20000)]).numpy()
            w = 1 + 20 * s ** 2
        nb = a.batch * 3 // 4; pb = a.batch // 8
        b = rng.choice(len(Xn), nb, p=w / w.sum())
        bp, bs = rng.choice(len(Xp), pb), rng.choice(len(Xs), a.batch - nb - pb)
        X = torch.cat([Xn[b], Xp[bp], Xs[bs]]); t = torch.cat([torch.zeros(nb), torch.ones(a.batch - nb)])
        net.train()
        loss = bce(net(X).squeeze(1), t)
        opt.zero_grad(); loss.backward(); opt.step(); sched.step()
        if step % 250 == 249 or step == a.steps - 1:
            net.eval()
            with torch.no_grad():
                rp = (net(Xp).squeeze(1) > .5).float().mean().item(); fn = (net(Xn[:50000]).squeeze(1) > .5).float().mean().item()
            print(f"{base} step {step+1} loss {loss.item():.4f} personal-train recall@0.5 {rp:.3f} neg-window FP@0.5 {fn:.5f} {time.time()-t0:.0f}s", flush=True)
    net.eval()
    out = f"{a.out}/ft_{base}.onnx"
    torch.onnx.export(net, torch.zeros(1, C.WIN, 96), out, input_names=["input"], output_names=["output"],
                      dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}}, opset_version=13, dynamo=False)
    print("exportiert", out, os.path.getsize(out), "Bytes", flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=f"{KWS}/wp106/finetune"); p.add_argument("--bases", default="v7,v9")
    p.add_argument("--feat", default=f"{KWS}/wp58/work5/feat_train.npz", help="WP58-Negativ-/Positiv-Features (nur Training)")
    p.add_argument("--n-clips", type=int, default=2000); p.add_argument("--steps", type=int, default=1200)
    p.add_argument("--lr", type=float, default=2e-4); p.add_argument("--batch", type=int, default=512)
    p.add_argument("--neg-sub", type=int, default=400000)
    p.add_argument("--threads", type=int, default=4); p.add_argument("--seed", type=int, default=1)
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    words = enroll_words()
    print("Einlern-Woerter", len(words), [round(len(w) / C.SR, 2) for w in words], flush=True)
    af = C.make_features(f"{KWS}/wp58/dl/oww", a.threads)
    cache = f"{a.out}/personal_feat.npz"
    if os.path.exists(cache):
        z = np.load(cache); pe, pend = z["emb"], z["end"]
    else:
        pe, pend = personal_features(words, a.n_clips, af, a.seed, a.threads)
        np.savez(cache, emb=pe, end=pend)
    print("persoenliche Clips", pe.shape, flush=True)
    d = np.load(a.feat)
    d = {"emb": d["emb"], "end": d["end"]}
    for base in a.bases.split(","):
        finetune(base, a, words, pe, pend, d)


if __name__ == "__main__":
    main()
