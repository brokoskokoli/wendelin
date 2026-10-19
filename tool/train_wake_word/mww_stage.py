"""microWakeWord-Streaming-Modell (tflite, Apache-2.0) als Stufe 1 in real_measure.py (WP106).

Nur ai-edge-litert + pymicro-features (kein TensorFlow): Mikrofrontend (40 Merkmale/10 ms), Streaming-Modell
(3 Merkmalsrahmen je Schritt = 30 ms), Smoothing wie in ESPHome (Mittel der letzten 5 Ausgaben).
"""
import numpy as np


class MwwScorer:
    def __init__(self, path, smooth=5):
        self.path, self.smooth = path, smooth
        self._new()

    def _new(self):
        from ai_edge_litert.interpreter import Interpreter
        it = Interpreter(model_path=self.path); it.allocate_tensors()
        self.it = it
        self.i0, self.o0 = it.get_input_details(), it.get_output_details()
        self.q = self.i0[0]["dtype"] == np.int8
        self.stride = self.i0[0]["shape"][1]
        for d in self.i0:
            it.set_tensor(d["index"], np.zeros(d["shape"], dtype=np.int8 if self.q else np.float32))

    def features(self, x):
        from pymicro_features import MicroFrontend
        a = np.clip(x * 32768, -32768, 32767).astype(np.int16).tobytes()
        mf, f, i = MicroFrontend(), [], 0
        while i + 320 < len(a):
            r = mf.process_samples(a[i:i + 320]); i += r.samples_read * 2
            if r.features: f.append(r.features)
        return np.array(f).astype(np.float32)

    def probs(self, x):
        """Rohwahrscheinlichkeit je Schritt; Schritt k endet bei Sample 480*k + 800."""
        self._new()
        sp = self.features(x)
        out = []
        d0, o = self.i0[0], self.o0[0]
        for last in range(self.stride, len(sp) + 1, self.stride):
            c = sp[last - self.stride:last]
            if self.q:
                sc, zp = d0["quantization_parameters"]["scales"][0], d0["quantization_parameters"]["zero_points"][0]
                c = (c / sc + zp).astype(np.int8)
            self.it.set_tensor(d0["index"], np.reshape(c, d0["shape"]))
            self.it.invoke()
            v = self.it.get_tensor(o["index"])[0][0]
            if self.q: v = (v.astype(np.float32) - o["quantization_parameters"]["zero_points"][0]) / 255.0
            out.append(float(v))
        return np.array(out, "float32")

    def on_grid(self, x, we):
        """Wert je oWW-Fenster (Fensterende `we` in Samples von x): Maximum der geglaetteten Wahrscheinlichkeit der letzten 80 ms."""
        p = self.probs(x)
        if not len(p): return np.zeros(len(we), "float32")
        k = self.smooth
        sm = np.convolve(p, np.ones(k) / k)[:len(p)]; sm[:k - 1] = 0     # Mittel der letzten k Ausgaben
        end = 480 * np.arange(len(p)) + 800
        res = np.zeros(len(we), "float32")
        for j, e in enumerate(we):
            m = (end > e - 1280) & (end <= e)
            if m.any(): res[j] = sm[m].max()
        return res
