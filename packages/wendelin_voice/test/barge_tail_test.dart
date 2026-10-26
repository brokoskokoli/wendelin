import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const frame = Duration(milliseconds: 30);

/// Samples of „speech“ level (the fake VAD threshold) in [pcm].
int loud(Int16List pcm) => pcm.where((s) => s.abs() > 1000).length;

final class _Agent implements AgentRun {
  final inputs = <String>[];

  @override
  Stream<AgentEvent> run(UserInput input) async* {
    inputs.add(input.text);
    yield const AgentTextDelta('Antwort.');
    yield const AgentDone(
      finalText: 'Antwort.',
      stopReason: StopReason.endTurn,
    );
  }

  @override
  void cancel() {}
}

/// A conversation: the first question, the answer, then the user speaks at
/// once (24 frames = 720 ms of speech from the end of the answer on) while
/// the follow-up microphone opens ~480 ms late and hears the last 8 frames.
final class W {
  W({
    bool tail = false,
    Duration idle = Duration.zero,
    int maxFollowUps = 1,
    DevClips? devClips,
  }) {
    audio = FakeAudioInput(
      frames: AudioFrames.pattern('.....${'S' * 20}${'.' * 30}', frame: frame),
      frameInterval: frame,
    );
    detector = FakeBargeInDetector(
      tail: tail ? AudioFrames.pattern('S' * 16, frame: frame) : null,
      tailIdle: idle,
    );
    stt = FakeSpeechToText([
      const Transcript(text: 'Eins'),
      const Transcript(text: 'Zwei'),
    ]);
    pipeline = VoicePipeline(
      audio: audio,
      vad: FakeVoiceActivityDetector(),
      stt: stt,
      agent: agent,
      textToSpeech: (_) async => FakeTextToSpeech(
        utteranceDuration: const Duration(milliseconds: 200),
      ),
      config: VoicePipelineConfig(
        conversationMode: true,
        bargeIn: BargeInMode.keywords,
        maxFollowUps: maxFollowUps,
      ),
      clock: FixedClock(DateTime.utc(2026, 10, 25, 9)),
      bargeInDetector: detector,
      diagnostics: diag.add,
    )..devClips = devClips;
  }

  late final FakeAudioInput audio;
  late final FakeBargeInDetector detector;
  late final FakeSpeechToText stt;
  late final VoicePipeline pipeline;
  final agent = _Agent();
  final diag = <String>[];

  void run(FakeAsync async) {
    pipeline.start();
    async.flushMicrotasks();
    // The later microphone: what the user says after the opening.
    audio.script(AudioFrames.pattern('${'S' * 8}${'.' * 40}', frame: frame));
    for (var i = 0; i < 2000 && agent.inputs.length < 2; i++) {
      async.elapse(const Duration(milliseconds: 10));
    }
  }
}

