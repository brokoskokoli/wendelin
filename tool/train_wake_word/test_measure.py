"""Selbsttests (stdlib unittest, ohne Modelle/Audio) fuer die Messhelfer von WP111.
Lauf (Venv mit numpy/scipy, z. B. wp58):
  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_measure.py'
Hinweis: Das Gate (tool/gate.dart, tool/t.sh) fuehrt keine Python-Tests aus."""
import os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import kws_measure as K            # noqa: E402
import station_measure as S        # noqa: E402
import words_labels as L           # noqa: E402
import words_measure as W          # noqa: E402


class HeyRule(unittest.TestCase):
    def test_hey_pflicht(self):
        self.assertFalse(K.matches_hey_wake_word("Hallo Wendelin"))
        self.assertFalse(K.matches_hey_wake_word("Wendelin"))
        self.assertTrue(K.matches_wake_word("Wendelin"))

    def test_hey_wendelin_varianten(self):
        for t in ["Hey Wendelin", "hey Vendelin wie spät", "Heywendelin", "Hei Wendelin", "hey wen delin"]:
            self.assertTrue(K.matches_hey_wake_word(t), t)

    def test_verwechsler(self):
        for t in ["Hey Wendel", "Hey Berlin"]:
            self.assertFalse(K.matches_hey_wake_word(t), t)

    def test_funktionswort_trennt(self):
        self.assertFalse(K.matches_hey_wake_word("hey in wendelin"))
        self.assertFalse(K.matches_hey_wake_word("hey wendel in der Küche"))   # Funktionswort nach dem Teilwort trennt nicht zusammen


class Stats(unittest.TestCase):
    def test_wilson(self):
        self.assertEqual(S.wilson(0, 0), (0.0, 0.0))
        lo, hi = S.wilson(40, 50)
        self.assertAlmostEqual(lo, 0.6696, places=3); self.assertAlmostEqual(hi, 0.8876, places=3)
        self.assertEqual(S.wilson(0, 10)[0], 0.0); self.assertEqual(S.wilson(10, 10)[1], 1.0)
        self.assertAlmostEqual(S.wilson(0, 10)[1], 0.2775, places=3)

    def test_poisson_upper(self):
        self.assertAlmostEqual(S.poisson_upper(0, 1), 3.689, places=3)
        self.assertAlmostEqual(S.poisson_upper(2, 2), 3.612, places=3)
        self.assertAlmostEqual(S.poisson_upper(0, 2), S.poisson_upper(0, 1) / 2, places=6)


class Rules(unittest.TestCase):
    def test_parse_rules(self):
        r = S.parse_rules("T0.9,M0.5, W0.8,Kz2/0.15")
        self.assertEqual([x["kind"] for x in r], ["T", "M", "W", "K"])
        self.assertEqual(r[0]["thr"], 0.9)
        self.assertEqual(r[2]["name"], "W0.8")
        self.assertEqual((r[3]["model"], r[3]["boost"], r[3]["thr"]), ("z", 2.0, 0.15))
        self.assertEqual(S.parse_rules("Kg4/0.05")[0]["model"], "g")


class Pairs(unittest.TestCase):
    def test_paare_gleich(self):
        S.check_pairs(["a/x_1.wav", "a/y_2.wav"], ["b/x_1.wav", "b/y_2.wav"])

    def test_paare_ungleich(self):
        with self.assertRaises(AssertionError):
            S.check_pairs(["a/x_1.wav", "a/y_2.wav"], ["b/x_1.wav", "b/z_2.wav"])
        with self.assertRaises(AssertionError):
            S.check_pairs(["a/x_1.wav"], ["b/x_1.wav", "b/y_2.wav"])


class Exclusion(unittest.TestCase):
    def test_ausschluss(self):
        clips = [{"name": n} for n in ["a.wav", "b.wav", "c.wav", "d.wav", "b6-x.wav"]]
        scan = {"a.wav": {"hit": False, "hit2": False},
                "b.wav": {"hit": True, "hit2": False},      # nur gemessener Erkenner hoert Wort
                "c.wav": {"hit": False, "hit2": True},      # nur zweiter Erkenner
                "d.wav": {"hit": False},                    # ohne zweiten Erkenner
                "b6-x.wav": {"hit": False, "hit2": False}}
        self.assertEqual(S.exclusion_names(clips, scan), ["b.wav", "c.wav", "b6-x.wav"])

    def test_cache_neuscan(self):
        self.assertTrue(S.scan_current({"n": 5, "hit": False}, 5, False))
        self.assertTrue(S.scan_current({"n": 5, "hit": False, "hit2": False}, 5, True))
        self.assertFalse(S.scan_current({"n": 5, "hit": False}, 5, True))     # ohne Whisper-Treffer-Feld: neu scannen
        self.assertFalse(S.scan_current({"n": 6, "hit": False, "hit2": False}, 5, True))
        self.assertFalse(S.scan_current(None, 5, False))


