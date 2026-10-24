"""Selbsttest (stdlib unittest, erfundene Mini-Daten, ohne Modelle/Audio) fuer stage2_cut.py (WP133 A2: Ausschnitt-Paritaet, Vor-/Nachlauf).
Lauf (Venv mit numpy/soundfile/piper, z. B. wp58):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_stage2_cut.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import json, os, sys, unittest

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


PAD = [0.1] * 12                                                                # Auslauf: das Halten (0,8 s = 10 Fenster) wird fertig


class AppHalten(unittest.TestCase):
    def test_spitze_dann_abfall_entscheidet_erst_am_ende(self):
        # Abfall beendet nichts: Start bei Fenster 2 (0,16 s), Spitze 0,99 bei 0,24 s, Entscheidung bei 0,16 + 0,8 = 0,96 s, Zeit = Spitze
        self.assertEqual(ev([0.1, 0.97, 0.985, 0.99, 0.985] + PAD), [(0.24, 0.99)])

    def test_ende_einschliesslich_nach_zehn_fenstern(self):
        # Start bei Fenster 0; Fenster 10 (+0,80 s) zaehlt noch mit, Fenster 11 (+0,88 s) nicht
        self.assertEqual(ev([0.981] + [0.982] * 9 + [0.99, 0.995, 0.1]), [(0.8, 0.99)])
        self.assertEqual(ev([0.981] + [0.982] * 9 + [0.99, 0.995, 0.1]), ev([0.981] + [0.982] * 9 + [0.99, 0.1, 0.1]))

    def test_gleicher_wert_spaeteres_fenster(self):
        self.assertEqual(ev([0.985, 0.985, 0.985] + PAD), [(0.16, 0.985)])

    def test_sofort_ab_obergrenze(self):
        self.assertEqual(ev([0.1, 0.996, 0.5]), [(0.08, 0.996)])
        t = 10 + HOP * np.arange(3)
        self.assertEqual([p for _, p in C.app_events(t, np.array([0.1, 0.995, 0.5]), 0.98)], [0.995])     # Obergrenze inklusive (float64: float32 liegt knapp darueber)
        self.assertEqual([round(x - 10, 2) for x, _ in C.app_events(t, np.array([0.1, 0.995, 0.5]), 0.98)], [0.08])
        self.assertEqual(ev([0.1, 0.985, 0.996, 0.1]), [(0.16, 0.996)])          # waehrend des Haltens: sofort mit dem neuen Wert und dessen Zeit

    def test_obergrenze_genau_entscheidet_sofort_ausserhalb_und_im_halten(self):
        t = 10 + HOP * np.arange(4)
        im = C.app_events(t, np.array([0.1, 0.985, 0.995, 0.1]), 0.98)
        self.assertEqual([(round(x - 10, 2), p) for x, p in im], [(0.16, 0.995)])                # im Halten: sofort
        eig = C.app_events(t, np.array([0.1, 0.985, 0.9, 0.1]), 0.98, upper=0.985)
        self.assertEqual([(round(x - 10, 2), p) for x, p in eig], [(0.08, 0.985)])               # eigene Obergrenze 0.985 gilt auch

    def test_erstes_fenster_genau_obergrenze_entscheidet_sofort(self):
        t = 10 + HOP * np.arange(4)
        e = C.app_events(t, np.array([0.1, 0.995, 0.5, 0.5]), 0.98, flush=False)
        self.assertEqual([(round(x - 10, 2), p) for x, p in e], [(0.08, 0.995)])                 # sofort: mit Halten fehlte das Ereignis (Kurve endet vor 0,8 s, flush=False)

    def test_untere_grenze_inklusive_und_darunter_nichts(self):
        self.assertEqual(ev([0.1, 0.98, 0.1] + PAD), [(0.08, 0.98)])
        self.assertEqual(ev([0.1, 0.9799, 0.9799, 0.1] + PAD), [])

    def test_nan_beendet_das_halten_nicht(self):
        self.assertEqual(ev([0.985, float("nan"), 0.99] + PAD), [(0.16, 0.99)])
        self.assertEqual(ev([float("nan"), float("nan")]), [])
        self.assertEqual(ev([0.985, 0.99, None] + PAD), [(0.08, 0.99)])                  # None wie NaN

    def test_unvollstaendiges_halten_gibt_ohne_flush_kein_ereignis(self):
        self.assertEqual(ev([0.985, 0.99, 0.985], flush=False), [])

    def test_sperrzeit_von_trefferzeit_zu_trefferzeit(self):
        v = [0.996] + [0.1] * 18 + [0.996, 0.1, 0.996]                           # Fenster 0, 19 (1,52 s), 21
        self.assertEqual(ev(v), [(0.0, 0.996), (1.52, 0.996)])
        v2 = [0.996] + [0.1] * 17 + [0.996]                                      # Fenster 18 = 1,44 s < 1,5 s
        self.assertEqual(ev(v2), [(0.0, 0.996)])

    def test_sperrzeit_ab_spitze_nicht_ab_entscheidung(self):
        # Spitze bei 0,16 s, Entscheidung bei 0,88 s. Zweiter Ruf: Spitze bei 1,60 s (1,44 s nach der ersten Spitze) ist gesperrt, bei 1,68 s nicht.
        v = [0.985, 0.986, 0.987] + [0.1] * 16 + [0.985, 0.99] + PAD            # Fenster 19 = 1,52 s Start, 20 = 1,60 s Spitze
        self.assertEqual(ev(v), [(0.16, 0.987)])
        v = [0.985, 0.986, 0.987] + [0.1] * 17 + [0.985, 0.99] + PAD            # Spitze Fenster 21 = 1,68 s
        self.assertEqual(ev(v), [(0.16, 0.987), (1.68, 0.99)])

    def test_obergrenze_bestimmt_den_zeitpunkt(self):
        v = [0.1, 0.981, 0.996, 0.9995, 0.1] + PAD
        self.assertEqual(ev(v, upper=0.995), [(0.16, 0.996)])                    # Band 0,995: sofort beim ersten Wert >= 0,995
        self.assertEqual(ev(v, upper=0.999), [(0.24, 0.9995)])                   # Band 0,999: gehalten bis 0,999 (Wert >= Obergrenze entscheidet sofort)
        self.assertEqual(ev([0.1, 0.981, 0.996, 0.997, 0.1] + PAD, upper=0.999), [(0.24, 0.997)])   # nie >= 0,999: Spitze nach 0,8 s

    def test_hold_null_ist_roh(self):
        t, v = grid([0.1, 0.985, 0.99, 0.985, 0.1])
        self.assertEqual([x for x, _ in C.app_events(t, v, 0.98, hold=1)], W.score_events(t, v, 0.98))
        self.assertEqual(C.app_events(t, v, 0.98, hold=1), C.app_events(t, v, 0.98, hold_s=0))
        self.assertEqual(C.app_events(t, v, 0.98, hold=C.APP_HOLD), C.app_events(t, v, 0.98))   # Alias 11 Fenster = 0,8 s

    def test_spitze_liegt_hoechstens_0_8_s_nach_einem_bandfenster(self):
        rng = np.random.RandomState(0)
        v = np.clip(rng.rand(400) * 1.2 - 0.1 + (rng.rand(400) > 0.9), 0, 1)
        t = 10 + HOP * np.arange(400)
        app = [x for x, _ in C.app_events(t, v, 0.98)]
        self.assertGreaterEqual(len(app), 3)
        inband = t[v >= 0.98]
        for a in app: self.assertTrue(any(-1e-6 <= a - f <= 0.8 + 1e-4 for f in inband), a)

    def test_flush_offenes_halten_am_ende_gibt_spitze(self):
        v = [0.1, 0.985, 0.99, 0.986]                                            # Kurve endet 0,16 s nach dem ersten Bandfenster
        self.assertEqual(ev(v), [(0.16, 0.99)])
        self.assertEqual(ev(v, flush=False), [])

    def test_flush_gleich_elf_nullfenster_angehaengt(self):
        rng = np.random.RandomState(3)
        n_ev = 0
        for k in range(60):
            n = int(rng.randint(3, 80))
            v = np.clip(rng.rand(n) * 1.2 - 0.1 + (rng.rand(n) > 0.8), 0, 1).astype("float32")
            t = 10 + HOP * np.arange(n)
            t0 = np.concatenate([t, t[-1] + HOP * np.arange(1, 12)])
            v0 = np.concatenate([v, np.zeros(11, dtype="float32")])
            a = C.app_events(t, v, 0.98)
            self.assertEqual(a, C.app_events(t0, v0, 0.98, flush=False), k)
            n_ev += len(a)
        self.assertGreater(n_ev, 20)

    def test_flush_ereignis_beachtet_sperrzeit(self):
        v = [0.1, 0.985, 0.99] + [0.1] * 12 + [0.985, 0.99]                      # zweites Halten offen am Ende, Spitze bei 1,28 s
        self.assertEqual(ev(v, refr=1.0), [(0.16, 0.99), (1.28, 0.99)])          # Abstand 1,12 s >= 1,0 s: Flush-Ereignis
        self.assertEqual(ev(v), [(0.16, 0.99)])                                  # Abstand 1,12 s < 1,5 s: Sperrzeit gilt auch fuer das Flush-Ereignis
        self.assertEqual(ev(v, refr=1.0, flush=False), [(0.16, 0.99)])

    def test_paritaet_mit_dart_fixture(self):
        with open(os.path.join(os.path.dirname(os.path.dirname(HERE)), "packages", "wendelin_voice", "test", "fixtures", "wake_hold_parity.json")) as f:
            fx = json.load(f)
        r = fx["rule"]
        self.assertEqual(r["hold_ms"], round(C.APP_HOLD_S * 1000))
        self.assertGreater(len(fx["cases"]), 15)
        for c in fx["cases"]:
            with self.subTest(c["name"]):
                t = np.array([10.0 + w[0] / 1000 for w in c["windows"]])
                v = [w[1] for w in c["windows"]]
                got = C.app_events(t, v, r["lower"], r["upper"], r["hold_ms"] / 1000, r["refractory_ms"] / 1000, flush=False)   # Dart entscheidet beim Stromende nicht
                got = [(round((te - 10.0) * 1000), p, p >= r["upper"]) for te, p in got]
                want = [(e["t_ms"], e["score"], e["direct"]) for e in c["events"]]
                self.assertEqual([(a, b, d) for a, b, d in got], [(a, b, d) for a, b, d in want])


class EreignisseUndSegmente(unittest.TestCase):
    def test_events_cut_erst_gleich_messung(self):
        t, v = grid([0.1, 0.985, 0.99, 0.985, 0.1] + PAD)
        e, pk = C.events_cut({"s": {"i": (t, v)}}, 0.98, "erst")
        self.assertEqual(e["s"]["i"], W.score_events(t, v, 0.98))
        self.assertAlmostEqual(pk[("s", "i", W.seg_key("s", "i", e["s"]["i"][0]))], 0.99, 4)    # Spitze im Sperrfenster

    def test_events_cut_app_zeit_und_spitze(self):
        t, v = grid([0.1, 0.985, 0.99, 0.985, 0.1] + PAD)
        e, pk = C.events_cut({"s": {"i": (t, v)}}, 0.98, "app")
        self.assertAlmostEqual(e["s"]["i"][0], 10.16, 4)                             # Spitzenfenster
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
        # Ruf in Block 4: Halten 0,981..0,99, App-Zeit (Spitzenfenster) 0,16 s nach dem ersten Fenster; Text nur zur App-Zeit korrekt
        t, v = grid([0.981, 0.985, 0.99, 0.985, 0.1] + PAD, t0=400.0)
        self.curves = curves_mini({"pos_huawei": (t, v)})
        self.labels = [{"dev": "huawei", "block": 4, "round": 1, "word": "Wendelin", "start": 399.0, "end": 399.5, "status": "ok"}]
        self.hr = {s: 1.0 for s in W.NEG_SRC + ["conf"]}
        kE, kA = (W.seg_key("pos_huawei", "pos_huawei", x) for x in (400.0, 400.16))
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
        t, v = grid([0.981, 0.985, 0.9995, 0.985, 0.1] + PAD, t0=400.0)
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


class ModelleUndSeeds(unittest.TestCase):
    """WP137 Teil 1: --cut-only fuer jedes Modell, eigener Cache je Modell, Seed-Zusammenfassung."""
    def test_cache_je_modell_v8a_unveraendert(self):
        keep = dict(V.CACHE_TAG)
        try:
            V.CACHE_TAG.update({"v8a": "v8a-11111111", "v8c": "v8c-22222222"})
            a, c = C.cut_path("v8a", "Wendelin", 2.0, 0.9, False), C.cut_path("v8c", "Wendelin", 2.0, 0.9, False)
            self.assertEqual(a, f"{V.RES}/s2p/v8a-11111111-p2.0-t0.9/hw2@wendelin.json")
            self.assertEqual(c, f"{V.RES}/s2p/v8c-22222222-p2.0-t0.9/hw2@wendelin.json")
        finally:
            V.CACHE_TAG.clear(); V.CACHE_TAG.update(keep)

    def test_standard_ist_v8a_und_tabellenname(self):
        self.assertEqual(C.CUT_TAG, "v8a")
        self.assertTrue(C.table_path().endswith("/stage2_cut_table.md"))
        self.assertTrue(C.table_path("v8a").endswith("/stage2_cut_table.md"))
        self.assertTrue(C.table_path("c-s2").endswith("/stage2_cut_table_c-s2.md"))

    def test_load_cut_tx_je_modell(self):
        import json, tempfile
        keep = V.RES
        with tempfile.TemporaryDirectory() as d:
            try:
                V.RES = d
                p = C.cut_path("v8c", "Wendelin", 2.0, 0.9, False)
                os.makedirs(os.path.dirname(p)); json.dump({"k": "Wendelin"}, open(p, "w"))
                self.assertEqual(C.load_cut_tx("v8c")[(2.0, 0.9, False)]["Wendelin"], {"k": "Wendelin"})
                self.assertIsNone(C.load_cut_tx("v8a")[(2.0, 0.9, False)]["Wendelin"])     # v8a-Cache bleibt getrennt
                self.assertIsNone(C.load_cut_tx()[(2.0, 0.9, False)]["Wendelin"])          # Standard = v8a
            finally:
                V.RES = keep

    def test_zeilen_und_titel_tragen_das_modell(self):
        t, v = grid([0.981, 0.985, 0.99, 0.985, 0.1], t0=400.0)
        cv = curves_mini({"pos_huawei": (t, v)})
        labels = [{"dev": "huawei", "block": 4, "round": 1, "word": "Wendelin", "start": 399.0, "end": 399.5, "status": "ok"}]
        hr = {s: 1.0 for s in W.NEG_SRC + ["conf"]}
        tx = {c: {w: None for w in V.WORDS} for c in C.combos()}
        rows, skipped = C.cut_rows(cv, labels, hr, tx, "v8c")
        self.assertEqual({r["prog"] for r in rows["app"]}, {"v8c"})
        md = C.render_cut(rows, C.cut_fixed(cv, labels, tx), skipped, 2.0, "v8c")
        self.assertIn(": v8c, Prüfsplit", md)
        self.assertNotIn("v8a", md)
        self.assertIn(": v8a, Prüfsplit", C.render_cut(rows, C.cut_fixed(cv, labels, tx), skipped, 2.0))

    def test_cut_fixed_filter_gleich_vollem_lauf(self):
        t, v = grid([0.981, 0.985, 0.99, 0.985, 0.1], t0=400.0)
        cv = curves_mini({"pos_huawei": (t, v)})
        labels = [{"dev": "huawei", "block": 4, "round": 1, "word": "Wendelin", "start": 399.0, "end": 399.5, "status": "ok"}]
        tx = {c: {w: None for w in V.WORDS} for c in C.combos()}
        full = C.cut_fixed(cv, labels, tx, 0.95)
        part = C.cut_fixed(cv, labels, tx, 0.95, refs=("app",), only=C.SEED_STAGES)
        self.assertEqual(sorted(part), [("app", "-"), ("app", C.SEED_BAND)])
        self.assertEqual(part[("app", "-")], full[("app", "-")])
        self.assertEqual(part[("app", C.SEED_BAND)], full[("app", C.SEED_BAND)])
        self.assertEqual(part[("app", "-")]["hits"][("huawei", "Wendelin")], (1, 1))

    def test_run_all_schreibt_je_modell_und_liefert_seed_daten(self):
        import tempfile
        t, v = grid([0.981, 0.985, 0.99, 0.985, 0.1], t0=400.0)
        cv = curves_mini({"pos_huawei": (t, v)})
        labels = [{"dev": "huawei", "block": 4, "round": 1, "word": "Wendelin", "start": 399.0, "end": 399.5, "status": "ok"}]
        hr = {s: 1.0 for s in W.NEG_SRC + ["conf"]}
        keep = V.RES
        with tempfile.TemporaryDirectory() as d:
            try:
                V.RES = d
                self.assertEqual(C.run_all(cv, labels, hr, 2.0, 1, True), {})                       # Standard: wie bisher, keine Seed-Daten
                sd = C.run_all(cv, labels, hr, 2.0, 1, True, "v8c", C.SEED_THRS)
                self.assertEqual(sorted(os.listdir(d)), ["stage2_cut_table.md", "stage2_cut_table_v8c.md"])
                self.assertEqual(sorted(sd), list(C.SEED_THRS))
                self.assertEqual(sorted(sd[0.95]), [("app", "-"), ("app", C.SEED_BAND)])
                self.assertIn(": v8c,", open(os.path.join(d, "stage2_cut_table_v8c.md"), encoding="utf-8").read())
            finally:
                V.RES = keep

    @staticmethod
    def fx(hits, conf, syn, nh, n2):
        """cut_fixed-Ergebnis fuer eine Variante: hits = (Treffer, n) je Geraet fuer Wendelin; Hey Wendelin ohne Rufe."""
        h = {(d, w): (0, 0) for d in V.DEVICES for w in V.WORDS}
        h[("huawei", "Wendelin")], h[("handy2", "Wendelin")] = hits
        z = dict.fromkeys(A.FIXED_SRC, 0)
        p = {"Wendelin": dict(z, conf=conf, syn=syn, neg_huawei=nh, neg_handy2=n2), "Hey Wendelin": dict(z)}
        return {"hits": h, "pass": p, "n": {}}

    def test_seed_values(self):
        hr = {"neg_huawei": 1.0, "neg_handy2": 3.0, "syn": 2.0, "fleurs": 1.0, "conf": 1.0}
        o = C.seed_values(self.fx(((3, 4), (1, 4)), 5, 4, 2, 2), hr)
        self.assertEqual(o["Treffer Wendelin [%]"], 50.0)
        self.assertIsNone(o["Treffer Hey Wendelin [%]"])            # keine Rufe -> kein Wert statt 0 %
        self.assertEqual((o["Verwechsler (Ereignisse)"], o["FA/h syn"], o["FA/h echt"]), (5, 2.0, 1.0))   # echt = (2+2)/(1+3)
        bad = self.fx(((3, 4), (1, 4)), 5, 4, 2, 2); bad["pass"]["Wendelin"]["conf"] = None
        self.assertIsNone(C.seed_values(bad, hr)["FA/h echt"])

    def test_seed_summary_mittel_min_max_und_fehlende_werte(self):
        hr = {"neg_huawei": 1.0, "neg_handy2": 1.0, "syn": 1.0, "fleurs": 1.0, "conf": 1.0}

        def tag(hit, conf):
            r = {("app", "-"): self.fx(((hit, 10), (hit, 10)), conf, 0, 0, 0), ("app", C.SEED_BAND): self.fx(((hit, 10), (hit, 10)), conf, 0, 0, 0)}
            return {thr: r for thr in C.SEED_THRS}
        for w in ("Hey Wendelin",):
            pass
        per = {"a": tag(4, 2), "b": tag(8, 6)}
        for t in per.values():                                     # Hey Wendelin braucht Rufe, sonst „-“
            for r in t.values():
                for x in r.values(): x["hits"][("huawei", "Hey Wendelin")] = (1, 2); x["hits"][("handy2", "Hey Wendelin")] = (1, 2)
        md = C.seed_summary([("g", ["a", "b"])], per, hr)
        self.assertIn("| g | 2 | 0,98 | Stufe 1 | 60 [40–80] | 50 [50–50] | 4 [2–6] |", md)
        self.assertEqual(md.count("| g | 2 |"), 6)
        md2 = C.seed_summary([("g", ["a", "fehlt"])], per, hr)
        self.assertIn("| g | 2 | 0,95 | Band 0,999 | - | - | - |", md2)      # ein Seed ohne Daten -> kein Mittel aus dem Rest

    def test_parse_seed_group(self):
        self.assertEqual(C.parse_seed_group("v8c=v8c,c-s2,c-s3"), ("v8c", ["v8c", "c-s2", "c-s3"]))
        for bad in ("v8c", "=a", "g=", "g=a,a"):
            with self.assertRaises(ValueError): C.parse_seed_group(bad)

    def test_cli_cut_only_ohne_modell_und_mit_unbekannter_gruppe(self):
        import subprocess, tempfile
        py = [sys.executable, "-I", os.path.join(HERE, "stage2_analysis.py")]
        p = subprocess.run(py + ["--cut-only", "--no-v7"], capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0); self.assertIn("--model", p.stderr + p.stdout)
        with tempfile.NamedTemporaryFile() as f:
            p = subprocess.run(py + ["--cut-only", "--no-v7", "--model", f"v8c={f.name}", "--seed-group", "g=v8c,x"], capture_output=True, text=True)
            self.assertNotEqual(p.returncode, 0); self.assertIn("Modell x fehlt", p.stderr + p.stdout)


if __name__ == "__main__":
    unittest.main()
