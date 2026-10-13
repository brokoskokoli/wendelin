import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const ms = Duration(milliseconds: 1);

String rep(String c, int n) => c * n;

/// Feeds [pattern] (`S` speech, `.` silence) in [frame] steps; returns the
/// endpoint or `null` if still listening.
Endpoint? feed(
  String pattern, {
  EndpointConfig config = const EndpointConfig(),
  Duration frame = const Duration(milliseconds: 50),
  Endpointer? into,
}) {
  final e = into ?? Endpointer(config);
  for (final f in AudioFrames.pattern(pattern, frame: frame)) {
    final r = e.add(f, speech: f[0] != 0);
    if (r != null) return r;
  }
  return null;
}

int msOf(Int16List pcm) => samplesToDuration(pcm.length).inMilliseconds;

void main() {
  const short = EndpointConfig(
    noSpeechTimeout: Duration(seconds: 1),
    maxDuration: Duration(seconds: 2),
  );

  // name, pattern (50 ms per char), config, kind, reason,
  // speech start/end ms, pcm ms, elapsed ms
  final table =
      <
        (
          String,
          String,
          EndpointConfig,
          EndpointKind,
          EndpointReason,
          int?,
          int?,
          int,
          int,
        )
      >[
        (
          'Pause, Sprache, 800 ms Stille: Pre-Roll 300 ms',
          '${rep('.', 10)}${rep('S', 10)}${rep('.', 16)}',
          const EndpointConfig(),
          EndpointKind.utterance,
          EndpointReason.silence,
          500,
          1000,
          300 + 500 + 800,
          1800,
        ),
        (
          'Sprache sofort: kein Pre-Roll vorhanden',
          '${rep('S', 6)}${rep('.', 16)}',
          const EndpointConfig(),
          EndpointKind.utterance,
          EndpointReason.silence,
          0,
          300,
          1100,
          1100,
        ),
        (
          'Pause < 800 ms beendet nicht',
          '${rep('S', 5)}${rep('.', 15)}${rep('S', 5)}${rep('.', 16)}',
          const EndpointConfig(),
          EndpointKind.utterance,
          EndpointReason.silence,
          0,
          1250,
          2050,
          2050,
        ),
        (
          'Geräusch < 200 ms wird verworfen, echte Äußerung danach',
          '..SS${rep('.', 16)}${rep('S', 6)}${rep('.', 16)}',
          const EndpointConfig(),
          EndpointKind.utterance,
          EndpointReason.silence,
          1000,
          1300,
          300 + 300 + 800,
          2100,
        ),
        (
          'genau 200 ms Sprache reichen',
          '${rep('S', 4)}${rep('.', 16)}',
          const EndpointConfig(),
          EndpointKind.utterance,
          EndpointReason.silence,
          0,
          200,
          1000,
          1000,
        ),
        (
          'nur Stille: nichts nach Timeout',
          rep('.', 30),
          short,
          EndpointKind.nothing,
          EndpointReason.noSpeech,
          null,
          null,
          0,
          1000,
        ),
        (
          'nur ein Geräusch: nichts nach Timeout',
          'SS${rep('.', 30)}',
          short,
          EndpointKind.nothing,
          EndpointReason.noSpeech,
          null,
          null,
          0,
          1000,
        ),
        (
          'Dauersprache: Schluss beim Maximum',
          rep('S', 60),
          short,
          EndpointKind.utterance,
          EndpointReason.maxDuration,
          0,
          2000,
          2000,
          2000,
        ),
        (
          'Rauschen bis zum Maximum: nichts',
          'SSS${rep('.', 40)}',
          const EndpointConfig(maxDuration: Duration(seconds: 1)),
          EndpointKind.nothing,
          EndpointReason.maxDuration,
          null,
          null,
          0,
          1000,
        ),
        (
          'Sprache beginnt kurz vor dem Timeout: kein Timeout',
          '${rep('.', 19)}${rep('S', 6)}${rep('.', 16)}',
          const EndpointConfig(noSpeechTimeout: Duration(seconds: 1)),
          EndpointKind.utterance,
          EndpointReason.silence,
          950,
          1250,
          1400,
          2050,
        ),
      ];

  group('Endpointing-Tabelle', () {
    for (final (name, pattern, config, kind, reason, s, e, pcm, el) in table) {
      test(name, () {
        final r = feed(pattern, config: config)!;
        expect(r.kind, kind);
        expect(r.reason, reason);
        expect(r.speechStart?.inMilliseconds, s);
        expect(r.speechEnd?.inMilliseconds, e);
        expect(msOf(r.pcm), pcm);
        expect(r.elapsed.inMilliseconds, el);
      });
    }
  });

  test('750 ms Stille beenden noch nicht, 800 ms schon', () {
    final e = Endpointer();
    expect(feed('${rep('S', 6)}${rep('.', 15)}', into: e), isNull);
    expect(e.inSpeech, isTrue);
    expect(feed('.', into: e)?.reason, EndpointReason.silence);
  });

  test('150 ms Sprache sind zu kurz und werden verworfen', () {
    final e = Endpointer();
    expect(feed('${rep('S', 3)}${rep('.', 16)}', into: e), isNull);
    expect(e.inSpeech, isFalse);
    expect(e.result, isNull);
  });

  test('Pre-Roll ist genau 300 ms, auch bei krummen Framelängen', () {
    final r = feed(
      '${rep('.', 10)}${rep('S', 6)}${rep('.', 12)}',
      frame: const Duration(milliseconds: 70),
    )!;
    expect(r.pcm.length, 4800 + 18 * 1120);
    expect(r.speechStart, ms * 700);
    // The pre-roll is silence, the speech follows directly.
    expect(r.pcm.sublist(0, 4800).every((s) => s == 0), isTrue);
    expect(r.pcm[4800], AudioFrames.speechAmplitude);
  });

  test('finish: laufende Sprache wird Äußerung, sonst nichts', () {
    final e = Endpointer();
    feed('..${rep('S', 6)}', into: e);
    final r = e.finish();
    expect(r.kind, EndpointKind.utterance);
    expect(r.reason, EndpointReason.manual);
    expect(e.finish(), same(r));
    expect(e.add(AudioFrames.speech(), speech: true), same(r));

    final quiet = Endpointer();
    feed('....', into: quiet);
    expect(quiet.finish().kind, EndpointKind.nothing);

    final noise = Endpointer();
    feed('SS', into: noise);
    expect(noise.finish().kind, EndpointKind.nothing);
  });

  test('withNoSpeechTimeout ändert nur den Timeout', () {
    const c = EndpointConfig(minSpeech: Duration(milliseconds: 100));
    final f = c.withNoSpeechTimeout(const Duration(seconds: 5));
    expect(f.noSpeechTimeout, const Duration(seconds: 5));
    expect(f.minSpeech, c.minSpeech);
    expect(f.preRoll, c.preRoll);
    expect(f.endSilence, c.endSilence);
    expect(f.maxDuration, c.maxDuration);
  });

  test('Standardwerte laut Konzept', () {
    const c = EndpointConfig();
    expect(c.preRoll, ms * 300);
    expect(c.endSilence, ms * 800);
    expect(c.maxDuration, const Duration(seconds: 30));
    expect(c.minSpeech, ms * 200); // Review WP15; Kalibrierung in WP17
  });

  test('Endpoint.toString nennt Art und Grund', () {
    final r = feed('${rep('S', 6)}${rep('.', 16)}')!;
    expect(r.toString(), contains('utterance'));
    expect(r.toString(), contains('silence'));
  });
}
