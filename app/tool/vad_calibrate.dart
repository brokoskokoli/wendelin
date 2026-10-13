// Kalibriert VAD-Schwelle und Mindestsprechdauer mit echtem Silero-VAD
// (sherpa-onnx-Desktop-Bindings) auf den STT-Fixtures und synthetischen
// Störgeräuschen (Klick, Tippen, Atmer, Husten, Klopfen).
//
//   cd app
//   dart run tool/vad_calibrate.dart --vad <pfad/zu/silero_vad.onnx>
//       [--fixtures test/fixtures/stt]
//
// Jede Aufnahme liegt in einem Grundrauschen (−60 dBFS) mit 1 s Vorlauf und
// 1,5 s Nachlauf und läuft in 20-ms-Frames (wie vom Mikrofon) durch
// `SileroVoiceActivityDetector` und den `Endpointer` (Mindestsprechdauer 0).
// Gemessen wird die erkannte Sprechdauer (erster bis letzter Sprach-Frame).
// Ausgabe: Markdown-Tabellen auf stdout.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/silero_vad.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main(List<String> args) {
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final vadPath = opt('vad');
  if (vadPath == null) {
    stderr.writeln('--vad <silero_vad.onnx> fehlt');
    exitCode = 64;
    return;
  }
  final dir = opt('fixtures') ?? 'test/fixtures/stt';
  final speech = <(String, bool, Int16List)>[
    for (final line in File('$dir/manifest.tsv').readAsLinesSync())
      if (line.trim().isNotEmpty && !line.startsWith('#'))
        (
          line.split('\t')[0],
          // One-word answers („Ja“, „Non“, „Yes“): the shortest speech.
          !line.split('\t')[3].trim().contains(' '),
          Wav.read('$dir/${line.split('\t')[0]}.wav').samples,
        ),
  ];
  final noises = syntheticNoises();

  stdout
    ..writeln(
      '| Schwelle | kürzestes Wort | Ø Wort | Sätze erkannt | '
      'längstes Störgeräusch | Störgeräusche erkannt |',
    )
    ..writeln('|---:|---:|---:|---:|---:|---:|');
  final details = StringBuffer();
  for (final threshold in [0.3, 0.4, 0.5, 0.6, 0.7]) {
    final vad = SileroVoiceActivityDetector(
      modelPath: vadPath,
      threshold: threshold,
    );
    final words = <int>[];
    var found = 0;
    for (final (_, word, pcm) in speech) {
      final ms = speechMs(vad, embed(pcm));
      if (ms > 0) found++;
      if (word) words.add(ms);
    }
    var noiseMax = 0;
    var noiseHits = 0;
    for (final (name, pcm) in noises) {
      final ms = speechMs(vad, embed(pcm));
      if (ms > 0) noiseHits++;
      noiseMax = math.max(noiseMax, ms);
      details.writeln('| $threshold | $name | $ms ms |');
    }
    vad.dispose();
    words.sort();
    final avg = words.isEmpty
        ? 0
        : words.reduce((a, b) => a + b) ~/ words.length;
    stdout.writeln(
      '| $threshold | ${words.first} ms | $avg ms | '
      '$found/${speech.length} | $noiseMax ms | '
      '$noiseHits/${noises.length} |',
    );
  }
  stdout
    ..writeln()
    ..writeln('| Schwelle | Störgeräusch | erkannte Sprechdauer |')
    ..writeln('|---:|---|---:|')
    ..write(details);
}

/// Detected speech duration in [pcm] (first to last speech frame) in ms;
/// 0 if Silero heard nothing.
int speechMs(SileroVoiceActivityDetector vad, Int16List pcm) {
  vad.reset();
  final ep = Endpointer(
    const EndpointConfig(
      minSpeech: Duration.zero,
      maxDuration: Duration(seconds: 60),
      noSpeechTimeout: Duration(seconds: 60),
    ),
  );
  const frame = 320; // 20 ms
  Endpoint? end;
  for (var i = 0; i + frame <= pcm.length && end == null; i += frame) {
    final f = Int16List.sublistView(pcm, i, i + frame);
    end = ep.add(f, speech: vad.isSpeech(f));
  }
  end ??= ep.finish();
  if (end.kind != EndpointKind.utterance) return 0;
  return (end.speechEnd! - end.speechStart!).inMilliseconds;
}

final _rng = math.Random(17);

/// [pcm] with 1 s noise floor before and 1.5 s after.
Int16List embed(Int16List pcm) {
  const before = 16000, after = 24000;
  final out = floor(before + pcm.length + after);
  for (var i = 0; i < pcm.length; i++) {
    out[before + i] = (out[before + i] + pcm[i]).clamp(-32768, 32767);
  }
  return out;
}

/// White noise at −60 dBFS (quiet room, phone microphone).
Int16List floor(int n) => Int16List.fromList([
  for (var i = 0; i < n; i++) ((_rng.nextDouble() * 2 - 1) * 33 * 1.7).round(),
]);

/// Noise of [ms] milliseconds at [level] (full scale = 1) with a smooth
/// envelope; [lowpass] 0–1 makes it darker (breath).
Int16List burst(int ms, double level, {double lowpass = 0}) {
  final n = ms * 16;
  final out = Int16List(n);
  var y = 0.0;
  for (var i = 0; i < n; i++) {
    final x = _rng.nextDouble() * 2 - 1;
    y = lowpass * y + (1 - lowpass) * x;
    final env = math.sin(math.pi * i / n);
    out[i] = (y * env * level * 32767).round().clamp(-32768, 32767);
  }
  return out;
}

/// Decaying tone (knock).
Int16List knock(int hz, double level) {
  final n = 30 * 16;
  return Int16List.fromList([
    for (var i = 0; i < n; i++)
      (math.sin(2 * math.pi * hz * i / 16000) *
              math.exp(-i / 80) *
              level *
              32767)
          .round(),
  ]);
}

/// Concatenates [parts] with [gapMs] of silence in between.
Int16List seq(List<Int16List> parts, int gapMs) {
  final out = <int>[];
  for (final p in parts) {
    out
      ..addAll(p)
      ..addAll(List.filled(gapMs * 16, 0));
  }
  return Int16List.fromList(out);
}

/// Synthetic disturbances that must not count as speech.
List<(String, Int16List)> syntheticNoises() {
  final click = Int16List.fromList([
    for (var i = 0; i < 48; i++) i.isEven ? 16000 : -16000,
  ]);
  return [
    ('Klick (3 ms, −6 dBFS)', click),
    ('Tippen (5 Klicks, 120 ms Abstand)', seq(List.filled(5, click), 120)),
    ('Atmer (400 ms, −30 dBFS)', burst(400, 0.03, lowpass: 0.9)),
    ('lauter Atmer (600 ms, −20 dBFS)', burst(600, 0.1, lowpass: 0.9)),
    ('Husten-Stoß (150 ms, −12 dBFS)', burst(150, 0.25, lowpass: 0.5)),
    ('Klopfen (2×, 400 Hz)', seq([knock(400, 0.5), knock(400, 0.5)], 150)),
  ];
}
