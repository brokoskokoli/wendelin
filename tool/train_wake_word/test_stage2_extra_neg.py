"""Selbsttest (stdlib unittest, erfundene Mini-Daten, ohne Modelle/Audio) fuer stage2_extra_neg.py (WP133 A3: zusaetzliche Negativquellen fuer das Band).
Lauf (Venv mit numpy/soundfile/piper, z. B. wp58):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_stage2_extra_neg.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import json, os, sys, tempfile, unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np  # noqa: E402
import words_measure as W  # noqa: E402
import stage2_cut as C  # noqa: E402
import stage2_extra_neg as E  # noqa: E402
import v8_measure as V  # noqa: E402


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


class TagTest(unittest.TestCase):
    """--tag: Caches/Kurven/Berichte des gewaehlten Tags, nicht die von v8a (Mini-Daten in tmp, V.RES und E.TAG werden gesetzt)."""
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.res = self.tmp.name
        for patch in (mock.patch.object(V, "RES", self.res), mock.patch.object(V, "CACHE_TAG", {}), mock.patch.object(E, "TAG", E.TAG)):
            patch.start(); self.addCleanup(patch.stop)

    def put_s1x(self, tag, val):
        p = E.s1x_path(tag, E.NEW_SRC[0]); os.makedirs(os.path.dirname(p), exist_ok=True)
        np.savez_compressed(p, **{"x|t": np.zeros(2, "float32"), "x|s": np.full(2, val, "float32")})

    def put_cut(self, tag, txt):
        for w in V.WORDS:
            p = C.cut_path(tag, w, *E.CUT, False); os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as fh: json.dump({"k": txt}, fh)

    def test_curves_follow_tag(self):
        self.put_s1x("v8a", 0.1); self.put_s1x("ca1", 0.9)
        for tag in ("v8a", "ca1"):                            # zweite Quelle leer, nur die erste zaehlt
            np.savez_compressed(E.s1x_path(tag, E.NEW_SRC[1]))
        E.TAG = "ca1"
        self.assertAlmostEqual(float(E.load_new_curves()[E.NEW_SRC[0]]["x"][1][0]), 0.9, places=5)
        E.TAG = "v8a"
        self.assertAlmostEqual(float(E.load_new_curves()[E.NEW_SRC[0]]["x"][1][0]), 0.1, places=5)

    def test_cut_cache_follows_tag_and_missing_is_reported(self):
        self.put_cut("v8a", "alt"); self.put_cut("ca1", "neu")
        E.TAG = "ca1"
        for w in V.WORDS:                                     # s2n nur fuer ca1
            p = E.s2n_path(w, False); os.makedirs(os.path.dirname(p), exist_ok=True); 
            with open(p, "w") as fh: json.dump({"n": "x"}, fh)
        tx = E.load_tx()[(*E.CUT, False)]
        self.assertEqual(tx[V.WORDS[0]], {"k": "neu", "n": "x"})
        E.TAG = "v8a"
        self.assertEqual(E.missing_caches(E.load_tx()), [(False, w) for w in V.WORDS] + [(True, w) for w in V.WORDS])
        E.TAG = "ca1"
        self.assertEqual([m for m in E.missing_caches(E.load_tx()) if not m[0]], [])

    def test_report_path_per_tag(self):
        self.assertTrue(E.report_path("v8a").endswith("/stage2_extra_neg.md"))
        self.assertTrue(E.report_path("v8a", True).endswith("/stage2_extra_neg_passed.local.md"))
        self.assertTrue(E.report_path("ca1").endswith("/stage2_extra_neg_ca1.md"))
        self.assertTrue(E.report_path("ca1", True).endswith("/stage2_extra_neg_passed_ca1.local.md"))

    def test_title_names_tag(self):
        E.TAG = "ca1"
        res = {(s, w, vn, t): None for s in E.NEW_SRC + E.OLD_SRC for w in V.WORDS for vn in E.VARIANTS for t in E.THRS}
        with mock.patch.object(E, "hours", return_value=1.0), mock.patch.object(E, "clip_paths", return_value={}):
            self.assertIn(": ca1, App-Bezug", E.render(res).splitlines()[0])

    def test_main_requires_model_for_tag(self):
        m = os.path.join(self.res, "m.onnx"); 
        with open(m, "w") as fh: fh.write("x")
        with mock.patch.object(sys, "argv", ["x", "--tag", "ca1", "--model", f"fc1={m}"]):
            with self.assertRaises(SystemExit) as cm: E.main()
        self.assertIn("ca1", str(cm.exception))
        self.assertEqual(E.TAG, "ca1")

    def run_main(self, *extra):
        m = os.path.join(self.res, "m.onnx")
        with open(m, "w") as fh: fh.write("x")
        files = [("a", 1.0)]
        with mock.patch.object(sys, "argv", ["x", "--tag", "ca1", "--model", f"ca1={m}", *extra]), \
                mock.patch.object(E, "fleurs_files", return_value=files), mock.patch.object(W, "clip_list", return_value=files), \
                mock.patch.object(E, "split_first_hour", return_value=(files, [])), \
                mock.patch.object(V, "load_curves", return_value={}), mock.patch.object(E, "load_new_curves", return_value={}), \
                mock.patch.object(E, "run_s1x") as s1x, mock.patch.object(E, "run_s2n") as s2n:
            with self.assertRaises(SystemExit) as cm: E.main()
        return str(cm.exception), s1x, s2n

    def test_main_aborts_without_s2n_cache(self):
        self.put_cut("ca1", "neu")                            # s2p da, s2n fehlt
        msg, s1x, _ = self.run_main("--report-only")
        self.assertIn("hw2-Caches fehlen", msg)
        s1x.assert_not_called()

    def test_main_checks_s2p_before_compute(self):
        msg, s1x, s2n = self.run_main()                       # kein s2p-Cache: vor den Rechenlaeufen Abbruch
        self.assertIn("s2p-Caches fehlen", msg)
        self.assertIn("--cut-only", msg)
        s1x.assert_not_called(); s2n.assert_not_called()


if __name__ == "__main__":
    unittest.main()
