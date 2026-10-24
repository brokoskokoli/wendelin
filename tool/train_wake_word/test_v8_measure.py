"""Selbsttest (stdlib unittest, erfundene Mini-Daten, ohne Modelle/Audio) fuer v8_measure.py (WP130).
Lauf (Venv mit numpy/soundfile/piper, z. B. wp58):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_v8_measure.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import v8_measure as V   # noqa: E402
import real_split as R   # noqa: E402
import words_measure as W  # noqa: E402
import station_measure as S  # noqa: E402


def labels():
    out = []
    for dev in ("huawei", "handy2"):
        for b in range(1, 7):
            for i, w in enumerate(("Wendelin", "Hey Wendelin", "Alexa")):
                off = 0.0 if dev == "huawei" else 1.7 * (i + 1) * b          # zweites Handy: eigene Sitzung (kein fester Versatz zu huawei)
                out.append({"dev": dev, "block": b, "round": 1, "word": w, "start": 100.0 * b + off, "end": 100.0 * b + off + 1, "status": "ok"})
    return out


def paired_labels(offset=0.72, devs=("huawei", "handy2")):
    """Eine Sitzung (Block 1 bis 6, 4 Runden, 3 Woerter), von mehreren Geraeten gleichzeitig aufgenommen: Start = Basis + Geraeteversatz."""
    out = []
    for k, dev in enumerate(devs):
        for b in range(1, 7):
            for rd in range(1, 5):
                for i, w in enumerate(("Wendelin", "Hey Wendelin", "Alexa")):
                    st = 100.0 * b + 10.0 * rd + 2.5 * i + offset * k
                    out.append({"dev": dev, "block": b, "round": rd, "word": w, "start": st, "end": st + 1, "status": "ok"})
    return out


class Split(unittest.TestCase):
    def test_keine_huawei_1_bis_3(self):
        sel = V.filter_labels(labels())
        self.assertFalse([lb for lb in sel if lb["dev"] == "huawei" and lb["block"] in R.TRAIN_BLOCKS])
        self.assertEqual(sorted({lb["block"] for lb in sel if lb["dev"] == "huawei"}), [4, 5, 6])
        self.assertEqual(sorted({lb["block"] for lb in sel if lb["dev"] == "handy2"}), [1, 2, 3, 4, 5, 6])    # eigene Sitzung: bleibt
        self.assertEqual(len(sel), (3 + 6) * 2)                                  # nur die beiden Woerter
        self.assertEqual({lb["word"] for lb in sel}, {"Wendelin", "Hey Wendelin"})

    def test_gleiche_sitzung_faellt_heraus(self):
        """Zweites Geraet derselben Sitzung (fester Versatz) ist Datenleck in Block 1 bis 3; ein drittes Geraet ebenso."""
        lab = paired_labels(devs=("huawei", "handy2"))
        sel = V.filter_labels(lab)
        self.assertEqual(sorted({(lb["dev"], lb["block"]) for lb in sel}), [(d, b) for d in ("handy2", "huawei") for b in (4, 5, 6)])
        self.assertEqual(len(sel), 2 * 3 * 4 * 2)
        old = [lb for lb in lab if lb["word"] in V.WORDS and lb["dev"] in V.DEVICES
               and not (lb["dev"] == R.TRAIN_DEVICE and lb["block"] in R.TRAIN_BLOCKS)]      # alte eval_blocks-Logik: Mutationsbeleg
        self.assertEqual((len(old), len(sel)), (72, 48))                                         # ohne Fix 24 Labels (handy2 Block 1 bis 3) zu viel
        three = R.paired_sessions(paired_labels(devs=("huawei", "handy2", "handy3")))
        self.assertEqual(sorted(three), [("handy2", b) for b in (1, 2, 3)] + [("handy3", b) for b in (1, 2, 3)])
        self.assertEqual(set(three.values()), {"huawei"})

    def test_mehrheit_noetig(self):
        """handy2 Block 1: 3 von 8 Labels passen zum Training (Versatz), die anderen 5 sind eigene Rufe -> keine Mehrheit, nicht gepaart."""
        lab = [lb for lb in paired_labels() if lb["dev"] == "huawei"]
        h1 = [lb for lb in lab if lb["block"] == 1 and lb["word"] == "Wendelin"]                    # 4 Runden
        mine = [dict(lb, dev="handy2", start=lb["start"] + 0.72, end=lb["end"] + 0.72) for lb in h1[:3]]
        fremd = [{"dev": "handy2", "block": 1, "round": 9, "word": "Wendelin", "start": 5000.0 + 7 * i, "end": 5001.0 + 7 * i, "status": "ok"} for i in range(5)]
        self.assertEqual(R.paired_sessions(lab + mine + fremd), {})                                  # 3 von 8: keine Mehrheit
        self.assertEqual(R.paired_sessions(lab + mine), {("handy2", 1): "huawei"})                   # 3 von 3: gepaart

    def test_toleranz_gilt(self):
        """Versatz streut je Ruf um bis 0,1 s: noch gepaart (Toleranz 0,2 s); ein Versatz von 0,5 s Unterschied nicht."""
        lab = [lb for lb in paired_labels() if lb["dev"] == "huawei"]
        h1 = [lb for lb in lab if lb["block"] == 1 and lb["word"] == "Wendelin"]
        wob = lambda sh: [dict(lb, dev="handy2", start=lb["start"] + 0.72 + d, end=lb["end"] + 0.72 + d) for lb, d in zip(h1, sh)]
        self.assertEqual(R.paired_sessions(lab + wob([0.0, 0.1, -0.1, 0.05])), {("handy2", 1): "huawei"})
        self.assertEqual(R.paired_sessions(lab + wob([0.0, 0.5, -0.5, 1.0])), {})

    def test_zu_wenige_rufe_nicht_gepaart(self):
        lab = [lb for lb in paired_labels() if lb["dev"] == "huawei"]
        h1 = [lb for lb in lab if lb["block"] == 1 and lb["word"] == "Wendelin"][:2]
        self.assertEqual(R.paired_sessions(lab + [dict(lb, dev="handy2", start=lb["start"] + 0.72) for lb in h1]), {})

    def test_ohne_trainingszeilen_bricht_ab(self):
        """fail-closed: nur Pruef-Labels uebergeben -> Abbruch statt stillem Durchlassen; leere Eingabe bleibt leer."""
        pruef = [lb for lb in paired_labels() if lb["block"] >= 4]
        with self.assertRaises(SystemExit): R.paired_sessions(pruef)
        with self.assertRaises(SystemExit): V.filter_labels(pruef)
        self.assertEqual(R.paired_sessions([]), {})

    def test_cv_cell_ohne_labels_im_block_ist_kein_fold(self):
        """Test-Bloecke ohne Pruef-Labels (gepaarte Sitzung) zaehlen nicht als Fold: handy2 hat nur Block 4 bis 6."""
        def row(bl):
            d = {"dev": "handy2", "word": "Wendelin", "prog": "m", "thr": "0.9", "stage2": "-", "ord": 0.9, "fa_real": 0, "h_real": 1.0}
            for b in range(1, 7): d[f"hit_b{b}"] = 3 if b in bl else 0; d[f"n_b{b}"] = 5 if b in bl else 0
            return d
        rows = [row((4, 5, 6))]
        c = V.cv_cell(rows, "handy2", "Wendelin", "m", ("-",), "real", 2.0)
        self.assertEqual((c[:2], len(c[2])), ((9, 15), 3))
        self.assertEqual(V.cell_folds(rows, "handy2", "Wendelin", "m"), [(tuple(b for b in range(1, 7) if b != t), (t,)) for t in (4, 5, 6)])
        self.assertEqual(len(V.cell_folds(rows, "handy2", "Wendelin", "m", "all")), 6)

    def test_eigene_sitzung_wird_nicht_gepaart(self):
        self.assertEqual(R.paired_sessions(labels()), {})
        self.assertEqual(R.paired_sessions([]), {})

    def test_assert_bricht_bei_gepaartem_label_ab(self):
        lab = paired_labels()
        leak = [lb for lb in lab if lb["dev"] == "handy2" and lb["block"] == 2]
        with self.assertRaises(SystemExit): V.assert_eval_only(leak, "eval", lab)
        with self.assertRaises(SystemExit): V.assert_eval_only(leak + [lb for lb in lab if lb["dev"] == "huawei"], "eval")   # ohne ref: Paarung in den Labels selbst
        V.assert_eval_only([lb for lb in lab if lb["block"] >= 4], "eval", lab)
        V.assert_eval_only(leak, "all", lab)

    def test_pruefung_bricht_bei_trainingslabel_ab(self):
        with self.assertRaises(SystemExit):
            V.assert_eval_only([{"dev": "huawei", "block": 2}])
        V.assert_eval_only([{"dev": "huawei", "block": 4}, {"dev": "handy2", "block": 2}])

    def test_folds_je_geraet(self):
        self.assertEqual(V.folds_for("huawei"), [((5, 6), (4,)), ((4, 6), (5,)), ((4, 5), (6,))])
        self.assertEqual(len(V.folds_for("handy2")), 6)
        for dev in V.DEVICES:
            for sel, test in V.folds_for(dev):
                self.assertFalse(set(sel) & set(test))
                self.assertTrue(set(sel + test) <= set(V.eval_blocks(dev)))

    def test_training_nie_im_ergebnis(self):
        # Ereignis im Trainingsblock 2 (Zeit 200 s) darf nicht als Treffer zaehlen
        ev = {"pos_huawei": {"pos_huawei": [200.2, 400.2]}, "pos_handy2": {"pos_handy2": []},
              "neg_huawei": {"n": []}, "neg_handy2": {"n": []}, "syn": {"s": []}, "fleurs": {"f": []}, "conf": {"c": []}}
        hr = {"neg_huawei": 1.0, "neg_handy2": 1.0, "syn": 1.0, "fleurs": 1.0, "conf": 0.1}
        rows = V.rows_for_cfg("m", "Wendelin", 0.5, "-", ev, {}, hr, V.filter_labels(labels()))
        h = next(r for r in rows if r["dev"] == "huawei")
        self.assertEqual((h["n"], h["hit"], h["n_b2"], h["hit_b2"], h["n_b4"], h["hit_b4"]), (3, 1, 0, 0, 1, 1))


class Auswahl(unittest.TestCase):
    def test_wilson(self):
        lo, hi = S.wilson(5, 10)
        self.assertAlmostEqual(lo, 0.2366, places=3); self.assertAlmostEqual(hi, 0.7634, places=3)
        self.assertEqual(S.wilson(0, 0), (0.0, 0.0))
        self.assertIn("(5/10)", W.fmt_hit(5, 10))

    def pts(self):
        # zwei Konfigurationen: scharf (kein FA, wenig Treffer) und lasch (viele Treffer, zu viele FA bei 1 h / Ziel 2)
        def p(thr, hit, fa):
            d = {"prog": "m", "thr": str(thr), "stage2": "-", "ord": thr, "hit": 0, "fa": fa, "hours": 1.0}
            for b in range(1, 7):
                d[f"hit_b{b}"] = hit if b in (4, 5, 6) else 0; d[f"n_b{b}"] = 5 if b in (4, 5, 6) else 0
            return d
        return [p(0.9, 3, 0), p(0.2, 5, 9)]

    def test_kreuzauswahl_haelt_fa_grenze(self):
        hit, n, cfgs = W.cv_pick(self.pts(), 1.0, 2.0, V.folds_for("huawei"))
        self.assertEqual((hit, n), (9, 15))                                       # nur die scharfe Konfiguration (3 je Block)
        self.assertEqual(set(cfgs), {"m0.9+-"})

    def test_keine_konfiguration_unter_ziel(self):
        pts = [dict(p, fa=9) for p in self.pts()]
        self.assertIsNone(W.cv_pick(pts, 1.0, 2.0, V.folds_for("huawei"))[0])

    def test_cv_cell_nutzt_pruefblocks(self):
        rows = [dict(p, dev="huawei", word="Wendelin", fa_real=p["fa"], h_real=1.0) for p in self.pts()]
        c = V.cv_cell(rows, "huawei", "Wendelin", "m", ("-",), "real", 2.0)
        self.assertEqual(c[:2], (9, 15))
        self.assertEqual(len(c[2]), 3)                                             # ein Fold je Pruef-Block (4, 5, 6)
        self.assertIsNone(V.cv_cell(rows, "handy2", "Wendelin", "m", ("-",), "real", 2.0))


class Ausgabe(unittest.TestCase):
    def test_render_tabelle(self):
        pts = Auswahl().pts()
        rows = [dict(p, dev="huawei", word="Wendelin", fa_real=p["fa"], h_real=1.0, fa_syn=1, h_syn=2.0, fa_fleurs=0, h_fleurs=1.0,
                     conf_n=10, conf_hit=1, conf_ev=1, conf_h=0.01) for p in pts]
        hr = {"neg_huawei": 1.0, "neg_handy2": 1.0, "syn": 2.0, "fleurs": 1.0, "conf": 0.01}
        md = V.render(rows, {"m": "x"}, 2.0, hr)
        self.assertIn("| huawei | Wendelin | m | 60 % [", md)                       # 9/15
        self.assertIn("(1/10)", md)                                                 # Verwechsler-Clips
        self.assertIn("keine Konfiguration ≤ Ziel", md)                             # handy2: keine Zeilen


class Verwechsler(unittest.TestCase):
    def test_plan_reproduzierbar_und_seed_getrennt(self):
        a, b = V.conf_plan(20, V.CONF_SEED), V.conf_plan(20, V.CONF_SEED)
        self.assertEqual(a, b)
        self.assertNotEqual(a, V.conf_plan(20, V.CONF_SEED + 1))
        self.assertTrue(V.CONF_SEED > 202)                                        # Trainingsseeds 201, 202
        import gen_say_test as T
        self.assertTrue({v for _, _, v, _ in a} <= set(T.VOICES))

    def test_parse_models(self):
        with self.assertRaises(SystemExit): V.parse_models(["ohne-gleich"])
        with self.assertRaises(SystemExit): V.parse_models(["a b=/nope"])
        with self.assertRaises(SystemExit): V.parse_models(["x=/gibt/es/nicht.onnx"], with_v7=False)


class SplitAll(unittest.TestCase):
    """WP133: --split all wertet alle Bloecke, aber nur fuer v7 und Modelle mit Sidecar real_pos == 0."""

    def mk(self, td, name, meta):
        import json
        p = os.path.join(td, name + ".onnx"); open(p, "w").write("x")
        if meta is not None:
            open(p + ".meta.json", "w").write(meta if isinstance(meta, str) else json.dumps(meta))
        return p

    def test_alle_bloecke_beider_geraete(self):
        sel = V.filter_labels(labels(), "all")
        self.assertEqual(sorted({lb["block"] for lb in sel if lb["dev"] == "huawei"}), [1, 2, 3, 4, 5, 6])
        self.assertEqual(len(sel), 6 * 2 * 2)
        self.assertEqual(V.filter_labels(labels()), V.filter_labels(labels(), "eval"))         # Standard unveraendert
        self.assertEqual(len(V.folds_for("huawei", "all")), 6)
        self.assertEqual(len(V.folds_for("huawei")), 3)
        V.assert_eval_only([{"dev": "huawei", "block": 2}], "all")
        with self.assertRaises(SystemExit): V.assert_eval_only([{"dev": "huawei", "block": 2}], "eval")
        with self.assertRaises(SystemExit): V.eval_blocks("huawei", "alle")

    def test_huawei_1_bis_3_zaehlen_nur_bei_all(self):
        ev = {"pos_huawei": {"pos_huawei": [200.2]}, "pos_handy2": {"pos_handy2": []},
              "neg_huawei": {"n": []}, "neg_handy2": {"n": []}, "syn": {"s": []}, "fleurs": {"f": []}, "conf": {"c": []}}
        hr = {"neg_huawei": 1.0, "neg_handy2": 1.0, "syn": 1.0, "fleurs": 1.0, "conf": 0.1}
        h_all = next(r for r in V.rows_for_cfg("m", "Wendelin", 0.5, "-", ev, {}, hr, V.filter_labels(labels(), "all")) if r["dev"] == "huawei")
        self.assertEqual((h_all["n"], h_all["n_b2"], h_all["hit_b2"]), (6, 1, 1))
        h_ev = next(r for r in V.rows_for_cfg("m", "Wendelin", 0.5, "-", ev, {}, hr, V.filter_labels(labels())) if r["dev"] == "huawei")
        self.assertEqual((h_ev["n"], h_ev["n_b2"], h_ev["hit_b2"]), (3, 0, 0))

    def test_modelle_pruefung(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            V.check_split_models("eval", {"v8a": self.mk(td, "a", None)})                      # eval: keine Pruefung
            V.check_split_models("all", {"v7": V.V7})                                          # v7 immer erlaubt (Pfad, kein Sidecar)
            V.check_split_models("all", {"s": self.mk(td, "s", {"real_pos": 0, "tag": "a-syn"})})
            for bad in (None, {"real_pos": 1}, {"tag": "x"}, {"real_pos": False}, {"real_pos": "0"}, "kein json", "[]"):
                with self.assertRaises(SystemExit, msg=repr(bad)):
                    V.check_split_models("all", {"b": self.mk(td, "b", bad)})
            with self.assertRaises(SystemExit):                                                # ein schlechtes Modell unter guten
                V.check_split_models("all", {"v7": V.V7, "s": self.mk(td, "s2", {"real_pos": 0}), "a": self.mk(td, "a2", {"real_pos": 1})})

    def test_ausgabedateien_und_titel(self):
        self.assertTrue(V.out_names("all")[0].endswith("v8_grid_all.csv") and V.out_names("all")[1].endswith("v8_table_all.md"))
        self.assertTrue(V.out_names("eval")[0].endswith("v8_grid.csv") and V.out_names("eval")[1].endswith("v8_table.md"))
        pts = Auswahl().pts()
        rows = [dict(p, dev="huawei", word="Wendelin", fa_real=p["fa"], h_real=1.0, fa_syn=1, h_syn=2.0, fa_fleurs=0, h_fleurs=1.0,
                     conf_n=10, conf_hit=1, conf_ev=1, conf_h=0.01) for p in pts]
        hr = {"neg_huawei": 1.0, "neg_handy2": 1.0, "syn": 2.0, "fleurs": 1.0, "conf": 0.01}
        self.assertIn("allen Blöcken", V.render(rows, {"m": "x"}, 2.0, hr, "all"))
        self.assertIn("dem Prüf-Split", V.render(rows, {"m": "x"}, 2.0, hr))

    def test_cv_cell_all_nutzt_alle_bloecke(self):
        rows = [dict(p, dev="huawei", word="Wendelin", fa_real=p["fa"], h_real=1.0) for p in Auswahl().pts()]
        self.assertEqual(len(V.cv_cell(rows, "huawei", "Wendelin", "m", ("-",), "real", 2.0, "all")[2]), 6)


if __name__ == "__main__":
    unittest.main()
