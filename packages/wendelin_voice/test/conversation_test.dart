import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const frame = Duration(milliseconds: 30);

List<Int16List> utterance() =>
    AudioFrames.pattern('${'.' * 5}${'S' * 20}${'.' * 30}', frame: frame);

/// Plays one scripted answer per run (the last one repeats).
final class ScriptedAgent implements AgentRun {
  ScriptedAgent(this.answers, {this.step = Duration.zero});

  final List<List<AgentEvent>> answers;
  final Duration step;
  final inputs = <String>[];

  @override
  Stream<AgentEvent> run(UserInput input) async* {
    final i = inputs.length < answers.length
        ? inputs.length
        : answers.length - 1;
    inputs.add(input.text);
    for (final e in answers[i]) {
      await Future<void>.delayed(step);
      yield e;
    }
  }

  @override
  void cancel() {}
}

List<AgentEvent> say(String text) => [
  AgentTextDelta(text),
  AgentDone(finalText: text, stopReason: StopReason.endTurn),
];

final class H {
  H({
    List<String> transcripts = const ['Eins'],
    List<List<AgentEvent>>? answers,
    VoicePipelineConfig config = const VoicePipelineConfig(
      conversationMode: true,
    ),
    bool manualTts = false,
    this.withDetector = true,
    Duration agentStep = Duration.zero,
    Duration detectorStartDelay = Duration.zero,
    Duration detectorStopDelay = Duration.zero,
    bool detectorUsesMic = false,
    bool detectorHangs = false,
  }) : agent = ScriptedAgent(answers ?? [say('Antwort.')], step: agentStep),
       tts = FakeTextToSpeech(
         utteranceDuration: const Duration(milliseconds: 200),
         manual: manualTts,
       ),
       stt = FakeSpeechToText([
         for (final t in transcripts) Transcript(text: t),
       ]),
       audio = FakeAudioInput(frames: utterance(), frameInterval: frame) {
    detector = FakeBargeInDetector(
      startDelay: detectorStartDelay,
      stopDelay: detectorStopDelay,
      audio: detectorUsesMic ? audio : null,
      hangOnStop: detectorHangs,
    );
    pipeline = VoicePipeline(
      audio: audio,
      vad: FakeVoiceActivityDetector(),
      stt: stt,
      agent: agent,
      textToSpeech: (_) async => tts,
      config: config,
      clock: FixedClock(DateTime.utc(2026, 10, 14, 9)),
      bargeInDetector: withDetector ? detector : null,
      diagnostics: diag.add,
    );
    pipeline.events.listen(events.add);
    pipeline.states.listen(states.add);
  }

  final bool withDetector;
  final ScriptedAgent agent;
  final FakeTextToSpeech tts;
  final FakeSpeechToText stt;
  final FakeAudioInput audio;
  late final FakeBargeInDetector detector;
  late final VoicePipeline pipeline;
  final diag = <String>[];
  final events = <VoiceEvent>[];
  final states = <VoiceState>[];

  List<ConversationEndReason> get ends => [
    for (final e in events.whereType<VoiceConversationEnded>()) e.reason,
  ];

  /// Silence for every later recording (the first one hears the question).
  void silenceAfterFirst(FakeAsync async) {
    async.flushMicrotasks();
    audio.script(AudioFrames.pattern('.' * 400, frame: frame));
  }

  void until(FakeAsync async, bool Function() cond) {
    for (var i = 0; i < 2000 && !cond(); i++) {
      async.elapse(const Duration(milliseconds: 10));
    }
    expect(cond(), isTrue, reason: 'Bedingung nicht erreicht');
  }
}

