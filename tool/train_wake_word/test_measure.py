"""Selbsttests (stdlib unittest, ohne Modelle/Audio) fuer die Messhelfer von WP111.
Lauf (Venv mit numpy/scipy, z. B. wp58):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_measure.py'
Hinweis: Das Gate (tool/gate.dart, tool/t.sh) fuehrt keine Python-Tests aus."""
import os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import kws_measure as K            # noqa: E402
import station_measure as S        # noqa: E402


class HeyRule(unittest.TestCase):
    def test_hey_pflicht(self):
        self.assertFalse(K.matches_hey_wake_word("Hallo Wendelin"))
        self.assertFalse(K.matches_hey_wake_word("Wendelin"))
        self.assertTrue(K.matches_wake_word("Wendelin"))

    def test_hey_wendelin_varianten(self):
        for t in ["Hey Wendelin", "hey Vendelin wie spät", "Heywendelin", "Hei Wendelin", "hey wen delin"]:
            self.assertTrue(K.matches_hey_wake_word(t), t)

    def test_verwechsler(self):
        for t in ["Hey Wendel", "Hey Berlin"]:
            self.assertFalse(K.matches_hey_wake_word(t), t)

    def test_funktionswort_trennt(self):
        self.assertFalse(K.matches_hey_wake_word("hey in wendelin"))
        self.assertFalse(K.matches_hey_wake_word("hey wendel in der Küche"))   # Funktionswort nach dem Teilwort trennt nicht zusammen


class Stats(unittest.TestCase):
    def test_wilson(self):
        self.assertEqual(S.wilson(0, 0), (0.0, 0.0))
        lo, hi = S.wilson(40, 50)
        self.assertAlmostEqual(lo, 0.6696, places=3); self.assertAlmostEqual(hi, 0.8876, places=3)
        self.assertEqual(S.wilson(0, 10)[0], 0.0); self.assertEqual(S.wilson(10, 10)[1], 1.0)
        self.assertAlmostEqual(S.wilson(0, 10)[1], 0.2775, places=3)

    def test_poisson_upper(self):
        self.assertAlmostEqual(S.poisson_upper(0, 1), 3.689, places=3)
        self.assertAlmostEqual(S.poisson_upper(2, 2), 3.612, places=3)
        self.assertAlmostEqual(S.poisson_upper(0, 2), S.poisson_upper(0, 1) / 2, places=6)


class Rules(unittest.TestCase):
    def test_parse_rules(self):
        r = S.parse_rules("T0.9,M0.5, W0.8,Kz2/0.15")
        self.assertEqual([x["kind"] for x in r], ["T", "M", "W", "K"])
        self.assertEqual(r[0]["thr"], 0.9)
        self.assertEqual(r[2]["name"], "W0.8")
        self.assertEqual((r[3]["model"], r[3]["boost"], r[3]["thr"]), ("z", 2.0, 0.15))
        self.assertEqual(S.parse_rules("Kg4/0.05")[0]["model"], "g")


class Pairs(unittest.TestCase):
    def test_paare_gleich(self):
        S.check_pairs(["a/x_1.wav", "a/y_2.wav"], ["b/x_1.wav", "b/y_2.wav"])

    def test_paare_ungleich(self):
        with self.assertRaises(AssertionError):
            S.check_pairs(["a/x_1.wav", "a/y_2.wav"], ["b/x_1.wav", "b/z_2.wav"])
        with self.assertRaises(AssertionError):
            S.check_pairs(["a/x_1.wav"], ["b/x_1.wav", "b/y_2.wav"])


class Exclusion(unittest.TestCase):
    def test_ausschluss(self):
        clips = [{"name": n} for n in ["a.wav", "b.wav", "c.wav", "d.wav", "b6-x.wav"]]
        scan = {"a.wav": {"hit": False, "hit2": False},
                "b.wav": {"hit": True, "hit2": False},      # nur gemessener Erkenner hoert Wort
                "c.wav": {"hit": False, "hit2": True},      # nur zweiter Erkenner
                "d.wav": {"hit": False},                    # ohne zweiten Erkenner
                "b6-x.wav": {"hit": False, "hit2": False}}
        self.assertEqual(S.exclusion_names(clips, scan), ["b.wav", "c.wav", "b6-x.wav"])

    def test_cache_neuscan(self):
        self.assertTrue(S.scan_current({"n": 5, "hit": False}, 5, False))
        self.assertTrue(S.scan_current({"n": 5, "hit": False, "hit2": False}, 5, True))
        self.assertFalse(S.scan_current({"n": 5, "hit": False}, 5, True))     # ohne Whisper-Treffer-Feld: neu scannen
        self.assertFalse(S.scan_current({"n": 6, "hit": False, "hit2": False}, 5, True))
        self.assertFalse(S.scan_current(None, 5, False))


if __name__ == "__main__":
    unittest.main()
