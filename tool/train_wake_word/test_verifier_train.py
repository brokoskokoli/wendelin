"""Selbsttest (stdlib unittest, erfundene Mini-Daten) fuer verifier_train.py (WP137 Teil 2: Pruefer A).
Lauf:  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_verifier_train.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import json, os, sys, tempfile, unittest
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np  # noqa: E402
import verifier_data as D  # noqa: E402
import verifier_train as T  # noqa: E402

K = D.KIND


def toy(n=240, f=25, seed=0, signal=2.0, groups=3):
    """Mini-Satz: Positive (hey, bare) mit Signal in den letzten Frames, Negative (Verwechsler, Mining) ohne; alle im Band."""
    rng = np.random.default_rng(seed)
    parts = []
    for i, (kind, word) in enumerate([(K["pos_syn"], "hey"), (K["pos_real"], "bare"), (K["conf"], None), (K["mined"], None)] * (n // 4)):
        e = rng.standard_normal((1, f, 96)).astype("float32")
        if word == "hey": e[0, -8:, :12] += signal
        if word == "bare": e[0, -8:, 12:24] += signal
        parts.append(D.Examples(**D.make_rows(e, [0.99], kind, word, [i % groups])))
    return D.Examples.concat(parts)


class Netz(unittest.TestCase):
    def test_groesse_und_form(self):
        net = T.Net(25)
        self.assertLessEqual(T.n_params(net), T.MAX_PARAMS)
        import torch
        self.assertEqual(tuple(net(torch.zeros(3, 25, 96)).shape), (3, 2))

    def test_nicht_teilbare_frames(self):
        import torch
        self.assertEqual(tuple(T.Net(26).eval()(torch.zeros(2, 26, 96)).shape), (2, 2))

    def test_onnx_export_paritaet_und_groessengrenze(self):
        net = T.Net(26).eval()
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "m.onnx")
            sha = T.export_onnx(net, p)
            self.assertEqual(len(sha), 64); self.assertLess(os.path.getsize(p), T.MAX_BYTES)
            old = T.MAX_BYTES; T.MAX_BYTES = 1000
            try:
                with self.assertRaises(SystemExit): T.export_onnx(net, p)
            finally: T.MAX_BYTES = old


class Schwelle(unittest.TestCase):
    def test_niedrigste_schwelle_mit_verwerfung(self):
        neg = np.array([True] * 10 + [False] * 4)
        sc = np.array([0.05, 0.1, 0.1, 0.2, 0.2, 0.3, 0.3, 0.4, 0.5, 0.9, 0.6, 0.7, 0.8, 0.95])
        pos = ~neg
        thr, acc, rej = T.choose_threshold(sc, pos, neg, 0.9)
        self.assertGreaterEqual(rej, 0.9)                              # >= 90 % der Negativen verworfen
        self.assertEqual(thr, 0.9); self.assertEqual(acc, 0.25)       # niedrigste Schwelle: 9 von 10 Negativen < 0,9
        thr2, acc2, _ = T.choose_threshold(sc, pos, neg, 0.5)
        self.assertLess(thr2, thr); self.assertGreater(acc2, acc)

    def test_ohne_positive_oder_negative_verwirft_alles(self):
        z = np.zeros(3, bool)
        self.assertEqual(T.choose_threshold(np.array([.1, .2, .3]), np.array([1, 1, 0], bool), z), (1.0, 0.0, 1.0))
        self.assertEqual(T.choose_threshold(np.array([.1, .2, .3]), z, np.array([1, 1, 0], bool)), (1.0, 0.0, 1.0))

    def test_band_und_kopfmasken(self):
        ex = D.Examples.concat([D.Examples(**D.make_rows(np.zeros((1, 25, 96)), [p], K["pos_syn"], w, [0])) for p, w in
                                [(0.97, "hey"), (0.98, "hey"), (0.998, "bare"), (0.999, "hey"), (0.99, None)]])
        pw, nw = T.band_masks(ex, 0); ph, nh = T.band_masks(ex, 1)
        self.assertEqual(pw.tolist(), [False, True, True, False, False]); self.assertEqual(nw.tolist(), [False, False, False, False, True])
        self.assertEqual(ph.tolist(), [False, True, False, False, False]); self.assertEqual(nh.tolist(), [False, False, True, False, True])   # bare ist fuer HW negativ

    def test_gewichte(self):
        w = T.weights(np.array([K["conf"], K["pos_syn"], K["mined"]]), np.array([0.99, 0.99, 0.9], "float32"))
        self.assertEqual(w.tolist(), [6.0, 3.0, 2.0])


class Training(unittest.TestCase):
    def test_lernt_trennbares_und_oof_ohne_leck(self):
        ex = toy()
        oof = T.oof_scores(ex, 12, threads=1, batch=32)
        pos, neg = T.band_masks(ex, 1)
        self.assertGreater(oof[pos, 1].mean(), oof[neg, 1].mean() + 0.3)
        pw, nw = T.band_masks(ex, 0)                                    # Kopf W nimmt bare und hey an
        self.assertGreater(oof[pw, 0].mean(), oof[nw, 0].mean() + 0.3)

    def test_oof_ist_ehrlich_bei_unlernbaren_labels(self):
        # Zufallslabels: das Netz kann sie im Training auswendig lernen (hohe Treffer in-sample), OOF muss bei ~50 % bleiben
        rng = np.random.default_rng(3)
        ex = toy(n=120)
        y = rng.integers(0, 2, len(ex)).astype("int8")
        ex.d["yw"], ex.d["yhw"] = y, y.copy(); ex.d["kind"][:] = K["conf"]
        oof = T.oof_scores(ex, 40, threads=1, lr=5e-3, batch=32)
        acc_oof = ((oof[:, 0] > 0.5) == y).mean()
        net = T.fit(ex, np.arange(len(ex)), 60, threads=1, lr=5e-3, batch=32)
        acc_in = ((T.predict(net, ex.d["emb"])[:, 0] > 0.5) == y).mean()
        self.assertGreater(acc_in, 0.8); self.assertLess(acc_oof, 0.65)

    def test_leere_faltung_bricht_ab(self):
        ex = toy(n=40, groups=2)                                         # Gruppe 2 fehlt
        with self.assertRaises(SystemExit): T.oof_scores(ex, 1, threads=1)

    def test_run_schreibt_modell_meta_und_braucht_stempel(self):
        with tempfile.TemporaryDirectory() as t:
            f = os.path.join(t, "feat.npz"); toy().save(f)
            with self.assertRaises(D.LeakError): T.run([f], os.path.join(t, "o"), 2, threads=1, log=lambda *a: None)     # ohne Stempel
            D.write_stamp(f, {}, dict(pre=1.7, tail=0.6))
            meta = T.run([f], os.path.join(t, "o"), 1, threads=1, log=lambda *a: None)
            self.assertTrue(os.path.exists(os.path.join(t, "o", "verifier_a.onnx")))
            self.assertLessEqual(meta["params"], T.MAX_PARAMS); self.assertEqual(meta["frames"], 25)
            self.assertEqual((meta["pre"], meta["tail"]), (1.7, 0.6))                    # aus dem Stempel der Merkmalsdatei, nicht aus der CLI
            self.assertEqual(D._jload(os.path.join(t, "o", "verifier_a.onnx.meta.json"))["sha256"], meta["sha256"])
            self.assertEqual(np.load(os.path.join(t, "o", "oof.npz"))["oof"].shape, (len(toy()), 2))
            self.assertIn("| Schwelle |", D._read(os.path.join(t, "o", "sweep.md")).decode())


if __name__ == "__main__":
    unittest.main()
