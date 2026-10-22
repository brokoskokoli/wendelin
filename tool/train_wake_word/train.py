#!/usr/bin/env python3
"""Trainiert den openWakeWord-Klassifikator fuer „Wendelin“ (WP58).

  python train.py features --gen <gen-ordner> --models <oww-modelle> --work <arbeitsordner> [--n-pos N --n-neg N]
  python train.py train    --work <arbeitsordner> --out <modell.onnx>

Stufe 1 baut aus synthetischen Piper-Clips augmentierte 4-s-Clips (Positiv mit bekanntem
Wortende, Negativ), berechnet die eingefrorenen openWakeWord-Embeddings. Stufe 2 trainiert
den kleinen Klassifikator (16x96 -> DNN) mit Hard-Negative-Gewichtung und exportiert ONNX.
"""
import argparse, os, sys, time
import numpy as np
import torch
from torch import nn
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *


def feat_stage(a):
    rng = np.random.default_rng(a.seed)
    ld = lambda names, **k: sum((load_dir(os.path.join(a.gen, n), dtype="float16", **k) for n in names.split(",") if n), [])
    pos = ld(a.pos_dirs, max_s=1.8)
    rng.shuffle(pos)
    # WP130: echte Positive (nur Trainings-Split, siehe real_split.py), mehrfach in den Trainings-Positiven; Val bleibt synthetisch
    real_pos = load_dir(a.real_pos, dtype="float16", max_s=2.2) if a.real_pos else []
    conf = ld(a.conf_dirs)
    neg = ld(a.neg_dirs)
    # Echte Sprache (FLEURS, CC-BY 4.0): --real (Train, Komma-Liste) / --real-val (z. B. dev, sprecherfremd);
    # ohne --real-val: letzte 10 % der Liste als Val (v7-Verhalten)
    real = sum((load_dir(d, dtype="float16") for d in a.real.split(",") if d), []) if a.real else []
    cut = lambda l: int(len(l) * .9)
    if a.real_val:
        real_tr, real_va = real, sum((load_dir(d, dtype="float16") for d in a.real_val.split(",")), [])
    else:
        real_tr, real_va = real[:cut(real)], real[cut(real):]
    neg_tr = neg[:cut(neg)] + real_tr * a.real_rep
    neg_va = neg[cut(neg):cut(neg) + 600] + real_va * max(1, a.real_rep // 2)
    print(f"real_pos {len(real_pos)} x{a.real_pos_rep}", flush=True)
    print(f"pos {len(pos)}, conf {len(conf)}, neg {len(neg)} ({sum(map(len,neg))/SR/3600:.1f} h), real {len(real)}", flush=True)
    af = make_features(a.models, ncpu=a.ncpu)
    pool = neg[:200]
    t0 = time.time()
    for split in ("train", "val"):
        npos = a.n_pos if split == "train" else a.n_pos // 9
        nneg = a.n_neg if split == "train" else a.n_neg // 9
        ps = pos[: int(len(pos) * .9)] + real_pos * a.real_pos_rep if split == "train" else pos[int(len(pos) * .9):]
        ns = neg_tr if split == "train" else neg_va
        cs = conf[: int(len(conf) * .9)] if split == "train" else conf[int(len(conf) * .9):]
        embs, ends = [], []
        for kind, n in (("pos", npos), ("neg", nneg)):
            done = 0
            while done < n:
                m = min(128, n - done)
                clips, es = [], []
                for _ in range(m):
                    w = ps[int(rng.integers(len(ps)))] if kind == "pos" else None
                    x, e = build_clip(rng, ns, cs, w)
                    clips.append(augment(x, rng, pool)); es.append(-1 if e is None else e)
                embs.append(embed(af, clips, a.ncpu)); ends += es
                done += m
                print(f"{split} {kind} {done}/{n} {time.time()-t0:.0f}s", flush=True)
        np.savez(os.path.join(a.work, f"feat_{split}.npz"), emb=np.concatenate(embs), end=np.array(ends))


def windows(emb, end):
    """-> X (N,16,96), y (N,) mit y=1 bei Fenster-Ende 0..0,8 s nach Wortende (Wort noch im Fenster), -1 = ignoriert."""
    X, y = [], []
    nf = emb.shape[1]
    for c in range(len(emb)):
        for j in range(nf - WIN + 1):
            if end[c] < 0:
                lab = 0
            else:
                d = (window_end(j) - end[c]) / SR
                lab = 1 if 0 <= d <= 0.8 else (-1 if -0.5 < d < 2.2 else 0)
            if lab >= 0:
                X.append((c, j)); y.append(lab)
    idx = np.array(X)
    return idx, np.array(y)


def gather(emb, idx):
    return np.stack([emb[c, j:j + WIN] for c, j in idx])


def make_net(h=128):
    return nn.Sequential(nn.Flatten(), nn.Linear(WIN * 96, h), nn.LayerNorm(h), nn.ReLU(), nn.Dropout(0.3),
                         nn.Linear(h, h), nn.LayerNorm(h), nn.ReLU(), nn.Linear(h, 1), nn.Sigmoid())


def train_stage(a):
    torch.set_num_threads(a.threads)
    torch.manual_seed(a.seed); rng = np.random.default_rng(a.seed)
    d = {s: np.load(os.path.join(a.work, f"feat_{s}.npz")) for s in ("train", "val")}
    idx, y = windows(d["train"]["emb"], d["train"]["end"])
    vidx, vy = windows(d["val"]["emb"], d["val"]["end"])
    Xt = torch.from_numpy(gather(d["train"]["emb"], idx)); yt = torch.tensor(y, dtype=torch.float32)
    Xv = torch.from_numpy(gather(d["val"]["emb"], vidx)); yv = vy
    print(f"train: {int(y.sum())} pos / {int((y==0).sum())} neg Fenster; val: {int(vy.sum())} / {int((vy==0).sum())}", flush=True)
    net = make_net(a.hidden)
    opt = torch.optim.Adam(net.parameters(), 1e-3, weight_decay=1e-5)
    steps = a.steps
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, 2e-3, total_steps=steps)
    ip = np.where(y == 1)[0]; ineg = np.where(y == 0)[0]
    w = np.ones(len(ineg))
    bce = nn.BCELoss(reduction="none")
    for step in range(steps):
        if step and step % 500 == 0:       # Hard-Negative-Gewichte neu berechnen
            with torch.no_grad():       # in Bloecken: Xt[ineg] auf einmal waere eine Kopie von mehreren GB
                s = np.concatenate([net(Xt[ineg[i:i + 65536]]).squeeze(1).numpy() for i in range(0, len(ineg), 65536)])
            w = 1 + 20 * s ** 2
        bn = rng.choice(ineg, a.batch * 3 // 4, p=w / w.sum()); bp = rng.choice(ip, a.batch // 4)
        b = np.concatenate([bn, bp])
        net.train()
        out = net(Xt[b]).squeeze(1)
        loss = (bce(out, yt[b]) * torch.where(yt[b] == 1, 1.0, 1.0)).mean()
        opt.zero_grad(); loss.backward(); opt.step(); sched.step()
        if step % 500 == 499 or step == steps - 1:
            net.eval()
            with torch.no_grad():
                sv = net(Xv).squeeze(1).numpy()
            tp = (sv[yv == 1] > .5).mean(); fp = (sv[yv == 0] > .5).mean()
            print(f"step {step+1} loss {loss.item():.4f} val recall@0.5 {tp:.3f} val FP-window@0.5 {fp:.5f}", flush=True)
    net.eval()
    torch.onnx.export(net, torch.zeros(1, WIN, 96), a.out, input_names=["input"], output_names=["output"],
                      dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
                      opset_version=13, dynamo=False)
    print("exportiert", a.out, os.path.getsize(a.out), "Bytes")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("stage", choices=["features", "train"])
    p.add_argument("--gen"); p.add_argument("--models"); p.add_argument("--work", required=True)
    p.add_argument("--out"); p.add_argument("--real"); p.add_argument("--seed", type=int, default=1)
    p.add_argument("--pos-dirs", default="pos,pos2"); p.add_argument("--conf-dirs", default="conf2")
    p.add_argument("--neg-dirs", default="neg"); p.add_argument("--real-val"); p.add_argument("--real-pos"); p.add_argument("--real-pos-rep", type=int, default=100); p.add_argument("--real-rep", type=int, default=12)
    p.add_argument("--n-pos", type=int, default=8000); p.add_argument("--n-neg", type=int, default=9000)
    p.add_argument("--ncpu", type=int, default=4); p.add_argument("--threads", type=int, default=4)
    p.add_argument("--steps", type=int, default=6000); p.add_argument("--batch", type=int, default=512)
    p.add_argument("--hidden", type=int, default=128)
    a = p.parse_args()
    os.makedirs(a.work, exist_ok=True)
    (feat_stage if a.stage == "features" else train_stage)(a)
