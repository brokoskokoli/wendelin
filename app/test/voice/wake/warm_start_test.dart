import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/barge_meter.dart';
import 'package:wendelin/voice/wake/mic_tail.dart';
import 'package:wendelin/voice/wake/wake_barge_in.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

WakeTemplates tpl(double threshold) => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'fake-1',
  threshold: threshold,
  embeddings: [
    Float32List.fromList([1, 0]),
  ],
);

/// Runs [body] on a fake clock: the detector's frame timers and the test's
/// waits advance in 5 ms steps of virtual time, without real delays. Between
/// the steps the real event loop turns once, because futures that are
/// already completed in the root zone (a cancelled subscription) resume
/// there.
Future<void> runFake(Future<void> Function() body) async {
  final fake = FakeAsync();
  var done = false;
  Object? error;
  StackTrace? trace;
  fake.run((_) {
    body().then<void>(
      (_) => done = true,
      onError: (Object e, StackTrace s) {
        error = e;
        trace = s;
        done = true;
      },
    );
  });
  for (var i = 0; i < 20000 && !done; i++) {
    fake.elapse(const Duration(milliseconds: 5));
    await Future<void>.delayed(Duration.zero);
  }
  if (!done) throw TestFailure('Test hängt auch in virtueller Zeit');
  if (error != null) Error.throwWithStackTrace(error!, trace!);
}

void ftest(String name, Future<void> Function() body) =>
    test(name, () => runFake(body));

/// Chain like the real one: the first window comes only after [coldSamples]
/// of audio since the last reset (2.1 s), then one per 480 samples.
class _ColdChain implements WakeFeatureExtractor {
  _ColdChain(this.onFirstWindow);
  static const coldSamples = 33600;
  final void Function() onFirstWindow;
  int _seen = 0;
  bool _first = true;

  @override
  String get featureVersion => 'fake-1';
  @override
  Future<void> open() async {}
  @override
  Future<List<WakeWindow>> accept(Int16List frame) async {
    _seen += frame.length;
    if (_seen < coldSamples) return const [];
    if (_first) {
      _first = false;
      onFirstWindow();
    }
    return [
      WakeWindow(endSample: _seen, embedding: Float32List.fromList([0, 1])),
    ];
  }

  @override
  void reset() {
    _seen = 0;
    _first = true;
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('WP123 Warmstart', () {
    late List<String> lines;
    late void Function(String) saved;
    setUp(() {
      saved = voiceLogSink;
      lines = [];
      voiceLogSink = lines.add;
    });
    tearDown(() => voiceLogSink = saved);

    // Live samples delivered when the first window is rated.
    Future<int> liveAtFirstWindow({Int16List Function()? warm}) async {
      final audio = FakeAudioInput(
        frames: [for (var i = 0; i < 100; i++) Int16List(480)],
        frameInterval: const Duration(milliseconds: 5),
      );
      var live = -1;
      final d = LazyWakeBargeInDetector(
        audio: audio,
        templates: () async => [tpl(0.9)],
        warm: warm,
        diagInterval: const Duration(milliseconds: 20),
        features: () => _ColdChain(() => live = audio.deliveredFrames * 480),
      );
      await d.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await d.stop();
      await d.dispose();
      return live;
    }

    ftest('mit Warmstart: erstes Fenster nach <= 0,3 s Live-Audio', () async {
      final tail = MicTail()..add(Int16List(38400));
      final live = await liveAtFirstWindow(warm: tail.snapshot);
      expect(live, inInclusiveRange(0, 4800), reason: 'Samples live');
    });

    ftest('ohne Warmstart braucht die Kette ~2,1 s (Gegenprobe)', () async {
      final live = await liveAtFirstWindow();
      expect(live, greaterThanOrEqualTo(_ColdChain.coldSamples));
    });

    ftest('Warmstart scheitert: kalter Start, kein Absturz', () async {
      final live = await liveAtFirstWindow(warm: () => throw StateError('x'));
      expect(live, greaterThanOrEqualTo(_ColdChain.coldSamples));
    });

    ftest('barge-diag und barge-end tragen win=', () async {
      await liveAtFirstWindow();
      final diag = lines.where((l) => l.contains('barge-diag')).toList();
      expect(diag, isNotEmpty);
      expect(diag.first, contains('win=0'), reason: 'Kette noch kalt');
      expect(diag.any((l) => RegExp(r'win=[1-9]').hasMatch(l)), isTrue);
      expect(
        lines.singleWhere((l) => l.contains('barge-end')),
        contains('win='),
      );
    });
  });

  group('BargeMeter win', () {
    test('win zählt je diag-Zeile neu, barge-end die ganze Sitzung', () {
      final saved = voiceLogSink;
      final lines = <String>[];
      voiceLogSink = lines.add;
      addTearDown(() => voiceLogSink = saved);
      final m = BargeMeter();
      m
        ..onWindow(0.1, 0.1)
        ..onWindow(0.1, 0.1)
        ..onWindow(0.1, 0.1)
        ..flush()
        ..onWindow(0.1, 0.1)
        ..flush()
        ..flush()
        ..summary();
      final win = [
        for (final l in lines)
          if (l.contains('barge-diag'))
            RegExp(r'win=(\d+)').firstMatch(l)!.group(1),
      ];
      expect(win, ['3', '1', '0']);
      expect(lines.last, contains('barge-end'));
      expect(lines.last, contains('win=4'));
    });
  });

  group('MicTail', () {
    test('take gibt den Vorlauf einmal her und leert ihn', () {
      final tail = MicTail()..add(Int16List.fromList([1, 2, 3]));
      expect(tail.take(), [1, 2, 3]);
      expect(tail.snapshot(), isEmpty);
      expect(tail.take(), isEmpty);
    });

    test('behält die letzten 2,4 s, TappedAudioInput füttert sie', () async {
      final tail = MicTail()..add(Int16List.fromList([9, 9]));
      final input = TappedAudioInput(
        FakeAudioInput(frames: [Int16List.fromList(List.filled(480, 7))]),
        tail,
      );
      await input.start().first;
      expect(
        tail.snapshot(),
        hasLength(480),
        reason: 'Rest der alten Aufnahme weg',
      );
      tail.add(Int16List(48000));
      expect(tail.snapshot(), hasLength(38400));
      tail.clear();
      expect(tail.snapshot(), isEmpty);
      await input.stop();
    });
  });
}
