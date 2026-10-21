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


if __name__ == "__main__":
    unittest.main()
