// WP146: Der Barge-in-Detektor nimmt nach der Antwort weiter auf, sammelt das
// Audio ab `beginTail` und gibt es beim ersten Frame der Folgeaufnahme ab.
// Danach, bei `stop` und nach `tailMax` läuft keine zweite Aufnahme mehr.
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

final class _NoHits implements WakeWordEngine {
  int frames = 0;

  @override
  Future<void> open(List<KeywordSpec> keywords) async {}

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    frames++;
    return const [];
  }

  @override
  void reset() {}

  @override
  Future<void> close() async {}
}

/// A microphone whose recording can be detached; counts the ends.
final class _Mic implements DetachableAudioInput {
  StreamController<Int16List>? current;
  final detached = <StreamController<Int16List>>[];
  int detachedEnds = 0, stops = 0;
  bool refuse = false;

  @override
  bool get isRunning => current != null;

  @override
  Stream<Int16List> start() {
    // onCancel: the cancel future belongs to the fake zone.
    current = StreamController<Int16List>(onCancel: Future<void>.value);
    return current!.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    final done = current?.close();
    current = null;
    await done;
  }

  @override
  Future<void> Function()? detach() {
    final c = current;
    if (c == null || refuse) return null;
    current = null;
    detached.add(c);
    return () async {
      detachedEnds++;
      await c.close();
    };
  }

  void push(StreamController<Int16List> c, int value, [int n = 480]) =>
      c.add(Int16List(n)..fillRange(0, n, value));
}

final class _HeldVerifier implements BargeVerifier {
  final hold = Completer<void>();

  @override
  Future<BargeVerdict> verify(
    Int16List pcm, {
    required BargeInKeyword candidate,
  }) async {
    await hold.future;
    return const BargeVerdict('wake', BargeInKeyword.wake);
  }
}

void main() {
  late _Mic mic;
  late FixedClock clock;
  late WakeWordBargeInDetector detector;

  // Built inside `fakeAsync`: the futures of the detector belong to its zone.
  void fake(void Function(FakeAsync async) body) => fakeAsync((async) {
    mic = _Mic();
    clock = FixedClock(DateTime.utc(2026, 10, 25, 9));
    detector = WakeWordBargeInDetector(
      audio: mic,
      engine: _NoHits(),
      clock: clock,
    );
    body(async);
  });

  test(
    'sammelt ab beginTail, gibt es mit der Ruhezeit ab, beendet die Aufnahme',
    () {
      fake((async) {
        detector.start();
        async.flushMicrotasks();
        final first = mic.current!;
        mic.push(first, 1);
        async.flushMicrotasks();
        expect(detector.beginTail(), isTrue);
        expect(mic.isRunning, isFalse, reason: 'die Eingabe ist frei');
        mic.push(first, 7);
        clock.advance(const Duration(milliseconds: 30));
        mic.push(first, 8);
        async.flushMicrotasks();
        clock.advance(const Duration(milliseconds: 50));
        final tail = detector.endTail()!;
        async.flushMicrotasks();
        expect(tail.pcm.length, 960);
        expect(tail.pcm.first, 7, reason: 'nichts von vor beginTail');
        expect(tail.pcm.last, 8);
        expect(tail.idle, const Duration(milliseconds: 50));
        expect(mic.detachedEnds, 1);
        expect(mic.stops, 0, reason: 'die neue Aufnahme bleibt unberührt');
        expect(detector.isRunning, isFalse);
        expect(detector.endTail(), isNull, reason: 'nur einmal');
      });
    },
  );

  test('beginTail verwirft die laufende Gegenprüfung (kein Signal danach)', () {
    fakeAsync((async) {
      mic = _Mic();
      final verifier = _HeldVerifier();
      final got = <String>[];
      final d = WakeWordBargeInDetector(
        audio: mic,
        engine: FakeWakeWordEngine(keywordId: 'wake', hitAtFrame: const {}),
        verifier: verifier,
        settle: Duration.zero,
        verifyTimeout: const Duration(seconds: 6),
      );
      d.signals.listen((s) => got.add(s.code));
      d.start();
      async.flushMicrotasks();
      final first = mic.current!;
      first.add(FakeWakeWordEngine.markerFrame());
      async.flushMicrotasks();
      expect(d.beginTail(), isTrue);
      verifier.hold.complete();
      async.flushMicrotasks();
      expect(got, isEmpty, reason: 'die Antwort ist vorbei, kein Abbruch mehr');
      d.endTail();
      d.dispose();
      unawaited(first.close());
      async.flushMicrotasks();
    });
  });

  test(
    'Eingabe ohne Ablösen: beginTail lehnt ab (dann stoppt der Aufrufer)',
    () {
      fake((async) {
        mic.refuse = true;
        detector.start();
        async.flushMicrotasks();
        expect(detector.beginTail(), isFalse);
        expect(detector.isRunning, isTrue);
      });
    },
  );

  test('ohne Lauf kein beginTail', () {
    fake((async) {
      expect(detector.beginTail(), isFalse);
      expect(detector.endTail(), isNull);
    });
  });

  test('stop während des Sammelns beendet die abgelöste Aufnahme', () {
    fake((async) {
      detector.start();
      async.flushMicrotasks();
      detector.beginTail();
      detector.stop();
      async.flushMicrotasks();
      expect(mic.detachedEnds, 1);
      expect(detector.isRunning, isFalse);
      expect(detector.endTail(), isNull, reason: 'nichts übrig');
    });
  });

  test('ohne erstes Frame endet die Aufnahme nach tailMax von selbst', () {
    fake((async) {
      detector.start();
      async.flushMicrotasks();
      detector.beginTail();
      async.elapse(detector.tailMax - const Duration(milliseconds: 1));
      expect(mic.detachedEnds, 0);
      async.elapse(const Duration(milliseconds: 2));
      expect(mic.detachedEnds, 1);
      expect(detector.isRunning, isFalse);
    });
  });

  test('beginTail macht offene Kandidaten ungültig: kein Signal', () {
    fake((async) {
      final signals = <BargeInSignal>[];
      detector.signals.listen(signals.add);
      detector.start();
      async.flushMicrotasks();
      detector.beginTail();
      mic.push(mic.detached.single, 9);
      async.flushMicrotasks();
      expect(signals, isEmpty);
    });
  });
}
