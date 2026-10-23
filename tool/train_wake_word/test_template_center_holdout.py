"""Selbsttest (stdlib unittest, erfundene Daten, ohne Modelle) fuer template_center_holdout.py (WP134 Nachbesserung).
Lauf: ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_template_center_holdout.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import template_center_holdout as H  # noqa: E402


class Calibrate(unittest.TestCase):
    def test_negative_bestimmen_die_schwelle(self):
        thr, rec, fa = H.calibrate([0.6, 0.7, 0.8, 0.9], [0.35, 0.55], hours=0.5)   # erlaubt 0: ueber dem hoechsten Ereignis
        self.assertAlmostEqual(thr, 0.55, places=3)
        self.assertEqual(rec, 1.0)
        self.assertEqual(fa, 0.0)

    def test_ohne_ereignisse_quantil_der_positiven(self):
        thr, _, _ = H.calibrate([0.9, 0.5, 0.6, 0.7, 0.8], [], hours=0.03)
        self.assertEqual(thr, 0.5)                                   # floor(4 * 0.1) = 0 -> niedrigster Wert

    def test_untergrenze_und_deckel(self):
        self.assertEqual(H.calibrate([0.1, 0.2], [], 1.0)[0], H.MIN_THR)
        self.assertEqual(H.calibrate([0.95, 0.99], [0.97], 0.5)[0], H.MAX_THR)

    def test_slots(self):
        t, v = [0.5, 1.0, 1.6, 2.0], [0.2, 0.6, 0.4, 0.31]           # Slot 0: 0..1,5 s, Slot 1: ab 1,5 s
        self.assertEqual(sorted(H.slot_events(t, v)), [0.4, 0.6])    # Spitze je Slot; 0,2 allein faellt unter den Boden


if __name__ == "__main__":
    unittest.main()
