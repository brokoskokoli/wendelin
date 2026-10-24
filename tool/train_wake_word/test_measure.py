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

class FakeSpotter:
    """Liefert je decode-Schritt ein vorgegebenes Ergebnis (Label oder "") ohne sherpa."""

    def __init__(self, labels): self.labels, self.i, self.cur, self.resets = list(labels), 0, "", 0
    def create_stream(self, line): return self
    def accept_waveform(self, sr, x): self.pending = True
    def is_ready(self, s):
        r = self.pending; self.pending = False; return r
    def decode_stream(self, s): self.cur = self.labels[self.i] if self.i < len(self.labels) else ""; self.i += 1
    def get_result(self, s): return self.cur
    def reset_stream(self, s): self.resets += 1


class OwnHits(unittest.TestCase):
    def test_nur_eigenes_label(self):
        import numpy as np
        sp = FakeSpotter(["", "X", "", "HEY_OCTAVIA", "X"])
        hits = W.own_hits(sp, np.zeros(5 * 1600, "float32"), "x", "HEY_OCTAVIA", tail=0.0)
        self.assertEqual(hits, [0.4])                      # X (Platzhalter) zaehlt nicht, fremdes Label auch nicht
        self.assertEqual(sp.resets, 3)                     # der Stream wird nach jedem Ergebnis zurueckgesetzt

    def test_kein_treffer_ohne_label(self):
        import numpy as np
        sp = FakeSpotter(["X", "X", "X"])
        self.assertEqual(W.own_hits(sp, np.zeros(3 * 1600, "float32"), "x", "WENDELIN", tail=0.0), [])

    def test_platzhalter_ist_kein_wort(self):
        for bpe in (False, True):
            self.assertTrue(W.DUMMY_KW[bpe].endswith("@" + W.DUMMY_LABEL + "\n"))
        self.assertNotIn(W.DUMMY_LABEL, [W.key(w).upper() for w in W.WORDS])


class Varianten(unittest.TestCase):
    def test_anzahl_und_gleichbehandlung(self):
        n = {w: len(W.SPEC[w]["ph"]) for w in W.WORDS}
        self.assertEqual(n, {"Wendelin": 6, "Hey Wendelin": 6, "Alexa": 4, "Hey Octavia": 8, "Kobalos": 8})
        for w in W.WORDS: self.assertEqual(len(set(W.SPEC[w]["ph"])), n[w], w)            # keine Duplikate

    def test_hey_ist_vorspann(self):
        self.assertEqual(W.SPEC["Hey Wendelin"]["ph"], ["HH EY1 " + p for p in W.SPEC["Wendelin"]["ph"]])

    def test_octavia_deutsch_und_englisch(self):
        ph = W.SPEC["Hey Octavia"]["ph"]
        self.assertIn("HH EY1 AA0 K T EY1 V IY0 AH0", ph)          # englisch
        self.assertIn("HH EY1 AO0 K T AA1 V IY0 AA0", ph)          # deutsch: offenes O, Ok-TAH-via

    def test_phoneme_im_modell(self):
        import glob
        f = glob.glob(os.path.expanduser("~/wendelin-models/kws/x-*zh-en*/*/tokens.txt"))
        if not f: self.skipTest("Modell nicht vorhanden")
        tok = {l.split()[0] for l in open(f[0])}
        for w in W.WORDS:
            for p in W.SPEC[w]["ph"]: self.assertLessEqual(set(p.split()), tok, p)


class Kreuz(unittest.TestCase):
    @staticmethod
    def pt(name, blocks, fa, ordv=0):
        """blocks: Treffer je Block 1..6 (n = 5 je Block)."""
        d = {"prog": "M", "thr": name, "stage2": "-", "fa": fa, "hours": 1.0, "ord": ordv, "hit": sum(blocks)}
        for b, h in enumerate(blocks, 1): d[f"hit_b{b}"], d[f"n_b{b}"] = h, 5
        return d

    def test_auswahl_und_zaehlung_getrennt(self):
        a = self.pt("a", [5, 5, 5, 0, 0, 0], 0)          # nur auf Block 1-3 gut
        b = self.pt("b", [2, 2, 2, 3, 3, 3], 0)
        hit, n, cfgs = W.cv_pick([a, b], 1.0, 1)
        # Fold 1: Auswahl 1-3 -> a (15 > 6), Test 4-6: 0. Fold 2: Auswahl 4-6 -> b (9 > 0), Test 1-3: 6. In-sample waehlt a mit 15.
        self.assertEqual((hit, n), (6, 30))
        self.assertEqual(cfgs, ["Ma+-", "Mb+-"])

    def test_fa_grenze_je_fold(self):
        a = self.pt("a", [5, 5, 5, 5, 5, 5], 3)          # zu viele FA
        b = self.pt("b", [1, 0, 0, 0, 0, 1], 0)
        hit, n, cfgs = W.cv_pick([a, b], 1.0, 1)
        self.assertEqual((hit, n), (2, 30))
        hit, n, cfgs = W.cv_pick([a], 1.0, 1)
        self.assertEqual((hit, cfgs), (None, None))

    def test_leerer_test_fold_bricht_ab(self):
        """Test-Fold ohne Aufnahmen (n=0) darf nicht still 0/0 zaehlen (Review: 3/15 statt 15/15)."""
        a = self.pt("a", [5, 5, 5, 5, 5, 5], 0)
        for b in (1, 2, 3): a[f"n_b{b}"] = 0
        with self.assertRaises(ValueError): W.cv_pick([a], 1.0, 1)

    def test_gleichstand_frueherer_eintrag(self):
        a = self.pt("a", [1, 1, 1, 1, 1, 1], 0); b = self.pt("b", [1, 1, 1, 1, 1, 1], 0)
        self.assertEqual(W.cv_pick([a, b], 1.0, 1)[2], ["Ma+-", "Ma+-"])


