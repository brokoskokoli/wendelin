"""Selbsttest (stdlib unittest, erfundene Daten, ohne Modelle) fuer template_center_measure.py (WP134).
Lauf (Venv mit numpy/scipy):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_template_center_measure.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import os, sys, unittest
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import template_center_measure as M  # noqa: E402


def row(dev="huawei", block=1, word="Wendelin", start=1.0, end=1.8, status="ok", runde=1):
    return dict(geraet=dev, block=str(block), runde=str(runde), wort=word, start=str(start), ende=str(end), status=status)


class Split(unittest.TestCase):
    def test_einlernen_nur_huawei_1_bis_3_wendelin(self):
        ok = [row(block=b) for b in (1, 2, 3)]
        self.assertTrue(all(M.is_train_row(r) for r in ok))
        for r in (row(block=4), row(dev="handy2"), row(word="Hey Wendelin"), row(status="fehler"), row(start=0, end=2.5), row(word="Alexa")):
            self.assertFalse(M.is_train_row(r), r)
        self.assertFalse(M.is_train_row({}))                       # fail-closed

    def test_pruefung_schliesst_einlernen_aus(self):
        every = [row(dev=d, block=b, word=w) for d in M.DEVICES for b in range(1, 7) for w in ("Wendelin", "Hey Wendelin", "Alexa")]
        ev = [r for r in every if M.is_eval_row(r)]
        self.assertEqual(len(ev), 18)
        self.assertFalse(any(M.is_train_row(r) for r in ev))
        self.assertFalse(any(r["geraet"] == "huawei" and int(r["block"]) <= 3 for r in ev))

    def test_pruefung_ohne_gepaarte_sitzung(self):
        rows = [row(dev=d, block=b, word=w, start=100.0 * b + 10 * i + (0.72 if d == "handy2" else 0)) for d in M.DEVICES for b in range(1, 7)
                for i, w in enumerate(("Wendelin", "Hey Wendelin", "Alexa"))]
        self.assertEqual(sorted({(r["geraet"], int(r["block"])) for r in M.pruef_rows(rows)}), [(d, b) for d in sorted(M.DEVICES) for b in (4, 5, 6)])


class Mathe(unittest.TestCase):
    def test_zentrieren_und_kosinus(self):
        rng = np.random.default_rng(1)
        mu = rng.normal(size=1536).astype("float32") * 5
        a, b = rng.normal(size=(2, 1536)).astype("float32")
        W, T = (mu + a)[None], (mu + b)[None]
        raw = M.best_sim(W, T, None)[0]
        cen = M.best_sim(W, T, mu)[0]
        self.assertGreater(raw, 0.9)                               # gemeinsamer Anteil dominiert
        self.assertAlmostEqual(float(cen), float(a @ b / np.linalg.norm(a) / np.linalg.norm(b)), places=4)

    def test_max_ueber_vorlagen_und_nullvektor(self):
        T = np.eye(4, 1536, dtype="float32")
        W = np.stack([T[2] * 3, np.zeros(1536, "float32")])
        s = M.best_sim(W, T, None)
        self.assertAlmostEqual(float(s[0]), 1.0, places=5)
        self.assertEqual(float(s[1]), 0.0)                         # wie cosineSimilarity: Nullvektor -> 0

    def test_fenster_aus_embeddings(self):
        E = np.arange(20 * 96, dtype="float32").reshape(20, 96)
        W = M.windows_from_emb(E)
        self.assertEqual(W.shape, (5, 1536))
        np.testing.assert_array_equal(W[1][:96], E[1]); np.testing.assert_array_equal(W[1][-96:], E[16])
        self.assertEqual(M.windows_from_emb(E[:10]).shape, (0, 1536))

    def test_fensterende(self):
        self.assertEqual(M.window_end(0), 25 * 1280)               # erstes Fenster nach Block 24 (0-basiert), Ende = Blockende
        self.assertEqual(M.window_end(3) - M.window_end(0), 3 * 1280)

    def test_ereignisse_mit_sperrzeit(self):
        t = np.arange(0, 10, 0.1); v = np.zeros(len(t)); v[[10, 12, 40, 90]] = 1
        self.assertEqual(M.events(t, v, 0.5, 1.5), [1.0, 4.0, 9.0])
        self.assertEqual(M.n_events(t, v, 2), 0)

    def test_schwelle_und_wilson(self):
        g = np.arange(0, 1, 0.1)
        self.assertEqual(M.pick_threshold(g, lambda th: 5 if th < 0.55 else 1, 2), g[6])
        self.assertIsNone(M.pick_threshold(g, lambda th: 9, 2))
        self.assertEqual(M.fa_limit(2.0, 1.22), 2)
        lo, hi = M.wilson(30, 30)
        self.assertLess(lo, 1.0); self.assertEqual(hi, 1.0)
        self.assertEqual(M.wilson(0, 0), (0.0, 0.0))


class Einlernen(unittest.TestCase):
    def test_polster_wie_embedUtterance(self):
        pcm = (np.arange(8000) % 100 + 1).astype("int16")
        s, tgt = M.pad_stream(pcm, 7000, "zero", np.random.default_rng(0))
        self.assertEqual(len(s), 16000 + 8000 + 32000)
        self.assertTrue((s[:16000] == 0).all() and (s[-32000:] == 0).all())
        self.assertEqual(tgt, 16000 + 7000)

    def test_rauschpolster_hat_pegel_des_vorlaufs(self):
        pcm = (np.random.default_rng(0).normal(0, 40, 8000)).astype("int16")
        s, _ = M.pad_stream(pcm, 7000, "noise", np.random.default_rng(1))
        self.assertAlmostEqual(float(s[:16000].std()), float(pcm[:3200].std()), delta=3.0)
        self.assertFalse((s[:16000] == 0).all())

    def test_fenster_naechstes_ende(self):
        tgt = M.window_end(10) + 100
        self.assertEqual(M.pick_window(30, tgt), 10)
        self.assertEqual(M.pick_window(5, M.window_end(100)), 4)

    def test_aufnahme_grenzen_wie_utterance_capture(self):
        x = np.zeros(10 * M.SR, "float32")
        a, b, se = M.capture_bounds(x, 2.0, 2.8)
        self.assertEqual(a, (2 * 50 - 10) * 320)                   # 10 Bloecke Vorlauf
        self.assertEqual(b, (int(2.8 * M.SR) // 320 + 1 + 8) * 320)
        self.assertEqual(se, (int(2.8 * M.SR) // 320 + 1) * 320 - a)


class Sauber(unittest.TestCase):
    def test_sauber_nimmt_nur_block_4_bis_6_und_prueft_sortierung(self):
        peaks = {"huawei": {"Wendelin": [.1, .2, .3, .4]}, "handy2": {"Wendelin": [.5, .6, .7, .8]}}
        blocks = {"huawei": {"Wendelin": [1, 3, 4, 6]}, "handy2": {"Wendelin": [1, 2, 5, 6]}}
        self.assertEqual(M.clean_peaks(peaks, blocks, "Wendelin"), [.3, .4, .7, .8])
        blocks["handy2"]["Wendelin"] = [5, 1, 2, 6]                # unsortiert -> Abbruch statt falscher Zuordnung
        with self.assertRaises(AssertionError):
            M.clean_peaks(peaks, blocks, "Wendelin")
        blocks["handy2"]["Wendelin"] = [1, 2, 5]                   # Laenge passt nicht
        with self.assertRaises(AssertionError):
            M.clean_peaks(peaks, blocks, "Wendelin")


class Export(unittest.TestCase):
    def test_dart_quelltext_rundreise(self):
        import base64, re
        mu = np.random.default_rng(3).normal(size=1536).astype("float32")
        src = M.dart_center_source(mu, "fv-test")
        self.assertIn("const wakeCenterFeatureVersion = 'fv-test';", src)
        b64 = "".join(re.findall(r"^\s+'([A-Za-z0-9+/=]+)'", src, re.M))
        np.testing.assert_array_equal(np.frombuffer(base64.b64decode(b64), "<f4"), mu)
        with self.assertRaises(AssertionError):
            M.dart_center_source(mu[:100], "x")
        with self.assertRaises(AssertionError):
            M.dart_center_source(np.full(1536, np.nan), "x")


if __name__ == "__main__":
    unittest.main()