class WordLabels(unittest.TestCase):
    """WP121: Labels aus Ansagen und Reihenfolge (words_labels.py)."""

    @staticmethod
    def _block(t0, n=L.PER_BLOCK, step=4.5):
        return [{"s": t0 + i * step, "e": t0 + i * step + 0.8, "huawei": "Wort", "handy2": "Wort"} for i in range(n)]

    def test_noise_text(self):
        for t in ["[Musik]", "*hust*", "* Gelaechter *", "(Stimmengewirr)", "", "[SCHLUS", "[Stille] | [Musik]"]:
            self.assertTrue(L.is_noise_text(t), t)
        for t in ["Alexa?", "*hust* Hey, Wendelien.", "Wendelin [Musik]"]:
            self.assertFalse(L.is_noise_text(t), t)

    def test_ansage(self):
        self.assertEqual(L.announce_no(["Block 4", ""]), 4)
        self.assertEqual(L.announce_no(["", "block5, zwei Meter"]), 5)
        self.assertIsNone(L.announce_no(["Alexa", "Blockade"]))

    def test_merge_intervals(self):
        self.assertEqual(L.merge_intervals([(0, 1), (1.1, 2), (5, 6), (0.5, 0.7)]), [(0, 2), (5, 6)])

    def test_regionen_fehlende_ansage(self):
        ev = self._block(0) + [{"s": 120, "e": 122, "huawei": "Block 2", "handy2": ""}] + self._block(125, 50) \
            + [{"s": 400, "e": 402, "huawei": "Block 4", "handy2": ""}] + self._block(405)
        r = L.regions(ev)
        self.assertEqual([b for b, _ in r], [[1], [2, 3], [4]])
        self.assertEqual(len(r[1][1]), 50)

    def test_zuordnung_reihenfolge(self):
        rows = L.assign(self._block(0))
        self.assertEqual([r[2] for r in rows[:6]], ["Wendelin", "Hey Wendelin", "Alexa", "Hey Octavia", "Kobalos", "Wendelin"])
        self.assertEqual((rows[-1][0], rows[-1][1]), (1, 5))
        self.assertTrue(all(r[5] == "ok" for r in rows))
        self.assertEqual(sum(L.count_table(rows).values()), 25)

    def test_geraeusch_zaehlt_nicht(self):
        ev = self._block(0)
        ev.insert(7, {"s": 31.0, "e": 31.3, "huawei": "*hust*", "handy2": "[Musik]"})
        self.assertEqual(len(L.assign(ev)), 25)

    def test_falsche_zahl_bricht_ab(self):
        with self.assertRaises(SystemExit):
            L.assign(self._block(0, 24))
        with self.assertRaises(SystemExit):
            L.assign(self._block(0, 26))

    def test_manual_fehler_drop_split(self):
        ev = self._block(0, 24)          # ein zusammengezogenes Ereignis (zwei Woerter)
        ev.insert(4, {"s": 50.0, "e": 51.0, "huawei": "Wort", "handy2": "Wort"})       # Versprecher
        ev.insert(5, {"s": 51.5, "e": 52.0, "huawei": "Ach", "handy2": "Ach"})          # Zwischenruf
        ev[8] = dict(ev[8], e=ev[8]["s"] + 3.0)                                          # zwei Woerter in einem Ereignis
        man = [{"start": 50.0, "aktion": "fehler", "wert": "", "grund": "x"}, {"start": 51.5, "aktion": "drop", "wert": "", "grund": "y"},
               {"start": ev[8]["s"], "aktion": "split", "wert": "2", "grund": "z"}]
        rows = L.assign(ev, man)
        self.assertEqual([r[5] for r in rows].count("fehler"), 1)
        self.assertEqual([r[5] for r in rows].count("unsicher"), 2)
        self.assertEqual(len([r for r in rows if r[5] != "fehler"]), 25)
        with self.assertRaises(SystemExit):       # manual.csv nennt ein Ereignis, das es nicht gibt
            L.assign(ev, man + [dict(man[1], start=51.51)])

    def test_split_gleiche_teile(self):
        p = L.split_event({"s": 10.0, "e": 14.0}, 2)
        self.assertEqual([(x["s"], x["e"]) for x in p], [(10.0, 12.0), (12.0, 14.0)])
        self.assertTrue(all(x["status"] == "unsicher" for x in p))

    def test_negativ_klassen(self):
        self.assertIn("wendelin", L.neg_classes("das ist Wendelin"))
        self.assertIn("alexa", L.neg_classes("Alexa, mach Licht an"))
        self.assertIn("kobalos", L.neg_classes("Kobalos"))
        self.assertEqual(L.neg_classes("Wendel in der Kueche"), ["verwechsler"])
        self.assertEqual(L.neg_classes("heute ist das Wetter schoen"), [])


