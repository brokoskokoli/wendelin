"""Selbsttest (stdlib unittest, erfundene Mini-Daten) fuer verifier_eval.py (WP137 Teil 2: Pruefer B, Fusion C, Zaehlung, Tabelle).
Lauf:  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_verifier_eval.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import os, sys, tempfile, unittest
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np  # noqa: E402
import verifier_data as D  # noqa: E402
import verifier_train as T  # noqa: E402
import verifier_eval as E  # noqa: E402

K = D.KIND


def vec(rng, n=96): return rng.standard_normal(n).astype("float32")


class Vorlagen(unittest.TestCase):
    def test_auswahl_gleichmaessig_und_deterministisch(self):
        names = [f"huawei_b{1 + i % 3}_r{i:02d}_hey_{i:06d}.wav" for i in range(20)]
        p = E.pick_templates(names)
        self.assertEqual(len(p), E.N_TEMPL); self.assertEqual(p, E.pick_templates(list(reversed(names))))
        self.assertEqual((p[0], p[-1]), (sorted(names)[0], sorted(names)[-1]))
        self.assertEqual(E.pick_templates(names[:4]), sorted(names[:4]))

    def test_b_findet_vorlage_mit_versatz_und_trennt_zufall(self):
        rng = np.random.default_rng(0)
        mu = np.zeros(96, "float32")
        tm = rng.standard_normal((4, 96)).astype("float32")
        hit = rng.standard_normal((1, 25, 96)).astype("float32") * 0.3
        hit[0, 9:13] = tm
        miss = rng.standard_normal((1, 25, 96)).astype("float32")
        t = E.prep_templates([tm], mu)
        sh, sm = E.b_score(hit, t, mu)[0], E.b_score(miss, t, mu)[0]
        self.assertGreater(sh, 0.8); self.assertLess(sm, 0.4)
        hit2 = np.zeros_like(hit); hit2[0, 3:7] = tm; hit2 += rng.standard_normal(hit.shape).astype("float32") * 0.01
        self.assertAlmostEqual(float(E.b_score(hit2, t, mu)[0]), float(sh), delta=0.2)             # Zeitversatz egal

    def test_zentrieren_wirkt(self):
        rng = np.random.default_rng(1)
        off = np.full(96, 5.0, "float32")                                # gemeinsamer Hintergrund-Anteil: ohne Zentrieren sind alle aehnlich
        tm = (rng.standard_normal((3, 96)) + off).astype("float32"); q = (rng.standard_normal((1, 20, 96)) + off).astype("float32")
        raw = E.b_score(q, E.prep_templates([tm], np.zeros(96, "float32")), np.zeros(96, "float32"))[0]
        cen = E.b_score(q, E.prep_templates([tm], off), off)[0]
        self.assertGreater(raw, 0.8); self.assertLess(cen, 0.4)

    def test_vorlage_laenger_als_ausschnitt_gibt_minimum(self):
        mu = np.zeros(96, "float32")
        t = E.prep_templates([np.ones((30, 96), "float32")], mu)
        self.assertEqual(float(E.b_score(np.ones((1, 25, 96), "float32"), t, mu)[0]), -1.0)

    def test_speicher_und_block_ausschluss(self):
        rng = np.random.default_rng(2)
        mu = np.zeros(96, "float32")
        a, b = rng.standard_normal((4, 96)).astype("float32"), rng.standard_normal((4, 96)).astype("float32")
        st = E.BStore(mu, [("bare", 1, a), ("bare", 2, b), ("hey", 1, a), ("hey", 3, b)])
        q = np.zeros((1, 25, 96), "float32"); q[0, 5:9] = a
        full = st.scores(q)[0, 0]
        excl = st.scores(q, np.array([1]))[0, 0]                          # Block 1 raus: Vorlage a fehlt
        self.assertGreater(full, excl + 0.3); self.assertLess(excl, 0.3)       # Mittel der besten Vorlagen: ohne a nur noch b
        p = os.path.join(tempfile.mkdtemp(), "b.npz"); st.save(p)
        st2 = E.BStore.load(p)
        self.assertEqual([(w, bl) for w, bl, _ in st2.items], [(w, bl) for w, bl, _ in st.items])
        self.assertAlmostEqual(float(st2.scores(q)[0, 0]), float(full), places=5)

    def test_build_templates_verlangt_beide_woerter(self):
        embed = lambda x: np.ones((3, 96), "float32")
        clips = {f"huawei_b1_r0{i}_hey_00010{i}.wav": np.ones(1600, "float32") for i in range(3)}
        with self.assertRaises(SystemExit): E.build_templates(clips, embed, np.zeros(96, "float32"))
        clips.update({f"huawei_b2_r0{i}_bare_00020{i}.wav": np.ones(1600, "float32") for i in range(3)})
        st = E.build_templates(clips, embed, np.zeros(96, "float32"))
        self.assertEqual({w for w, _, _ in st.items}, {"bare", "hey"})

    def test_mu_nur_aus_negativen(self):
        ex = D.Examples.concat([D.Examples(**D.make_rows(np.full((2, 25, 96), 10.0), [0.99] * 2, K["pos_syn"], "hey", [0, 1])),
                                D.Examples(**D.make_rows(np.full((2, 25, 96), 2.0), [0.99] * 2, K["conf"], None, [0, 1]))])
        np.testing.assert_allclose(E.center_mu(ex), 2.0)

    def test_blockausschluss_nur_fuer_echte(self):
        ex = D.Examples.concat([D.Examples(**D.make_rows(np.zeros((1, 25, 96)), [0.99], K["pos_real"], "hey", [1])),
                                D.Examples(**D.make_rows(np.zeros((1, 25, 96)), [0.99], K["pos_syn"], "hey", [1]))])
        self.assertEqual(E.train_blocks(ex).tolist(), [2, 0])


class Fusion(unittest.TestCase):
    def test_lr_trennt(self):
        rng = np.random.default_rng(0)
        y = np.r_[np.ones(100), np.zeros(100)]
        F = np.stack([rng.normal(0, 1, 200), rng.normal(0, 1, 200) + 3 * (2 * y - 1), rng.normal(0, 1, 200)], 1)
        c, b = E.lr_fit(F, y)
        p = E.lr_apply(c, b, F)
        self.assertGreater(((p > 0.5) == y).mean(), 0.9); self.assertGreater(c[1], abs(c[0]) * 3)

    def test_fit_fusion_schwelle_aus_oof_regel(self):
        rng = np.random.default_rng(1)
        n = 240
        kinds = np.array([K["pos_syn"], K["conf"], K["mined"], K["pos_real"]] * (n // 4))
        word = np.array(["hey", None, None, "bare"] * (n // 4), dtype=object)
        ex = D.Examples.concat([D.Examples(**D.make_rows(np.zeros((1, 25, 96)), [0.99], int(k), w, [i % 3])) for i, (k, w) in enumerate(zip(kinds, word))])
        y = ex.d["yw"].astype(float)
        a = np.stack([np.clip(0.5 + 0.4 * (2 * y - 1) + rng.normal(0, 0.15, n), 0.01, 0.99)] * 2, 1)
        b = np.stack([0.5 * (2 * y - 1) + rng.normal(0, 0.3, n)] * 2, 1)
        f = E.fit_fusion(ex, a, b)
        self.assertEqual(set(f), {"W", "HW"})
        for k in f.values(): self.assertGreaterEqual(k["reject"], T.REJECT_MIN)
        self.assertGreater(f["W"]["accept"], 0.5)

    def test_fusion_leere_faltung_bricht_ab(self):
        ex = D.Examples.concat([D.Examples(**D.make_rows(np.zeros((1, 25, 96)), [0.99], K["conf"], None, [i % 2])) for i in range(6)])
        with self.assertRaises(SystemExit): E.fit_fusion(ex, np.full((6, 2), .5), np.zeros((6, 2)))


def ev(src, item, t, peak): return dict(src=src, item=item, t=t, peak=peak, key=f"{src}|{item}|{int(round(t * 100))}")


class Zaehlen(unittest.TestCase):
    def setUp(self):
        self.sc = {"k1": {"a": np.array([0.9, 0.1]), "b": np.array([0.2, 0.2]), "c": np.array([0.7, 0.7])}}

    def test_direktannahme_ab_obergrenze_und_stufe1(self):
        p = E.make_pass("A", 0, {}, 0.5)
        self.assertTrue(p(ev("x", "y", 1, 0.999)))                      # ohne Wert, aber Direktannahme
        self.assertTrue(E.make_pass("s1", 0, {}, 0)(ev("x", "y", 1, 0.98)))
        with self.assertRaises(KeyError): p(dict(ev("x", "y", 1, 0.99), key="fehlt"))     # kein stilles Durchlassen

    def test_schwelle_je_kopf(self):
        e = dict(ev("x", "y", 1, 0.99), key="k1")
        self.assertTrue(E.make_pass("a", 0, self.sc, 0.5)(e)); self.assertFalse(E.make_pass("a", 1, self.sc, 0.5)(e))
        self.assertTrue(E.make_pass("c", 1, self.sc, 0.7)(e))

    def test_hw2_funktion(self):
        p = E.make_pass("hw2", 0, {}, 0, hw2=lambda e: e["t"] > 1)
        self.assertFalse(p(ev("x", "y", 1, 0.99))); self.assertTrue(p(ev("x", "y", 2, 0.99)))

    def test_treffer_leise_laut_und_fenster(self):
        labels = [dict(dev="huawei", word="Wendelin", start=10.0, end=11.0, status="ok", level=-30),
                  dict(dev="huawei", word="Wendelin", start=20.0, end=21.0, status="ok", level=-40),
                  dict(dev="huawei", word="Wendelin", start=30.0, end=31.0, status="ok", level=-36)]
        events = {"pos_huawei": [ev("pos_huawei", "pos_huawei", 11.5, 0.99), ev("pos_huawei", "pos_huawei", 22.5, 0.99)]}
        r = E.hit_counts(events, labels, lambda e: True)[("huawei", "Wendelin")]
        self.assertEqual(r["alle"], (1, 3))                             # zweites Ereignis liegt ausserhalb von end + 1,2; drittes Label ohne Ereignis
        self.assertEqual((r["laut"], r["leise"]), ((1, 1), (0, 2)))
        events["pos_huawei"].append(ev("pos_huawei", "pos_huawei", 20.9, 0.99))
        self.assertEqual(E.hit_counts(events, labels, lambda e: e["t"] < 20)[("huawei", "Wendelin")]["alle"], (1, 3))

    def test_verwechsler_nach_text_split(self):
        info = {"a.wav": ("x", "test"), "b.wav": ("y", "train"), "c.wav": ("z", "test")}
        events = {"conf": [ev("conf", "a.wav", 1, .99), ev("conf", "a.wav", 5, .99), ev("conf", "b.wav", 1, .99)]}
        self.assertEqual(E.conf_counts(events, lambda e: True, info), {"test": (1, 2), "train": (1, 1)})   # Clip zaehlt einmal, c ohne Ereignis
        self.assertEqual(E.conf_counts(events, lambda e: e["item"] != "a.wav", info), {"test": (0, 2), "train": (1, 1)})

    def test_verwechsler_plan_muss_zum_cache_passen(self):
        info = {"a.wav": ("x", "test"), "b.wav": ("y", "train")}
        E.assert_conf_plan(["a.wav", "b.wav"], info)
        for bad in (["a.wav"], ["a.wav", "b.wav", "z.wav"]):
            with self.assertRaises(SystemExit): E.assert_conf_plan(bad, info)
        E.assert_conf_plan(["a.wav"], info, probe=True)                                   # Probe: gekuerzte Kurven
        with self.assertRaises(SystemExit): E.assert_conf_plan(["z.wav"], info, probe=True)

    def test_hw2_transkripte_fehlen_bricht_ab(self):
        tx = {w: {"k": "x"} for w in E.HEADS}
        self.assertTrue(E.hw2_available(tx))
        for bad in ({}, None, {**tx, "Wendelin": None}):
            with self.assertRaises(SystemExit): E.hw2_available(bad)
            self.assertFalse(E.hw2_available(bad, probe=True))

    def test_kreuzauswahl_schwelle_aus_den_uebrigen_bloecken(self):
        # zwei Bloecke; Block 4: Treffer 0,60, Fehl 0,90/0,85; Block 5: Treffer 0,70, Fehl 0,10/0,20. Regel reject_min 0,5: Schwelle = Negativ-Wert, der die Haelfte der Negativen der uebrigen Bloecke verwirft
        def e(t, key): return dict(src="pos_huawei", item="pos_huawei", t=t, peak=0.99, key=key)
        events = {"pos_huawei": [e(1.0, "a"), e(5.0, "b"), e(4.0, "b2"), e(11.0, "c"), e(15.0, "d"), e(16.0, "d2")]}
        sc = {k: {"c": np.array([x, x])} for k, x in dict(a=0.6, b=0.9, b2=0.85, c=0.7, d=0.1, d2=0.2).items()}
        labels = [dict(dev="huawei", block=4, word="Wendelin", start=0.8, end=1.0, status="ok", level=-20),
                  dict(dev="huawei", block=5, word="Wendelin", start=10.8, end=11.0, status="ok", level=-20)]
        h, thr, nneg = E.cross_select_hits(events, labels, sc, 0, reject_min=0.5)
        self.assertAlmostEqual(thr[("huawei", 4)], 0.2)             # Block 5: Negative 0,10/0,20 -> 0,20
        self.assertAlmostEqual(thr[("huawei", 5)], 0.9)             # Block 4: Negative 0,85/0,90 -> 0,90
        self.assertEqual(h[("huawei", "Wendelin")]["alle"], (1, 2))    # Block 4: 0,6 >= 0,2 Treffer; Block 5: 0,7 < 0,9 verfehlt

    def test_kreuzauswahl_w_kopf_wertet_hey_wendelin_als_positiv(self):
        # Gegenprobe Review: W- und HW-Ruf mit gleichem C 0,8 (je ein Block) und Negative 0,1/0,2 -> W-Kopf: beide Positiv, 2/2; HW-Kopf: W-Ruf ist Negativ
        def e(t, key): return dict(src="pos_huawei", item="pos_huawei", t=t, peak=0.99, key=key)
        events = {"pos_huawei": [e(1.0, "w"), e(5.0, "n1"), e(4.0, "n1b"), e(11.0, "hw"), e(15.0, "n2"), e(17.0, "n2b")]}
        sc = {k: {"c": np.array([x, x])} for k, x in dict(w=0.8, hw=0.8, n1=0.1, n1b=0.15, n2=0.2, n2b=0.25).items()}
        labels = [dict(dev="huawei", block=4, word="Wendelin", start=0.8, end=1.0, status="ok", level=-20),
                  dict(dev="huawei", block=5, word="Hey Wendelin", start=10.8, end=11.0, status="ok", level=-20)]
        h, thr, _ = E.cross_select_hits(events, labels, sc, 0, reject_min=0.5)
        self.assertEqual(h[("huawei", "Wendelin")]["alle"], (1, 1))
        self.assertIsNotNone(thr[("huawei", 4)])
        self.assertLessEqual(thr[("huawei", 4)], 0.8)
        self.assertEqual(E.cross_select_hits(events, labels, sc, 0, reject_min=0.5)[2][("huawei", 5)], 2)      # W-Kopf: W-Ruf Positiv, nur n1/n1b Negativ
        h, thr, nneg = E.cross_select_hits(events, labels, sc, 1, reject_min=0.5)
        self.assertEqual(nneg[("huawei", 5)], 3)                  # HW-Kopf: der W-Ruf (0,8) ist Negativ wie im Training (yhw=0)
        self.assertIsNone(thr[("huawei", 5)])                     # und Block 4 hat keinen HW-Ruf als Positiv -> n/a
        self.assertTrue(E.head_positive("Hey Wendelin", 0) and E.head_positive("Wendelin", 0) and not E.head_positive("Wendelin", 1))

    def test_kreuzauswahl_ohne_negative_ist_na(self):
        def e(t, key): return dict(src="pos_huawei", item="pos_huawei", t=t, peak=0.99, key=key)
        events = {"pos_huawei": [e(1.0, "a"), e(11.0, "b")]}
        sc = {k: {"c": np.array([0.8, 0.8])} for k in "ab"}
        labels = [dict(dev="huawei", block=4, word="Wendelin", start=0.8, end=1.0, status="ok", level=-20),
                  dict(dev="huawei", block=5, word="Wendelin", start=10.8, end=11.0, status="ok", level=-20)]
        h, thr, nneg = E.cross_select_hits(events, labels, sc, 0, reject_min=0.5)
        self.assertEqual((thr, nneg, h), ({("huawei", 4): None, ("huawei", 5): None}, {("huawei", 4): 0, ("huawei", 5): 0}, {}))
        note = E.cross_notes(events, labels, {k: {"c": np.array([0.8, 0.8])} for k in "ab"})[0]
        self.assertIn("n/a", note); self.assertIn("Neg. 0", note); self.assertNotIn("1.000", note)

    def test_fa_und_flat_events(self):
        events = {"syn": [ev("syn", "a", 1, .99), ev("syn", "a", 9, .99)], "fleurs": [ev("fleurs", "b", 1, .99)]}
        self.assertEqual(E.fa_count(events, ["syn", "fleurs", "fehlt_nicht"], lambda e: True) if False else E.fa_count(events, ["syn", "fleurs"], lambda e: e["t"] < 5), 2)
        fl = E.flat_events({("syn", "a", "syn|a|150"): 0.99})
        self.assertEqual(fl["syn"][0]["t"], 1.5)

    def test_pegel_und_cpu(self):
        self.assertAlmostEqual(E.level_of(np.full(32000, 0.1, "float32"), 0.5, 1.5), -20.0, 3)
        m, q = E.cpu_stats([1, 2, 3, 4, 100])
        self.assertEqual(m, 3.0); self.assertGreater(q, 4)
        calls = []
        E.bench(lambda i: calls.append(i), list(range(8)), warm=3)
        self.assertEqual(calls, list(range(3)) + list(range(3, 8)) if False else list(range(3)) + list(range(3, 8)))


class Tabelle(unittest.TestCase):
    def test_render_enthaelt_alle_abschnitte(self):
        cell = {"alle": (3, 4), "leise": (1, 2), "laut": (2, 2)}
        h = {(d, w): cell for d in ("huawei", "handy2") for w in E.HEADS}
        r = {"hits": h, "conf": {w: {"test": (1, 90), "train": (2, 210)} for w in E.HEADS},
             "fa": {s: {w: (1, 2.0) for w in E.HEADS} for s in ("syn", "echt")}}
        md = E.render({"Stufe 1": r, "A": r}, ["Notiz"])
        for s in ("Notiz", "## Treffer", "## Leise Rufe", "## Verwechsler", "## Fehlalarme", "| A |", "Test-Texte 30 %", "≤"): self.assertIn(s, md)
        self.assertIn("(12/16)", md)

    def test_ausschnitt_aus_merkmalsdatei_nicht_aus_cli(self):
        import argparse, tempfile
        with tempfile.TemporaryDirectory() as t:
            f = os.path.join(t, "p1.5-t0.5.npz"); open(f, "wb").write(b"x"); D.write_stamp(f, {}, dict(pre=1.5, tail=0.5))
            ns = lambda **k: argparse.Namespace(feat=f, pre=k.get("pre"), tail=k.get("tail"))
            self.assertEqual(E.cut_of(ns(), dict(pre=1.5, tail=0.5)), (1.5, 0.5))              # CLI leer: Wert der Merkmalsdatei
            self.assertEqual(E.cut_of(ns(pre=1.5, tail=0.5), dict(pre=1.5, tail=0.5)), (1.5, 0.5))
            with self.assertRaises(SystemExit): E.cut_of(ns(pre=1.9), dict(pre=1.5, tail=0.5))    # CLI widerspricht (frueher stilles Standardfenster)
            with self.assertRaises(SystemExit): E.cut_of(ns(), dict(pre=1.9, tail=0.85))          # meta (anderer Kandidat) widerspricht
            with self.assertRaises(SystemExit): E.cut_of(ns(), dict())                            # meta ohne Ausschnitt

    def test_fit_ohne_stempel_bricht_ab(self):
        import argparse
        with self.assertRaises(D.LeakError): E.phase_fit(argparse.Namespace(feat="/nicht/da.npz"))
        with self.assertRaises(D.LeakError): E.phase_run(argparse.Namespace(feat="/nicht/da.npz"))


if __name__ == "__main__":
    unittest.main()
