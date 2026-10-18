import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'voice_controller_test.dart' show utterance;

enum _Phase { listening }

void main() {
  group('logValue: nur Codes, nie Inhalte', () {
    test('Zahlen, Wahrheitswerte, Dauern, Enums, kurze Codes', () {
      expect(logValue(42), '42');
      expect(logValue(0.123), '0.12');
      expect(logValue(true), 'true');
      expect(logValue(const Duration(milliseconds: 1530)), '1530');
      expect(logValue(_Phase.listening), 'listening');
      expect(logValue('whisper-small'), 'whisper-small');
      expect(logValue('capture-null(no-speech)'), 'capture-null(no-speech)');
    });

    test('Text mit Leerzeichen, Großbuchstaben oder Umlauten wird zu ?', () {
      expect(logValue('Lösch den Zahnarzttermin'), '?');
      expect(logValue('Wendelin-Test'), '?');
      expect(logValue('Ja'), '?');
      expect(logValue('a' * 49), '?');
      expect(logValue(Object()), '?');
    });

    test('Fehler nur mit ihrem Typ', () {
      expect(
        errorCode(const VoiceException(VoiceErrorKind.failed, 'Notiz X')),
        'voiceexception',
      );
      expect(errorCode(StateError('geheim')), 'stateerror');
    });

    test('Zeile: Präfix, Ereignis, Engine, Felder; null fällt weg', () {
      final lines = <String>[];
      final saved = voiceLogSink;
      voiceLogSink = lines.add;
      addTearDown(() => voiceLogSink = saved);
      voiceLog('confirm-exit', {'reason': 'unclear', 'tap': true, 'x': null});
      expect(lines, [
        'Wendelin/voice: confirm-exit engine=app reason=unclear tap=true',
      ]);
    });
  });

  test('Beispielanfrage per Stimme: kein Transkript, keine Notiz, keine Antwort im Log', () async {
    // Everything printed during the request (also other debugPrint lines).
    final printed = <String>[];
    final savedPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = savedPrint);
    // flutter_test_config.dart puffert die Senke; hier soll sie drucken.
    voiceLogSink = (l) => debugPrint(l);

    const secrets = [
      'Xylophon', // transcript
      'Wendelin-Test', // note name in the request and the tool call
      'Geheimantwort', // answer text
      'Vielleicht', // unclear spoken answer
    ];
    final tts = FakeTextToSpeech();
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
          ], text: 'Ich lösche Wendelin-Test.'),
          ScriptedTurn.text('Geheimantwort für dich.'),
        ]),
      ),
      extraOverrides: [
        activeVoiceProvider.overrideWith(
          (ref) async => VoiceComponents(
            audio: FakeAudioInput(frames: utterance()),
            vad: FakeVoiceActivityDetector(),
            stt: FakeSpeechToText(const [
              Transcript(text: 'Lösch Xylophon in Wendelin-Test'),
              Transcript(text: 'Vielleicht'),
              Transcript(text: 'Nein'),
            ]),
            textToSpeech: (_) async => tts,
            config: const VoicePipelineConfig(),
          ),
        ),
      ],
    );
    final c = env.container();
    addTearDown(c.dispose);
    await env.calendar.createEvent(zahnarztDraft());
    final voice = c.read(voiceControllerProvider.notifier);
    await voice.start(TriggerKind.pushToTalk);
    await voice.whenIdle;
    await c.read(agentControllerProvider.notifier).idle;

    final voiceLines = printed.where((l) => l.startsWith(voiceLogPrefix));
    expect(voiceLines, isNotEmpty);
    expect(
      voiceLines.where((l) => l.contains(' confirm-exit ')).single,
      contains('reason=answered(no)'),
    );
    for (final line in printed) {
      for (final s in secrets) {
        expect(line, isNot(contains(s)), reason: line);
      }
    }
  });
}
