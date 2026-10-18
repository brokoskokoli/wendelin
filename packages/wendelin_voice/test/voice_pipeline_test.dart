import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const frame = Duration(milliseconds: 30);

/// 150 ms silence, 600 ms speech, 900 ms silence (ends after 800 ms).
List<Int16List> utterance() =>
    AudioFrames.pattern('${'.' * 5}${'S' * 20}${'.' * 30}', frame: frame);

/// Records the inputs and delegates to [inner].
final class RecordingAgent implements AgentRun {
  RecordingAgent(this.inner);

  final AgentRun inner;
  final inputs = <UserInput>[];
  int cancels = 0;

  @override
  Stream<AgentEvent> run(UserInput input) {
    inputs.add(input);
    return inner.run(input);
  }

  @override
  void cancel() {
    cancels++;
    inner.cancel();
  }
}

/// Plays fixed agent events (to test reactions without the agent loop).
final class ScriptedAgent implements AgentRun {
  ScriptedAgent(this.events);

  final List<AgentEvent> events;

  @override
  Stream<AgentEvent> run(UserInput input) async* {
    for (final e in events) {
      await Future<void>.delayed(Duration.zero);
      yield e;
    }
  }

  @override
  void cancel() {}
}

/// Plays [before], then waits for [gate] (a pending receipt), then [after].
/// Emits `AgentTextComplete` after [before] like the agent loop does.
final class GatedAgent implements AgentRun {
  GatedAgent({required this.before, required this.gate, required this.after});

  final List<AgentEvent> before;
  final Future<void> gate;
  final List<AgentEvent> after;

  @override
  Stream<AgentEvent> run(UserInput input) async* {
    for (final e in before) {
      yield e;
    }
    yield const AgentTextComplete();
    await gate;
    for (final e in after) {
      yield e;
    }
  }

  @override
  void cancel() {}
}

/// Agent whose stream fails (contract violation).
final class BrokenAgent implements AgentRun {
  @override
  Stream<AgentEvent> run(UserInput input) => Stream.error(StateError('kaputt'));

  @override
  void cancel() {}
}

final class Harness {
  Harness({
    List<ScriptedTurn> turns = const [],
    List<Tool> tools = const [],
    this.config = const VoicePipelineConfig(),
    Duration utteranceDuration = const Duration(milliseconds: 200),
    bool manualTts = false,
    bool withTts = true,
    AgentRun? agent,
    AudioInput? audio,
    VoiceActivityDetector? vad,
    Future<TextToSpeech?> Function(String?)? textToSpeech,
    List<Transcript> transcripts = const [
      Transcript(text: 'Wie wird das Wetter?', language: 'de', confidence: 0.9),
    ],
  }) : provider = FakeLlmProvider(turns),
       tts = FakeTextToSpeech(
         utteranceDuration: utteranceDuration,
         manual: manualTts,
       ),
       stt = FakeSpeechToText(transcripts),
       fakeAudio = FakeAudioInput(frames: utterance(), frameInterval: frame) {
    final clock = FixedClock(DateTime.utc(2026, 10, 13, 9));
    final catalog = FakeToolCatalog(tools);
    final runner = AgentRunner(
      resolver: DefaultProviderResolver(
        ProviderTarget(
          profileId: 'p',
          modelId: 'm',
          provider: provider,
          privacy: PrivacyLevel.standard,
        ),
      ),
      contextBuilder: ContextBuilder(
        config: const AgentConfig(),
        clock: clock,
        device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
        catalog: catalog,
        history: InMemoryConversation(),
      ),
      invoker: FakeToolInvoker(catalog),
      clock: clock,
      sessionId: 's',
    );
    recording = RecordingAgent(agent ?? runner);
    triggers = FakeTriggerSource(clock);
    pipeline = VoicePipeline(
      audio: audio ?? fakeAudio,
      vad: vad ?? this.vad,
      stt: stt,
      agent: recording,
      textToSpeech: textToSpeech ?? (_) async => withTts ? tts : null,
      config: config,
      clock: clock,
      triggers: triggers,
    );
    pipeline.states.listen(states.add);
    pipeline.events.listen(events.add);
  }

  final VoicePipelineConfig config;
  final FakeLlmProvider provider;
  final FakeTextToSpeech tts;
  final FakeSpeechToText stt;
  final FakeAudioInput fakeAudio;
  final vad = FakeVoiceActivityDetector();
  late final RecordingAgent recording;
  late final FakeTriggerSource triggers;
  late final VoicePipeline pipeline;
  final states = <VoiceState>[];
  final events = <VoiceEvent>[];

  List<T> eventsOf<T extends VoiceEvent>() => events.whereType<T>().toList();

  List<AgentEvent> get agentEvents => [
    for (final e in eventsOf<VoiceAgentEvent>()) e.event,
  ];
}

void runFake(void Function(FakeAsync async) body) => fakeAsync(body);

void settle(FakeAsync async) => async.elapse(const Duration(seconds: 10));

