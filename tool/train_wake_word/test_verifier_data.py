"""Selbsttest (stdlib unittest, erfundene Mini-Daten, ohne Modelle) fuer verifier_data.py (WP137 Teil 2: Pruefer-Daten, Leckpruefung).
Lauf:  ~/wendelin-models/kws/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_verifier_data.py'
Hinweis: Das Gate fuehrt keine Python-Tests aus."""
import argparse, json, os, sys, tempfile, unittest
from unittest import mock
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.dirname(HERE))
import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402
import verifier_data as D  # noqa: E402
import gen_samples as G  # noqa: E402

SR = D.SR
_ALLOWED_DIR = tempfile.TemporaryDirectory()                                   # lokale Liste erlaubter Stimmen (erfundene Namen)
_ALLOWED = os.path.join(_ALLOWED_DIR.name, "voices.allowed")
with open(_ALLOWED, "w") as _fh: _fh.write("v-a\nv-b\nv-c\n")
os.environ[D.VOICES_ALLOWED_ENV] = _ALLOWED


def wr(f, b):
    with open(f, "wb") as fh: fh.write(b)


def jd(o, f):
    with open(f, "w") as fh: json.dump(o, fh)


def wav(path, n=1600, v=0.1, seed=0):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sf.write(path, (np.random.default_rng(seed).standard_normal(n) * v).astype("float32"), SR, subtype="PCM_16")


class Texte(unittest.TestCase):
    def test_split_fest_disjunkt_und_beide_nicht_leer(self):
        tr, te = D.conf_pool("train"), D.conf_pool("test")
        self.assertTrue(len(tr) > 20 and len(te) > 10)
        self.assertFalse({D.norm_text(t) for t in tr} & {D.norm_text(t) for t in te})
        self.assertGreater(len(tr), len(te))

    def test_normalisierung_gleicher_split(self):
        self.assertEqual(D.text_split("Wendel."), D.text_split("  wendel "))
        self.assertEqual(D.text_split("Hey, Wendel!"), D.text_split("hey wendel"))

    def test_ziehen_nur_trainings_texte(self):
        rng = np.random.default_rng(1)
        for _ in range(300):
            t, cut = D.draw_conf(rng, "train")
            self.assertEqual(D.text_split(D.base_text(t, cut)), "train", t)

    def test_basistext_nur_bei_abgeschnittenen(self):
        self.assertEqual(D.base_text("Wendel, mach das Licht an", True), "Wendel")
        self.assertEqual(D.base_text("hey, wenn der Wind", False), "hey, wenn der Wind")

    def test_conf_say_info_split_aus_basistext(self):
        import v8_measure as V
        info = D.conf_say_info(40, 5)
        self.assertEqual(len(info), 40)
        for i, (text, cut, _, _) in enumerate(V.conf_plan(40, 5)):
            b, sp = info[f"conf5_{i:04d}.wav"]
            self.assertEqual((b, sp), (D.base_text(text, cut), D.text_split(D.base_text(text, cut))))
        self.assertEqual({sp for _, sp in info.values()}, {"train", "test"})