void main() {
  test('Sprache direkt nach Antwortende geht nicht verloren (WP146)', () {
    fakeAsync((async) {
      final w = W(tail: true)..run(async);
      expect(w.agent.inputs, ['Eins', 'Zwei']);
      // 24 frames of speech were spoken; at most the overlap (1 frame) and
      // the VAD edge may be missing.
      expect(loud(w.stt.pcms[1]), greaterThanOrEqualTo(22 * 480));
    });
  });

  test('Diagnose: Länge, Lücke, Kürzung, Pegel je Teil, nur Zahlen', () {
    fakeAsync((async) {
      final w = W(tail: true)..run(async);
      final line = w.diag.singleWhere((l) => l.startsWith('bridge-tail'));
      expect(line, matches(RegExp(r'^bridge-tail( \w+=(-?\d+|true|false))+$')));
      // 16 frames, first frame 30 ms, tail ended just now: 30 ms twice.
      expect(line, contains('ms=480 gap=-30 trim=30 silence=0'));
      expect(line, isNot(contains('tailDb=-99')));
      expect(line, contains('early=false'));
    });
  });

  test('Restlücke wird Stille, Überlappung gekürzt', () {
    fakeAsync((async) {
      final w = W(tail: true, idle: const Duration(milliseconds: 130))
        ..run(async);
      expect(
        w.diag.singleWhere((l) => l.startsWith('bridge-tail')),
        contains('gap=100 trim=0 silence=100'),
      );
    });
  });

  test('Tonaufnahme: Vorlauf, eingefügte Stille und Mikrofon in einer Datei (WP148)', () {
    fakeAsync((async) {
      final clips = <DevClip>[];
      final w = W(
        tail: true,
        idle: const Duration(milliseconds: 130),
        devClips: DevClips(enabled: () => true, write: clips.add),
      )..run(async);
      expect(w.agent.inputs, ['Eins', 'Zwei']);
      // Die Folgerunde ist die zweite Aufnahme.
      final rec = clips.where((c) => c.event == 'rec').toList()[1];
      final m = rec.marksMs;
      // Vorlauf (16 Frames, 30 ms gekürzt = 450 ms? hier 0 Kürzung) 480 ms,
      // dann 100 ms Stille, dann das Mikrofon.
      expect(m['tail'], 0);
      expect(m['silence'], 480);
      expect(m['mic'], 580);
      // Die eingefügte Stille ist wirklich Stille, der Vorlauf nicht.
      expect(rec.pcm.sublist(480 * 16, 580 * 16).every((s) => s == 0), isTrue);
      expect(loud(rec.pcm.sublist(0, 480 * 16)), greaterThan(0));
      expect(rec.pcm.length, greaterThan(580 * 16));
    });
  });

  test('Eine Lücke über der Grenze ist keine Übergabelücke: keine Stille', () {
    fakeAsync((async) {
      final w = W(tail: true, idle: const Duration(seconds: 2))..run(async);
      final line = w.diag.singleWhere((l) => l.startsWith('bridge-tail'));
      expect(line, contains('silence=0'));
      expect(line, contains('trim=0'));
    });
  });

  test(
    'Ohne Vorlauf (Detektor lehnt ab): Detektor wird wie bisher gestoppt',
    () {
      fakeAsync((async) {
        final w = W()..run(async);
        async.elapse(const Duration(seconds: 30));
        expect(w.diag.where((l) => l.startsWith('bridge-tail')), [
          'bridge-tail got=none',
        ]);
        expect(w.detector.tailBegun, 0);
        expect(w.detector.isRunning, isFalse);
        expect(loud(w.stt.pcms[1]), lessThan(10 * 480));
      });
    },
  );

  test('Nach der letzten Runde läuft nichts weiter (keine Folgerunde)', () {
    fakeAsync((async) {
      final w = W(tail: true, maxFollowUps: 0)..pipeline.start();
      async.elapse(const Duration(seconds: 30));
      expect(w.detector.tailBegun, 0);
      expect(w.detector.isRunning, isFalse);
    });
  });

  test('Abbruch vor dem ersten Frame (Tap): keine zweite Aufnahme bleibt', () {
    fakeAsync((async) {
      final w = W(tail: true)..pipeline.start();
      async.flushMicrotasks();
      // The follow-up microphone never delivers (no frames, no end).
      w.audio.script(const []);
      for (var i = 0; i < 2000 && w.detector.tailBegun == 0; i++) {
        async.elapse(const Duration(milliseconds: 10));
      }
      expect(w.detector.isTailing, isTrue);
      w.pipeline.cancel();
      async.elapse(const Duration(seconds: 1));
      expect(w.detector.isTailing, isFalse);
      expect(w.detector.isRunning, isFalse);
    });
  });

  test('Mikrofonfehler der Folgeaufnahme: der Vorlauf wird beendet', () {
    fakeAsync((async) {
      final w = W(tail: true)..pipeline.start();
      async.flushMicrotasks();
      w.audio.script(const []);
      for (var i = 0; i < 2000 && !w.detector.isTailing; i++) {
        async.elapse(const Duration(milliseconds: 10));
      }
      expect(w.detector.isTailing, isTrue);
      // The follow-up microphone is open (no frame yet) and fails.
      for (var i = 0; i < 200 && w.audio.startCount < 2; i++) {
        async.elapse(const Duration(milliseconds: 10));
      }
      w.audio.fail(StateError('Mikrofon weg'));
      async.elapse(const Duration(seconds: 1));
      expect(w.detector.isTailing, isFalse);
      expect(w.detector.tailEnded, 1, reason: 'über endTail, nicht stop');
      expect(w.detector.isRunning, isFalse);
    });
  });

  test(
    'Abbruch während der Antwort der Folgerunde: Detektor wird gestoppt',
    () {
      fakeAsync((async) {
        final w = W(tail: true)..pipeline.start();
        async.flushMicrotasks();
        w.audio.script(
          AudioFrames.pattern('${'S' * 8}${'.' * 40}', frame: frame),
        );
        // Until the answer of the follow-up round is read aloud.
        for (var i = 0; i < 2000 && w.agent.inputs.length < 2; i++) {
          async.elapse(const Duration(milliseconds: 10));
        }
        for (
          var i = 0;
          i < 200 && w.pipeline.state != VoiceState.speaking;
          i++
        ) {
          async.elapse(const Duration(milliseconds: 5));
        }
        expect(w.pipeline.state, VoiceState.speaking);
        expect(w.detector.tailBegun, 1);
        w.pipeline.cancel();
        async.elapse(const Duration(seconds: 5));
        expect(w.detector.tailBegun, 1, reason: 'keine zweite Folgeaufnahme');
        expect(w.detector.isTailing, isFalse);
        expect(w.detector.isRunning, isFalse);
      });
    },
  );
}
