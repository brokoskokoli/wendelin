import 'dart:math' as math;
import 'dart:typed_data';

/// Synthetic noises for the content check of the enrollment (WP140). Frames
/// of 30 ms like `recording()`: [lead] ms of faint noise, the sound, [tail]
/// ms of faint noise. No real recordings.
enum Noise { click, knock, cough, steadyNoise, silence, anotherWord }

/// Deterministic pseudo noise in -1..1.
double _noise(int i) {
  final x = math.sin(i * 12.9898) * 43758.5453;
  return (x - x.floor()) * 2 - 1;
}

/// Samples of [kind] at 16 kHz.
Int16List soundOf(Noise kind) {
  int ms(int m) => 16 * m;
  Int16List build(int n, double Function(int i) f) =>
      Int16List.fromList([for (var i = 0; i < n; i++) (f(i) * 32767).round()]);
  return switch (kind) {
    // 2 ms broadband impulse.
    Noise.click => build(ms(2), (i) => _noise(i) * 0.9 * math.exp(-i / 12)),
    // 120 ms decaying low thump.
    Noise.knock => build(
      ms(120),
      (i) => math.sin(2 * math.pi * 110 * i / 16000) * 0.8 * math.exp(-i / 500),
    ),
    // 450 ms noise burst with a fast rise and a slow fall.
    Noise.cough => build(ms(450), (i) {
      final t = i / ms(450);
      return _noise(i) * 0.5 * math.sin(math.pi * math.pow(t, 0.4));
    }),
    // 1.1 s steady noise (fan, rustling).
    Noise.steadyNoise => build(ms(1100), (i) => _noise(i) * 0.25),
    Noise.silence => Int16List(ms(1100)),
    // 0.9 s harmonic sweep with a syllable rhythm: loud, speech-like, but
    // no „Wendelin“ (the content check decides by the recognizer).
    Noise.anotherWord => build(ms(900), (i) {
      final t = i / 16000;
      final env = 0.5 + 0.5 * math.sin(2 * math.pi * 4 * t - 1.2);
      final f = 140 + 60 * t;
      return 0.4 *
          env *
          (math.sin(2 * math.pi * f * t) +
              0.5 * math.sin(2 * math.pi * 2 * f * t) +
              0.25 * math.sin(2 * math.pi * 3 * f * t));
    }),
  };
}

/// [soundOf] as microphone frames of 30 ms with faint noise around it.
List<Int16List> clip(Noise kind, {int lead = 450, int tail = 700}) {
  final sound = soundOf(kind);
  Int16List faint(int ms) => Int16List.fromList([
    for (var i = 0; i < 16 * ms; i++) (_noise(i + 7) * 20).round(),
  ]);
  final all = Int16List.fromList([...faint(lead), ...sound, ...faint(tail)]);
  const frame = 480;
  return [
    for (var i = 0; i < all.length; i += frame)
      Int16List.sublistView(all, i, math.min(i + frame, all.length)),
  ];
}
