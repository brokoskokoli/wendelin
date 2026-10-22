"""Selbsttest (stdlib unittest, erfundene Mini-Daten, ohne Modelle/Audio) fuer stage2_analysis.py (WP133 Teil A).
Lauf (Venv mit numpy/soundfile/piper, z. B. wp58):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_stage2_analysis.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np  # noqa: E402
import kws_measure as K  # noqa: E402
import words_measure as W  # noqa: E402
import v8_measure as V  # noqa: E402
import stage2_analysis as A  # noqa: E402

TEXTS = ["Wendelin", "Hey Wendelin", "hey wendeling", "Wendel", "Wandel", "wendelien", "hey wen", "Hey Windel", "", "Alexa", "Hallo Welt",
         "hey wende lin", "heywendelin", "vendelin mach", "wen delin", "ey wendelin"]


class Regeln(unittest.TestCase):
    def test_app_regel_gleich_kws_measure(self):
        for t in TEXTS:
            self.assertEqual(A.match_name(t, False), K.matches_wake_word(t, 2), t)
            self.assertEqual(A.match_name(t, True), K.matches_hey_wake_word(t, 2), t)
            self.assertEqual(A.rule_app("Wendelin", t), W.MATCH["Wendelin"](t, 2), t)
            self.assertEqual(A.rule_app("Hey Wendelin", t), W.MATCH["Hey Wendelin"](t, 2), t)

    def test_locker_nimmt_mehr_an(self):
        self.assertFalse(A.rule_app("Wendelin", "Wendelinger"))                 # Basis: 3 Aenderungen
        self.assertTrue(A.rule_loose(A.d3_near)("Wendelin", "Wendelinger"))
        self.assertFalse(A.rule_app("Wendelin", "Wendel"))
        self.assertTrue(A.rule_loose(A.cp_near)("Wendelin", "Wendel"))          # Koelner Praefix
        self.assertTrue(A.rule_loose(A.cp_near)("Hey Wendelin", "hey wendel"))
        self.assertFalse(A.rule_loose(A.cp_near)("Hey Wendelin", "wendel"))     # Hey bleibt Pflicht
        for t in TEXTS:                                                          # locker ist nie strenger als die App-Regel
            if A.rule_app("Wendelin", t): self.assertTrue(A.rule_loose(A.d3_near)("Wendelin", t))

    def test_extra_regeln_grenzen(self):
        self.assertFalse(A.cp_near("wen")); self.assertFalse(A.cp_near("hallo")); self.assertFalse(A.d3_near("welt"))
        self.assertFalse(A.d3_near("alexander"))                                 # Anfangsbuchstabe w/v/f

    def test_hey_optional(self):
        self.assertFalse(A.rule_app("Hey Wendelin", "Wendelin"))
        self.assertTrue(A.rule_hey_opt("Hey Wendelin", "Wendelin"))
        self.assertTrue(A.rule_hey_opt("Hey Wendelin", "hey wendelin"))
        self.assertFalse(A.rule_hey_opt("Hey Wendelin", "Hallo Welt"))
        self.assertFalse(A.rule_hey_opt("Wendelin", "Hallo Welt"))

    def test_band(self):
        v = A.VARIANTS["band995"]
        self.assertTrue(A.passes_rule(v, "Wendelin", "Hallo", 0.996))           # ueber der Obergrenze: Stufe 1 genuegt
        self.assertFalse(A.passes_rule(v, "Wendelin", "Hallo", 0.99))           # darunter entscheidet Stufe 2
        self.assertTrue(A.passes_rule(v, "Wendelin", "Wendelin", 0.5))
        self.assertTrue(A.passes_rule(v, "Wendelin", "Hallo", 0.995))           # genau auf der Obergrenze: durch (>=)
        self.assertFalse(A.passes_rule(v, "Wendelin", "Hallo", 0.9949))
        self.assertTrue(A.passes_rule(A.VARIANTS["band999"], "Wendelin", "Hallo", 0.999))
        self.assertFalse(A.passes_rule(A.VARIANTS["band999"], "Wendelin", "Hallo", 0.9989))
        self.assertFalse(A.passes_rule(A.VARIANTS["app"], "Wendelin", "Hallo", 1.0))

    def test_peak(self):
        t = np.array([0.0, 0.5, 1.0, 1.6, 3.0]); v = np.array([0.1, 0.96, 0.99, 0.4, 0.999])
        self.assertAlmostEqual(A.peak_at(t, v, 0.5), 0.99)                      # Fenster [0,5; 2,0)
        self.assertAlmostEqual(A.peak_at(t, v, 3.0), 0.999)
        self.assertEqual(A.peak_at(t, v, 9.0), 0.0)


class Kategorien(unittest.TestCase):
    def test_kategorien(self):
        c = A.categorize
        self.assertEqual(c("Wendelin", ""), "leer")
        self.assertEqual(c("Wendelin", "  . "), "leer")
        self.assertEqual(c("Wendelin", "Wendelinger"), "Schreibvariante")
        self.assertEqual(c("Wendelin", "Wendel"), "Schreibvariante")            # nah genug: Koelner Praefix
        self.assertEqual(c("Wendelin", "Hallo Welt"), "anderes Wort")
        self.assertEqual(c("Wendelin", "delin"), "abgeschnitten")
        self.assertEqual(c("Wendelin", "wen"), "abgeschnitten")
        self.assertEqual(c("Hey Wendelin", "Wendelin"), "Hey fehlt")
        self.assertEqual(c("Hey Wendelin", "hey wen"), "abgeschnitten")
        self.assertEqual(c("Hey Wendelin", "hey wendel"), "Schreibvariante")
        self.assertEqual(c("Hey Wendelin", "Hallo"), "anderes Wort")
        self.assertEqual(c("Hey Wendelin", "Na, hey"), "abgeschnitten")          # nur Hey erkannt
        self.assertEqual(c("Wendelin", "Na, hey"), "anderes Wort")
        self.assertEqual(c("Hey Wendelin", "Hey Windows"), "anderes Wort")

    def test_hey_fehlt_nur_fuer_hey_wort(self):
        self.assertNotEqual(c := A.categorize("Wendelin", "Hallo"), "Hey fehlt", c)

    def test_prioritaet_mehrere_texte(self):
        self.assertEqual(A.categorize_all("Wendelin", ["", "Hallo"]), "anderes Wort")
        self.assertEqual(A.categorize_all("Wendelin", ["", "Hallo", "Wendelinger"]), "Schreibvariante")
        self.assertEqual(A.categorize_all("Wendelin", []), "leer")
        self.assertEqual(A.categorize_all("Hey Wendelin", ["wen", "Wendelin"]), "Hey fehlt")


def curves_mini(vals):
    """Alle Quellen mit je einem Item; vals: {Quelle: (t, v)}."""
    return {s: {s: vals.get(s, (np.array([0.0]), np.array([0.0])))} for s in V.SRCS}


class Ausschnitt(unittest.TestCase):
    def test_segment_laenger_als_heute(self):
        x = np.arange(20 * A.SR, dtype="float32")
        k = "pos_huawei|pos_huawei|1000"                                        # 10 s
        a, b = W.segment(x, k), A.segment_x(x, k)
        self.assertEqual(len(a), int((2 + W.TAIL) * A.SR)); self.assertEqual(len(b), int((A.PRE_X + A.TAIL_X) * A.SR))
        self.assertEqual(b[0], x[int((10 - A.PRE_X) * A.SR)])
        self.assertEqual(len(A.segment_x(x, "a|b|100")), int((1 + A.TAIL_X) * A.SR))   # am Anfang gekuerzt

    def test_nur_schwellen_ab_09(self):
        cv = curves_mini({"pos_huawei": (np.array([1.0, 5.0, 9.0]), np.array([0.5, 0.93, 0.999]))})
        keys = A.ausschnitt_keys(cv)
        self.assertEqual(sorted(keys), sorted([W.seg_key("pos_huawei", "pos_huawei", 5.0), W.seg_key("pos_huawei", "pos_huawei", 9.0)]))
        self.assertEqual(A.ausschnitt_keys(cv, 0.2) >= keys | {W.seg_key("pos_huawei", "pos_huawei", 1.0)}, True)

    def test_ausschnitt_parameter(self):
        self.assertGreater(A.PRE_X, 2.0); self.assertGreater(A.TAIL_X, W.TAIL)    # wirklich laenger als der heutige Ausschnitt
        self.assertGreaterEqual(A.VARIANTS["ausschnitt"]["thr_min"], 0.9)
        self.assertEqual(A.VARIANTS["ausschnitt"]["src"], "s2x")

    def test_cache_pfad_traegt_parameter(self):
        self.assertIn(f"-p{A.PRE_X}-t{A.TAIL_X}", A.s2x_path("v8a", "Hey Wendelin"))
        self.assertTrue(A.s2x_path("v8a", "Hey Wendelin").endswith("hw2@hey_wendelin.json"))


class WeitereErkenner(unittest.TestCase):
    def test_varianten_registriert(self):
        for n, src in (("whisper_de", "wh"), ("hw4", "hw4")):
            self.assertEqual(A.VARIANTS[n]["src"], src); self.assertIsNone(A.VARIANTS[n]["ceil"])
            self.assertEqual(A.VARIANTS[n + "_band999"]["ceil"], 0.999); self.assertEqual(A.VARIANTS[n + "_band995"]["ceil"], 0.995)
            self.assertEqual(A.VARIANTS[n + "_band999"]["src"], src)

    def test_schwellenminimum_095(self):
        for n in ("whisper_de", "hw4", "whisper_de_band999", "hw4_band995"):
            self.assertEqual(A.VARIANTS[n]["thr_min"], 0.95)
        cv = curves_mini({"pos_huawei": (np.array([1.0, 5.0, 9.0]), np.array([0.5, 0.93, 0.96]))})
        self.assertEqual(A.ausschnitt_keys(cv, A.E_THR_MIN), {W.seg_key("pos_huawei", "pos_huawei", 9.0)})
        self.assertEqual(A.E_TAGS, ("v8a",))

    def test_cache_pfade(self):
        self.assertIn("whisper-small-de", A.wh_path("v8a")); self.assertNotIn("hey", A.wh_path("v8a"))      # ein Cache fuer beide Woerter
        self.assertTrue(A.hw4_path("v8a", "Hey Wendelin").endswith("parakeet-hw4.0@hey_wendelin.json"))
        self.assertIn("parakeet-hw4.0", A.hw4_path("v8a", "Wendelin"))
        paths = {A.wh_path("v8a"), A.hw4_path("v8a", "Wendelin"), A.hw4_path("v8a", "Hey Wendelin"), A.s2x_path("v8a", "Wendelin"), V.s2_path("v8a", "Wendelin")}
        self.assertEqual(len(paths), 5)                                           # keine Kollision, vorhandene Caches bleiben unberuehrt

    def test_quelle_und_regel(self):
        tx = {"wh": {"k": "Wendelin"}, "hw4": {"k": "Hallo"}}
        v = A.VARIANTS
        self.assertTrue(A.passes_rule(v["whisper_de"], "Wendelin", tx[v["whisper_de"]["src"]]["k"], 0.0))
        self.assertFalse(A.passes_rule(v["hw4"], "Wendelin", tx[v["hw4"]["src"]]["k"], 0.0))
        self.assertTrue(A.passes_rule(v["hw4_band999"], "Wendelin", "Hallo", 0.9995))


def labels_huawei(word="Wendelin"):
    return [{"dev": "huawei", "block": b, "round": 1, "word": word, "start": 100.0 * b, "end": 100.0 * b + 1, "status": "ok"} for b in (4, 5, 6)]


class Arbeitspunkt(unittest.TestCase):
    def setUp(self):
        # Block 4: Treffer, Text passt; Block 5: Treffer, Text „Hallo“ (verloren); Block 6: kein Ereignis
        self.t4, self.t5 = 400.5, 500.5
        self.curves = curves_mini({"pos_huawei": (np.array([self.t4, self.t5, 700.0]), np.array([0.9, 0.97, 0.1]))})
        self.key = lambda t: W.seg_key("pos_huawei", "pos_huawei", t)
        self.tx = {"s2": {self.key(self.t4): "Wendelin", self.key(self.t5): "Hallo"},
                   "s2x": {self.key(self.t4): "Wendelin", self.key(self.t5): "Wendelin"}}
        self.evs = {0.9: V.events_at(self.curves, 0.9)}

    def test_verlorene_rufe(self):
        folds = [((5, 6), (4,)), ((4, 6), (5,)), ((4, 5), (6,))]
        n1, lost = A.lost_calls("huawei", "Wendelin", [0.9] * 3, folds, self.curves, self.tx, labels_huawei(), self.evs)
        self.assertEqual(n1, 2)                                                  # Block 6 ohne Stufe-1-Treffer
        self.assertEqual([(x["block"], x["cat"]) for x in lost], [(5, "anderes Wort")])
        self.assertTrue(lost[0]["rec"]["ausschnitt"])                            # laengerer Ausschnitt holt zurueck
        self.assertFalse(lost[0]["rec"]["band995"])                              # Spitzenwert 0,97 < 0,995
        self.assertFalse(lost[0]["rec"]["locker_d3"])

    def test_fehlender_text_bricht_ab(self):
        folds = [((5, 6), (4,))]
        del self.tx["s2"][self.key(self.t4)]
        with self.assertRaises(KeyError):
            A.lost_calls("huawei", "Wendelin", [0.9], folds, self.curves, self.tx, labels_huawei(), self.evs)

    def test_fehlender_variantentext_ist_none(self):
        del self.tx["s2x"][self.key(self.t5)]
        _, lost = A.lost_calls("huawei", "Wendelin", [0.9], [((4, 6), (5,))], self.curves, self.tx, labels_huawei(), self.evs)
        self.assertIsNone(lost[0]["rec"]["ausschnitt"])

    def test_nur_testbloecke_zaehlen(self):
        n1, lost = A.lost_calls("huawei", "Wendelin", [0.9], [((4, 6), (5,))], self.curves, self.tx, labels_huawei(), self.evs)
        self.assertEqual((n1, len(lost)), (1, 1))

    def test_herausgefilterte_ereignisse(self):
        cv = curves_mini({"syn": (np.array([2.0, 6.0]), np.array([0.998, 0.95])), "neg_huawei": (np.array([3.0]), np.array([0.95]))})
        ev = {0.9: V.events_at(cv, 0.9)}
        tx = {"s2": {W.seg_key("syn", "syn", 2.0): "Hallo", W.seg_key("syn", "syn", 6.0): "Wendelin",
                     W.seg_key("neg_huawei", "neg_huawei", 3.0): "Wendel"},
              "s2x": {W.seg_key("syn", "syn", 2.0): "Hallo", W.seg_key("neg_huawei", "neg_huawei", 3.0): "Wendelin"}}
        f = A.filtered_events("huawei", "Wendelin", 0.9, cv, tx, ev)
        self.assertEqual(f["syn"][:2], (2, 1))                                   # zwei Ereignisse, eines verworfen
        self.assertEqual(f["syn"][2]["band995"], 1)                              # Spitzenwert 0,998 >= 0,995: kommt zurueck
        self.assertEqual(f["syn"][2]["band999"], 0)                              # darunter entscheidet Stufe 2
        self.assertEqual(f["neg_huawei"][:2], (1, 1))
        self.assertEqual(f["neg_huawei"][2]["locker_cp"], 1)                     # „Wendel“
        self.assertEqual(f["neg_huawei"][2]["ausschnitt"], 1)
        self.assertEqual(f["neg_huawei"][2]["app_ge09"], 0)
        self.assertEqual(f["conf"][:2], (0, 0))
        f2 = A.filtered_events("huawei", "Wendelin", 0.9, cv, {"s2": tx["s2"], "s2x": {}}, ev)
        self.assertIsNone(f2["syn"][2]["ausschnitt"])                            # Text fehlt -> None, kein Absturz

    def test_schwelle_unter_minimum(self):
        cv = curves_mini({"syn": (np.array([2.0]), np.array([0.5]))})
        ev = {0.3: V.events_at(cv, 0.3)}
        tx = {"s2": {W.seg_key("syn", "syn", 2.0): "Hallo"}, "s2x": {W.seg_key("syn", "syn", 2.0): "Wendelin"}}
        f = A.filtered_events("huawei", "Wendelin", 0.3, cv, tx, ev)
        self.assertIsNone(f["syn"][2]["ausschnitt"]); self.assertEqual(f["syn"][2]["locker_cp"], 0)

    def test_op_schwellen(self):
        self.assertEqual(A.op_thresholds("v8a", ["v8a0.9+-", "v8a0.99+-", "v8a0.2+-"]), [0.9, 0.99, 0.2])

    def test_zeilen_je_variante(self):
        hr = {"neg_huawei": 1.0, "neg_handy2": 1.0, "syn": 1.0, "fleurs": 1.0, "conf": 0.1}
        ev = {s: {i: W.score_events(t, v, 0.9) for i, (t, v) in d.items()} for s, d in self.curves.items()}
        lab = [lb for lb in labels_huawei()] + [dict(lb, dev="handy2") for lb in labels_huawei()]
        rows = A.variant_rows("m", "Wendelin", 0.9, "app", self.tx["s2"], ev, self.curves, hr, V.filter_labels(lab))
        h = next(r for r in rows if r["dev"] == "huawei")
        self.assertEqual((h["stage2"], h["n"], h["hit"]), ("app", 3, 1))        # nur Block 4 besteht Stufe 2
        rows = A.variant_rows("m", "Wendelin", 0.9, "ausschnitt", self.tx["s2x"], ev, self.curves, hr, V.filter_labels(lab))
        self.assertEqual(next(r for r in rows if r["dev"] == "huawei")["hit"], 2)
        with self.assertRaises(KeyError):
            A.variant_rows("m", "Wendelin", 0.9, "app", {}, ev, self.curves, hr, V.filter_labels(lab))


class FesteSchwelle(unittest.TestCase):
    def setUp(self):
        # Ruf 4: Spitzenwert 0,9995, Text falsch; Ruf 5: 0,996, Text ok; Ruf 6: 0,985, Text falsch; Ruf 7: kein Ereignis
        self.ts = {4: 400.5, 5: 500.5, 6: 600.5}
        self.curves = curves_mini({"pos_huawei": (np.array([400.5, 500.5, 600.5, 800.0]), np.array([0.9995, 0.996, 0.985, 0.1]))})
        lab = [{"dev": "huawei", "block": b, "round": 1, "word": "Wendelin", "start": 100.0 * b, "end": 100.0 * b + 1, "status": "ok"} for b in (4, 5, 6, 7)]
        self.labels = lab
        k = lambda t: W.seg_key("pos_huawei", "pos_huawei", t)
        self.tx = {"s2": {k(400.5): "Hallo", k(500.5): "Wendelin", k(600.5): "Hallo"}, "s2x": {}, "wh": {}, "hw4": {}}
        self.evs = {0.98: V.events_at(self.curves, 0.98)}

    def test_baender(self):
        self.assertEqual([A.band_of(p) for p in (0.98, 0.9949, 0.995, 0.9989, 0.999, 1.0)], [0, 0, 1, 1, 2, 2])

    def test_rufe_je_band(self):
        c = A.fixed_calls("huawei", "Wendelin", 0.98, self.curves, self.tx, self.labels, self.evs)
        self.assertEqual((c["n"], c["miss"]), (4, 1))
        self.assertEqual(c["bands"], [[1, 0], [1, 1], [1, 0]])                  # 0,985 / 0,996 / 0,9995
        self.assertEqual(c["hits"]["-"], 3)
        self.assertEqual(c["hits"]["app"], 1)
        self.assertEqual(c["hits"]["band999"], 2)                               # Ruf 4 (>= 0,999) kommt direkt durch
        self.assertEqual(c["hits"]["band995"], 2)                               # Ruf 4 und 5 sind >= 0,995; Ruf 5 besteht ohnehin
        self.assertIsNone(c["hits"]["hw4"])                                     # Cache fehlt

    def test_fehlender_hw2_text(self):
        del self.tx["s2"][W.seg_key("pos_huawei", "pos_huawei", 400.5)]
        with self.assertRaises(KeyError):
            A.fixed_calls("huawei", "Wendelin", 0.98, self.curves, self.tx, self.labels, self.evs)

    def test_ereignisse_je_quelle(self):
        cv = curves_mini({"conf": (np.array([1.0, 5.0, 9.0]), np.array([0.9995, 0.99, 0.985])), "syn": (np.array([2.0]), np.array([0.996]))})
        k = lambda s, t: W.seg_key(s, s, t)
        tx = {"s2": {k("conf", 1.0): "Hallo", k("conf", 5.0): "Wendelin", k("conf", 9.0): "Hey Hallo", k("syn", 2.0): "Hallo"},
              "s2x": {}, "wh": {}, "hw4": {}}
        ev = {0.98: V.events_at(cv, 0.98)}
        for s in ("neg_huawei", "neg_handy2", "fleurs"): ev[0.98][s] = {}
        r = A.fixed_events("Wendelin", 0.98, cv, tx, ev)
        self.assertEqual(r["n"]["conf"], 3)
        self.assertEqual(r["conf_bands"], [[2, 1], [0, 0], [1, 0]])             # 0,99 besteht, 0,985 nicht
        self.assertEqual(r["pass"]["-"]["conf"], 3)
        self.assertEqual(r["pass"]["app"]["conf"], 1)
        self.assertEqual(r["pass"]["band999"]["conf"], 2)
        self.assertEqual(r["pass"]["band995"]["syn"], 1)
        self.assertEqual(r["pass"]["app"]["syn"], 0)
        self.assertIsNone(r["pass"]["whisper_de"]["conf"])
        self.assertEqual(r["pass"]["app"]["fleurs"], 0)

    def test_zwei_ereignisse_im_fenster(self):
        cv = curves_mini({"pos_huawei": (np.array([800.5, 802.1]), np.array([0.985, 0.986]))})
        k = lambda t: W.seg_key("pos_huawei", "pos_huawei", t)
        tx = {"s2": {k(800.5): "Hallo", k(802.1): "Wendelin"}}
        lab = [{"dev": "huawei", "block": 8, "round": 1, "word": "Wendelin", "start": 800.0, "end": 801.0, "status": "ok"}]
        c = A.fixed_calls("huawei", "Wendelin", 0.98, cv, tx, lab, {0.98: V.events_at(cv, 0.98)}, ("-", "app"))
        self.assertEqual((c["bands"][0], c["hits"]["app"]), ([1, 1], 1))         # ein Ereignis genuegt

    def test_schwelle_unter_minimum_ist_none(self):
        tx = {"hw4": {"k": "Wendelin"}}
        self.assertIsNone(A.fixed_pass("hw4", "Wendelin", tx, "syn", "k", 0.9, 0.9))
        self.assertTrue(A.fixed_pass("hw4", "Wendelin", tx, "syn", "k", 0.9, 0.98))

    def test_render_abschnitt_6(self):
        low = (np.array([800.0]), np.array([0.1]))
        cv = {s: {s: low} for s in ("neg_huawei", "neg_handy2", "syn", "fleurs", "conf")}
        cv["pos_huawei"] = self.curves["pos_huawei"]; cv["pos_handy2"] = {"pos_handy2": low}
        txs = {"s2": {w: self.tx["s2"] for w in V.WORDS}, "s2x": {}, "wh": {}, "hw4": {}}
        fx = A.fixed_analysis({s: d for s, d in ((s, {s: low}) for s in cv) if s != "pos_huawei"} | {"pos_huawei": self.curves["pos_huawei"]},
                              {k: {w: (v if k == "s2" else None) for w in V.WORDS} for k, v in {"s2": self.tx["s2"], "s2x": None, "wh": None, "hw4": None}.items()},
                              self.labels, 0.98)
        md = A.render_fixed(fx, 0.98)
        self.assertIn("| huawei | Wendelin | 4 | 1 (0) | 1 (1) | 1 (0) | 1 |", md)
        self.assertIn("| Summe | beide | 4 | 1 (0) | 1 (1) | 1 (0) | 1 |", md)
        self.assertIn("| app | 1/4 |", md)
        self.assertIn("| band999 | 2/4 |", md)


class ExtraQuellen(unittest.TestCase):
    def test_normalisierung(self):
        x = np.array([0.0, 0.02, -0.04, 0.01], "float32")
        y = A.normalize_peak(x, 0.5)
        self.assertAlmostEqual(float(np.abs(y).max()), 0.5, places=6)
        np.testing.assert_allclose(y / y[2], x / x[2], atol=1e-6)               # nur skaliert, Form gleich
        self.assertEqual(y.dtype, np.float32)
        z = np.zeros(5, "float32")
        np.testing.assert_array_equal(A.normalize_peak(z), z)                    # Stille: keine Division durch 0
        self.assertEqual(A.normalize_peak(np.zeros(0, "float32")).size, 0)

    def test_varianten_und_baender(self):
        for n, (src, *_rest) in A.EXTRA.items():
            self.assertEqual(A.VARIANTS[n]["src"], src); self.assertEqual(A.VARIANTS[n]["thr_min"], 0.95)
            self.assertEqual(A.VARIANTS[n + "_band999"]["ceil"], 0.999); self.assertEqual(A.VARIANTS[n + "_band995"]["ceil"], 0.995)
            self.assertIn(n, A.FIXED_VARIANTS); self.assertIn(n + "_band995", A.FIXED_VARIANTS)
        self.assertEqual(len({v[0] for v in A.EXTRA.values()}), len(A.EXTRA))   # Quellen verschieden
        self.assertEqual((A.EXTRA["norm"][3], A.EXTRA["blank1"][4], A.EXTRA["blank2"][4]), (0.5, 1.0, 2.0))

    def test_cache_pfade_tragen_parameter_und_kollidieren_nicht(self):
        paths = {A.extra_path("v8a", n, "Wendelin") for n in A.EXTRA} | {A.hw4_path("v8a", "Wendelin"), V.s2_path("v8a", "Wendelin"), A.s2x_path("v8a", "Wendelin")}
        self.assertEqual(len(paths), len(A.EXTRA) + 3)
        self.assertIn("norm0.5", A.extra_path("v8a", "norm", "Wendelin")); self.assertIn("bp2.0", A.extra_path("v8a", "blank2", "Wendelin"))
        self.assertTrue(A.extra_path("v8a", "hw3", "Hey Wendelin").endswith("parakeet-hw3.0@hey_wendelin.json"))
        self.assertNotEqual(A.extra_path("v8a", "blank1", "Wendelin"), A.extra_path("v8a", "blank2", "Wendelin"))

    def test_load_tx_hat_quellen(self):
        self.assertTrue({v[0] for v in A.EXTRA.values()} <= set(A.load_tx("nichtda")))

    def test_fixed_pass_fehlende_quelle_ist_none(self):
        self.assertIsNone(A.fixed_pass("norm", "Wendelin", {"s2": {}}, "syn", "k", 0.9, 0.98))
        self.assertTrue(A.fixed_pass("norm", "Wendelin", {"nm": {"k": "Wendelin"}}, "syn", "k", 0.9, 0.98))
        self.assertTrue(A.fixed_pass("blank1_band999", "Wendelin", {"b1": {"k": "Hallo"}}, "syn", "k", 0.9995, 0.98))


class MakeRecBlankPenalty(unittest.TestCase):
    def _call(self, **kw):
        import types, station_measure as SM
        seen = {}
        fake = types.SimpleNamespace(OfflineRecognizer=types.SimpleNamespace(from_transducer=lambda **k: seen.update(k) or "rec"))
        old = sys.modules.get("sherpa_onnx"); sys.modules["sherpa_onnx"] = fake
        old_exists = os.path.exists
        os.path.exists = lambda p: True
        old_wd = (SM.WORK, SM.WORK111); SM.WORK = SM.WORK111 = os.path.join(os.environ.get("TMPDIR", "/tmp"), "s2a_test")
        SM.WORDS.setdefault("wendelin", {})["hot"] = ["Wendelin"]
        try: SM.make_rec("parakeet-hw2@wendelin", 1, **kw)
        finally:
            os.path.exists = old_exists; SM.WORK, SM.WORK111 = old_wd
            if old is None: del sys.modules["sherpa_onnx"]
            else: sys.modules["sherpa_onnx"] = old
        return seen

    def test_standard_unveraendert(self):
        self.assertNotIn("blank_penalty", self._call())

    def test_penalty_durchgereicht(self):
        self.assertEqual(self._call(blank_penalty=2.0)["blank_penalty"], 2.0)


class Ausgabe(unittest.TestCase):
    def test_render_ohne_transkripte(self):
        op = {("huawei", "Wendelin", "m"): {"basis": "Stufe 1", "n1": 3, "lost": [{"block": 5, "thr": 0.9, "texts": ["GEHEIMTEXT"], "cat": "leer", "rec": {"ausschnitt": True}}],
                                           "thrs": [0.9], "filt": {0.9: {s: (2, 1, {vn: 0 for vn in A.VARIANTS if vn != "app"})
                                                                         for s in ("neg_huawei", "syn", "fleurs", "conf")}}}}
        md = A.render([], {"m": "x"}, 2.0, op, {("m", "ausschnitt"): 4})
        self.assertNotIn("GEHEIMTEXT", md)
        self.assertIn("| huawei | Wendelin | m | Stufe 1 | 3 | 1 | 1 | 0 | 0 | 0 | 0 |", md)
        self.assertIn("m/ausschnitt: 4", md)
        self.assertIn("GEHEIMTEXT", A.render_lost(op))


if __name__ == "__main__":
    unittest.main()