void main() {
  group('Endebedingungen des Gesprächsmodus (genau ein Grundcode)', () {
    void table(
      String name,
      ConversationEndReason expected,
      H Function() make, {
      void Function(H h, FakeAsync async)? during,
    }) {
      test('$name -> ${expected.name}', () {
        fakeAsync((async) {
          final h = make();
          h.pipeline.start();
          if (during != null) {
            during(h, async);
          } else {
            h.silenceAfterFirst(async);
          }
          async.elapse(const Duration(seconds: 30));
          expect(h.ends, [expected]);
          expect(h.pipeline.state, VoiceState.idle);
          expect(h.audio.isRunning, isFalse);
        });
      });
    }

    table('Stille im Fenster', ConversationEndReason.silence, H.new);
    table(
      'Stopp',
      ConversationEndReason.stopWord,
      () => H(transcripts: ['Eins', 'Stopp bitte']),
      during: (h, async) {},
    );
    table(
      'Danke',
      ConversationEndReason.closingPhrase,
      () => H(transcripts: ['Eins', 'Danke, das war’s']),
      during: (h, async) {},
    );
    table(
      'Tipp im Fenster',
      ConversationEndReason.tap,
      H.new,
      during: (h, async) {
        h.silenceAfterFirst(async);
        h.until(async, () => h.events.any((e) => e is VoiceFollowUpListening));
        h.pipeline.cancel();
      },
    );
    table(
      'offene Bestätigungskarte',
      ConversationEndReason.confirmation,
      () => H(
        answers: [
          [
            ConfirmationRequired(
              call: const ToolCallBlock(
                id: '1',
                name: 'sms__send',
                argumentsJson: '{}',
              ),
              description: 'SMS senden?',
              respond: (_) {},
            ),
            const AgentDone(finalText: '', stopReason: StopReason.endTurn),
          ],
        ],
      ),
      during: (h, async) {},
    );
    table(
      'Höchstzahl an Folgerunden',
      ConversationEndReason.maxFollowUps,
      () => H(
        transcripts: ['Eins', 'Zwei', 'Drei', 'Vier'],
        config: const VoicePipelineConfig(
          conversationMode: true,
          maxFollowUps: 2,
        ),
      ),
      during: (h, async) {},
    );
    table(
      'Fehler des Agenten',
      ConversationEndReason.error,
      () => H(
        answers: [
          [
            const AgentFailed(
              error: AgentErrorKind.provider,
              message: 'kaputt',
            ),
          ],
        ],
      ),
      during: (h, async) {},
    );
    table(
      'Rote Quittung',
      ConversationEndReason.error,
      () => H(
        answers: [
          [
            const AgentTextDelta('Antwort.'),
            const AttestationStatusChanged(
              stepId: 's:1',
              status: AttestationStatus.red,
              logId: 'att-1',
            ),
            const AgentDone(finalText: 'x', stopReason: StopReason.endTurn),
          ],
        ],
      ),
      during: (h, async) {},
    );
    test('AgentTextComplete wird als answer-complete protokolliert', () {
      fakeAsync((async) {
        final h = H(
          answers: [
            [const AgentTextDelta('Antwort.'), const AgentTextComplete()],
          ],
        );
        h.pipeline.start();
        async.elapse(const Duration(seconds: 5));
        expect(h.diag, contains('answer-complete'));
      });
    });
    table(
      'TTS-Fehler',
      ConversationEndReason.error,
      () => H()..tts.nextError = StateError('tts'),
      during: (h, async) {},
    );
    table(
      'Mikrofonfehler im Fenster',
      ConversationEndReason.error,
      H.new,
      during: (h, async) {
        h.silenceAfterFirst(async);
        h.until(async, () => h.events.any((e) => e is VoiceFollowUpListening));
        h.audio.fail(StateError('mic'));
      },
    );

    test('nach dem Ende keine ausstehenden Timer', () {
      fakeAsync((async) {
        final h = H()..pipeline.start();
        h.silenceAfterFirst(async);
        h.until(async, () => h.ends.isNotEmpty);
        expect(h.ends, [ConversationEndReason.silence]);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('Höchstzahl: 1 Frage + maxFollowUps Folgefragen', () {
      fakeAsync((async) {
        final h = H(
          transcripts: ['Eins', 'Zwei', 'Drei', 'Vier'],
          config: const VoicePipelineConfig(
            conversationMode: true,
            maxFollowUps: 2,
          ),
        )..pipeline.start();
        async.elapse(const Duration(seconds: 30));
        expect(h.agent.inputs, ['Eins', 'Zwei', 'Drei']);
        expect(
          h.events.whereType<VoiceConversationEnded>().single.followUps,
          2,
        );
      });
    });

    test('Danke mit weiterer Frage ist keine Abschlussphrase', () {
      fakeAsync((async) {
        final h = H(transcripts: ['Eins', 'Danke, wie spät ist es?'])
          ..pipeline.start();
        async.elapse(const Duration(seconds: 30));
        expect(h.agent.inputs.last, 'Danke, wie spät ist es?');
      });
    });

    test('Abschlussphrase gilt nur im Fenster, nicht als erste Äußerung', () {
      fakeAsync((async) {
        final h = H(transcripts: ['Danke'])..pipeline.start();
        async.elapse(const Duration(seconds: 30));
        expect(h.agent.inputs, ['Danke']);
      });
    });

    test('Diagnose ohne Inhalte', () {
      fakeAsync((async) {
        final h = H(transcripts: ['Geheim', 'Stopp'])..pipeline.start();
        async.elapse(const Duration(seconds: 30));
        final end = h.events.whereType<VoiceConversationEnded>().single;
        expect(end.diagnostic, 'conv-exit reason=stopWord');
      });
    });

    test('Modus aus: keine Gesprächsereignisse', () {
      fakeAsync((async) {
        final h = H(config: const VoicePipelineConfig())..pipeline.start();
        async.elapse(const Duration(seconds: 30));
        expect(h.ends, isEmpty);
        expect(h.events.whereType<VoiceFollowUpListening>(), isEmpty);
        expect(h.audio.startCount, 1);
      });
    });
  });

  group('Folgefenster', () {
    test('Folgefrage im Fenster ist eine neue Anfrage, danach Ruhe', () {
      fakeAsync((async) {
        final h = H(transcripts: ['Eins', 'Zwei'])..pipeline.start();
        h.until(async, () => h.agent.inputs.length == 2);
        final window = h.events.whereType<VoiceFollowUpListening>().first;
        expect(window.window, const Duration(seconds: 5));
        h.silenceAfterFirst(async);
        async.elapse(const Duration(seconds: 30));
        expect(h.agent.inputs, ['Eins', 'Zwei']);
        expect(h.pipeline.state, VoiceState.idle);
        expect(h.audio.isRunning, isFalse);
        final startsAfter = h.audio.startCount;
        async.elapse(const Duration(seconds: 30));
        expect(h.audio.startCount, startsAfter);
      });
    });
  });

  group('Barge-in', () {
    H speaking(
      FakeAsync async, {
      BargeInMode mode = BargeInMode.keywords,
      bool conversation = false,
    }) {
      final h = H(
        manualTts: true,
        transcripts: ['Eins', 'Zwei'],
        config: VoicePipelineConfig(
          bargeIn: mode,
          conversationMode: conversation,
        ),
      )..pipeline.start();
      h.until(async, () => h.pipeline.state == VoiceState.speaking);
      return h;
    }

    test('WP113: der Detektor erfährt den vorgelesenen Satz (Eigen-Echo)', () {
      fakeAsync((async) {
        final h = speaking(async);
        expect(h.detector.spoken, ['Antwort.']);
      });
    });

    test('Detektor läuft nur während der Ausgabe', () {
      fakeAsync((async) {
        final h = speaking(async);
        expect(h.detector.isRunning, isTrue);
        h.tts.completeCurrent();
        async.elapse(const Duration(seconds: 1));
        expect(h.pipeline.state, VoiceState.idle);
        expect(h.detector.isRunning, isFalse);
        expect(h.detector.startCount, 1);
      });
    });

    test('Stopp-Signal: Queue sofort gestoppt, Anfrage beendet', () {
      fakeAsync((async) {
        final h = speaking(async, conversation: true);
        h.detector.emit(const BargeInSignal.keyword(BargeInKeyword.stop));
        // No time has passed: the engine was stopped synchronously.
        expect(h.tts.stops, 1);
        expect(h.tts.interrupted, ['Antwort.']);
        async.flushMicrotasks();
        expect(h.pipeline.state, VoiceState.idle);
        final bi = h.events.whereType<VoiceBargeIn>().single;
        expect(bi.diagnostic, 'barge-in kind=keyword-stop');
        expect(
          h.events.whereType<VoiceCancelled>().single.reason,
          VoiceCancelReason.stopWord,
        );
        expect(h.ends, [ConversationEndReason.stopWord]);
        async.elapse(const Duration(seconds: 30));
        expect(h.agent.inputs, ['Eins']); // no new request
        expect(h.audio.startCount, 1);
      });
    });

    test('Wake-Signal: Queue gestoppt, neues Zuhören mit Pre-Roll', () {
      fakeAsync((async) {
        final h = speaking(async, conversation: true);
        final preRoll = AudioFrames.speech(const Duration(milliseconds: 240));
        h.detector.emit(
          BargeInSignal.keyword(BargeInKeyword.wake, preRoll: preRoll),
        );
        expect(h.tts.stops, 1);
        expect(h.pipeline.state, VoiceState.listening);
        async.elapse(const Duration(seconds: 2));
        final listening = h.events.whereType<VoiceListening>().last;
        expect(listening.trigger?.source, TriggerKind.wakeWord);
        expect(
          h.events.whereType<VoiceCancelled>().single.reason,
          VoiceCancelReason.bargeIn,
        );
        expect(h.ends, isEmpty); // the conversation goes on
        // The second utterance contains the pre-roll (240 ms = 3840 samples
        // more than the 300 ms pre-roll alone would give).
        expect(h.stt.calls, hasLength(2));
        expect(h.stt.calls[1].samples, greaterThan(h.stt.calls[0].samples));
        h.until(async, () => h.agent.inputs.length == 2);
        expect(h.agent.inputs, ['Eins', 'Zwei']);
      });
    });

    test('Signale außerhalb von speaking werden ignoriert', () {
      fakeAsync((async) {
        final h = H(
          manualTts: true,
          config: const VoicePipelineConfig(bargeIn: BargeInMode.keywords),
        );
        h.detector.start();
        async.flushMicrotasks();
        const stop = BargeInSignal.keyword(BargeInKeyword.stop);
        h.detector.emit(stop); // idle
        h.pipeline.start();
        h.detector.emit(stop); // listening
        expect(h.pipeline.state, VoiceState.listening);
        h.stt.hold = true;
        h.until(async, () => h.pipeline.state == VoiceState.transcribing);
        h.detector.emit(stop); // transcribing
        expect(h.pipeline.state, VoiceState.transcribing);
        expect(h.events.whereType<VoiceBargeIn>(), isEmpty);
        expect(h.tts.stops, 0);
      });
    });

    test('keywords ignoriert freie Sprache, off ignoriert alles', () {
      fakeAsync((async) {
        final h = speaking(async);
        h.detector.emit(const BargeInSignal.speech());
        expect(h.tts.stops, 0);
        expect(h.pipeline.state, VoiceState.speaking);

        final off = speaking(async, mode: BargeInMode.off);
        off.detector.start();
        async.flushMicrotasks();
        off.detector.emit(const BargeInSignal.keyword(BargeInKeyword.stop));
        expect(off.tts.stops, 0);
        expect(off.pipeline.state, VoiceState.speaking);
        expect(off.detector.startCount, 1); // started by hand only
      });
    });

    test('speech-Modus: freie Sprache hört neu zu', () {
      fakeAsync((async) {
        final h = speaking(async, mode: BargeInMode.speech);
        h.detector.emit(const BargeInSignal.speech());
        expect(h.tts.stops, 1);
        expect(h.pipeline.state, VoiceState.listening);
        expect(
          h.events.whereType<VoiceBargeIn>().single.diagnostic,
          'barge-in kind=speech',
        );
      });
    });

    test('Detektor-Startfehler wird gemeldet, Ausgabe läuft weiter', () {
      fakeAsync((async) {
        final h = H(
          manualTts: true,
          config: const VoicePipelineConfig(bargeIn: BargeInMode.keywords),
        );
        h.detector.startError = StateError('mic');
        h.pipeline.start();
        h.until(async, () => h.pipeline.state == VoiceState.speaking);
        async.flushMicrotasks();
        expect(h.events.whereType<VoiceError>(), hasLength(1));
        h.tts.completeCurrent();
        async.elapse(const Duration(seconds: 1));
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('Tipp im Spalt eines ausstehenden Starts: Detektor aus', () {
      fakeAsync((async) {
        final h = H(
          manualTts: true,
          detectorStartDelay: const Duration(milliseconds: 500),
          config: const VoicePipelineConfig(bargeIn: BargeInMode.keywords),
        )..pipeline.start();
        h.until(async, () => h.pipeline.state == VoiceState.speaking);
        expect(h.detector.isRunning, isFalse); // start still pending
        h.pipeline.cancel();
        async.elapse(const Duration(seconds: 2));
        expect(h.pipeline.state, VoiceState.idle);
        expect(h.detector.isRunning, isFalse);
      });
    });

    test('dispose kündigt das Signal-Abonnement', () {
      fakeAsync((async) {
        final h = speaking(async);
        expect(h.detector.hasListeners, isTrue);
        h.pipeline.dispose();
        async.flushMicrotasks();
        expect(h.detector.hasListeners, isFalse);
      });
    });

    test('speaking -> thinking -> speaking: Detektor bleibt, Signal wirkt', () {
      fakeAsync((async) {
        final h = H(
          manualTts: true,
          agentStep: const Duration(seconds: 1),
          answers: [
            [
              const AgentTextDelta('Erster Satz. '),
              const AgentTextDelta('Zweiter Satz.'),
              const AgentDone(
                finalText: 'Erster Satz. Zweiter Satz.',
                stopReason: StopReason.endTurn,
              ),
            ],
          ],
          config: const VoicePipelineConfig(bargeIn: BargeInMode.keywords),
        )..pipeline.start();
        h.until(async, () => h.pipeline.state == VoiceState.speaking);
        h.tts.completeCurrent();
        h.until(async, () => h.pipeline.state == VoiceState.thinking);
        expect(h.detector.isRunning, isTrue);
        h.until(async, () => h.pipeline.state == VoiceState.speaking);
        expect(h.detector.isRunning, isTrue);
        expect(h.detector.startCount, 1);
        h.detector.emit(const BargeInSignal.keyword(BargeInKeyword.stop));
        async.flushMicrotasks();
        expect(h.events.whereType<VoiceBargeIn>(), hasLength(1));
        expect(h.pipeline.state, VoiceState.idle);
        expect(h.detector.isRunning, isFalse);
      });
    });

    // WP64: on the device the detector holds the microphone while the answer
    // is spoken. The follow-up recording must wait until it is released
    // (before: "Bad state: Die Aufnahme läuft bereits.").
    for (final stopDelay in [Duration.zero, const Duration(milliseconds: 80)]) {
      test('Folgefenster nach der Ausgabe: Mikrofon frei '
          '(Detektor stoppt in ${stopDelay.inMilliseconds} ms)', () {
        fakeAsync((async) {
          final h = H(
            transcripts: ['Eins', 'Zwei'],
            config: const VoicePipelineConfig(
              bargeIn: BargeInMode.keywords,
              conversationMode: true,
            ),
            detectorUsesMic: true,
            detectorStopDelay: stopDelay,
          )..pipeline.start();
          // The first recording starts once the detector is out of the way.
          async.elapse(const Duration(milliseconds: 100));
          h.audio.script(AudioFrames.pattern('.' * 400, frame: frame));
          async.elapse(const Duration(seconds: 30));
          expect(h.events.whereType<VoiceError>(), isEmpty);
          expect(h.ends, [ConversationEndReason.silence]);
          expect(h.audio.isRunning, isFalse);
        });
      });
    }

    test('hängender Detektor: Zuhören startet nach 2 s trotzdem', () {
      fakeAsync((async) {
        final h = H(
          transcripts: ['Eins', 'Zwei'],
          config: const VoicePipelineConfig(
            bargeIn: BargeInMode.keywords,
            conversationMode: true,
          ),
          detectorUsesMic: true,
          detectorHangs: true,
        )..pipeline.start();
        async.elapse(const Duration(seconds: 1));
        h.audio.script(AudioFrames.pattern('.' * 400, frame: frame));
        async.elapse(const Duration(seconds: 30));
        expect(h.diag, contains('barge-wait-timeout'));
        // The microphone stayed busy: a clear error, not a hang.
        expect(h.events.whereType<VoiceError>(), isNotEmpty);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('Wake-Signal mit belegtem Mikrofon: Zuhören startet ohne Fehler', () {
      fakeAsync((async) {
        final h = H(
          manualTts: true,
          transcripts: ['Eins', 'Zwei'],
          config: const VoicePipelineConfig(
            bargeIn: BargeInMode.keywords,
            conversationMode: true,
          ),
          detectorUsesMic: true,
          detectorStopDelay: const Duration(milliseconds: 80),
        )..pipeline.start();
        h.until(async, () => h.pipeline.state == VoiceState.speaking);
        h.detector.emit(const BargeInSignal.keyword(BargeInKeyword.wake));
        async.elapse(const Duration(seconds: 3));
        expect(h.events.whereType<VoiceError>(), isEmpty);
        expect(h.stt.calls, hasLength(2));
      });
    });

    test('„Wendelin, stopp“ während der Ausgabe: Ausgabe aus, Sitzung zu', () {
      fakeAsync((async) {
        final h = H(
          manualTts: true,
          transcripts: ['Eins', 'Wendelin, stopp'],
          config: const VoicePipelineConfig(
            bargeIn: BargeInMode.keywords,
            conversationMode: true,
          ),
          detectorUsesMic: true,
        )..pipeline.start();
        h.until(async, () => h.pipeline.state == VoiceState.speaking);
        h.detector.emit(const BargeInSignal.keyword(BargeInKeyword.wake));
        expect(h.tts.stops, 1);
        async.elapse(const Duration(seconds: 3));
        expect(h.events.whereType<VoiceError>(), isEmpty);
        expect(h.ends, [ConversationEndReason.stopWord]);
        expect(h.pipeline.state, VoiceState.idle);
        expect(h.agent.inputs, ['Eins']);
      });
    });

    test('ohne Detektor: wie bisher', () {
      fakeAsync((async) {
        final h = H(
          withDetector: false,
          config: const VoicePipelineConfig(bargeIn: BargeInMode.keywords),
        )..pipeline.start();
        async.elapse(const Duration(seconds: 5));
        expect(h.pipeline.state, VoiceState.idle);
        expect(h.tts.spoken, ['Antwort.']);
      });
    });
  });

  group('Hilfsfunktionen', () {
    test('isClosingPhrase', () {
      const p = VoicePipelineConfig.defaultClosingPhrases;
      expect(isClosingPhrase('Danke!', p), isTrue);
      expect(isClosingPhrase('Das war’s.', p), isTrue);
      expect(isClosingPhrase('Merci beaucoup', p), isTrue);
      expect(isClosingPhrase('Thanks, thank you', p), isTrue);
      expect(isClosingPhrase('Danke und wie spät ist es', p), isFalse);
      expect(isClosingPhrase('', p), isFalse);
    });
  });
}
