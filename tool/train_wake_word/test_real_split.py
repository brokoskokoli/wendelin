"""Selbsttest (stdlib unittest, erfundene Daten) fuer den festen Trainings-/Pruefsplit der echten Positive (WP130).
Lauf (Venv mit numpy/soundfile, z. B. wp58):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_real_split.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import os, subprocess, sys, tempfile, unittest
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

    def test_check_dir_fail_closed(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(SystemExit):
                R.check_dir(os.path.join(d, "fehlt"))
            R.check_dir(d)                                   # leer ist ohne require_nonempty erlaubt
            with self.assertRaises(SystemExit):
                R.check_dir(d, require_nonempty=True)
            open(os.path.join(d, "fremd.wav"), "w").close()   # fremdes Namensschema
            with self.assertRaises(SystemExit):
                R.check_dir(d)
            os.remove(os.path.join(d, "fremd.wav"))
            open(os.path.join(d, "handy2_b1_r01_bare_000100.wav"), "w").close()   # anderes Geraet
            with self.assertRaises(SystemExit):
                R.check_dir(d)

    def test_clip_name_passt_zum_muster(self):
        r = R.select(rows())[0]
        self.assertTrue(R.NAME_RE.match(R.clip_name(r)))

    def test_train_py_bricht_mit_pruefclips_ab(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "huawei_b5_r01_bare_000100.wav"), "w").close()
            p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "train.py"), "features", "--work", d, "--real-pos", d],
                               capture_output=True, text=True)
            self.assertNotEqual(p.returncode, 0)
            self.assertIn("Pruef-Clip", p.stderr + p.stdout)


class PosForSplit(unittest.TestCase):
    def test_train_py_nutzt_pos_for_split_und_check_dir(self):
        src = open(os.path.join(HERE, "train.py"), encoding="utf-8").read()
        self.assertIn("real_split.pos_for_split(pos, real_pos, a.real_pos_rep, split)", src)
        self.assertLess(src.index("real_split.check_dir(a.real_pos"), src.index("load_dir(a.real_pos"))

    def test_echte_positive_nur_im_training(self):
        pos = [f"s{i}" for i in range(100)]; real = ["R1", "R2"]
        tr = R.pos_for_split(pos, real, 3, "train"); va = R.pos_for_split(pos, real, 3, "val")
        self.assertEqual(tr.count("R1"), 3); self.assertEqual(len(tr), 90 + 6)
        self.assertFalse(set(va) & set(real))
        self.assertEqual(va, pos[90:])
        self.assertFalse(set(tr[:90]) & set(va))             # synthetisch disjunkt

    def test_ohne_echte_wie_v7(self):
        pos = list(range(50))
        self.assertEqual(R.pos_for_split(pos, [], 100, "train"), pos[:45])


class ConfV8(unittest.TestCase):
    def test_kein_eintrag_ist_das_wake_word(self):
        bad = [c for c in G.CONF_V8 if "wendelin" in c.casefold()]
        self.assertEqual(bad, [])


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


class CvAbschnitt(unittest.TestCase):
    def test_cv_extract_abgeschnittenes_tar_nur_mit_flag(self):
        import io, tarfile
        with tempfile.TemporaryDirectory() as d:
            buf = io.BytesIO()
            with tarfile.open(fileobj=buf, mode="w") as tf:
                for i in range(2):
                    ti = tarfile.TarInfo(f"clip{i}.mp3"); ti.size = 3000
                    tf.addfile(ti, io.BytesIO(b"x" * 3000))
            tar = os.path.join(d, "t.tar")
            open(tar, "wb").write(buf.getvalue()[:5000])      # mitten in den Daten des zweiten Eintrags abgeschnitten
            cmd = [sys.executable, "-I", os.path.join(HERE, "cv_extract.py"), "--tar", tar, "--out", os.path.join(d, "o"), "--every", "1"]
            p = subprocess.run(cmd, capture_output=True, text=True)
            self.assertNotEqual(p.returncode, 0)
            self.assertIn("unvollstaendig", p.stderr + p.stdout)
            p = subprocess.run(cmd + ["--allow-truncated"], capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("abgeschnitten", p.stdout)


class RunV8Cv(unittest.TestCase):
    def test_n_cv_0_ueberspringt_ohne_download(self):
        with tempfile.TemporaryDirectory() as d:
            bin_, log = os.path.join(d, "bin"), os.path.join(d, "calls.log")
            py = os.path.join(d, "k", "wp58", "venv", "bin")
            os.makedirs(bin_); os.makedirs(py)
            for path in (os.path.join(bin_, "curl"), os.path.join(py, "python")):
                open(path, "w").write(f'#!/bin/sh\necho "$0 $@" >> "{log}"\nexit 1\n'); os.chmod(path, 0o755)
            env = dict(os.environ, PATH=bin_ + os.pathsep + os.environ["PATH"], K0=os.path.join(d, "k"),
                       W=os.path.join(d, "w"), N_CV="0")
            p = subprocess.run(["bash", os.path.join(HERE, "run_v8.sh"), "cv"], env=env, capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertFalse(os.path.exists(log), "weder curl noch python duerfen laufen")
            self.assertTrue(os.path.exists(os.path.join(d, "w", "gen", ".done", "cv")))
            self.assertEqual(os.listdir(os.path.join(d, "w", "gen", "cv")), [])


if __name__ == "__main__":
    unittest.main()
