"""Selbsttest fuer verifier_export.py (WP137: Export Pruefer B fuer den Dart-Nachbau). Prueft die eingecheckten Testdaten.
Lauf:  ~/wendelin-models/kws/wp58/venv/bin/python -B -I -m unittest discover -s tool/train_wake_word -p 'test_verifier_export.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import json, os, re, sys, tempfile, unittest
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np  # noqa: E402
import verifier_data as D  # noqa: E402
import real_split as R  # noqa: E402
import common as CM  # noqa: E402
import verifier_eval as E  # noqa: E402
import verifier_export as X  # noqa: E402

DATA = os.path.join(HERE, "testdata")
MU_PATH, PAR_PATH = os.path.join(DATA, "wake_verifier_b_mu.json"), os.path.join(DATA, "verifier_b_parity.json")
MU_KEYS = {"name", "feature_version", "dims", "source", "cut", "mu"}


def load(p):
    with open(p) as f: return json.load(f)


class Export(unittest.TestCase):
    def test_paritaet_neu_gerechnet_gleich_datei(self):
        par, mu = load(PAR_PATH), np.array(load(MU_PATH)["mu"], "float32")
        self.assertTrue(par["synthetic"])
        n = 0
        for c in par["cases"]:
            q = np.array(c["queries"], "float32")
            for h, tl in c["templates"].items():
                t = E.prep_templates([np.array(x, "float32") for x in tl], mu)
                got = E.b_score(q, t, mu, topk=par["topk"])
                np.testing.assert_allclose(got, c["expected"][h], atol=2e-6)
                n += 1
        self.assertGreaterEqual(n, 5)

    def test_paritaet_reproduzierbar_aus_seed(self):
        par, mu = load(PAR_PATH), np.array(load(MU_PATH)["mu"], "float32")
        meta = {"topk": par["topk"], "thresholds": {"B": par["thresholds_trainingsseite"]}}
        self.assertEqual(json.loads(json.dumps(X.parity(mu, meta, par["seed"]))), par)

    def test_paritaet_deckt_faelle_ab(self):
        par = load(PAR_PATH)
        f25 = par["cases"][0]
        self.assertEqual({len(q) for q in f25["queries"]}, {25}); self.assertEqual(len(f25["queries"]), 4)
        for h in ("W", "HW"): self.assertEqual(sorted(len(t) for t in f25["templates"][h]), sorted(set(len(t) for t in f25["templates"][h])))
        self.assertGreater(max(f25["expected"]["W"]), 0.3); self.assertGreater(max(f25["expected"]["HW"]), 0.3)     # Treffer erkennbar
        self.assertEqual(par["cases"][-1]["expected"]["W"], [-1.0, -1.0])                                          # keine brauchbare Vorlage
        self.assertLess(os.path.getsize(PAR_PATH), 300_000)

    def test_top3_aus_mehr_als_3_vorlagen(self):
        """Fall mit 6 (W) und 5 (HW) Vorlagen: Kopfwert = Mittel der 3 besten Vorlagenwerte, deutlich verschieden von den schlechtesten 3 und vom Mittel aller."""
        par, mu = load(PAR_PATH), np.array(load(MU_PATH)["mu"], "float32")
        c = {c["name"]: c for c in par["cases"]}["top3_aus_6_vorlagen"]
        q = np.array(c["queries"], "float32")
        self.assertEqual((len(c["templates"]["W"]), len(c["templates"]["HW"])), (6, 5))
        for h, tl in c["templates"].items():
            tm = E.prep_templates([np.array(x, "float32") for x in tl], mu)
            per = np.array([float(E.b_score(q[:1], [t], mu, topk=1)[0]) for t in tm])          # Wert je Vorlage (Anfrage 0)
            srt = np.sort(per)[::-1]
            self.assertGreater(srt[2] - srt[3], 0.02); self.assertGreater(srt[0] - srt[5 if h == "W" else 4], 0.3)   # klar verschieden, Rang 3/4 trennt
            self.assertAlmostEqual(c["expected"][h][0], float(srt[:3].mean()), delta=2e-6)
            self.assertGreater(c["expected"][h][0] - float(srt[-3:].mean()), 0.1); self.assertGreater(c["expected"][h][0] - float(per.mean()), 0.02)

    def test_mu_json(self):
        j = load(MU_PATH)
        self.assertEqual(len(j["mu"]), 96); self.assertEqual(j["dims"], 96)
        self.assertEqual(j["feature_version"], "oww-0.5.1-mel-emb-1")
        self.assertTrue(np.isfinite(np.array(j["mu"])).all()); self.assertGreater(float(np.abs(j["mu"]).max()), 1.0)
        self.assertEqual((j["cut"]["pre_s"], j["cut"]["tail_s"], j["cut"]["norm_peak"]), (1.9, 0.85, 0.5))
        self.assertTrue(j["source"])

    def test_nur_neutrale_texte_in_den_ausgaben(self):
        """Allowlist statt Sperrliste: mu-JSON hat genau die erwarteten Felder und als Herkunft den festen neutralen Text aus verifier_export;
        die Paritaetsdatei enthaelt nur Texte, die woertlich in verifier_export.py stehen (keine von aussen eingelesenen Texte)."""
        mu = load(MU_PATH)
        self.assertEqual(set(mu), MU_KEYS)
        self.assertEqual(mu["source"], X.SOURCE)
        def strings(o):
            if isinstance(o, dict): return [s for v in o.values() for s in strings(v)]
            if isinstance(o, list): return [s for v in o for s in strings(v)]
            return [o] if isinstance(o, str) else []
        src = open(os.path.join(HERE, "verifier_export.py"), encoding="utf-8").read()
        free = {t for t in strings(load(PAR_PATH)) if t not in src and not re.fullmatch(r"f\d+", t)}
        self.assertEqual(free, set(), "freie Texte in der Paritaetsdatei")

    def test_export_schreibt_beide_dateien_und_lehnt_falsches_mu_ab(self):
        with tempfile.TemporaryDirectory() as d:
            m = os.path.join(d, "m", "t"); os.makedirs(m)
            meta = {"pre": 1.9, "tail": 0.85, "topk": 3, "thresholds": {"B": {"W": 0.6, "HW": 0.7}}}
            json.dump(meta, open(os.path.join(m, "verifier.json"), "w"))
            np.savez(os.path.join(m, "b_templates.npz"), mu=np.arange(96, dtype="float32"), t0=np.ones((3, 96), "float32"))
            X.export(os.path.join(d, "m"), "t", os.path.join(d, "o"), oww=None)
            self.assertEqual(sorted(os.listdir(os.path.join(d, "o"))), ["verifier_b_parity.json", "wake_verifier_b_mu.json"])
            self.assertNotIn("t0", open(os.path.join(d, "o", "wake_verifier_b_mu.json")).read())
            with self.assertRaises(SystemExit): X.mu_json(np.zeros(95), meta)


OWW = os.path.expanduser("~/wendelin-models/kws/wp130/dl/oww")


class PcmZuschnitt(unittest.TestCase):
    def setUp(self): self.pcm = load(PAR_PATH)["pcm"]

    def test_pcm_neu_gerechnet_gleich_datei(self):
        self.assertEqual(json.loads(json.dumps(X.pcm_cases())), self.pcm)

    def test_live_grenzen_gleich_echtem_segment(self):
        for c in self.pcm["live"]:
            x = X.live_signal(c["signal"]["len"])
            seg = D.segment(x, c["decision_end_sample"] / X.SR)           # echter Code
            mine = np.zeros(c["seg_len"], "float32")
            mine[c["zeros_front"]:c["zeros_front"] + c["copy_hi"] - c["copy_lo"]] = x[c["copy_lo"]:c["copy_hi"]]
            np.testing.assert_array_equal(seg, mine)
            self.assertEqual(c["seg_len"], 44000); self.assertEqual(c["peak_out"], 0.5)

    def test_live_rundung_halbe_zur_geraden(self):
        c = {c["name"]: c for c in self.pcm["live"]}
        self.assertEqual(c["halbe_abgerundet"]["e"], 80000)       # 500,5 -> 500 (nicht 501 wie Dart round())
        self.assertEqual(c["halbe_aufgerundet"]["e"], 80320)      # 501,5 -> 502
        self.assertEqual(c["rand_anfang"]["zeros_front"], 10400); self.assertEqual(c["rand_ende"]["zeros_back"], 11680)

    def test_template_gleich_real_split(self):
        for c in self.pcm["template"]:
            x = X.template_signal(c["signal"]["len"], c["start_s"], c["end_s"], c["signal"]["bg"])
            a, b = max(0, int((c["start_s"] - R.PRE) * X.SR)), min(len(x), int((c["end_s"] + R.POST) * X.SR))
            self.assertEqual((a, b), (c["label_a"], c["label_b"]))
            t = R.trim(x[a:b])
            self.assertEqual(len(t), c["clip_len"]); np.testing.assert_array_equal(t, x[c["clip_a"]:c["clip_b"]])
        n = {c["name"]: c for c in self.pcm["template"]}
        self.assertEqual(n["rundung_start"]["label_a"], 16159)    # Gleitkomma: (1,13 - 0,12)*16000 = 16159,999..., abgeschnitten
        self.assertEqual(n["rundung_ende"]["label_b"], 21279)
        self.assertGreater(n["normal"]["trim_lo"], 0); self.assertEqual(n["trim_greift_nicht"]["trim_lo"], 0)
        self.assertIsNone(n["zu_kurz"]["m"]); self.assertEqual(n["normal"]["peak_out"], 0.5)

    def test_annahme_durch_cut_clips_getrennt_von_vorlage(self):
        n = {c["name"]: c for c in self.pcm["template"]}
        self.assertNotIn("accepted", n["normal"])
        z = n["zu_kurz"]; self.assertEqual(z["clip_len"], 4800)
        self.assertTrue(z["accepted_by_cut_clips"]); self.assertFalse(z["usable_as_template"])                 # cut_clips nimmt, Vorlage nicht
        for name, ln, m, ok in (("grenze_13919", 13919, 1, False), ("grenze_13920", 13920, 2, True)):
            c = n[name]
            self.assertEqual((c["clip_len"], c["m"], c["usable_as_template"], c["accepted_by_cut_clips"]), (ln, m, ok, True))
        self.assertTrue(n["normal"]["usable_as_template"]); self.assertTrue(all(c["accepted_by_cut_clips"] for c in n.values()))
        self.assertEqual(X.MAX_TEMPLATE_SAMPLES, 35200)
        self.assertTrue(all(c["clip_len"] <= X.MAX_TEMPLATE_SAMPLES for c in n.values()))

    def test_frames_formel(self):
        for r in self.pcm["oww_frames_checked"]: self.assertEqual(X.oww_frames(r["samples"]), r["F"])
        self.assertEqual(X.oww_frames(44000), 25); self.assertIsNone(X.oww_frames(12000))

    @unittest.skipUnless(os.path.isfile(os.path.join(OWW, "embedding_model.onnx")), "lokale oww-Modelle fehlen")
    def test_frames_gegen_echtes_oww(self):
        af = CM.make_features(OWW)
        for n in (16000, 24000, 44000, 44160, 19040, 18880):
            e = CM.embed(af, [np.random.default_rng(0).standard_normal(n).astype("float32") * 0.1])[0]
            self.assertEqual(len(e), X.oww_frames(n), n)


CHAIN_PATH = os.path.join(DATA, "verifier_b_chain_parity.json")
HAVE_OWW = os.path.isfile(os.path.join(OWW, "embedding_model.onnx"))


class Kettenfall(unittest.TestCase):
    def setUp(self): self.j, self.mu = load(CHAIN_PATH), np.array(load(MU_PATH)["mu"], "float32")

    def test_laengen_und_formel(self):
        j = self.j
        self.assertLess(os.path.getsize(CHAIN_PATH), 300_000)
        self.assertEqual(j["live"]["segment_len"], 44000); self.assertEqual(j["live"]["frames_F"], X.oww_frames(44000))
        self.assertEqual(len(j["live"]["embeddings"]), 25); self.assertEqual({len(v) for v in j["live"]["embeddings"]}, {96})
        enroll = X.chain_enroll_signal()
        for t, (s, e, _) in zip(j["templates"], X.CHAIN_WORDS):
            c = R.cut_clips([{"geraet": R.TRAIN_DEVICE, "block": "1", "runde": "1", "wort": "Wendelin", "status": "ok", "start": str(s), "ende": str(e)}], enroll)[0][1]
            self.assertEqual(len(c), t["clip_len"]); self.assertEqual(t["frames_m"], X.oww_frames(len(c))); self.assertGreaterEqual(t["frames_m"], 2)
            self.assertEqual(len(t["embeddings"]), t["frames_m"])

    def test_kopfwerte_aus_gespeicherten_embeddings(self):
        j = self.j
        q = np.array(j["live"]["embeddings"], "float32"); tm = [np.array(t["embeddings"], "float32") for t in j["templates"]]
        for h, v in j["heads"].items():
            got = X.chain_scores(q, [tm[i] for i in v["templates"]], self.mu, j["topk"])
            np.testing.assert_allclose(got["template_scores"], v["template_scores"], atol=2e-6)
            self.assertAlmostEqual(got["head_score"], v["head_score"], delta=2e-6)
        self.assertLess(j["heads"]["W"]["template_scores"][1], 0.9)       # nicht alle Vorlagen gleich gut: Fehler im Pfad faellt auf

    def test_kettenfall_hat_mehr_als_3_vorlagen_und_top3(self):
        w = self.j["heads"]["W"]; sc = w["template_scores"]
        self.assertGreaterEqual(len(sc), 5); self.assertEqual(len(w["templates"]), len(sc))
        top = sorted(sc)[::-1]
        self.assertAlmostEqual(w["head_score"], sum(top[:3]) / 3, delta=2e-6)
        self.assertGreater(w["head_score"] - sum(top[-3:]) / 3, 0.05); self.assertGreater(top[2] - top[3], 0.01)

    @unittest.skipUnless(HAVE_OWW, "lokale oww-Modelle fehlen")
    def test_datei_reproduziert_mit_echtem_oww(self):
        meta = {"topk": self.j["topk"]}
        new = json.loads(json.dumps(X.chain_parity(self.mu, meta, OWW)))
        np.testing.assert_allclose(new["live"]["embeddings"], self.j["live"]["embeddings"], atol=self.j["tolerance"]["embeddings"])
        for a, b in zip(new["templates"], self.j["templates"]):
            self.assertEqual((a["clip_len"], a["frames_m"]), (b["clip_len"], b["frames_m"]))
            np.testing.assert_allclose(a["embeddings"], b["embeddings"], atol=self.j["tolerance"]["embeddings"])
        self.assertEqual(new, self.j)


if __name__ == "__main__":
    unittest.main()
