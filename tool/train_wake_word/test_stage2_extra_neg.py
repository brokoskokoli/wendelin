"""Selbsttest (stdlib unittest, erfundene Mini-Daten, ohne Modelle/Audio) fuer stage2_extra_neg.py (WP133 A3: zusaetzliche Negativquellen fuer das Band).
Lauf (Venv mit numpy/soundfile/piper, z. B. wp58):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_stage2_extra_neg.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np  # noqa: E402
import words_measure as W  # noqa: E402
import stage2_cut as C  # noqa: E402
import stage2_extra_neg as E  # noqa: E402


def curve(points, n=400, step=0.08):
    """Kurve mit Grundwert 0 und gesetzten Werten {Index: Wert}."""
    t = np.arange(n) * step + 2.0
    v = np.zeros(n)
    for i, x in points.items(): v[i] = x
    return t, v


class SplitTest(unittest.TestCase):
    def test_clip_after_crossing_goes_to_rest(self):
        files = [("a", 2000.0), ("b", 1700.0), ("c", 500.0), ("d", 100.0)]      # nach b: 3700 s >= 3600 s (b ueberschreitet und bleibt vorn)
        first, rest = E.split_first_hour(files)
        self.assertEqual([n for n, _ in first], ["a", "b"])
        self.assertEqual([n for n, _ in rest], ["c", "d"])

    def test_exact_hour_goes_to_rest(self):
        first, rest = E.split_first_hour([("a", 3600.0), ("b", 10.0)])
        self.assertEqual(([n for n, _ in first], [n for n, _ in rest]), (["a"], ["b"]))

    def test_short_list_has_no_rest(self):
        self.assertEqual(E.split_first_hour([("a", 10.0)])[1], [])


class PoissonTest(unittest.TestCase):
    def test_zero_events(self):
        self.assertAlmostEqual(E.poisson_upper(0, 1.0), 3.6889, places=3)

    def test_known_value_and_scaling(self):
        self.assertAlmostEqual(E.poisson_upper(5, 1.0), 11.668, places=2)
        self.assertAlmostEqual(E.poisson_upper(5, 2.0), E.poisson_upper(5, 1.0) / 2, places=6)

    def test_monotonic_and_above_point_estimate(self):
        ub = [E.poisson_upper(k, 1.0) for k in range(8)]
        self.assertEqual(ub, sorted(ub))
        self.assertTrue(all(u > k for k, u in enumerate(ub)))

    def test_no_hours(self):
        self.assertEqual(E.poisson_upper(1, 0.0), float("inf"))


class CountTest(unittest.TestCase):
    def setUp(self):
        # Ereignis 1: Spitze 0,97 (Band), Ereignis 2: 0,9995 (direkt angenommen), mit >= 1,5 s Abstand; zweiter Clip ohne Ereignis
        self.curves = {"s": {"a": curve({10: 0.97, 11: 0.5, 100: 0.9995, 101: 0.5}), "b": curve({})}}

    def test_pass_all(self):
        r, passed = E.fa_count(self.curves, "s", 0.95, C.APP_UPPER, lambda pk: (lambda *_: True))
        self.assertEqual((r["n_ev"], r["n_pass"], r["n_clip"], r["n_top"]), (2, 2, 1, 1))
        self.assertEqual(len(passed), 2)

    def test_filter_and_top(self):
        r, passed = E.fa_count(self.curves, "s", 0.95, 0.999, lambda pk: (lambda s, i, t: pk[(s, i, W.seg_key(s, i, t))] >= 0.999))
        self.assertEqual((r["n_ev"], r["n_pass"], r["n_clip"], r["n_top"]), (2, 1, 1, 1))
        self.assertAlmostEqual(passed[0][2], 0.9995)

    def test_none_pass(self):
        r, passed = E.fa_count(self.curves, "s", 0.95, C.APP_UPPER, lambda pk: (lambda *_: False))
        self.assertEqual((r["n_pass"], r["n_clip"], passed), (0, 0, []))


class PoolTest(unittest.TestCase):
    def test_sum(self):
        a = ({"n_pass": 1, "n_ev": 2}, 1.5)
        b = ({"n_pass": 3, "n_ev": 4}, 2.0)
        self.assertEqual(E.merge_pool([a, b]), ({"n_pass": 4, "n_ev": 6}, 3.5))

    def test_missing(self):
        self.assertIsNone(E.merge_pool([({"n_pass": 1}, 1.0), None]))

    def test_cell(self):
        self.assertEqual(E.cell({"n_pass": 0}, 2.0), "0 (0,00/h, ≤1,84)")
        self.assertEqual(E.cell(None, 2.0), "-")


class CacheTest(unittest.TestCase):
    def test_new_cache_is_separate(self):
        for norm in (False, True):
            self.assertNotEqual(E.s2n_path("Wendelin", norm), C.cut_path(E.TAG, "Wendelin", *E.CUT, norm))
            self.assertIn("/s2n/", E.s2n_path("Wendelin", norm))

    def test_variants_exist(self):
        for vn in E.VARIANTS[1:]: self.assertIn(vn, C.VARS)
        self.assertEqual(C.VARS["app-2.0-0.9-b995"]["upper"], C.APP_UPPER)
        self.assertEqual(C.VARS["app-2.0-0.9-b999"]["upper"], 0.999)


if __name__ == "__main__":
    unittest.main()