class RowsFor(unittest.TestCase):
    """Kernzaehlung rows_for / calib_point (Treffer je Label, Fenster, eigenes Wort, Kalibrierungsquelle)."""
    FA = {"neg_huawei": 1, "neg_handy2": 2, "syn": 3, "fleurs": 4}
    HR = {"neg_huawei": 0.5, "neg_handy2": 0.5, "syn": 2.0, "fleurs": 1.0}

    @staticmethod
    def lb(dev, word, start, end, status="ok", block=1):
        return {"dev": dev, "word": word, "start": start, "end": end, "status": status, "block": block}

    def rows(self, w, labels, huawei, handy2=(), passes=None):
        ev = {"pos_huawei": {"pos_huawei": list(huawei)}, "pos_handy2": {"pos_handy2": list(handy2)},
              "neg_huawei": {"f": [1.0, 2.0]}, "neg_handy2": {}}
        passes = passes or (lambda s, i, t: True)
        return {r["dev"]: r for r in W.rows_for(w, "M", 0.5, "-", ev, passes, self.FA, self.HR, labels)}

    def test_fenster_hat_ober_und_untergrenze(self):
        labels = [self.lb("huawei", "Wendelin", 10.0, 11.0, block=1),     # Fenster 9.7 .. 12.2
                  self.lb("huawei", "Wendelin", 20.0, 21.0, block=2),
                  self.lb("huawei", "Wendelin", 30.0, 31.0, block=3),
                  self.lb("huawei", "Wendelin", 40.0, 41.0, block=4)]
        r = self.rows("Wendelin", labels, [11.0, 20.0 - 0.5, 31.0 + 2.0, 40.0])["huawei"]
        self.assertEqual((r["n"], r["hit"]), (4, 2))                      # zu frueh (19.5) und zu spaet (33.0) zaehlen nicht
        self.assertEqual([r[f"hit_b{b}"] for b in (1, 2, 3, 4)], [1, 0, 0, 1])

    def test_nur_eigenes_wort_und_verwechsler(self):
        labels = [self.lb("huawei", "Wendelin", 10.0, 11.0), self.lb("huawei", "Alexa", 20.0, 21.0)]
        r = self.rows("Wendelin", labels, [20.5])["huawei"]
        self.assertEqual((r["n"], r["hit"], r["n_ok"], r["hit_ok"]), (1, 0, 1, 0))       # Treffer im Alexa-Fenster ist kein Wendelin-Treffer
        self.assertEqual(r["x_alexa"], 1)                                                 # sondern ein Verwechsler
        self.assertEqual(r["x_hey_wendelin"], 0)
        self.assertNotIn("x_wendelin", r)

    def test_stufe2_filter_und_geraet(self):
        labels = [self.lb("huawei", "Wendelin", 10.0, 11.0), self.lb("handy2", "Wendelin", 10.0, 11.0, "unsicher")]
        rows = self.rows("Wendelin", labels, [10.5], [], passes=lambda s, i, t: False)
        self.assertEqual((rows["huawei"]["hit"], rows["handy2"]["hit"]), (0, 0))
        rows = self.rows("Wendelin", labels, [10.5], [])
        self.assertEqual((rows["huawei"]["hit"], rows["handy2"]["hit"]), (1, 0))           # handy2 hat keine eigene Detektion
        self.assertEqual((rows["handy2"]["n"], rows["handy2"]["n_ok"]), (1, 0))
        self.assertEqual((rows["huawei"]["fa_real"], rows["handy2"]["fa_real"], rows["huawei"]["cand_real"]), (1, 2, 2))

    def test_calib_point_quellen(self):
        r = self.rows("Wendelin", [], [])["huawei"]
        s, e = W.calib_point(r, "syn"), W.calib_point(r, "real")
        self.assertEqual((s["fa"], s["hours"]), (7, 3.0))                  # synthetisch + FLEURS
        self.assertEqual((e["fa"], e["hours"]), (1, 0.5))                  # nur die echte Negativ-Aufnahme des Geraets


class KwsRun(unittest.TestCase):
    def test_platzhalter_zaehlt_nicht(self):
        import numpy as np
        sp = FakeSpotter(["", "X", "", "WENDELIN", "X"])
        hits, _ = K.run(sp, np.zeros(5 * 1600, "float32"), "x", tail=0.0)
        self.assertEqual(hits, [0.4])                      # Platzhalter X ist kein Treffer
        self.assertEqual(sp.resets, 3)                     # er setzt den Stream trotzdem zurueck

    def test_platzhalterdatei_je_inhalt_und_prozess(self):
        a, b = K.dummy_path("/m", "A @X\n"), K.dummy_path("/m", "B @X\n")
        self.assertNotEqual(a, b)
        self.assertEqual(a, K.dummy_path("/m", "A @X\n"))
        self.assertIn(str(os.getpid()), a)
        self.assertNotEqual(os.path.basename(a), "_dummy_keywords.txt")


if __name__ == "__main__":
    unittest.main()