class Sweep(unittest.TestCase):
    """WP121: Schwellen-Sweep und Kalibrierung auf gleiche FA/h (words_measure.py)."""
    T = [0.0, 0.1, 0.2, 2.0, 2.1, 5.0, 8.0]
    V = [0.9, 0.5, 0.2, 0.7, 0.95, 0.4, 0.6]

    def test_ereignisse_und_totzeit(self):
        self.assertEqual(W.score_events(self.T, self.V, 0.4), [0.0, 2.0, 5.0, 8.0])     # 0,1 s nach 0,0 und 2,1 s nach 2,0: Totzeit 1,5 s
        self.assertEqual(W.score_events(self.T, self.V, 0.95), [2.1])

    def test_totzeit_grenze(self):
        self.assertEqual(W.score_events([0.0, 1.5], [1.0, 1.0], 0.5), [0.0, 1.5])      # genau 1,5 s Abstand: zwei Ereignisse
        self.assertEqual(W.score_events([0.0, 1.4], [1.0, 1.0], 0.5), [0.0])

    def test_schwelle_gleich_zaehlt(self):
        self.assertEqual(W.score_events([0.0], [0.5], 0.5), [0.0])
        self.assertEqual(W.score_events([0.0], [0.4999], 0.5), [])

    def test_sweep_monoton(self):
        n = [len(W.score_events(self.T, self.V, t)) for t in (0.1, 0.3, 0.5, 0.7, 0.9, 0.99)]
        self.assertEqual(n, sorted(n, reverse=True))
        self.assertEqual(n[-1], 0)

    def test_merge_times(self):
        self.assertEqual(W.merge_times([3.2, 0.0, 1.0, 1.6]), [0.0, 1.6, 3.2])

    def test_fa_grenze(self):
        self.assertEqual(W.fa_limit(1, 0.62), 0)          # 0,62 h bei 1 FA/h: kein Ereignis erlaubt
        self.assertEqual(W.fa_limit(2, 0.62), 1)
        self.assertEqual(W.fa_limit(2, 1.0), 2)           # Rate genau am Ziel zaehlt noch dazu

    def test_kalibrierung_waehlt_besten_treffer_unter_grenze(self):
        pts = [{"hit": 10, "fa": 0, "n": "a"}, {"hit": 25, "fa": 1, "n": "b"}, {"hit": 28, "fa": 4, "n": "c"}, {"hit": 25, "fa": 0, "n": "d"}]
        self.assertEqual(W.pick_op(pts, 1.0, 1)["n"], "d")        # b und d gleich, d hat weniger FA
        self.assertEqual(W.pick_op(pts, 1.0, 4)["n"], "c")
        self.assertEqual(W.pick_op(pts, 0.5, 1)["n"], "d")       # 0,5 h x 1 = 0 Ereignisse erlaubt
        self.assertIsNone(W.pick_op([{"hit": 5, "fa": 3}], 1.0, 2))

    def test_pareto(self):
        pts = [{"fa": 0, "hit": 3}, {"fa": 1, "hit": 2}, {"fa": 2, "hit": 9}, {"fa": 3, "hit": 9}]
        self.assertEqual([(p["fa"], p["hit"]) for p in W.pareto(pts)], [(0, 3), (2, 9)])


class WordsRules(unittest.TestCase):
    def test_label_fenster(self):
        self.assertEqual(W.label_window(10.0, 11.0, "ok"), (9.7, 12.2))
        lo, hi = W.label_window(10.0, 11.0, "unsicher")
        self.assertLess(lo, 9.7); self.assertGreater(hi, 12.2)

    def test_labels_ohne_versprecher(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False) as f:
            f.write("geraet,block,runde,wort,start,ende,status,bemerkung\n"
                    "huawei,2,2,Alexa,165.5,166.0,fehler,Versprecher\nhuawei,2,2,Alexa,170.0,170.7,ok,\nhuawei,1,1,Wendelin,0,4,unsicher,x\n")
        rows = W.read_labels(f.name); os.unlink(f.name)
        self.assertEqual([(r["word"], r["start"]) for r in rows], [("Alexa", 170.0), ("Wendelin", 0.0)])

    def test_alexa(self):
        for t in ["Alexa", "Alexa, wie spät ist es", "Aleksa", "alex a"]:
            self.assertTrue(W.matches_alexa(t), t)
        for t in ["Alexis", "Alex", "Alexander", ""]:
            self.assertFalse(W.matches_alexa(t), t)

    def test_octavia(self):
        for t in ["Hey Octavia", "hey Oktavia, hallo", "Heyoctavia"]:
            self.assertTrue(W.matches_hey_octavia(t), t)
        for t in ["Octavia", "Hey Olivia", "Hey Oktave", "Hey Octavian"]:
            self.assertFalse(W.matches_hey_octavia(t), t)

    def test_kobalos(self):
        for t in ["Kobalos", "Cobalos, stell bit in", "kobalus", "ko balos"]:
            self.assertTrue(W.matches_kobalos(t), t)
        for t in ["Carlos", "Kobold", "Cobalt", "Carbonos, why", "Copolos"]:
            self.assertFalse(W.matches_kobalos(t), t)


if __name__ == "__main__":
    unittest.main()
