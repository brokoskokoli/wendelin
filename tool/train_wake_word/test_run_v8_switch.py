"""Selbsttest (stdlib unittest, Fake-Python, ohne Training/Download) fuer die Schalter REAL_POS, EXCLUDE_VOICES, V7_DATA in run_v8.sh und --no-real-pos (WP133, WP137).
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


FAKE_SHASUM = """#!/bin/sh
case "$*" in *" -c"*) cat >/dev/null; exit 0 ;; esac
exec /usr/bin/shasum "$@"
"""


class Env:
    def __init__(self, td):
        self.td, self.k0 = td, os.path.join(td, "kws")
        py = os.path.join(self.k0, "wp58", "venv", "bin", "python")
        os.makedirs(os.path.dirname(py)); open(py, "w").write(FAKE); os.chmod(py, 0o755)
        self.log = os.path.join(td, "calls.log"); open(self.log, "w").close()
        self.bin = os.path.join(td, "bin"); os.makedirs(self.bin)
        sh = os.path.join(self.bin, "shasum"); open(sh, "w").write(FAKE_SHASUM); os.chmod(sh, 0o755)    # verify_dl gegen Fake-Downloads
        self.fix = os.path.join(td, "fix_sentinel")          # absichtlich nicht vorhanden: REAL_POS=0 darf ihn nie lesen

    def run(self, step, real_pos=None, **kw):
        env = dict(os.environ, K0=self.k0, FIX=self.fix, FAKELOG=self.log, PATH=self.bin + os.pathsep + os.environ["PATH"], **{k: str(v) for k, v in kw.items()})
        env.pop("REAL_POS", None)
        if real_pos is not None: env["REAL_POS"] = str(real_pos)
        return subprocess.run(["bash", SH, step], env=env, capture_output=True, text=True)

    def dl(self, *voices):      # Fake-Download-Ordner (dl.done) mit Stimmenordnern v-<name>
        d = os.path.join(self.td, "dl"); os.makedirs(d)
        open(os.path.join(d, "dl.done"), "w").close()
        for v in voices: os.makedirs(os.path.join(d, "v-" + v))
        return d

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
        self.assertEqual(m, {"real_pos": 0, "tag": "c-syn", "steps": 7, "seed": 3, "hidden": 256,
                                     "exclude_voices": "", "v7_data": 1})
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


GEN = dict(real_pos=0, N_CV=0)


class Clean(unittest.TestCase):
    """WP137: EXCLUDE_VOICES und V7_DATA=0."""
    def setUp(self):
        self._td = tempfile.TemporaryDirectory(); self.e = Env(self._td.name)
        self.w = os.path.join(self._td.name, "wclean")

    def tearDown(self): self._td.cleanup()

    def gen(self, dl, **kw):
        r = self.e.run("gen", W=self.w, DL=dl, **dict(GEN, **kw)); return r

    def test_ausgeschlossene_stimme_fehlt_in_voices(self):
        dl = self.e.dl("xa", "va", "vb", "xb")
        r = self.gen(dl, EXCLUDE_VOICES="xa,xb"); self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(os.listdir(os.path.join(self.w, "voices"))), ["v-va", "v-vb"])
        self.assertEqual(open(os.path.join(self.w, "gen", "voices.txt")).read().split(), ["v-va", "v-vb"])
        gens = [c for c in self.e.calls() if "gen_samples.py" in c]
        self.assertEqual(len(gens), 6)                       # 3 Arten x NJ=2
        self.assertTrue(all("--voices " + os.path.join(self.w, "voices") in c for c in gens))
        self.assertFalse(any("v-xa" in c for c in self.e.calls()))

    def test_ohne_exclude_voices_direkt_auf_dl(self):
        dl = self.e.dl("xa", "va")
        r = self.gen(dl); self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.w, "voices")))
        self.assertTrue(all("--voices " + dl + " " in c + " " for c in self.e.calls() if "gen_samples.py" in c))

    def test_exclude_voices_nicht_im_wp130_ordner(self):
        dl = self.e.dl("xa", "va")
        r = self.e.run("gen", DL=dl, EXCLUDE_VOICES="xa", **GEN)          # W = Standard = kws/wp130
        self.assertEqual(r.returncode, 2); self.assertIn("eigenes W", r.stderr)
        self.assertEqual(self.e.calls(), [])

    def test_vorhandener_symlink_der_ausgeschlossenen_stimme_bricht_ab(self):
        dl = self.e.dl("xa", "va")
        os.makedirs(os.path.join(self.w, "voices")); os.symlink(os.path.join(dl, "v-xa"), os.path.join(self.w, "voices", "v-xa"))
        r = self.gen(dl, EXCLUDE_VOICES="xa"); self.assertEqual(r.returncode, 1); self.assertIn("xa", r.stderr)
        self.assertFalse(any("gen_samples.py" in c for c in self.e.calls()))

    def test_v7_data_0_verlinkt_nichts(self):
        dl = self.e.dl("va")
        for d in ("pos", "pos2", "conf2", "neg", "real/train", "real/dev"): os.makedirs(os.path.join(self.e.k0, "wp58", "gen", d))
        r = self.gen(dl, V7_DATA=0); self.assertEqual(r.returncode, 0, r.stderr)
        g = os.path.join(self.w, "gen")
        for d in ("pos", "pos2", "conf2", "neg"): self.assertFalse(os.path.lexists(os.path.join(g, d)), d)
        self.assertTrue(os.path.lexists(os.path.join(g, "real", "train")))      # FLEURS bleibt
        r = self.gen(dl); self.assertEqual(r.returncode, 0, r.stderr)           # Standard (V7_DATA=1) verlinkt
        self.assertTrue(os.path.lexists(os.path.join(g, "pos2")))

    def test_v7_data_0_features_nur_v8_verzeichnisse(self):
        r = self.e.run("features", W=self.w, V7_DATA=0, real_pos=0); self.assertEqual(r.returncode, 0, r.stderr)
        (c,) = self.e.calls()
        self.assertIn("--pos-dirs pos_v8 --conf-dirs conf_v8 --neg-dirs neg_v8,cv", c)
        self.assertIn("--real " + os.path.join(self.w, "gen", "real", "train"), c)
        self.assertIn("--work " + os.path.join(self.w, "work_syn_nov7"), c)
        for d in ("pos,", "pos2", "conf2", "neg,"): self.assertNotIn(d, c)

    def test_v7_data_1_features_wie_bisher(self):
        r = self.e.run("features", W=self.w, real_pos=0); self.assertEqual(r.returncode, 0, r.stderr)
        (c,) = self.e.calls()
        self.assertIn("--pos-dirs pos,pos2,pos_v8 --conf-dirs conf2,conf_v8 --neg-dirs neg,neg_v8,cv", c)

    def test_v7_data_0_bricht_ab_wenn_v7_verzeichnis_existiert(self):
        for d in ("pos", "pos2", "conf2", "neg"):
            with self.subTest(d=d):
                open(self.e.log, "w").close()
                p = os.path.join(self.w, "gen", d); os.makedirs(p)
                r = self.e.run("features", W=self.w, V7_DATA=0, real_pos=0)
                self.assertEqual(r.returncode, 1); self.assertIn(d, r.stderr); self.assertEqual(self.e.calls(), [])
                r = self.gen(self.e.dl() if not os.path.exists(os.path.join(self.e.td, "dl")) else os.path.join(self.e.td, "dl"), V7_DATA=0)
                self.assertEqual(r.returncode, 1)
                os.rmdir(p)

    def test_sidecar_felder_und_wiederverwendung(self):
        kw = dict(W=self.w, TAG="k", EXCLUDE_VOICES="xa", V7_DATA=0, real_pos=0)
        self.assertEqual(self.e.run("train", **kw).returncode, 0)
        m = json.load(open(os.path.join(self.w, "out", "wendelin_wp130_k.onnx.meta.json")))
        self.assertEqual((m["exclude_voices"], m["v7_data"]), ("xa", 0))
        self.assertEqual(self.e.run("train", **kw).returncode, 0)                                   # gleiche Einstellung: ok
        self.assertNotEqual(self.e.run("train", **dict(kw, V7_DATA=1)).returncode, 0)
        self.assertNotEqual(self.e.run("train", **dict(kw, EXCLUDE_VOICES="")).returncode, 0)

    def test_ungueltiges_v7_data(self):
        self.assertEqual(self.e.run("features", V7_DATA=2).returncode, 2)


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
