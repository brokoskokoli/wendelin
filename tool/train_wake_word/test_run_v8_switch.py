"""Selbsttest (stdlib unittest, Fake-Python, ohne Training/Download) fuer den Schalter REAL_POS in run_v8.sh und --no-real-pos (WP133).
Lauf (Venv wie test_v8_measure.py):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_run_v8_switch.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus. Das Skript laeuft gegen ein temporaeres K0 mit einem Fake-$PY, der nur seine Argumente protokolliert."""
import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import real_split as R   # noqa: E402

SH = os.path.join(HERE, "run_v8.sh")
FAKE = """#!/bin/sh
echo "$@" >> "$FAKELOG"
case "$*" in *" train "*|train\\ *) while [ $# -gt 0 ]; do [ "$1" = --out ] && : > "$2"; shift; done ;; esac
"""


class Env:
    def __init__(self, td):
        self.td, self.k0 = td, os.path.join(td, "kws")
        py = os.path.join(self.k0, "wp58", "venv", "bin", "python")
        os.makedirs(os.path.dirname(py)); open(py, "w").write(FAKE); os.chmod(py, 0o755)
        self.log = os.path.join(td, "calls.log"); open(self.log, "w").close()
        self.fix = os.path.join(td, "fix_sentinel")          # absichtlich nicht vorhanden: REAL_POS=0 darf ihn nie lesen

    def run(self, step, real_pos=None, **kw):
        env = dict(os.environ, K0=self.k0, FIX=self.fix, FAKELOG=self.log, **{k: str(v) for k, v in kw.items()})
        env.pop("REAL_POS", None)
        if real_pos is not None: env["REAL_POS"] = str(real_pos)
        return subprocess.run(["bash", SH, step], env=env, capture_output=True, text=True)

    def calls(self): return open(self.log).read().splitlines()
    def w(self, *p): return os.path.join(self.k0, "wp130", *p)


class Schalter(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory(); self.e = Env(self._td.name)

    def tearDown(self): self._td.cleanup()

    def test_real_pos_0_liest_fix_und_real_pos_nie(self):
        r = self.e.run("real_pos", 0)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.e.calls(), [])                                    # kein real_split.py cut
        self.assertFalse(os.path.exists(self.e.w("gen", ".done", "real_pos")))

    def test_standard_ist_wp130(self):
        for rp in (None, 1):
            open(self.e.log, "w").close()
            r = self.e.run("real_pos", rp)
            self.assertEqual(r.returncode, 0, r.stderr)
            c = self.e.calls()
            self.assertEqual(len(c), 1)
            self.assertIn("real_split.py cut --fix " + self.e.fix, c[0])
            self.assertIn(self.e.w("work", "real_pos"), c[0])
            self.assertTrue(os.path.exists(self.e.w("gen", ".done", "real_pos")))
            os.remove(self.e.w("gen", ".done", "real_pos"))

    def features(self, rp):
        r = self.e.run("features", rp); self.assertEqual(r.returncode, 0, r.stderr)
        (c,) = self.e.calls(); return c

    def test_features_ohne_real_pos(self):
        c = self.features(0)
        self.assertIn("--no-real-pos", c); self.assertNotIn("--real-pos", c.replace("--no-real-pos", ""))
        self.assertIn("--work " + self.e.w("work_syn"), c)
        self.assertTrue(os.path.exists(self.e.w("work_syn", "features.done")))
        self.assertFalse(os.path.exists(self.e.w("work", "features.done")))
        self.assertNotIn(self.e.fix, c)

    def test_features_standard_mit_real_pos(self):
        c = self.features(1)
        self.assertIn("--real-pos " + self.e.w("work", "real_pos") + " --real-pos-rep 100", c)
        self.assertNotIn("--no-real-pos", c); self.assertIn("--work " + self.e.w("work"), c)

    def test_syn_laeufe_teilen_arbeitsordner(self):
        for tag, hid in (("a-syn", 128), ("c-syn", 256)):
            r = self.e.run("train", 0, TAG=tag, HIDDEN=hid, STEPS=7, SEED=3); self.assertEqual(r.returncode, 0, r.stderr)
        calls = self.e.calls()
        self.assertTrue(all("--work " + self.e.w("work_syn") in c for c in calls))
        m = json.load(open(self.e.w("out", "wendelin_wp130_c-syn.onnx.meta.json")))
        self.assertEqual(m, {"real_pos": 0, "tag": "c-syn", "steps": 7, "seed": 3, "hidden": 256})
        self.assertEqual(json.load(open(self.e.w("out", "wendelin_wp130_a-syn.onnx.meta.json")))["hidden"], 128)

    def test_sidecar_auch_im_standard(self):
        self.assertEqual(self.e.run("train", None, TAG="z").returncode, 0)
        self.assertEqual(json.load(open(self.e.w("out", "wendelin_wp130_z.onnx.meta.json")))["real_pos"], 1)

    def test_wiederverwendung_nur_mit_passendem_schalter(self):
        self.assertEqual(self.e.run("train", 1, TAG="a").returncode, 0)
        self.assertNotEqual(self.e.run("train", 0, TAG="a").returncode, 0)          # a (real_pos 1) darf nicht als syn gelten
        os.remove(self.e.w("out", "wendelin_wp130_a.onnx.meta.json"))                # Altbestand ohne Sidecar (WP130)
        self.assertNotEqual(self.e.run("train", 0, TAG="a").returncode, 0)
        self.assertEqual(self.e.run("train", 1, TAG="a").returncode, 0)

    def test_ungueltiger_schalter(self):
        self.assertEqual(self.e.run("real_pos", 2).returncode, 2)
        self.assertEqual(self.e.run("real_pos", "x").returncode, 2)


class SynOnly(unittest.TestCase):
    def test_assert_syn_only(self):
        pos = [object() for _ in range(10)]; real = [object(), object()]
        for sp in ("train", "val"):
            R.assert_syn_only(R.pos_for_split(pos, [], 100, sp), pos, sp)
        with self.assertRaises(SystemExit): R.assert_syn_only(R.pos_for_split(pos, real, 100, "train"), pos, "train")
        with self.assertRaises(SystemExit): R.assert_syn_only(R.pos_for_split(pos, real, 1, "train"), pos, "train")
        with self.assertRaises(SystemExit): R.assert_syn_only(pos[:8] + real, pos, "train")        # gleiche Laenge, fremdes Element

    def test_train_py_verdrahtung(self):
        src = open(os.path.join(HERE, "train.py")).read()
        self.assertIn("real_split.assert_syn_only(ps, pos, split)", src)
        self.assertIn("if a.no_real_pos and a.real_pos:", src)
        self.assertIn('"--no-real-pos"', src)


if __name__ == "__main__":
    unittest.main()
