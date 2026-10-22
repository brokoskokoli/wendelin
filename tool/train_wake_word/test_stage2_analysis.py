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