void main() {
  test('Ablauf: zuhören → transkribieren → denken → sprechen → idle', () {
    runFake((async) {
      final h = Harness(
        turns: [
          ScriptedTurn.text('Morgen wird es sonnig. Am Abend regnet es.'),
        ],
      );
      expect(h.pipeline.start(), isTrue);
      expect(h.pipeline.state, VoiceState.listening);
      settle(async);
      expect(h.states, [
        VoiceState.listening,
        VoiceState.transcribing,
        VoiceState.thinking,
        VoiceState.speaking,
        VoiceState.idle,
      ]);
      expect(h.tts.spoken, ['Morgen wird es sonnig.', 'Am Abend regnet es.']);
      final input = h.recording.inputs.single;
      expect(input.text, 'Wie wird das Wetter?');
      expect(input.source, InputSource.voice);
      expect(input.sttConfidence, 0.9);
      expect(input.language, 'de');
      expect(h.tts.calls.first.language, 'de');
      // Pre-roll + speech + trailing silence went to STT.
      expect(
        h.stt.calls.single.samples,
        greaterThan(durationToSamples(frame) * 20),
      );
      expect(h.fakeAudio.isRunning, isFalse);
      expect(h.vad.resets, 1);
      final listening = h.eventsOf<VoiceListening>().single;
      expect(listening.trigger?.source, TriggerKind.pushToTalk);
      expect(listening.followUp, isFalse);
      expect(
        h.eventsOf<VoiceTranscribed>().single.transcript.text,
        'Wie wird das Wetter?',
      );
      expect(h.agentEvents.last, isA<AgentDone>());
      expect(h.eventsOf<VoiceSpeaking>().map((e) => e.sentence), h.tts.spoken);
    });
  });

  test('Wake-Word-Auslöser ohne wakeEnd: Pre-Roll wird verworfen (WP73)', () {
    runFake((async) {
      final h = Harness(turns: [ScriptedTurn.text('Es ist Montag.')]);
      final preRoll = AudioFrames.speech(const Duration(milliseconds: 600));
      expect(
        h.pipeline.start(
          trigger: TriggerEvent(
            source: TriggerKind.wakeWord,
            at: DateTime.utc(2026, 10, 14),
            preRoll: preRoll,
          ),
        ),
        isTrue,
      );
      settle(async);
      // Same as without a pre-roll (24960 samples, measured): nothing from
      // before the wake word reaches the recognition.
      expect(h.stt.calls.single.samples, 24960);
      expect(
        h.eventsOf<VoiceListening>().single.trigger?.source,
        TriggerKind.wakeWord,
      );
    });
  });

  test('erster Satz wird gesprochen, bevor die Antwort fertig ist', () {
    runFake((async) {
      final h = Harness(
        turns: [
          ScriptedTurn.text(
            'Erster Satz hier. Und dann kommt noch viel mehr Text.',
          ),
        ],
      );
      final provider = FakeLlmProvider([
        ScriptedTurn.text(
          'Erster Satz hier. Und dann kommt noch viel mehr Text.',
        ),
      ], eventDelay: const Duration(milliseconds: 50));
      final slow = Harness(agent: _runnerFor(provider));
      slow.pipeline.start();
      async.elapse(const Duration(milliseconds: 1800)); // listening + STT
      while (slow.tts.spoken.isEmpty) {
        async.elapse(const Duration(milliseconds: 50));
      }
      expect(slow.tts.spoken, ['Erster Satz hier.']);
      expect(slow.agentEvents.whereType<AgentDone>(), isEmpty);
      settle(async);
      expect(slow.tts.spoken, hasLength(2));
      h.pipeline.dispose();
    });
  });

  test('Thinking wird angezeigt, aber nie gesprochen', () {
    runFake((async) {
      final h = Harness(
        turns: [
          ScriptedTurn.text(
            'Es wird sonnig.',
            thinking: 'Geheime Überlegung. Nicht vorlesen.',
          ),
        ],
      );
      h.pipeline.start();
      settle(async);
      expect(h.agentEvents.whereType<AgentThinkingDelta>(), isNotEmpty);
      expect(h.tts.spoken, ['Es wird sonnig.']);
      expect(h.tts.calls.map((c) => c.text).join(), isNot(contains('Geheim')));
    });
  });

  test('ProviderBlocks (z. B. Websuche) werden nie gesprochen', () {
    runFake((async) {
      final h = Harness(
        turns: [
          ScriptedTurn.events([
            const ProviderBlockComplete(
              ProviderBlock(
                provider: 'fake',
                rawJson: '{"result":"Suchergebnis: Geheimtext."}',
                summary: 'Websuche: Geheimtext',
              ),
            ),
            const TextDelta('Laut Suche wird es warm.'),
            const UsageEvent(Usage(inputTokens: 1, outputTokens: 1)),
            const Done(StopReason.endTurn),
          ]),
        ],
      );
      h.pipeline.start();
      settle(async);
      expect(h.tts.spoken, ['Laut Suche wird es warm.']);
      expect(h.tts.calls.map((c) => c.text).join(), isNot(contains('Geheim')));
    });
  });

  test('AgentTextReset verwirft gepufferte, noch nicht gesprochene Sätze', () {
    runFake((async) {
      final h = Harness(
        manualTts: true,
        turns: [
          ScriptedTurn.error(
            const ServerException('überlastet', statusCode: 503),
            partialText:
                'Erster Satz falsch. Zweiter Satz auch falsch. Dritter',
          ),
          ScriptedTurn.text('Richtige Antwort.'),
        ],
      );
      h.pipeline.start();
      settle(async);
      expect(h.agentEvents.whereType<AgentTextReset>(), hasLength(1));
      expect(h.tts.spoken, ['Erster Satz falsch.']); // already playing
      h.tts.completeCurrent();
      settle(async);
      h.tts.completeCurrent();
      settle(async);
      expect(h.tts.spoken, ['Erster Satz falsch.', 'Richtige Antwort.']);
      expect(h.pipeline.state, VoiceState.idle);
    });
  });

  test('pauseTurn-Retry: erneut gesendeter Pause-Text nicht doppelt', () {
    runFake((async) {
      final h = Harness(
        turns: [
          ScriptedTurn.text(
            'Ich suche kurz. Einen Moment bitte. ',
            stopReason: StopReason.pauseTurn,
          ),
          ScriptedTurn.error(
            const ServerException('überlastet', statusCode: 503),
          ),
          ScriptedTurn.text('Es wird warm.'),
        ],
      );
      h.pipeline.start();
      settle(async);
      expect(h.agentEvents.whereType<AgentTextReset>(), hasLength(1));
      expect(h.tts.spoken, [
        'Ich suche kurz.',
        'Einen Moment bitte.',
        'Es wird warm.',
      ]);
    });
  });

  test('Fehlermeldung in der Antwortsprache, Teiltext verworfen', () {
    runFake((async) {
      final h = Harness(
        transcripts: const [Transcript(text: 'Bonjour', language: 'fr')],
        turns: [
          ScriptedTurn.error(
            const AuthException('Schlüssel ungültig'),
            partialText: 'Je cherche',
          ),
        ],
      );
      h.pipeline.start();
      settle(async);
      // The translated reason is spoken, never the raw exception text.
      expect(h.tts.spoken.single, contains('refusé'));
      expect(h.tts.spoken.single, isNot(contains('Schlüssel')));
    });
  });

  test(
    'Reset verwirft nur den aktuellen Abschnitt, nicht Text vor dem Tool',
    () {
      runFake((async) {
        final call = const ToolCallBlock(
          id: 'c1',
          name: 'x',
          argumentsJson: '{}',
        );
        final h = Harness(
          manualTts: true,
          agent: ScriptedAgent([
            const AgentTextDelta('Ich schaue nach. Einen Moment.'),
            ToolCallStarted(call),
            ToolCallFinished(call: call, outcome: ToolOutcome.text('ok')),
            const AgentTextDelta('Falsch. Auch falsch.'),
            const AgentTextReset('Neuer Versuch'),
            const AgentTextDelta('Richtig.'),
            const AgentDone(
              finalText: 'Richtig.',
              stopReason: StopReason.endTurn,
            ),
          ]),
        );
        h.pipeline.start();
        settle(async);
        for (var i = 0; i < 5; i++) {
          h.tts.completeCurrent();
          settle(async);
        }
        expect(h.tts.spoken, ['Ich schaue nach.', 'Einen Moment.', 'Richtig.']);
      });
    },
  );

  test('Sprechtext-Block (WP41): nur er wird gesprochen, nicht der Text', () {
    runFake((async) {
      final h = Harness(
        agent: ScriptedAgent([
          const AgentSpokenText('Du hast heute zwei Termine.'),
          const AgentTextDelta('**Termine**\n- 10:00 Zahnarzt\n- 14:00 Chor\n'),
          const AgentDone(finalText: 'x', stopReason: StopReason.endTurn),
        ]),
      );
      h.pipeline.start();
      settle(async);
      expect(h.tts.spoken, ['Du hast heute zwei Termine.']);
    });
  });

  group('Sprechen vor der Quittung (WP81)', () {
    const red = AttestationStatusChanged(
      stepId: 's:1',
      status: AttestationStatus.red,
      logId: 'att-1',
    );

    test('letzter Satz wird vor Quittung und Ende gesprochen', () {
      runFake((async) {
        final receipt = Completer<void>();
        final h = Harness(
          agent: GatedAgent(
            before: [const AgentTextDelta('Das Licht ist an.')],
            gate: receipt.future,
            after: [
              const AgentDone(finalText: 'x', stopReason: StopReason.endTurn),
            ],
          ),
        );
        h.pipeline.start();
        settle(async);
        // Receipt still open: the sentence is spoken already.
        expect(receipt.isCompleted, isFalse);
        expect(h.tts.spoken, ['Das Licht ist an.']);
        expect(h.agentEvents.whereType<AgentDone>(), isEmpty);
        receipt.complete();
        settle(async);
        expect(h.agentEvents.whereType<AgentDone>(), hasLength(1));
        expect(h.tts.spoken, ['Das Licht ist an.']);
      });
    });

    test('pauseTurn: die Fortsetzung wird gesprochen', () {
      runFake((async) {
        final h = Harness(
          turns: [
            ScriptedTurn.text('Teil eins.', stopReason: StopReason.pauseTurn),
            ScriptedTurn.text('Teil zwei.'),
          ],
        );
        h.pipeline.start();
        settle(async);
        expect(
          h.tts.spoken.join(' '),
          allOf(contains('Teil eins.'), contains('Teil zwei.')),
        );
      });
    });

    test('Fehler nach Text: halber Satz wird nicht gesprochen', () {
      runFake((async) {
        final h = Harness(
          turns: [
            ScriptedTurn.error(
              const NetworkException('weg'),
              partialText: 'Halber Satz ohne Ende',
            ),
          ],
        );
        h.pipeline.start();
        settle(async);
        expect(h.tts.spoken.join(' '), isNot(contains('Halber')));
      });
    });

    test('rote Quittung: Ausgabe wird abgebrochen, Hinweis gesprochen', () {
      runFake((async) {
        final receipt = Completer<void>();
        final h = Harness(
          utteranceDuration: const Duration(seconds: 5),
          agent: GatedAgent(
            before: [const AgentTextDelta('Erster langer Satz. Zweiter Satz.')],
            gate: receipt.future,
            after: [
              red,
              const AgentDone(finalText: 'x', stopReason: StopReason.endTurn),
            ],
          ),
        );
        h.pipeline.start();
        async.elapse(
          const Duration(seconds: 3),
        ); // listening, STT, 1st sentence
        expect(h.tts.spoken, ['Erster langer Satz.']);
        receipt.complete(); // red arrives while the first sentence plays
        settle(async);
        expect(h.tts.stops, greaterThan(0));
        expect(h.tts.spoken, ['Erster langer Satz.', VoiceTexts.de.unverified]);
        expect(h.tts.spoken, isNot(contains('Zweiter Satz.')));
      });
    });
  });

  group('Prüfung des Sprechtexts (WP55)', () {
    List<String> spokenFor(List<AgentEvent> events) {
      late List<String> spoken;
      runFake((async) {
        final h = Harness(agent: ScriptedAgent(events));
        h.pipeline.start();
        settle(async);
        spoken = h.tts.spoken;
      });
      return spoken;
    }

    const done = AgentDone(finalText: 'x', stopReason: StopReason.endTurn);

    test('Treffer: der Sprechtext wird gesprochen, der Text nicht', () {
      expect(
        spokenFor([
          const AgentSpokenHold(),
          const AgentTextDelta('Termin um 10:00 Uhr.'),
          const AgentSpokenVerdict(accepted: true, reason: 'ok'),
          const AgentSpokenText('Termin um zehn Uhr.'),
          done,
        ]),
        ['Termin um zehn Uhr.'],
      );
    });

    test('kein Treffer: während der Prüfung still, dann die Antwort', () {
      expect(
        spokenFor([
          const AgentSpokenHold(),
          const AgentTextDelta('Termin um 10:00 Uhr.'),
          const AgentSpokenVerdict(accepted: false, reason: 'anders'),
          done,
        ]),
        ['Termin um 10 Uhr.'],
      );
    });

    test('Halten ohne Urteil vor dem Tool-Aufruf: Antwort wird gesprochen', () {
      expect(
        spokenFor([
          const AgentSpokenHold(),
          const AgentTextDelta('Ich schaue nach.'),
          const ToolCallStarted(
            ToolCallBlock(id: 'c', name: 't', argumentsJson: '{}'),
          ),
          done,
        ]),
        contains('Ich schaue nach.'),
      );
    });

    test(
      'Halten, Text, Ende ohne Tool und ohne Urteil: Antwort gesprochen',
      () {
        expect(
          spokenFor([
            const AgentSpokenHold(),
            const AgentTextDelta('Termin um 10:00 Uhr.'),
            done,
          ]),
          ['Termin um 10 Uhr.'],
        );
      },
    );

    test('Freigabe vor dem Tool-Aufruf: Reihenfolge bleibt erhalten', () {
      expect(
        spokenFor([
          const AgentSpokenHold(),
          const AgentTextDelta('Ich schaue nach.'),
          const ToolCallStarted(
            ToolCallBlock(id: 'c', name: 't', argumentsJson: '{}'),
          ),
          const AgentTextDelta('Fertig.'),
          done,
        ]),
        ['Ich schaue nach.', 'Fertig.'],
      );
    });

    test('Reset beendet das Halten: neuer Text wird gesprochen', () {
      expect(
        spokenFor([
          const AgentSpokenHold(),
          const AgentTextDelta('Alt.'),
          const AgentTextReset('neu'),
          const AgentTextDelta('Neu.'),
          done,
        ]),
        ['Neu.'],
      );
    });
  });

  test('AgentTextReset hebt die Block-Sperre auf: Antwort ohne Block wird '
      'gesprochen', () {
    runFake((async) {
      final h = Harness(
        agent: ScriptedAgent([
          const AgentSpokenText('Erster Versuch mit Block.'),
          const AgentTextDelta('Geschriebene Details.'),
          const AgentTextReset('Neuer Versuch'),
          const AgentTextDelta('Zweiter Versuch ohne Block.'),
          const AgentDone(finalText: 'x', stopReason: StopReason.endTurn),
        ]),
      );
      h.pipeline.start();
      settle(async);
      expect(h.tts.spoken, contains('Zweiter Versuch ohne Block.'));
      expect(h.tts.spoken, isNot(contains('Geschriebene Details.')));
    });
  });

  test('Kein Block: der geschriebene Text wird aufbereitet gesprochen', () {
    runFake((async) {
      final h = Harness(
        agent: ScriptedAgent([
          const AgentTextDelta('Dein Termin: um 10:00 Uhr.'),
          const AgentDone(finalText: 'x', stopReason: StopReason.endTurn),
        ]),
      );
      h.pipeline.start();
      settle(async);
      expect(h.tts.spoken, ['Dein Termin, um 10 Uhr.']);
    });
  });

  test('Text vor einem Tool-Aufruf wird gesprochen, dann die Antwort', () {
    runFake((async) {
      final h = Harness(
        tools: [FakeTool(name: 'weather__get')],
        turns: [
          ScriptedTurn.toolCalls([
            const ToolCallBlock(
              id: 'c1',
              name: 'weather__get',
              argumentsJson: '{}',
            ),
          ], text: 'Ich schaue nach'),
          ScriptedTurn.text('Es bleibt trocken.'),
        ],
      );
      h.pipeline.start();
      settle(async);
      expect(h.tts.spoken, ['Ich schaue nach', 'Es bleibt trocken.']);
      expect(h.agentEvents.whereType<ToolCallFinished>(), hasLength(1));
      expect(h.pipeline.state, VoiceState.idle);
    });
  });

  test('zwischen Sätzen und während Tools: Zustand thinking', () {
    runFake((async) {
      final h = Harness(
        tools: [FakeTool(name: 'slow', delay: const Duration(seconds: 2))],
        turns: [
          ScriptedTurn.toolCalls([
            const ToolCallBlock(id: 'c1', name: 'slow', argumentsJson: '{}'),
          ], text: 'Moment.'),
          ScriptedTurn.text('Fertig.'),
        ],
      );
      h.pipeline.start();
      settle(async);
      expect(
        h.states,
        containsAllInOrder([
          VoiceState.thinking,
          VoiceState.speaking,
          VoiceState.thinking,
          VoiceState.speaking,
          VoiceState.idle,
        ]),
      );
    });
  });

  test('Antwort wird für die Sprache gekürzt, Rest nur auf dem Bildschirm', () {
    runFake((async) {
      final h = Harness(
        turns: [
          ScriptedTurn.text(
            'Hier ist alles. Erstens dies. Zweitens das. Drittens jenes. '
            'Viertens noch mehr.',
          ),
        ],
      );
      h.pipeline.start();
      settle(async);
      expect(h.tts.spoken, [
        'Hier ist alles.',
        'Erstens dies.',
        'Zweitens das.',
        VoiceTexts.de.rest,
      ]);
      final done = h.agentEvents.whereType<AgentDone>().single;
      expect(done.finalText, contains('Viertens'));
    });
  });

  test('Sprache aus dem Transkript gilt für Agent, TTS und Hinweise', () {
    runFake((async) {
      final h = Harness(
        config: const VoicePipelineConfig(
          shortening: SpeechShortening(maxSentences: 1),
        ),
        transcripts: const [
          Transcript(text: 'Quel temps fait-il ?', language: 'fr'),
        ],
        turns: [ScriptedTurn.text('Il fait beau. Il fait chaud.')],
      );
      h.pipeline.start();
      settle(async);
      expect(h.recording.inputs.single.language, 'fr');
      expect(h.tts.spoken, ['Il fait beau.', VoiceTexts.fr.rest]);
      expect(h.tts.calls.every((c) => c.language == 'fr'), isTrue);
      expect(h.stt.calls.single.language, isNull);
    });
  });

  test('feste Sprache, Stimme und Tempo aus der Konfiguration', () {
    runFake((async) {
      final h = Harness(
        config: const VoicePipelineConfig(
          language: 'de',
          voice: 'v1',
          rate: 1.3,
        ),
        transcripts: const [Transcript(text: 'Hallo')],
        turns: [ScriptedTurn.text('Hallo.')],
      );
      h.pipeline.start();
      settle(async);
      expect(h.stt.calls.single.language, 'de');
      expect(h.recording.inputs.single.language, 'de');
      expect(h.tts.calls.single.voice, 'v1');
      expect(h.tts.calls.single.rate, 1.3);
    });
  });

  group('Abbruch in jedem Zustand', () {
    test('listening', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Nie.')]);
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 300));
        h.pipeline.cancel();
        expect(h.pipeline.state, VoiceState.idle);
        settle(async);
        expect(h.fakeAudio.isRunning, isFalse);
        expect(h.stt.calls, isEmpty);
        expect(h.recording.inputs, isEmpty);
        final c = h.eventsOf<VoiceCancelled>().single;
        expect(c.reason, VoiceCancelReason.tap);
        expect(c.during, VoiceState.listening);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('transcribing: STT-Ergebnis wird verworfen', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Nie.')]);
        h.stt.hold = true;
        h.pipeline.start();
        settle(async);
        expect(h.pipeline.state, VoiceState.transcribing);
        h.pipeline.cancel();
        h.stt.release();
        settle(async);
        expect(h.recording.inputs, isEmpty);
        expect(h.eventsOf<VoiceTranscribed>(), isEmpty);
        expect(
          h.eventsOf<VoiceCancelled>().single.during,
          VoiceState.transcribing,
        );
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('thinking: Agent wird abgebrochen, nichts gesprochen', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.hang()]);
        h.pipeline.start();
        settle(async);
        expect(h.pipeline.state, VoiceState.thinking);
        h.pipeline.cancel();
        settle(async);
        expect(h.recording.cancels, 1);
        expect(h.tts.spoken, isEmpty);
        expect(h.eventsOf<VoiceCancelled>().single.during, VoiceState.thinking);
        // The cancelled run's AgentFailed is not forwarded or spoken.
        expect(h.agentEvents.whereType<AgentFailed>(), isEmpty);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('speaking: Ausgabe gestoppt, Rest verworfen', () {
      runFake((async) {
        final h = Harness(
          manualTts: true,
          turns: [ScriptedTurn.text('Eins hier. Zwei hier. Drei hier.')],
        );
        h.pipeline.start();
        settle(async);
        expect(h.pipeline.state, VoiceState.speaking);
        h.pipeline.cancel();
        settle(async);
        expect(h.tts.interrupted, ['Eins hier.']);
        expect(h.tts.spoken, ['Eins hier.']);
        expect(h.eventsOf<VoiceCancelled>().single.during, VoiceState.speaking);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('nach dem Abbruch startet eine neue Anfrage normal', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.hang(), ScriptedTurn.text('Zweite Antwort.')],
          transcripts: const [
            Transcript(text: 'Erste'),
            Transcript(text: 'Zweite'),
          ],
        );
        h.pipeline.start();
        settle(async);
        h.pipeline.cancel();
        expect(h.pipeline.start(), isTrue);
        settle(async);
        expect(h.recording.inputs.map((i) => i.text), ['Erste', 'Zweite']);
        expect(h.tts.spoken, ['Zweite Antwort.']);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('cancel im Leerlauf ist wirkungslos', () {
      runFake((async) {
        final h = Harness();
        h.pipeline.cancel();
        settle(async);
        expect(h.events, isEmpty);
      });
    });
  });

  test('Abbruchwort „Stopp“ beendet ohne Agent', () {
    runFake((async) {
      final h = Harness(
        transcripts: const [Transcript(text: 'Stopp!', language: 'de')],
        turns: [ScriptedTurn.text('Nie.')],
      );
      h.pipeline.start();
      settle(async);
      expect(h.recording.inputs, isEmpty);
      final c = h.eventsOf<VoiceCancelled>().single;
      expect(c.reason, VoiceCancelReason.stopWord);
      expect(c.during, VoiceState.transcribing);
      expect(h.tts.spoken, isEmpty);
      expect(h.pipeline.state, VoiceState.idle);
    });
  });

  test('Abbruchwörter nur als ganze Äußerung', () {
    final p = Harness().pipeline;
    expect(p.isStopWord('Stopp.'), isTrue);
    expect(p.isStopWord('  ABBRECHEN '), isTrue);
    expect(p.isStopWord('Arrête-toi !'), isTrue);
    expect(p.isStopWord('Cancel'), isTrue);
    expect(p.isStopWord('Wendelin, stopp!'), isTrue);
    expect(p.isStopWord('Stopp die Musik'), isFalse);
    expect(p.isStopWord('Bushaltestelle'), isFalse);
  });

  test('Abbruchwörter mit Wiederholung und Füllwörtern (de/fr/en)', () {
    final p = Harness().pipeline;
    for (final t in [
      'Stopp, stopp.',
      'Stopp bitte',
      'Nein, stopp!',
      'Halt.',
      'Hör auf, stopp',
      'Hör auf!',
      'hör auf',
      'Bitte hör auf.',
      'Arrête ça !',
      'Tais-toi',
      'Stop it!',
      'Be quiet, please',
      'Arrête, s’il te plaît',
      'Non, arrête !',
      'Stop it, please',
      'No, cancel that',
    ]) {
      expect(p.isStopWord(t), isTrue, reason: t);
    }
    for (final t in [
      'Bitte',
      'Nein',
      'Das ist halt so',
      'Stop the timer',
      'Hör auf zu reden über das Wetter',
      'auf',
      'Arrête la musique',
    ]) {
      expect(p.isStopWord(t), isFalse, reason: t);
    }
  });

  group('nichts verstanden', () {
    test('nur Stille bis zum Timeout', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            endpoint: EndpointConfig(noSpeechTimeout: Duration(seconds: 1)),
          ),
        );
        h.fakeAudio.script(AudioFrames.pattern('.' * 60, frame: frame));
        h.pipeline.start();
        settle(async);
        expect(
          h.eventsOf<VoiceNothingUnderstood>().single.reason,
          EndpointReason.noSpeech,
        );
        expect(h.tts.spoken, [VoiceTexts.de.nothingUnderstood]);
        expect(h.stt.calls, isEmpty);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('leeres Transkript, ohne Ansage wenn abgeschaltet', () {
      runFake((async) {
        final h = Harness(
          transcripts: const [Transcript(text: '  ')],
          config: const VoicePipelineConfig(speakNothingUnderstood: false),
        );
        h.pipeline.start();
        settle(async);
        expect(h.eventsOf<VoiceNothingUnderstood>().single.reason, isNull);
        expect(h.tts.spoken, isEmpty);
        expect(h.recording.inputs, isEmpty);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('Mikrofon liefert nichts: Schutz-Timer beendet das Zuhören', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            endpoint: EndpointConfig(maxDuration: Duration(seconds: 2)),
            listenGrace: Duration(seconds: 1),
          ),
        );
        h.fakeAudio.script(const []);
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 2900));
        expect(h.pipeline.state, VoiceState.listening);
        async.elapse(const Duration(milliseconds: 200));
        expect(
          h.eventsOf<VoiceNothingUnderstood>().single.reason,
          EndpointReason.maxDuration,
        );
        settle(async);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('Mikrofon liefert nichts: vor Sprachbeginn greift der Timeout', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            endpoint: EndpointConfig(noSpeechTimeout: Duration(seconds: 2)),
            listenGrace: Duration(seconds: 1),
          ),
        );
        h.fakeAudio.script(const []);
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 2900));
        expect(h.pipeline.state, VoiceState.listening);
        async.elapse(const Duration(milliseconds: 200));
        expect(
          h.eventsOf<VoiceNothingUnderstood>().single.reason,
          EndpointReason.noSpeech,
        );
      });
    });

    test(
      'Mikrofon verstummt mitten in der Sprache: kein Abbruch vor Maximum',
      () {
        runFake((async) {
          final h = Harness(
            config: const VoicePipelineConfig(
              endpoint: EndpointConfig(
                noSpeechTimeout: Duration(seconds: 1),
                maxDuration: Duration(seconds: 5),
              ),
              listenGrace: Duration(seconds: 1),
            ),
            turns: [ScriptedTurn.text('Ok.')],
          );
          h.fakeAudio.script(AudioFrames.pattern('S' * 20, frame: frame));
          h.pipeline.start();
          async.elapse(const Duration(seconds: 3));
          expect(h.pipeline.state, VoiceState.listening);
          settle(async);
          expect(h.tts.spoken, ['Ok.']);
        });
      },
    );
  });

  test('finishListening (Push-to-talk losgelassen) transkribiert sofort', () {
    runFake((async) {
      final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
      h.fakeAudio.script(AudioFrames.pattern('S' * 200, frame: frame));
      h.pipeline.finishListening(); // no effect while idle
      h.pipeline.start();
      async.elapse(const Duration(seconds: 1));
      h.pipeline.finishListening();
      settle(async);
      expect(h.stt.calls, hasLength(1));
      expect(h.tts.spoken, ['Ja.']);
    });
  });

  test('Mikrofon-Stream endet von selbst: Gesagtes wird verarbeitet', () {
    runFake((async) {
      final audio = FakeAudioInput(
        frames: AudioFrames.pattern('S' * 20, frame: frame),
        frameInterval: frame,
        closeAfterFrames: true,
      );
      final h = Harness(audio: audio, turns: [ScriptedTurn.text('Ok.')]);
      h.pipeline.start();
      settle(async);
      expect(h.tts.spoken, ['Ok.']);
    });
  });

  group('Fehler', () {
    test('keine Mikrofon-Berechtigung', () {
      runFake((async) {
        final h = Harness(audio: DeniedAudioInput());
        h.pipeline.start();
        settle(async);
        final e = h.eventsOf<VoiceError>().single;
        expect(e.during, VoiceState.listening);
        expect(
          (e.error as VoiceException).kind,
          VoiceErrorKind.permissionDenied,
        );
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('Mikrofon bricht mit Fehler ab', () {
      runFake((async) {
        final h = Harness();
        h.fakeAudio.script(const []);
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 100));
        h.fakeAudio.fail(StateError('weg'));
        settle(async);
        expect(h.eventsOf<VoiceError>().single.during, VoiceState.listening);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('VAD wirft', () {
      runFake((async) {
        final h = Harness(vad: _ThrowingVad());
        h.pipeline.start();
        settle(async);
        expect(h.eventsOf<VoiceError>().single.error, isA<StateError>());
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('STT wirft', () {
      runFake((async) {
        final h = Harness();
        h.stt.nextError = const VoiceException(
          VoiceErrorKind.modelMissing,
          'Kein Modell',
        );
        h.pipeline.start();
        settle(async);
        expect(h.eventsOf<VoiceError>().single.during, VoiceState.transcribing);
        expect(h.recording.inputs, isEmpty);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('Agent schlägt fehl: Meldung wird gesprochen', () {
      runFake((async) {
        final h = Harness(
          turns: [
            ScriptedTurn.error(const AuthException('Schlüssel ungültig')),
          ],
        );
        h.pipeline.start();
        settle(async);
        final failed = h.agentEvents.whereType<AgentFailed>().single;
        expect(h.tts.spoken, [failed.message]);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('Agent schlägt fehl, Ansage abgeschaltet', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(speakErrors: false),
          turns: [
            ScriptedTurn.error(const AuthException('Schlüssel ungültig')),
          ],
        );
        h.pipeline.start();
        settle(async);
        expect(h.tts.spoken, isEmpty);
      });
    });

    test('Agent-Stream wirft', () {
      runFake((async) {
        final h = Harness(agent: BrokenAgent());
        h.pipeline.start();
        settle(async);
        expect(h.eventsOf<VoiceError>().single.during, VoiceState.thinking);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('TTS-Fehler wird gemeldet, Antwort läuft weiter', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Eins hier. Zwei hier.')]);
        h.tts.nextError = StateError('Audio belegt');
        h.pipeline.start();
        settle(async);
        expect(h.eventsOf<VoiceError>().single.during, VoiceState.speaking);
        expect(h.tts.spoken, ['Zwei hier.']);
      });
    });

    test('TTS-Auswahl wirft: Antwort nur als Text', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('Hallo.')],
          textToSpeech: (_) => Future.error(StateError('keine Engine')),
        );
        h.pipeline.start();
        settle(async);
        expect(h.eventsOf<VoiceError>(), hasLength(1));
        expect(h.agentEvents.last, isA<AgentDone>());
        expect(h.pipeline.state, VoiceState.idle);
      });
    });
  });

  test('von außen abgebrochener Agent-Lauf wird nicht angesagt', () {
    runFake((async) {
      final h = Harness(
        agent: ScriptedAgent([
          const AgentFailed(
            error: AgentErrorKind.cancelled,
            message: 'Abgebrochen',
          ),
        ]),
      );
      h.pipeline.start();
      settle(async);
      expect(h.agentEvents.single, isA<AgentFailed>());
      expect(h.tts.spoken, isEmpty);
      expect(h.pipeline.state, VoiceState.idle);
    });
  });

  test('ohne Sprachausgabe: nur Text, kein Zustand speaking', () {
    runFake((async) {
      final h = Harness(withTts: false, turns: [ScriptedTurn.text('Hallo.')]);
      h.pipeline.start();
      settle(async);
      expect(h.states, isNot(contains(VoiceState.speaking)));
      expect(h.agentEvents.last, isA<AgentDone>());
      expect(h.pipeline.state, VoiceState.idle);
    });
  });

  group('Gesprächsmodus (vorbereitet, Standard aus)', () {
    test('Standard: nach der Antwort kein weiteres Zuhören', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ok.')]);
        expect(h.config.conversationMode, isFalse);
        expect(h.config.followUpWindow, const Duration(seconds: 5));
        h.pipeline.start();
        settle(async);
        expect(h.fakeAudio.startCount, 1);
      });
    });

    test('an: hört 5 s weiter zu, schweigt still ohne Folgefrage', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(conversationMode: true),
          turns: [ScriptedTurn.text('Ok.')],
        );
        h.pipeline.start();
        async.flushMicrotasks(); // the first recording has its frames
        h.fakeAudio.script(AudioFrames.pattern('.' * 400, frame: frame));
        settle(async);
        expect(h.fakeAudio.startCount, 2);
        final followUp = h.eventsOf<VoiceListening>().last;
        expect(followUp.followUp, isTrue);
        expect(followUp.trigger, isNull);
        expect(h.eventsOf<VoiceNothingUnderstood>(), isEmpty);
        expect(h.tts.spoken, ['Ok.']);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('an: Folgefrage wird beantwortet', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(seconds: 1),
          ),
          transcripts: const [
            Transcript(text: 'Eins'),
            Transcript(text: 'Zwei'),
          ],
          turns: [ScriptedTurn.text('Erste.'), ScriptedTurn.text('Zweite.')],
        );
        h.pipeline.start();
        settle(async);
        expect(h.recording.inputs.map((i) => i.text), ['Eins', 'Zwei']);
        expect(h.tts.spoken, ['Erste.', 'Zweite.']);
        // Third window: the scripted audio has run out → silence → idle.
        expect(h.pipeline.state, VoiceState.idle);
      });
    });
  });

  group('Auslöser während des Zuhörens (Review WP15)', () {
    test('Trigger während listening: neue Anfrage wird beantwortet', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Antwort.')]);
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 300));
        h.triggers.fire(TriggerKind.assistant);
        settle(async);
        expect(h.eventsOf<VoiceError>(), isEmpty);
        expect(h.tts.spoken, ['Antwort.']);
        expect(h.fakeAudio.startCount, 2);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('cancel() und start() direkt nacheinander', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Antwort.')]);
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 300));
        h.pipeline.cancel();
        expect(h.pipeline.start(), isTrue);
        settle(async);
        expect(h.eventsOf<VoiceError>(), isEmpty);
        expect(h.tts.spoken, ['Antwort.']);
      });
    });

    test('Trigger, dann sofort cancel(): Mikrofon startet nicht erneut', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Nie.')]);
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 300));
        expect(h.fakeAudio.startCount, 1);
        h.triggers.fire(TriggerKind.assistant); // waits for the old stop
        h.pipeline.cancel();
        settle(async);
        expect(h.fakeAudio.startCount, 1);
        expect(h.fakeAudio.isRunning, isFalse);
        expect(h.pipeline.state, VoiceState.idle);
        expect(h.recording.inputs, isEmpty);
      });
    });

    test('doppelter Assistent-Trigger', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Antwort.')]);
        h.triggers
          ..fire(TriggerKind.assistant)
          ..fire(TriggerKind.assistant);
        settle(async);
        expect(h.eventsOf<VoiceError>(), isEmpty);
        expect(h.tts.spoken, ['Antwort.']);
        expect(h.recording.inputs, hasLength(1));
      });
    });

    test('finishListening nach Neustart beendet die neue Aufnahme', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
        h.fakeAudio.script(AudioFrames.pattern('S' * 200, frame: frame));
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 300));
        h.triggers.fire();
        async.elapse(const Duration(seconds: 1));
        h.pipeline.finishListening();
        settle(async);
        expect(h.stt.calls, hasLength(1));
        expect(h.tts.spoken, ['Ja.']);
      });
    });

    test('Trigger im Folgefenster des Gesprächsmodus', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(conversationMode: true),
          transcripts: const [
            Transcript(text: 'Eins'),
            Transcript(text: 'Zwei'),
          ],
          turns: [ScriptedTurn.text('Erste.'), ScriptedTurn.text('Zweite.')],
        );
        h.pipeline.start();
        while (!h.eventsOf<VoiceListening>().any((e) => e.followUp)) {
          async.elapse(const Duration(milliseconds: 10));
        }
        h.triggers.fire(TriggerKind.assistant);
        settle(async);
        expect(h.eventsOf<VoiceError>(), isEmpty);
        expect(h.tts.spoken, ['Erste.', 'Zweite.']);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });
  });

  group('Auslöser', () {
    test('TriggerSource startet das Zuhören mit Quelle', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ok.')]);
        final t = h.triggers.fire(TriggerKind.assistant);
        expect(h.pipeline.state, VoiceState.listening);
        expect(h.eventsOf<VoiceListening>().single.trigger, t);
        settle(async);
        expect(h.tts.spoken, ['Ok.']);
      });
    });

    test('neuer Auslöser während einer Anfrage startet neu', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.hang(), ScriptedTurn.text('Neu.')],
          transcripts: const [
            Transcript(text: 'A'),
            Transcript(text: 'B'),
          ],
        );
        h.pipeline.start();
        settle(async);
        expect(h.pipeline.state, VoiceState.thinking);
        h.triggers.fire(TriggerKind.widget);
        expect(h.pipeline.state, VoiceState.listening);
        expect(
          h.eventsOf<VoiceCancelled>().single.reason,
          VoiceCancelReason.retrigger,
        );
        settle(async);
        expect(h.tts.spoken, ['Neu.']);
      });
    });

    test('start während einer Anfrage liefert false', () {
      runFake((async) {
        final h = Harness();
        expect(h.pipeline.start(), isTrue);
        expect(h.pipeline.start(), isFalse);
        h.pipeline.cancel();
        settle(async);
      });
    });
  });

  test('dispose bricht ab und schließt die Streams', () {
    runFake((async) {
      final h = Harness(turns: [ScriptedTurn.hang()]);
      var statesDone = false;
      h.pipeline.states.listen(null, onDone: () => statesDone = true);
      h.pipeline.start();
      settle(async);
      h.pipeline.dispose();
      settle(async);
      expect(statesDone, isTrue);
      expect(
        h.eventsOf<VoiceCancelled>().single.reason,
        VoiceCancelReason.disposed,
      );
      expect(h.pipeline.start(), isFalse);
      h.pipeline.dispose(); // idempotent
      settle(async);
    });
  });

  test('whenIdle endet mit der Anfrage', () {
    runFake((async) {
      final h = Harness(turns: [ScriptedTurn.text('Ok.')]);
      h.pipeline.start();
      var done = false;
      h.pipeline.whenIdle.then((_) => done = true);
      settle(async);
      expect(done, isTrue);
    });
  });

  test('Ereignisse haben lesbare toString-Ausgaben', () {
    final t = TriggerEvent(source: TriggerKind.widget, at: DateTime.utc(2026));
    final strings = [
      VoiceListening(trigger: t, followUp: false),
      const VoiceTranscribed(Transcript(text: 'x')),
      const VoiceNothingUnderstood(EndpointReason.noSpeech),
      const VoiceAgentEvent(AgentTextDelta('y')),
      const VoiceSpeaking('z'),
      const VoiceCancelled(VoiceCancelReason.tap, during: VoiceState.speaking),
      VoiceError(VoiceState.listening, StateError('e')),
    ].map((e) => e.toString());
    expect(strings, everyElement(startsWith('Voice')));
  });
}

AgentRun _runnerFor(FakeLlmProvider provider) {
  final clock = FixedClock(DateTime.utc(2026, 10, 13, 9));
  final catalog = FakeToolCatalog(const []);
  return AgentRunner(
    resolver: DefaultProviderResolver(
      ProviderTarget(
        profileId: 'p',
        modelId: 'm',
        provider: provider,
        privacy: PrivacyLevel.standard,
      ),
    ),
    contextBuilder: ContextBuilder(
      config: const AgentConfig(),
      clock: clock,
      device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
      catalog: catalog,
      history: InMemoryConversation(),
    ),
    invoker: FakeToolInvoker(catalog),
    clock: clock,
    sessionId: 's',
  );
}

final class _ThrowingVad implements VoiceActivityDetector {
  @override
  double get threshold => 0.5;

  @override
  double speechProbability(Int16List frame) => throw StateError('VAD kaputt');

  @override
  void reset() {}
}
