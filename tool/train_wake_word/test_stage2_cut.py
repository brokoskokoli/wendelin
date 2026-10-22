"""Selbsttest (stdlib unittest, erfundene Mini-Daten, ohne Modelle/Audio) fuer stage2_cut.py (WP133 A2: Ausschnitt-Paritaet, Vor-/Nachlauf).
Lauf (Venv mit numpy/soundfile/piper, z. B. wp58):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_stage2_cut.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np  # noqa: E402
import words_measure as W  # noqa: E402
import v8_measure as V  # noqa: E402
import stage2_analysis as A  # noqa: E402
import stage2_cut as C  # noqa: E402

HOP = 0.08


def grid(vals, t0=10.0):
    """Kurve mit 80-ms-Fenstern ab t0."""
    return np.array([t0 + HOP * i for i in range(len(vals))]), np.array(vals, dtype="float32")


def ev(vals, lower=0.98, **kw):
    t, v = grid(vals)
    return [(round(te - 10.0, 2), round(p, 4)) for te, p in C.app_events(t, v, lower, **kw)]


class AppHalten(unittest.TestCase):
    def test_spitze_dann_abfall_entscheidet_am_abfallfenster(self):
        # Fenster 0.. : 0.97 (unter Schwelle), 0.985 startet, 0.99 neue Spitze, 0.985 faellt -> Entscheidung dort mit 0.99
        self.assertEqual(ev([0.1, 0.97, 0.985, 0.99, 0.985, 0.1]), [(0.32, 0.99)])

    def test_limit_nach_fuenf_fenstern(self):
        # steigend ueber 5 Fenster: Entscheidung im 5. Fenster des Haltens (Zaehler 5), nicht frueher
        self.assertEqual(ev([0.981, 0.982, 0.983, 0.984, 0.985, 0.986, 0.1]), [(0.32, 0.985)])

    def test_gleicher_wert_zaehlt_weiter(self):
        self.assertEqual(ev([0.985, 0.985, 0.985, 0.985, 0.985, 0.1]), [(0.32, 0.985)])

    def test_sofort_ab_obergrenze(self):
        self.assertEqual(ev([0.1, 0.996, 0.5]), [(0.08, 0.996)])
        t = 10 + HOP * np.arange(3)
        self.assertEqual([p for _, p in C.app_events(t, np.array([0.1, 0.995, 0.5]), 0.98)], [0.995])     # Obergrenze inklusive (float64: float32 liegt knapp darueber)
        self.assertEqual([round(x - 10, 2) for x, _ in C.app_events(t, np.array([0.1, 0.995, 0.5]), 0.98)], [0.08])
        self.assertEqual(ev([0.1, 0.985, 0.996, 0.1]), [(0.16, 0.996)])          # waehrend des Haltens: sofort mit dem neuen Wert

    def test_untere_grenze_inklusive_und_darunter_nichts(self):
        t = 10 + HOP * np.arange(3)
        self.assertEqual([round(x - 10, 2) for x, _ in C.app_events(t, np.array([0.1, 0.98, 0.1]), 0.98)], [0.16])   # Halten, Abfall im naechsten Fenster
        self.assertEqual(ev([0.1, 0.9799, 0.9799, 0.1]), [])

    def test_nan_beendet_das_halten_ohne_ereignis_selbst(self):
        self.assertEqual(ev([0.985, float("nan"), 0.1]), [(0.08, 0.985)])
        self.assertEqual(ev([float("nan"), float("nan")]), [])

    def test_sperrzeit(self):
        v = [0.996] + [0.1] * 18 + [0.996, 0.1, 0.996]                           # Fenster 0, 19 (1,52 s), 21
        self.assertEqual(ev(v), [(0.0, 0.996), (1.52, 0.996)])
        v2 = [0.996] + [0.1] * 17 + [0.996]                                      # Fenster 18 = 1,44 s < 1,5 s
        self.assertEqual(ev(v2), [(0.0, 0.996)])

    def test_sperrzeit_ab_entscheidung_nicht_ab_erstem_fenster(self):
        # Entscheidung bei 0,32 s; Sperre bis 1,82 s. Ein neuer Sofort-Wert bei 1,6 s ist gesperrt, einer bei 1,84 s nicht.
        v = [0.985, 0.986, 0.987, 0.988, 0.985] + [0.1] * 15 + [0.996, 0.1, 0.1, 0.996]
        self.assertEqual(ev(v), [(0.32, 0.988), (1.84, 0.996)])
        v = [0.985, 0.986, 0.987, 0.988, 0.985] + [0.1] * 14 + [0.996]            # Fenster 19 = 1,52 s
        self.assertEqual(ev(v), [(0.32, 0.988)])

    def test_obergrenze_bestimmt_den_zeitpunkt(self):
        v = [0.1, 0.981, 0.996, 0.9995, 0.1]
        self.assertEqual(ev(v, upper=0.995), [(0.16, 0.996)])                    # Band 0,995: sofort beim ersten Wert >= 0,995
        self.assertEqual(ev(v, upper=0.999), [(0.24, 0.9995)])                   # Band 0,999: gehalten bis 0,999 (Wert >= Obergrenze entscheidet sofort)
        self.assertEqual(ev([0.1, 0.981, 0.996, 0.997, 0.1], upper=0.999), [(0.32, 0.997)])   # nie >= 0,999: Abfall beendet das Halten mit der Spitze

    def test_hold_eins_ist_roh(self):
        t, v = grid([0.1, 0.985, 0.99, 0.985, 0.1])
        self.assertEqual([x for x, _ in C.app_events(t, v, 0.98, hold=1)], W.score_events(t, v, 0.98))

    def test_app_ist_nie_frueher_als_erst(self):
        rng = np.random.RandomState(0)
        v = np.clip(rng.rand(400) * 1.2 - 0.1 + (rng.rand(400) > 0.9), 0, 1)
        t = 10 + HOP * np.arange(400)
        first = W.score_events(t, v, 0.98)
        app = [x for x, _ in C.app_events(t, v, 0.98)]
        self.assertTrue(len(app) >= 1 and all(a >= f for a, f in zip(app, first)))
        self.assertLessEqual(max(a - f for a, f in zip(app, first)), 4 * HOP + 1e-4)   # hoechstens 4 Fenster spaeter (Zaehler 5 bei Start im ersten)


class EreignisseUndSegmente(unittest.TestCase):
    def test_events_cut_erst_gleich_messung(self):
        t, v = grid([0.1, 0.985, 0.99, 0.985, 0.1])
        e, pk = C.events_cut({"s": {"i": (t, v)}}, 0.98, "erst")
        self.assertEqual(e["s"]["i"], W.score_events(t, v, 0.98))
        self.assertAlmostEqual(pk[("s", "i", W.seg_key("s", "i", e["s"]["i"][0]))], 0.99, 4)    # Spitze im Sperrfenster

    def test_events_cut_app_zeit_und_spitze(self):
        t, v = grid([0.1, 0.985, 0.99, 0.985, 0.1])
        e, pk = C.events_cut({"s": {"i": (t, v)}}, 0.98, "app")
        self.assertAlmostEqual(e["s"]["i"][0], 10.24, 4)
        self.assertAlmostEqual(pk[("s", "i", W.seg_key("s", "i", e["s"]["i"][0]))], 0.99, 4)
        with self.assertRaises(ValueError): C.events_cut({"s": {"i": (t, v)}}, 0.98, "x")

    def test_segment_grenzen_und_paritaet(self):
        x = np.arange(20 * C.SR, dtype="float32")
        k = "pos_huawei|pos_huawei|1000"                                        # 10 s
        a, b = C.seg_bounds(k, 2.0, 0.9)
        self.assertEqual((a, b), (8 * C.SR, int(10.9 * C.SR)))
        np.testing.assert_array_equal(x[a:b], W.segment(x, k))                  # 2,0/0,9 = Ausschnitt der Messung (hw2-Cache s2)
        np.testing.assert_array_equal(x[a:b], A.segment_x(x, k, 2.0, 0.9))
        self.assertEqual(C.seg_bounds(k, 1.2, 1.8), (int(8.8 * C.SR), int(11.8 * C.SR)))
        self.assertEqual(C.seg_bounds("a|b|100", 2.5, 0.9)[0], 0)               # am Anfang gekuerzt

    def test_varianten(self):
        self.assertEqual(len(C.VARS), 2 * 3 * 3 * 2 * 2 + 2)                      # + Band 0,995 nur fuer den App-Ausschnitt
        self.assertEqual(sorted(n for n, v in C.VARS.items() if v["app"]),
                         sorted(C.vname("app", 2.0, 0.9, n, b) for n in (False, True) for b in (None, 0.995, 0.999)))
        self.assertEqual(C.VARS["app-2.0-0.9-nm-b999"]["ceil"], 0.999)
        self.assertEqual(C.VARS["app-2.0-0.9-b995"]["ceil"], 0.995)
        self.assertNotIn("erst-2.0-0.9-b995", C.VARS)
        self.assertEqual((C.VARS["app-1.2-0.9-b999"]["upper"], C.VARS["app-1.2-0.9"]["upper"], C.VARS["erst-1.2-0.9"]["upper"]), (0.999, 0.995, None))
        self.assertEqual(C.groups(), [("app", 0.995), ("app", 0.999), ("erst", None)])
        self.assertIsNone(C.VARS["erst-1.2-1.8"]["ceil"])
        self.assertEqual(C.combos()[0], (2.0, 0.9, False))
        self.assertEqual(len(set(C.combos())), 18)

    def test_cache_pfade(self):
        ps = {C.cut_path("v8a", w, *c) for w in V.WORDS for c in C.combos()}
        self.assertEqual(len(ps), 36)
        self.assertIn("-nm0.5", C.cut_path("v8a", "Wendelin", 2.0, 0.9, True))
        self.assertTrue(C.cut_path("v8a", "Hey Wendelin", 1.2, 1.8, False).endswith("-p1.2-t1.8/hw2@hey_wendelin.json"))


def curves_mini(vals):
    return {s: {s: vals.get(s, (np.array([0.0]), np.array([0.0])))} for s in V.SRCS}


class Auswertung(unittest.TestCase):
    def setUp(self):
        # Ruf in Block 4: Halten 0,981..0,99, App-Zeit 0,24 s nach dem ersten Fenster; Text nur zur App-Zeit korrekt
        t, v = grid([0.981, 0.985, 0.99, 0.985, 0.1], t0=400.0)
        self.curves = curves_mini({"pos_huawei": (t, v)})
        self.labels = [{"dev": "huawei", "block": 4, "round": 1, "word": "Wendelin", "start": 399.0, "end": 399.5, "status": "ok"}]
        self.hr = {s: 1.0 for s in W.NEG_SRC + ["conf"]}
        kE, kA = (W.seg_key("pos_huawei", "pos_huawei", x) for x in (400.0, 400.24))
        self.kE, self.kA = kE, kA
        self.tx = {c: {w: None for w in V.WORDS} for c in C.combos()}
        self.tx[(2.0, 0.9, False)]["Wendelin"] = {kE: "Hallo", kA: "Wendelin"}
        self.tx[(2.0, 0.9, False)]["Hey Wendelin"] = {kE: "Hallo", kA: "Hallo"}

    def row(self, rows, name, thr=0.98):
        return [r for r in rows if r["stage2"] == name and r["thr"] == W.cfg_s(thr) and r["dev"] == "huawei" and r["word"] == "Wendelin"][0]

    def test_zeilen_je_bezug(self):
        rows, skipped = C.cut_rows(self.curves, self.labels, self.hr, self.tx)
        self.assertEqual(self.row(rows["erst"], "-")["hit"], 1)
        self.assertEqual(self.row(rows["app"], "-")["hit"], 1)
        self.assertEqual(self.row(rows["erst"], "erst-2.0-0.9")["hit"], 0)       # Text zur ersten Zeit: „Hallo“
        self.assertEqual(self.row(rows["app"], "app-2.0-0.9")["hit"], 1)         # Text zur App-Zeit: „Wendelin“
        self.assertEqual(self.row(rows["app"], "app-2.0-0.9-b999")["hit"], 1)
        self.assertNotIn("erst-2.0-0.9", {r["stage2"] for r in rows["app"]})
        self.assertGreater(skipped["app-1.2-0.9"], 0)                           # Cache fehlt -> uebersprungen, kein Absturz
        self.assertNotIn("app-2.0-0.9", skipped)
        self.assertFalse([r for r in rows["app"] if r["stage2"] == "app-2.0-0.9" and r["thr"] == W.cfg_s(0.9)])   # Varianten erst ab 0,95

    def test_band_laesst_hohen_spitzenwert_durch(self):
        t, v = grid([0.981, 0.985, 0.9995, 0.985, 0.1], t0=400.0)
        cv = curves_mini({"pos_huawei": (t, v)})
        self.tx[(2.0, 0.9, False)]["Wendelin"][W.seg_key("pos_huawei", "pos_huawei", 400.16)] = "Hallo"      # App entscheidet sofort (>= 0,995)
        rows, _ = C.cut_rows(cv, self.labels, self.hr, self.tx)
        self.assertEqual(self.row(rows["erst"], "erst-2.0-0.9")["hit"], 0)
        self.assertEqual(self.row(rows["erst"], "erst-2.0-0.9-b999")["hit"], 1)  # Spitzenwert = Maximum im Sperrfenster (1,5 s) ab erstem Fenster
        self.assertEqual(self.row(rows["app"], "app-2.0-0.9")["hit"], 0)           # sofort bei 400,16 s, Text „Hallo“
        self.assertEqual(self.row(rows["app"], "app-2.0-0.9-b999")["hit"], 1)

    def test_feste_schwelle(self):
        fx = C.cut_fixed(self.curves, self.labels, self.tx)
        self.assertEqual(fx[("erst", "-")]["hits"][("huawei", "Wendelin")], (1, 1))
        self.assertEqual(fx[("erst", "erst-2.0-0.9")]["hits"][("huawei", "Wendelin")], (0, 1))
        self.assertEqual(fx[("app", "app-2.0-0.9")]["hits"][("huawei", "Wendelin")], (1, 1))
        self.assertEqual(fx[("app", "app-2.0-0.9")]["hits"][("huawei", "Hey Wendelin")], (0, 0))
        self.assertIsNone(fx[("app", "app-1.2-0.9")]["hits"][("huawei", "Wendelin")])           # Text fehlt
        self.assertIsNone(fx[("app", "app-1.2-0.9")]["pass"]["Wendelin"]["conf"])
        self.assertEqual(fx[("app", "-")]["n"]["Wendelin"]["conf"], 0)

    def test_render(self):
        rows, skipped = C.cut_rows(self.curves, self.labels, self.hr, self.tx)
        md = C.render_cut(rows, C.cut_fixed(self.curves, self.labels, self.tx), skipped, 2.0)
        self.assertIn("## 7a.", md); self.assertIn("## 7b.", md); self.assertIn("## 7c.", md)
        self.assertIn("| app | 2.0 / 0.9, hw2 **(App)** |", md)
        self.assertIn("| app | 2.0 / 0.9, hw2+norm + Band 0,999 **(App)** |", md)
        self.assertIn("| app | 2.0 / 0.9, hw2 + Band 0,995 **(App)** |", md)
        self.assertIn("| erst | Stufe 1 allein |", md)
        self.assertIn("| app | 2.0 / 0.9, hw2 **(App)** | 1/1 | 0/0 |", md)             # 7c: Treffer huawei Wendelin / Hey Wendelin
        self.assertIn("| erst | 2.0 / 0.9, hw2 | 0/1 | 0/0 |", md)


if __name__ == "__main__":
    unittest.main()
