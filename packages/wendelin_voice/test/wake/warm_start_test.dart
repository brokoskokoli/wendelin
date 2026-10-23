// WP123: Warmstart der Merkmalskette. Der Vorlauf füllt nur die Kette; er
// bewertet kein Fenster, hinterlässt keinen Zustand und kommt vor den
// Live-Frames. Das Ende des Befehls im Vorlauf stoppt die Antwort nicht.
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

final _wake = Float32List.fromList([1, 0]);
final _none = Float32List.fromList([-1, -1]);

WakeTemplates _tpl(Float32List e) => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'fake-1',
  threshold: 0.9,
  embeddings: [e],
);

/// Engine whose windows (one per frame of 100 samples) are [windows] in
/// order, first the warm-up ones, then the live ones.
CandidateWakeEngine _engine(
  List<Float32List> windows, {
  void Function(double, double?)? onWindow,
}) {
  var i = 0;
  return CandidateWakeEngine(
    features: FakeWakeFeatureExtractor(
      windowEvery: 100,
      windowFor: (end, _) =>
          WakeWindow(endSample: end, embedding: windows[i++]),
    ),
    templates: _tpl(_wake),
    modelThreshold: null,
    onWindow: onWindow,
  );
}

Future<void> _warm(CandidateWakeEngine e, int n) async {
  for (var k = 0; k < n; k++) {
    await e.warmUp(Int16List(100));
  }
}

Future<List<String>> _live(CandidateWakeEngine e, int n) async => [
  for (var k = 0; k < n; k++)
    for (final h in await e.accept(Int16List(100))) h.keywordId,
];

/// Engine that logs its calls; [warmUp] takes a turn of the event loop and
/// can be held.
final class _LogEngine implements WarmableWakeEngine {
  final log = <String>[];
  int warmCalls = 0;
  Completer<void>? hold;

  @override
  Future<void> open(List<KeywordSpec> keywords) async {}

  @override
  Future<void> warmUp(Int16List frame) async {
    warmCalls++;
    log.add('warm');
    await Future<void>.delayed(Duration.zero);
    await hold?.future;
  }

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    log.add('live');
    return [const WakeWordHit(keywordId: 'wake', endSample: 0, confidence: 1)];
  }

  @override
  void reset() => log.add('reset');

  @override
  Future<void> close() async {}
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Int16List _loud(int n) => Int16List(n)..fillRange(0, n, 3000);

void main() {
  group('CandidateWakeEngine.warmUp', () {
    test('Fenster im Vorlauf: kein onWindow, kein Zustand', () async {
      var seen = 0;
      final e = _engine([
        _none,
        _none,
        _none,
        _none,
      ], onWindow: (_, _) => seen++);
      await e.open([KeywordSpec.wendelin]);
      e.reset();
      await _warm(e, 3);
      expect(seen, 0, reason: 'der Vorlauf bewertet kein Fenster');
      expect(await _live(e, 1), isEmpty);
      expect(seen, 1);
    });

    test('Wake im Vorlauf sperrt das erste Live-Fenster nicht', () async {
      final e = _engine([_wake, _wake, _wake]);
      await e.open([KeywordSpec.wendelin]);
      e.reset();
      await _warm(e, 2);
      expect(await _live(e, 1), ['wake'], reason: 'keine Refraktärzeit');
    });

    test(
      'neutrale Live-Fenster nach einem Vorlauf aus Treffern: kein Treffer',
      () async {
        final e = _engine([_wake, _wake, _none, _none]);
        await e.open([KeywordSpec.wendelin]);
        e.reset();
        await _warm(e, 2);
        expect(await _live(e, 2), isEmpty);
      },
    );

    test('Engine nicht offen: Fehler', () async {
      final e = _engine([_none]);
      expect(() => e.warmUp(Int16List(100)), throwsStateError);
    });
  });

  group('WakeWordBargeInDetector Warmstart', () {
    late FakeAudioInput audio;
    late _LogEngine engine;
    late List<BargeInSignal> signals;

    WakeWordBargeInDetector detector(Int16List Function()? warm) {
      audio = FakeAudioInput();
      engine = _LogEngine();
      final d = WakeWordBargeInDetector(
        audio: audio,
        engine: engine,
        warm: warm,
      );
      signals = [];
      d.signals.listen(signals.add);
      return d;
    }

    test('Live-Frames kommen erst nach dem ganzen Vorlauf', () async {
      final d = detector(() => Int16List(1280 * 3));
      await d.start();
      for (var i = 0; i < 3; i++) {
        audio.push(Int16List(480));
      }
      await _until(() => engine.log.where((l) => l == 'live').length == 3);
      expect(engine.log, [
        'reset',
        'warm',
        'warm',
        'warm',
        'live',
        'live',
        'live',
      ]);
      await d.dispose();
    });

    test('stop() im Vorlauf bricht ihn ab', () async {
      final d = detector(() => Int16List(1280 * 5));
      engine.hold = Completer<void>();
      await d.start();
      await _until(() => engine.warmCalls == 1);
      await d.stop();
      engine.hold!.complete();
      await _until(() => false);
      expect(engine.warmCalls, 1, reason: 'kein weiterer Vorlauf nach stop');
      expect(engine.log.where((l) => l == 'live'), isEmpty);
      await d.dispose();
    });

    test('Befehl + 800 ms Stille: kein Treffer aus dem Vorlauf', () async {
      // Vorlauf 2,4 s: 1,6 s Sprache, dann 0,8 s Stille (endSilence).
      final pcm = Int16List(38400)..setRange(0, 25600, _loud(25600));
      final d = detector(() => pcm);
      await d.start();
      // Jeder Live-Frame meldet "wake" (Fenster reicht noch in den Befehl).
      for (var i = 0; i < 30; i++) {
        audio.push(Int16List(480));
      }
      await _until(() => engine.log.where((l) => l == 'live').length == 30);
      await _until(() => false);
      // Erst ab 11 200 Live-Samples (Fenster 1,5 s ohne Befehl) zählen Treffer.
      expect(signals, hasLength(30 - 23));
      await d.dispose();
    });

    test('stiller Vorlauf: Treffer zählen vom ersten Frame an', () async {
      final d = detector(() => Int16List(38400));
      await d.start();
      for (var i = 0; i < 5; i++) {
        audio.push(Int16List(480));
      }
      await _until(() => engine.log.where((l) => l == 'live').length == 5);
      await _until(() => false);
      expect(signals, hasLength(5));
      await d.dispose();
    });
  });
}
