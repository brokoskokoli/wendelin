// WP160 Analyse: Rollo gesperrt mit erkannter Stimme (Handy-Log 19:02:42).
// Erwartung ADR 0022: Standard C/D läuft gesperrt nie.
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../overlay/assistant_overlay_test.dart'
    show FakeAssistantPlatform, overlaySample, pumpOverlay;
import '../support/test_env.dart';
import 'voice_controller_test.dart' show fakeVoice;

final _known = FakeSpeakerRecognizer(
  const SpeakerMatch.known(personId: 'p1', name: 'Anna', score: 0.8),
);

Future<(TestEnv, FakeLlmProvider)> _run(
  WidgetTester tester,
  String entities,
  String service,
) async {
  final llm = FakeLlmProvider([
    ScriptedTurn.toolCalls([
      ToolCallBlock(
        id: '1',
        name: 'ha__call',
        argumentsJson:
            '{"entity":"cover.r","service":"$service","position_pct":50}',
      ),
    ]),
    ScriptedTurn.text('Fertig.'),
  ]);
  final env = TestEnv(
    providerConfig: scripted(llm),
    startup: const StartupSettings(enabledIntegrations: {'flashlight', 'ha'}),
  );
  await env.secrets.write('ha.url', 'http://192.168.1.20:8123');
  await env.secrets.write('ha.token', 'a' * 40);
  await env.secrets.write('ha.entities', entities);
  env.ha.set('light.a', 'off', const {});
  env.ha.set('cover.r', 'closed', const {'device_class': 'shutter'});
  // Kein Licht auf A, nur Rollo; Modelllauf nur, wenn Umfang > Lampe.
  final platform = FakeAssistantPlatform()
    ..locked = true
    ..unlockSucceeds = false;
  final c = await pumpOverlay(
    tester,
    env,
    platform,
    voice: fakeVoice(
      script: [const Transcript(text: 'Rollo halb', language: 'de')],
      tts: FakeTextToSpeech(),
      speaker: _known,
    ),
  );
  c.read(agentControllerProvider.notifier).seed(overlaySample());
  for (var i = 0; i < 800; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final v = c.read(voiceControllerProvider);
    if (i > 5 && !v.active && !v.preparing) break;
  }
  await c.read(voiceControllerProvider.notifier).whenIdle;
  await tester.pump(const Duration(milliseconds: 50));
  return (env, llm);
}

void main() {
  for (final svc in ['set_cover_position', 'open_cover']) {
    for (final quiet in [true, false]) {
      testWidgets('Rollo shutter gesperrt, Stimme erkannt, quiet=$quiet, '
          '$svc: kein HA-Aufruf', (tester) async {
        final (env, llm) = await _run(
          tester,
          '[{"id":"light.a","name":"Flur","level":"a"},{"id":"cover.r","name":"Rollo","quiet":$quiet}]',
          svc,
        );
        expect(llm.requests, isNotEmpty, reason: 'Modelllauf muss kommen');
        expect(env.ha.calls, isEmpty);
      });
    }
  }
  for (final lvl in ['a', 'b']) {
    testWidgets('Gegenprobe: Rollo mit gespeicherter Stufe $lvl, gesperrt, '
        'Stimme erkannt', (tester) async {
      final (env, llm) = await _run(
        tester,
        '[{"id":"light.a","name":"Flur","level":"a"},{"id":"cover.r","name":"Rollo","level":"$lvl"}]',
        'set_cover_position',
      );
      // Nur Beleg, welche Daten das Log erklären (läuft erwartungsgemäß).
      expect(env.ha.calls, isNotEmpty);
    });
  }
}