class Leck(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.t = self.tmp.name
    def tearDown(self): self.tmp.cleanup()

    def roots(self, p, ext=False): return {"x": (p, ext)}

    def test_verbotene_wurzel_bricht_ab(self):
        for bad in ("wp130/gen/pos_v8", "wp58/gen/neg", "nok/gen", "handy2/clips", "raw-neg/a", "conf_say", "fleurs/test", "mls_de_test/ex"):
            p = os.path.join(self.t, bad); os.makedirs(p)
            with self.assertRaises(D.LeakError, msg=bad): D.check_roots(self.roots(p))

    def test_fehlende_wurzel_bricht_ab(self):
        with self.assertRaises(D.LeakError): D.check_roots(self.roots(os.path.join(self.t, "nein")))

    def test_link_auf_verbotenes_bricht_ab(self):
        bad = os.path.join(self.t, "wp130", "gen", "pos_v8"); os.makedirs(bad)
        link = os.path.join(self.t, "clean_pos"); os.symlink(bad, link)
        with self.assertRaises(D.LeakError): D.check_roots(self.roots(link))

    def test_fleurs_extern_nur_train_dev(self):
        ok = os.path.join(self.t, "wp58", "gen", "real", "train"); os.makedirs(ok)
        D.check_roots(self.roots(ok, True))                       # FLEURS train per Link ausserhalb: erlaubt
        for bad in ("test", "dev2"):
            p = os.path.join(self.t, "wp58", "gen", "real", bad); os.makedirs(p)
            with self.assertRaises(D.LeakError): D.check_roots(self.roots(p, True))
        p = os.path.join(self.t, "wp58", "gen", "neg", "train"); os.makedirs(p)
        with self.assertRaises(D.LeakError): D.check_roots(self.roots(p, True))       # nicht unter real/

    def test_trainingsdatei_ausserhalb_oder_verboten(self):
        root = os.path.join(self.t, "ok"); wav(os.path.join(root, "a.wav"))
        r = self.roots(root)
        D.assert_train_files([os.path.join(root, "a.wav")], r)
        wav(os.path.join(self.t, "andere", "b.wav"))
        with self.assertRaises(D.LeakError): D.assert_train_files([os.path.join(self.t, "andere", "b.wav")], r)
        wav(os.path.join(root, "neg_huawei_1.wav"))
        with self.assertRaises(D.LeakError): D.assert_train_files([os.path.join(root, "neg_huawei_1.wav")], r)

    def test_conf_ohne_text_oder_mit_pruef_text(self):
        d = os.path.join(self.t, "conf"); wav(os.path.join(d, "conf01_00000.wav"))
        with self.assertRaises(D.LeakError): D.assert_conf_texts(d)                      # kein Sidecar
        import json
        te = D.conf_pool("test")[0]
        jd({"conf01_00000.wav": dict(text=te, cut=False, split="train")}, os.path.join(d, "texts-s1.json"))
        with self.assertRaises(D.LeakError): D.assert_conf_texts(d)                      # Sidecar luegt („train“), Neuberechnung findet Test-Text
        tr = D.conf_pool("train")[0]
        jd({"conf01_00000.wav": dict(text=tr, cut=False)}, os.path.join(d, "texts-s1.json"))
        D.assert_conf_texts(d)
        wav(os.path.join(d, "conf01_00001.wav"))
        with self.assertRaises(D.LeakError): D.assert_conf_texts(d)                      # zweiter Clip ohne Eintrag

    def test_abgeschnittene_variante_prueft_das_wort(self):
        import json
        d = os.path.join(self.t, "conf"); wav(os.path.join(d, "conf01_00000.wav"))
        te = [c for c in D.conf_pool("test") if " " not in c][0]
        jd({"conf01_00000.wav": dict(text=f"{te}, stopp", cut=True)}, os.path.join(d, "texts-s1.json"))
        with self.assertRaises(D.LeakError): D.assert_conf_texts(d)

    def test_texte_disjunkt(self):
        D.assert_text_disjoint(["Wendel"], ["Windel"])
        with self.assertRaises(D.LeakError): D.assert_text_disjoint(["Wendel."], ["wendel"])

    def test_stimmen_nur_clean_set(self):
        v = os.path.join(self.t, "voices")
        os.makedirs(v)
        with self.assertRaises(D.LeakError): D.assert_clean_voices(v)                    # leer
        for n in ("a", "b"): os.makedirs(os.path.join(v, f"v-{n}"))
        self.assertEqual(D.assert_clean_voices(v), ["a", "b"])
        os.makedirs(os.path.join(v, "v-x"))
        with self.assertRaises(D.LeakError): D.assert_clean_voices(v)

    def test_fehlende_oder_leere_erlaubtliste_bricht_ab(self):
        v = os.path.join(self.t, "voices"); os.makedirs(os.path.join(v, "v-a"))
        f = os.path.join(self.t, "voices.allowed")
        c = os.path.join(self.t, "clean"); os.makedirs(os.path.join(c, "gen")); open(os.path.join(c, "gen", "voices.txt"), "w").write("v-a\n")
        with mock.patch.dict(os.environ, {D.VOICES_ALLOWED_ENV: f}):
            with self.assertRaises(D.LeakError) as m: D.allowed_voices()                 # Datei fehlt
            self.assertIn("fehlt", str(m.exception))
            with self.assertRaises(D.LeakError): D.assert_clean_voices(v)
            with self.assertRaises(D.LeakError): D.assert_clean_voices_txt(c)
            open(f, "w").write("\n  \n")
            with self.assertRaises(D.LeakError) as m: D.allowed_voices()                 # leer
            self.assertIn("leer", str(m.exception))
            with self.assertRaises(D.LeakError): D.assert_clean_voices(v)                # leer
            with self.assertRaises(D.LeakError): D.assert_clean_voices_txt(c)
            open(f, "w").write("v-a\n"); self.assertEqual(D.assert_clean_voices(v), ["a"])

    def test_erlaubtliste_gewichte(self):
        f = os.path.join(self.t, "voices.allowed"); open(f, "w").write("# Kommentar\nv-a 4\nb\n")
        with mock.patch.dict(os.environ, {D.VOICES_ALLOWED_ENV: f}):
            self.assertEqual(D.voice_weights(), {"a": 4.0, "b": 1.0}); self.assertEqual(D.allowed_voices(), ["a", "b"])

    def test_erlaubtliste_ungueltig_bricht_ab(self):
        f = os.path.join(self.t, "voices.allowed")
        with mock.patch.dict(os.environ, {D.VOICES_ALLOWED_ENV: f}):
            for zeile in ("a abc", "a nan", "a inf", "a -inf", "a -1", "a 0", "a 1 2", "a 1 x"):
                with self.subTest(zeile=zeile):
                    open(f, "w").write(f"b 1\n{zeile}\n")
                    with self.assertRaises(D.LeakError) as m: D.voice_weights()
                    self.assertIn("Erlaubtliste", str(m.exception))

    def test_erlaubtliste_standardpfad_unter_clean(self):
        c = os.path.join(self.t, "cl"); os.makedirs(c); open(os.path.join(c, "voices.allowed"), "w").write("v-a 3\nb\n")
        env = {k: v for k, v in os.environ.items() if k != D.VOICES_ALLOWED_ENV}
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(D, "CLEAN", c):
            self.assertEqual(D.voice_weights(), {"a": 3.0, "b": 1.0})
            os.remove(os.path.join(c, "voices.allowed"))
            with self.assertRaises(D.LeakError): D.voice_weights()

    def test_audio_gleich_pruefclip_bricht_ab(self):
        a, b = os.path.join(self.t, "tr", "a.wav"), os.path.join(self.t, "ev", "b.wav")
        wav(a, seed=1); wav(b, seed=2)
        D.assert_no_audio_overlap([a], [os.path.join(self.t, "ev")])
        wav(os.path.join(self.t, "ev", "kopie.wav"), seed=1)
        with self.assertRaises(D.LeakError): D.assert_no_audio_overlap([a], [os.path.join(self.t, "ev")])

    def test_fehlender_pruefordner_bricht_ab_ausser_probe(self):
        a = os.path.join(self.t, "tr", "a.wav"); wav(a, seed=1); wav(os.path.join(self.t, "ev", "b.wav"), seed=2)
        dirs = [os.path.join(self.t, "ev"), os.path.join(self.t, "fehlt")]
        with self.assertRaises(D.LeakError): D.assert_no_audio_overlap([a], dirs)
        D.assert_no_audio_overlap([a], dirs, allow_missing=True)                           # nur Probe

    def test_voices_txt_nur_clean_stimmen(self):
        c = os.path.join(self.t, "clean"); os.makedirs(os.path.join(c, "gen"))
        with self.assertRaises(D.LeakError): D.assert_clean_voices_txt(c)                  # fehlt
        f = os.path.join(c, "gen", "voices.txt")
        open(f, "w").write("v-a\nv-b\n"); self.assertEqual(D.assert_clean_voices_txt(c), ["a", "b"])
        open(f, "w").write("v-a\nv-x\n")
        with self.assertRaises(D.LeakError): D.assert_clean_voices_txt(c)                  # fremde Stimme
        open(f, "w").write("")
        with self.assertRaises(D.LeakError): D.assert_clean_voices_txt(c)                  # leer

    def test_externe_wurzel_mit_test_im_pfad(self):
        # Pfad endet auf real/train, liegt aber unter .../test/...: nur die Pruefung auf "test" im Pfad faengt das ab
        for sub in ("fleurs/test/real/train", "x/test/real/dev"):
            p = os.path.join(self.t, sub); os.makedirs(p)
            with self.assertRaises(D.LeakError, msg=sub): D.check_roots(self.roots(p, True))
        ok = os.path.join(self.t, "fleurs", "gut", "real", "train"); os.makedirs(ok)
        D.check_roots(self.roots(ok, True))

    def test_stempel_ausschnitt(self):
        f = os.path.join(self.t, "p1.9-t0.85.npz"); wr(f, b"abc")
        with self.assertRaises(D.LeakError): D.feat_cut(f)                                 # kein Stempel
        D.write_stamp(f, {}); 
        with self.assertRaises(D.LeakError): D.feat_cut(f)                                 # Stempel ohne pre/tail
        D.write_stamp(f, {}, dict(pre=1.9, tail=0.85)); self.assertEqual(D.feat_cut(f), (1.9, 0.85))
        D.write_stamp(f, {}, dict(pre=1.5, tail=0.85))
        with self.assertRaises(D.LeakError): D.feat_cut(f)                                 # Dateiname widerspricht
        g = os.path.join(self.t, "andere.npz"); wr(g, b"x"); D.write_stamp(g, {}, dict(pre=1.5, tail=0.5))
        self.assertEqual(D.feat_cut(g), (1.5, 0.5))

    def test_stempel_pflicht(self):
        f = os.path.join(self.t, "f.npz"); wr(f, b"abc")
        with self.assertRaises(D.LeakError): D.require_stamp(f)
        D.write_stamp(f, {"a": 1}); D.require_stamp(f)
        wr(f, b"abd")
        with self.assertRaises(D.LeakError): D.require_stamp(f)                            # Datei nach dem Stempel veraendert

    def test_echte_clips_nur_trainingsbloecke(self):
        d = os.path.join(self.t, "real"); wav(os.path.join(d, "huawei_b2_r01_hey_000100.wav"))
        D.assert_group_blocks(d)
        wav(os.path.join(d, "huawei_b4_r01_hey_000100.wav"))
        with self.assertRaises(SystemExit): D.assert_group_blocks(d)
        with self.assertRaises(D.LeakError): D.real_group("handy2_b1_r01_hey_000100.wav") if False else D.real_group("kaputt.wav")
        self.assertEqual([D.real_group(f"huawei_b{b}_r01_bare_000100.wav") for b in (1, 2, 3)], [0, 1, 2])

    def test_gesamtpruefung_ruft_alles(self):
        c = os.path.join(self.t, "clean", "gen")
        for k in ("neg_v8",): wav(os.path.join(c, k, "n.wav"))
        wav(os.path.join(self.t, "ver", "gen", "pos", "p.wav"))
        for r in ("train", "dev"): wav(os.path.join(self.t, "wp58", "gen", "real", r, "f.wav"))
        os.symlink(os.path.join(self.t, "wp58", "gen", "real"), os.path.join(c, "real"))
        wav(os.path.join(self.t, "ver", "gen", "conf", "conf01_00000.wav"))
        import json
        jd({"conf01_00000.wav": dict(text=D.conf_pool("train")[0], cut=False)}, os.path.join(self.t, "ver", "gen", "conf", "texts-s1.json"))
        roots = D.default_roots(os.path.join(self.t, "clean"), os.path.join(self.t, "ver"))
        D.check_sources(roots, None, roots["conf"][0], roots["pos"][0], [])
        with self.assertRaises(D.LeakError): D.check_sources(roots, None, roots["conf"][0], roots["pos"][0], [], os.path.join(self.t, "clean"))   # voices.txt fehlt
        open(os.path.join(c, "voices.txt"), "w").write("v-a\nv-b\n")
        D.check_sources(roots, None, roots["conf"][0], roots["pos"][0], [], os.path.join(self.t, "clean"))
        wav(os.path.join(c, "neg_v8", "raw-neg_1.wav"))                                     # verbotener Name im erlaubten Ordner
        with self.assertRaises(D.LeakError): D.check_sources(roots, None, roots["conf"][0], roots["pos"][0], [])


class Ausschnitt(unittest.TestCase):
    def test_segment_feste_laenge_und_auffuellen(self):
        x = np.arange(SR * 3, dtype="float32") / SR
        s = D.segment(x, 0.5, 1.0, 0.5)
        self.assertEqual(len(s), int(1.5 * SR))
        self.assertTrue((s[:SR // 2] == 0).all())
        np.testing.assert_allclose(s[SR // 2:], x[:SR])
        s = D.segment(x, 2.8, 1.0, 0.5)
        self.assertEqual(len(s), int(1.5 * SR)); self.assertTrue((s[-int(0.3 * SR):] == 0).all())

    def test_normalisierung_spitze_und_stille(self):
        n = D.normalize(np.array([0.0, -0.1, 0.05], "float32"))
        self.assertAlmostEqual(float(np.abs(n).max()), 0.5, 5)
        self.assertTrue((D.normalize(np.zeros(5, "float32")) == 0).all())

    def test_pegel(self):
        self.assertAlmostEqual(D.level_db(np.full(100, 0.1)), -20.0, 3)
        self.assertLess(D.level_db(np.zeros(0)), -100)

    def test_stream_events_haelt_bis_zur_direktannahme(self):
        t = 10 + 0.08 * np.arange(5)
        v = np.array([0.1, 0.985, 0.996, 0.5, 0.1], "float32")
        ev = D.stream_events(lambda x: (t, v), None, 0.98)
        self.assertEqual([(round(a - 10, 2), round(p, 3)) for a, p in ev], [(0.24, 0.996)])      # Abfall-Fenster entscheidet mit Spitze (Obergrenze 0,999)

    @staticmethod
    def _rampe():
        """Kurve, bei der die Untergrenze die Entscheidung aendert: mit 0,9 faellt sie bei (0,32 s; 0,96), mit 0,98 bei (0,72 s; 0,998)."""
        v = np.array([0.1, 0.92, 0.93, 0.95, 0.96, 0.985, 0.99, 0.995, 0.997, 0.998, 0.1, 0.1], "float32")
        return 0.08 * np.arange(len(v)) + 10, v

    def test_training_und_pruefung_gleich_ausgerichtet(self):
        import stage2_cut as C
        import verifier_eval as E
        t, v = self._rampe()
        pruef = E.flat_events(C.events_cut({"s": {"i": (t, v)}}, 0.98, "app", 0.999)[1])["s"]          # wie phase_run
        train = D.stream_events(lambda x: (t, v), None)                                                    # wie build_features
        self.assertEqual([(round(a, 6), round(p, 6)) for a, p in train], [(round(e["t"], 6), round(e["peak"], 6)) for e in pruef])
        self.assertTrue(len(train) == 1 and train[0][1] > 0.99)
        self.assertNotEqual(D.stream_events(lambda x: (t, v), None, 0.9), train)                           # die alte Untergrenze 0,9 haette anders ausgerichtet

    def test_zusatz_negative_getrennt_unter_dem_band(self):
        v = np.array([0.1, 0.91, 0.92, 0.93, 0.94, 0.95, 0.1, 0.1], "float32"); t = 0.08 * np.arange(len(v)) + 10
        ex = D.extra_events(lambda x: (t, v), None, 0.9)
        self.assertEqual([(round(a - 10, 2), round(p, 2)) for a, p in ex], [(0.4, 0.95)])                  # an der eigenen Ueberschreitung von 0,9 ausgerichtet
        self.assertEqual(D.stream_events(lambda x: (t, v), None), [])                                       # kein Bandereignis
        t, v = self._rampe()
        self.assertEqual(D.extra_events(lambda x: (t, v), None, 0.9), [])                                   # Spitze 0,985 liegt im Band: kein Zusatz-Negativ
        v = np.array([0.1, 0.91, 0.92, 0.93, 0.94, 0.95, 0.1, 0.1], "float32"); t = 0.08 * np.arange(len(v)) + 10
        for off in (0, None, 0.98, 0.99): self.assertEqual(D.extra_events(lambda x: (t, v), None, off), [])    # abgeschaltet
        self.assertIn("extra", D.KIND); self.assertIn(D.KIND["extra"], D.NEG_KINDS)

    def test_label_examples_ziel_und_untergrenze(self):
        x = np.zeros(SR * 5, "float32")
        evs = [(1.0, 0.99), (3.0, 0.99), (1.2, 0.5)]
        out = D.label_examples(x, evs, 1.1, 0.98, 1.0, 0.5)
        self.assertEqual([(round(p, 2), t) for _, p, t in out], [(0.99, True), (0.99, False)])    # Ziel unter 0,98 verworfen
        out = D.label_examples(x, [(3.0, 0.99)], None, 0.98, 1.0, 0.5)
        self.assertFalse(out[0][2])

    def test_beispielzeilen_und_roundtrip(self):
        for word, yw, yhw in (("hey", 1, 1), ("bare", 1, 0), (None, 0, 0)):
            r = D.make_rows(np.zeros((2, 25, 96)), [0.99, 0.98], D.KIND["conf"], word, [0, 1])
            self.assertEqual((int(r["yw"][0]), int(r["yhw"][0])), (yw, yhw))
        ex = D.Examples.concat([D.Examples(**D.make_rows(np.ones((2, 25, 96)), [0.99, 0.98], 0, "hey", [0, 1])),
                                D.Examples(**D.make_rows(np.zeros((3, 25, 96)), [0.5] * 3, 3, None, [2, 2, 2]))])
        p = os.path.join(tempfile.mkdtemp(), "x", "e.npz"); ex.save(p)
        e2 = D.Examples.load(p)
        self.assertEqual(len(e2), 5); self.assertEqual(e2.d["emb"].dtype, np.float16)
        self.assertEqual(e2.d["group"].tolist(), [0, 1, 2, 2, 2])

    def test_gruppe_stabil(self):
        self.assertEqual(D.group_of("abc"), D.group_of("abc")); self.assertIn(D.group_of("x"), (0, 1, 2))


class Erzeugen(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.t = self.tmp.name
        self.o = (G.load_voice, G.synth)
        G.load_voice = lambda d: (object(), SR, 1)
        G.synth = lambda v, sr, ns, text, rng, wide=False, v8=False: (rng.standard_normal(SR) * 0.1).astype("float32")
        self.voices = os.path.join(self.t, "v")
        for n in D.allowed_voices(): os.makedirs(os.path.join(self.voices, f"v-{n}"))
    def tearDown(self): G.load_voice, G.synth = self.o; self.tmp.cleanup()

    def test_gen_conf_nur_trainings_texte_mit_sidecar(self):
        out = os.path.join(self.t, "conf")
        texts = D.gen_clips("conf", 40, 3, self.voices, out)
        self.assertGreater(len(texts), 10)
        for e in texts.values(): self.assertEqual(D.text_split(D.base_text(e["text"], e["cut"])), "train")
        D.assert_conf_texts(out)
        self.assertEqual(len(os.listdir(out)), len(texts) + 1)

    def test_gen_pos_wortart(self):
        texts = D.gen_clips("pos", 60, 4, self.voices, os.path.join(self.t, "pos"))
        self.assertEqual({e["word"] for e in texts.values()}, {"hey", "bare"})
        for e in texts.values(): self.assertEqual(e["word"] == "hey", e["text"].lower().startswith("hey"))

    def test_gen_nutzt_gewichte_der_erlaubtliste(self):
        v = os.path.join(self.t, "vw")
        for n in ("a", "b"): os.makedirs(os.path.join(v, f"v-{n}"))
        f = os.path.join(self.t, "w.allowed"); open(f, "w").write("a 9\nb 1\n")
        with mock.patch.dict(os.environ, {D.VOICES_ALLOWED_ENV: f}):
            texts = D.gen_clips("conf", 200, 5, v, os.path.join(self.t, "cw"))
        cnt = {n: sum(e["voice"] == n for e in texts.values()) for n in ("a", "b")}
        self.assertGreater(cnt["a"], 4 * cnt["b"]); self.assertGreater(cnt["b"], 0)           # 9:1 erwartet, gleichverteilt waere ~1:1

    def test_gen_mit_unerlaubter_stimme_bricht_ab(self):
        os.makedirs(os.path.join(self.voices, "v-x"))
        with self.assertRaises(D.LeakError): D.gen_clips("conf", 3, 1, self.voices, os.path.join(self.t, "c"))

    def test_features_invarianten(self):
        v = os.path.join(self.t, "ver"); c = os.path.join(self.t, "clean")
        D.gen_clips("pos", 12, 1, self.voices, f"{v}/gen/pos"); D.gen_clips("conf", 25, 1, self.voices, f"{v}/gen/conf")
        for i in range(6): wav(f"{c}/gen/neg_v8/n{i}.wav", n=3 * SR, v=0.1, seed=i)
        for r in ("train", "dev"):
            for i in range(3): wav(f"{c}/gen/real/{r}/f{i}.wav", n=3 * SR, seed=10 + i)
        real = os.path.join(self.t, "real")
        for b in (1, 2, 3): wav(f"{real}/huawei_b{b}_r01_hey_000100.wav", n=SR, v=0.3, seed=b); wav(f"{real}/huawei_b{b}_r01_bare_000200.wav", n=SR, v=0.3, seed=b + 5)

        class Fake:
            def curve(self, x):
                n = len(x) // 1280 - 1
                rms = np.array([np.sqrt((x[i * 1280:(i + 1) * 1280] ** 2).mean()) for i in range(n)])
                return np.arange(n) * 0.08, np.where(rms >= np.quantile(rms, 0.9), 0.99, 0.1).astype("float32")
            def embed_segs(self, segs): return np.random.default_rng(0).standard_normal((len(segs), 25, 96)).astype("float32")

        roots = D.default_roots(c, v)
        os.symlink(f"{c}/gen/real", f"{c}/gen/real") if False else None
        a = argparse.Namespace(ver=v, limit=None, pre=1.9, tail=0.8, extra_neg_lo=0.9, n_pos=30, n_real=30, n_conf=30, mine_hours=0.02)
        ex = D.build_features(Fake(), a, roots, real, np.random.default_rng(1), log=lambda *x, **k: None)
        d = ex.d
        self.assertGreater(len(ex), 0)
        self.assertEqual(d["emb"].shape[1:], (25, 96))
        self.assertTrue((d["yhw"] <= d["yw"]).all())
        self.assertTrue(set(d["kind"].tolist()) <= set(D.KIND.values()))
        self.assertTrue((d["yw"][np.isin(d["kind"], D.NEG_KINDS)] == 0).all())                 # Negative haben nie Positiv-Label
        self.assertTrue((d["peak"][np.isin(d["kind"], [0, 1])][d["yw"][np.isin(d["kind"], [0, 1])] == 1] >= D.BAND[0]).all())
        self.assertTrue(set(d["group"].tolist()) <= {0, 1, 2})
        self.assertIn(D.KIND["mined"], d["kind"].tolist())

    def test_features_ereignisse_ab_bandgrenze_extra_getrennt(self):
        v = os.path.join(self.t, "ver"); c = os.path.join(self.t, "clean")
        D.gen_clips("pos", 6, 1, self.voices, f"{v}/gen/pos"); D.gen_clips("conf", 10, 1, self.voices, f"{v}/gen/conf")
        for i in range(6): wav(f"{c}/gen/neg_v8/n{i}.wav", n=3 * SR, v=0.1, seed=i)
        for r in ("train", "dev"):
            for i in range(3): wav(f"{c}/gen/real/{r}/f{i}.wav", n=3 * SR, seed=10 + i)
        ramp = np.array([0.1, 0.91, 0.92, 0.93, 0.94, 0.95] + [0.1] * 5 + [0.99, 0.995, 0.997, 0.998, 0.998] + [0.1] * 40, "float32")    # erst Spitze 0,95, dann im Band

        class Fake:
            def curve(self, x):
                n = len(x) // 1280 - 1
                return np.arange(n) * 0.08, np.tile(ramp, n // len(ramp) + 1)[:n]
            def embed_segs(self, segs): return np.random.default_rng(0).standard_normal((len(segs), 25, 96)).astype("float32")

        roots = D.default_roots(c, v)
        for lo, want_extra in ((0.9, True), (0, False)):
            a = argparse.Namespace(ver=v, limit=None, pre=1.9, tail=0.8, extra_neg_lo=lo, n_pos=12, n_real=0, n_conf=12, mine_hours=0.02)
            d = D.build_features(Fake(), a, roots, None, np.random.default_rng(1), log=lambda *x, **k: None).d
            mined, extra = d["peak"][d["kind"] == D.KIND["mined"]], d["peak"][d["kind"] == D.KIND["extra"]]
            self.assertGreater(len(mined), 0); self.assertTrue((mined >= D.BAND[0]).all())          # Ereignisse wie in der Pruefung
            own = d["peak"][np.isin(d["kind"], [D.KIND["pos_syn"], D.KIND["conf"], D.KIND["filler"]])]
            self.assertGreater(len(own), 0); self.assertTrue((own >= D.BAND[0]).all())                 # auch Positive/Verwechsler/Fuellereignisse ab 0,98
            self.assertEqual(len(extra) > 0, want_extra); self.assertTrue((extra < D.BAND[0]).all())


if __name__ == "__main__":
    unittest.main()
