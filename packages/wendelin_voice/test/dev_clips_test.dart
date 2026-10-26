// WP148: Tonaufnahmen im Entwicklermodus, Seite des Sprachkerns. Alle Audiodaten
// sind synthetisch (fortlaufende Zähler, damit Offsets sample-genau prüfbar sind).
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Frame mit fortlaufenden Werten ab [from] (30 ms = 480 Samples).
Int16List counting(int from, [int n = 480]) =>
    Int16List.fromList([for (var i = 0; i < n; i++) (from + i) % 30000]);

final class _Sink {
  _Sink({this.on = true});
  bool on;
  final clips = <DevClip>[];
  late final hook = DevClips(enabled: () => on, write: clips.add);
  DevClip byEvent(String e) => clips.singleWhere((c) => c.event == e);
}

int ms(int samples) => samplesToDuration(samples).inMilliseconds;

void main() {
  group('DevAround', () {
    test('vorher + nachher, Marken stimmen mit der Samplezahl überein', () {
      final a = DevAround(
        event: 'x',
        before: counting(0, 1000),
        already: counting(1000, 100),
        afterWanted: 400,
        at: DateTime(2026),
      );
      expect(a.complete, isFalse);
      expect(a.add(counting(1100, 200)), isFalse);
      expect(a.add(counting(1300, 200)), isTrue); // 500 >= 400
      final c = a.build();
      expect(c.pcm.length, 1000 + 400);
      expect(c.marksMs, {'cand': ms(1000), 'post': ms(400)});
      for (var i = 0; i < c.pcm.length; i++) {
        expect(c.pcm[i], i, reason: 'lückenlos bei $i');
      }
    });

    test('abgebrochen: nur was da ist, "post" nennt es ehrlich', () {
      final a = DevAround(
        event: 'x',
        before: counting(0, 1600),
        afterWanted: 32000,
      )..add(counting(1600, 800));
      final c = a.build();
      expect(c.pcm.length, 2400);
      expect(c.marksMs['cand'], 100);
      expect(c.marksMs['post'], 50);
    });
  });

  group('DevAroundSet', () {
    test('aus: nichts wird angelegt oder gesammelt', () {
      final sink = _Sink(on: false);
      final set = DevAroundSet(sink.hook);
      var made = 0;
      set.start(() {
        made++;
        return DevAround(event: 'x', before: Int16List(1), afterWanted: 1);
      });
      set
        ..feed(Int16List(10))
        ..flush();
      expect(made, 0);
      expect(sink.clips, isEmpty);
    });

    test(
      'Prüfung wirft: gilt als aus; Schreiben wirft: Sprachpfad bleibt ok',
      () {
        final broken = DevClips(
          enabled: () => throw StateError('x'),
          write: (_) {},
        );
        expect(broken.on, isFalse);
        final failing = DevClips(
          enabled: () => true,
          write: (_) => throw StateError('disk'),
        );
        expect(
          () => failing.emit(
            DevClip(event: 'x', pcm: Int16List(1), at: DateTime(2026)),
          ),
          returnsNormally,
        );
      },
    );

    test('höchstens $maxOpenForTest gleichzeitig', () {
      final sink = _Sink();
      final set = DevAroundSet(sink.hook);
      for (var i = 0; i < 10; i++) {
        set.start(
          () => DevAround(event: 'x', before: Int16List(1), afterWanted: 10),
        );
      }
      set.flush();
      expect(sink.clips, hasLength(DevAroundSet.maxOpen));
    });
  });

  group('WakeWordListener', () {
    late FakeAudioInput audio;
    late _Sink sink;
    late WakeWordListener listener;

    Future<void> setUpListener({bool on = true}) async {
      sink = _Sink(on: on);
      audio = FakeAudioInput();
      listener = WakeWordListener(
        audio: audio,
        // Treffer in Frame 99: Ende bei Sample 48000 (3 s).
        engine: FakeWakeWordEngine(hitAtFrame: {99}),
        verifier: FakeWakeVerifier(),
        verifyTail: Duration.zero,
        devClips: sink.hook,
      );
      await listener.start();
    }

    Future<void> feed(int frames, {int from = 0}) async {
      for (var i = 0; i < frames; i++) {
        audio.push(counting((from + i) * 480));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    tearDown(() => listener.dispose());

    test('Kandidat: 2 s davor, 2 s danach, sample-genau; Prüf-Ausschnitt gesondert', () async {
      await setUpListener();
      await feed(100); // bis zum Treffer
      expect(sink.clips.map((c) => c.event), ['wake-verify']);
      await feed(70, from: 100); // mehr als 2 s danach
      final cand = sink.byEvent('wake-cand');
      // 2 s vor dem Ende bei 48000 + 2 s danach.
      expect(cand.pcm.length, 64000);
      expect(cand.marksMs, {'cand': 2000, 'post': 2000});
      expect(cand.pcm.first, 16000);
      for (var i = 1; i < cand.pcm.length; i++) {
        expect(cand.pcm[i], (16000 + i) % 30000, reason: 'Lücke bei $i');
      }
      // Die Prüfung bekam genau diesen Ausschnitt (höchstens 2 s vor dem Treffer).
      final v = sink.byEvent('wake-verify');
      expect(v.pcm.last, 47999 % 30000);
      expect(v.marksMs['wakeEnd'], ms(v.pcm.length));
    });

    test(
      'Pause vor Ablauf der 2 s: Datei kürzer, "post" sagt wie viel',
      () async {
        await setUpListener();
        await feed(110); // 10 Frames = 300 ms nach dem Treffer
        await listener.pause();
        final cand = sink.byEvent('wake-cand');
        expect(cand.marksMs['post'], 300);
        expect(cand.pcm.length, 32000 + 4800);
        expect(cand.marksMs['cand'], 2000);
      },
    );

    test('Entwicklermodus aus: nichts gesammelt, nichts ausgegeben', () async {
      await setUpListener(on: false);
      await feed(175);
      await listener.pause();
      expect(sink.clips, isEmpty);
      expect(listener.stats.candidates, 1);
    });
  });

  group('WakeWordBargeInDetector', () {
    late FakeAudioInput audio;
    late _Sink sink;
    late WakeWordBargeInDetector d;
    final seen = <Int16List>[];

    Future<void> setUpDetector({bool on = true}) async {
      sink = _Sink(on: on);
      seen.clear();
      audio = FakeAudioInput();
      d = WakeWordBargeInDetector(
        audio: audio,
        engine: FakeWakeWordEngine(),
        verifier: _Recorder(seen),
        settle: Duration.zero,
        cooldown: const Duration(seconds: 100),
        devClips: sink.hook,
      );
      await d.start();
    }

    Future<void> loud(int n) async {
      for (var i = 0; i < n; i++) {
        audio.push(Int16List(1600)..fillRange(0, 1600, 5000));
      }
      await pumpEventQueue();
    }

    tearDown(() => d.dispose());

    test(
      'Kandidat ±2 s und Prüf-Ausschnitt gesondert, Länge = Samples',
      () async {
        await setUpDetector();
        await loud(30); // 3 s
        audio.push(FakeWakeWordEngine.markerFrame(1600));
        await pumpEventQueue();
        await loud(25); // 2,5 s danach
        final cand = sink.byEvent('barge-cand');
        expect(cand.pcm.length, 32000 + 32000);
        expect(cand.marksMs, {'cand': 2000, 'post': 2000});
        // Der Kandidat selbst (Marker-Frame) liegt am Ende des "vorher"-Teils.
        expect(
          cand.pcm.sublist(32000 - 1600, 32000),
          FakeWakeWordEngine.markerFrame(1600),
        );
        // Der Prüfer bekam genau das, was als barge-verify liegt.
        final verify = sink.byEvent('barge-verify');
        expect(seen, hasLength(1));
        expect(verify.pcm, seen.single);
        expect(verify.pcm.length, lessThanOrEqualTo(40000));
        expect(verify.marksMs['speechEnd'], greaterThan(0));
      },
    );

    test('Stopp vor Ablauf: Datei kürzer, ehrlich markiert', () async {
      await setUpDetector();
      await loud(30);
      audio.push(FakeWakeWordEngine.markerFrame(1600));
      await pumpEventQueue();
      await loud(5);
      await d.stop();
      final cand = sink.byEvent('barge-cand');
      expect(cand.marksMs['post'], 500);
      expect(cand.pcm.length, 32000 + 8000);
    });

    test('Entwicklermodus aus: weder Kandidat noch Prüf-Ausschnitt', () async {
      await setUpDetector(on: false);
      await loud(30);
      audio.push(FakeWakeWordEngine.markerFrame(1600));
      await pumpEventQueue();
      await loud(25);
      await d.stop();
      expect(sink.clips, isEmpty);
      expect(seen, hasLength(1)); // die Erkennung selbst läuft wie immer
    });
  });
}

const maxOpenForTest = DevAroundSet.maxOpen;

final class _Recorder implements BargeVerifier {
  _Recorder(this.seen);
  final List<Int16List> seen;

  @override
  Future<BargeVerdict> verify(
    Int16List pcm, {
    required BargeInKeyword candidate,
  }) async {
    seen.add(Int16List.fromList(pcm));
    return BargeVerdict.no;
  }
}
