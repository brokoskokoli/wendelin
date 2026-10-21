import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/latency_trace.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';

const _usage = Usage(inputTokens: 5, outputTokens: 5);

UsageReported _used() =>
    const UsageReported(profileId: 'p', modelId: 'm', usage: _usage);

ToolCallBlock _call() =>
    const ToolCallBlock(id: 'c1', name: 'flashlight', argumentsJson: '{}');

void main() {
  group('LatencyTrace', () {
    late Duration clock;
    late List<(String, Map<String, Object?>)> logged;
    late LatencyTrace trace;

    setUp(() {
      clock = const Duration(seconds: 100);
      logged = [];
      trace = LatencyTrace(now: () => clock, log: (e, f) => logged.add((e, f)));
    });

    void at(int ms) =>
        clock = const Duration(seconds: 100) + Duration(milliseconds: ms);

    test('fester Bestätigungssatz zählt keinen zweiten Modellaufruf', () {
      trace.begin();
      at(300);
      trace.sttDone();
      at(900);
      trace.agentEvent(_used());
      trace.agentEvent(ToolCallStarted(_call()));
      at(1100);
      trace.agentEvent(
        ToolCallFinished(call: _call(), outcome: ToolOutcome.text('an')),
      );
      at(1200);
      trace.agentEvent(const AgentTextDelta('Die Taschenlampe ist an.'));
      trace.agentEvent(
        const AgentDone(
          finalText: 'x',
          stopReason: StopReason.endTurn,
          fixed: true,
        ),
      );
      trace.finish();

      expect(logged.single.$2['calls'], 1);
      expect(logged.single.$2['tools'], 1);
      expect(logged.single.$2.containsKey('m2_req'), isFalse);
    });

    test('echter zweiter Aufruf ohne Usage bleibt (calls 2)', () {
      trace.begin();
      at(300);
      trace.sttDone();
      at(900);
      trace.agentEvent(_used());
      trace.agentEvent(ToolCallStarted(_call()));
      at(1100);
      trace.agentEvent(
        ToolCallFinished(call: _call(), outcome: ToolOutcome.text('an')),
      );
      at(1700);
      trace.agentEvent(const AgentTextDelta('Taschenlampe ist an.'));
      trace.agentEvent(
        const AgentDone(finalText: 'x', stopReason: StopReason.endTurn),
      );
      trace.finish();

      expect(logged.single.$2['calls'], 2);
    });

    test('fester Satz ohne Usage im ersten Aufruf: der Aufruf bleibt', () {
      trace.begin();
      at(300);
      trace.sttDone();
      at(900);
      trace.agentEvent(const AgentTextDelta('Ich schalte'));
      trace.agentEvent(ToolCallStarted(_call()));
      at(1100);
      trace.agentEvent(
        ToolCallFinished(call: _call(), outcome: ToolOutcome.text('an')),
      );
      at(1200);
      trace.agentEvent(const AgentTextDelta('Die Taschenlampe ist an.'));
      trace.agentEvent(
        const AgentDone(
          finalText: 'x',
          stopReason: StopReason.endTurn,
          fixed: true,
        ),
      );
      trace.finish();

      expect(logged.single.$2['calls'], 1);
    });

    test('Zeitleiste: zwei Modellaufrufe mit Werkzeug, zwei Sätze', () {
      trace.begin(); // t0 = 0
      at(300);
      trace.sttDone();
      at(900);
      trace.agentEvent(const AgentTextDelta('Ich schalte'));
      at(1000);
      trace.agentEvent(_used());
      trace.agentEvent(ToolCallStarted(_call()));
      at(1100);
      trace.agentEvent(
        ToolCallFinished(call: _call(), outcome: ToolOutcome.text('an')),
      );
      at(1700);
      trace.agentEvent(const AgentTextDelta('Taschenlampe ist an.'));
      at(1800);
      trace.agentEvent(_used());
      trace.sentenceToTts();
      at(2000);
      trace.synthesized(const Duration(milliseconds: 150));
      trace.audio(started: true);
      at(2900);
      trace.audio(started: false);
      trace.sentenceToTts();
      trace.synthesized(const Duration(milliseconds: 400));
      at(3300);
      trace.audio(started: true);
      at(4300);
      trace.audio(started: false);
      trace.finish();

      expect(logged, hasLength(1));
      expect(logged.single.$1, 'latency');
      expect(logged.single.$2, {
        'stt': const Duration(milliseconds: 300),
        'calls': 2,
        'tools': 1,
        'm1_req': const Duration(milliseconds: 300),
        'm1_first': const Duration(milliseconds: 900),
        'm1_done': const Duration(milliseconds: 1000),
        'm2_req': const Duration(milliseconds: 1100),
        'm2_first': const Duration(milliseconds: 1700),
        'm2_done': const Duration(milliseconds: 1800),
        'tts1': const Duration(milliseconds: 1800),
        'syn_end': const Duration(milliseconds: 2000),
        'audio_first': const Duration(milliseconds: 2000),
        'audio_last': const Duration(milliseconds: 4300),
        'sentences': 2,
        's1_syn': const Duration(milliseconds: 150),
        's2_syn': const Duration(milliseconds: 400),
        's2_gap': const Duration(milliseconds: 400),
      });
    });

    test('reine Tool-Antwort: erstes Token nie nach dem Ende des Aufrufs', () {
      trace.begin();
      at(300);
      trace.sttDone();
      at(1000);
      trace.agentEvent(_used()); // usage comes before the tool event
      at(1100);
      trace.agentEvent(ToolCallStarted(_call()));
      trace.finish();
      expect(logged.single.$2['m1_first'], const Duration(milliseconds: 1000));
      expect(logged.single.$2['m1_done'], const Duration(milliseconds: 1000));
    });

    test('ohne Transkript oder nach abort keine Zeile', () async {
      trace.begin();
      trace.finish();
      trace.begin();
      trace.sttDone();
      trace.finishSoon();
      trace.abort();
      await Future<void>.value();
      expect(logged, isEmpty);
    });

    test(
      'abort und neue Anfrage: das alte finishSoon schreibt nicht',
      () async {
        trace.begin();
        trace.sttDone();
        trace.finishSoon();
        trace.begin(); // next request starts in the same moment
        trace.sttDone();
        await Future<void>.value();
        expect(logged, isEmpty, reason: 'die neue Anfrage läuft noch');
        expect(trace.active, isTrue);
      },
    );

    test(
      'finishSoon schreibt nach den Ereignissen desselben Moments',
      () async {
        trace.begin();
        trace.sttDone();
        trace.finishSoon();
        expect(logged, isEmpty);
        await Future<void>.value();
        expect(logged, hasLength(1));
        expect(trace.active, isFalse);
      },
    );

    test('Ereignisse ohne laufende Zeitleiste werden ignoriert', () {
      trace
        ..sttDone()
        ..sentenceToTts()
        ..audio(started: true)
        ..synthesized(Duration.zero)
        ..agentEvent(const AgentTextDelta('x'))
        ..finish();
      expect(logged, isEmpty);
    });
  });

  test(
    'Sprachanfrage schreibt genau eine Zeile `latency`, nur Zahlen',
    () async {
      final lines = <String>[];
      voiceLogSink = lines.add;
      const secret = 'Streng geheimer Anfragetext';
      final tts = FakeTextToSpeech();
      final env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider([ScriptedTurn.text('Das Wasser hat 19 Grad.')]),
        ),
        extraOverrides: [
          activeVoiceProvider.overrideWith(
            (ref) async => VoiceComponents(
              audio: FakeAudioInput(
                frames: AudioFrames.pattern('S' * 10 + '.' * 30),
              ),
              vad: FakeVoiceActivityDetector(),
              stt: FakeSpeechToText(const [
                Transcript(text: secret, language: 'de', confidence: 0.8),
              ]),
              textToSpeech: (_) async => tts,
              config: const VoicePipelineConfig(),
            ),
          ),
        ],
      );
      final c = env.container();
      addTearDown(c.dispose);
      c.listen(agentControllerProvider, (_, _) {});
      final voice = c.read(voiceControllerProvider.notifier);
      expect(await voice.start(TriggerKind.pushToTalk), isTrue);
      await voice.whenIdle;
      await Future<void>.delayed(Duration.zero);

      final latency = lines.where((l) => l.contains(' latency ')).toList();
      expect(latency, hasLength(1));
      expect(
        latency.single,
        matches(
          RegExp(r'^Wendelin/voice: latency engine=app( [a-z0-9_]+=\d+)+$'),
        ),
      );
      expect(latency.single, contains('calls=1'));
      expect(latency.single, contains('sentences='));
      expect(latency.single, isNot(contains(secret)));
      expect(latency.single, isNot(contains('Wasser')));
    },
  );

  test('Abbruch (Stopp) schreibt keine Zeile `latency`', () async {
    final lines = <String>[];
    voiceLogSink = lines.add;
    final tts = FakeTextToSpeech(manual: true);
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([ScriptedTurn.text('Das Wasser hat 19 Grad.')]),
      ),
      extraOverrides: [
        activeVoiceProvider.overrideWith(
          (ref) async => VoiceComponents(
            audio: FakeAudioInput(
              frames: AudioFrames.pattern('S' * 10 + '.' * 30),
            ),
            vad: FakeVoiceActivityDetector(),
            stt: FakeSpeechToText(const [
              Transcript(text: 'Wie warm ist es', language: 'de'),
            ]),
            textToSpeech: (_) async => tts,
            config: const VoicePipelineConfig(),
          ),
        ),
      ],
    );
    final c = env.container();
    addTearDown(c.dispose);
    c.listen(agentControllerProvider, (_, _) {});
    final voice = c.read(voiceControllerProvider.notifier);
    expect(await voice.start(TriggerKind.pushToTalk), isTrue);
    for (var i = 0; i < 100 && tts.current == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(tts.current, isNotNull, reason: 'die Antwort wird gesprochen');
    await voice.cancel();
    await voice.whenIdle;
    await Future<void>.delayed(Duration.zero);
    expect(lines.any((l) => l.contains('voice-cancelled')), isTrue);
    expect(lines.where((l) => l.contains(' latency ')), isEmpty);
  });
}
