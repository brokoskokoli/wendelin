"""Selbsttest (stdlib unittest, erfundene Daten) fuer den festen Trainings-/Pruefsplit der echten Positive (WP130).
Lauf (Venv mit numpy/soundfile, z. B. wp58):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_real_split.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import os, sys, tempfile, unittest
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import real_split as R   # noqa: E402
import gen_samples as G  # noqa: E402

WORDS = ["Wendelin", "Hey Wendelin", "Alexa", "Hey Octavia", "Kobalos"]


def rows():
    out = []
    for g in ("huawei", "handy2"):
        for b in range(1, 7):
            for i, w in enumerate(WORDS):
                out.append(dict(geraet=g, block=str(b), runde="1", wort=w, start=str(10 * i + 100 * b), ende=str(10 * i + 100 * b + 1),
                                status="ok"))
    return out


class Split(unittest.TestCase):
    def test_nur_huawei_block_1_bis_3_und_beide_woerter(self):
        sel = R.select(rows())
        self.assertEqual(len(sel), 3 * 2)
        for r in sel:
            self.assertEqual(r["geraet"], "huawei"); self.assertIn(int(r["block"]), (1, 2, 3))
            self.assertIn(r["wort"], ("Wendelin", "Hey Wendelin"))

    def test_pruefclips_nie(self):
        for r in rows():
            if r["geraet"] != "huawei" or int(r["block"]) >= 4:
                self.assertFalse(R.is_train_clip(r), r)

    def test_fehler_und_zu_lange_und_unlesbare(self):
        base = dict(geraet="huawei", block="2", runde="1", wort="Wendelin", start="5", ende="6", status="ok")
        self.assertTrue(R.is_train_clip(base))
        self.assertFalse(R.is_train_clip(dict(base, status="fehler")))
        self.assertFalse(R.is_train_clip(dict(base, status="")))
        self.assertTrue(R.is_train_clip(dict(base, status="unsicher")))
        self.assertFalse(R.is_train_clip(dict(base, status="unsicher", ende="9")))
        self.assertFalse(R.is_train_clip(dict(base, block="x")))
        self.assertFalse(R.is_train_clip({}))

    def test_quelle_nur_huawei(self):
        self.assertEqual(set(R.SOURCES), {"huawei"})
        self.assertNotIn("neg", R.SOURCES["huawei"])
        with self.assertRaises(ValueError):
            R.source_for("handy2")

    def test_geschnittene_clips_nur_aus_trainingszeilen(self):
        x = np.random.default_rng(1).standard_normal(R.SR * 700).astype("float32") * 0.1
        names = [n for n, _ in R.cut_clips(rows(), x)]
        self.assertEqual(len(names), 6)
        self.assertTrue(all(n.startswith("huawei_b") and int(n.split("_")[1][1:]) <= 3 for n in names))

    def test_check_dir_lehnt_pruefclip_ab(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "huawei_b2_r01_bare_000100.wav"), "w").close()
            R.check_dir(d)
            open(os.path.join(d, "huawei_b4_r01_bare_000100.wav"), "w").close()
            with self.assertRaises(SystemExit):
                R.check_dir(d)


class CutFirstWord(unittest.TestCase):
    def sig(self, parts):
        rng = np.random.default_rng(2)
        return np.concatenate([(rng.standard_normal(int(d * 16000)) * a).astype("float32") for d, a in parts])

    def test_schneidet_an_der_pause(self):
        x = self.sig([(0.5, 0.3), (0.25, 0.0001), (0.8, 0.3)])
        c = G.cut_first_word(x)
        self.assertIsNotNone(c); self.assertAlmostEqual(len(c) / 16000, 0.5, delta=0.05)

    def test_ohne_pause_none(self):
        self.assertIsNone(G.cut_first_word(self.sig([(1.2, 0.3)])))
        self.assertIsNone(G.cut_first_word(np.zeros(16000, "float32")))


if __name__ == "__main__":
    unittest.main()
