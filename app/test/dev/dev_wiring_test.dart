// WP148: Verdrahtung des Entwicklerlogs – Werkzeugzeilen im Tipp-Chat und im
// Sprachweg (je genau einmal), Schalter wirkt ohne Neustart (Flag wird je
// Sitzung/Anfrage aus der Datenbank gelesen), stt-reject aus der Pipeline.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/dev_log.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';

const _create =
    '{"title":"Tauchen","start":"2026-10-14T10:00","end":"2026-10-14T11:00"}';

List<ScriptedTurn> _turns() => [
  ScriptedTurn.toolCalls([
    const ToolCallBlock(
      id: 'c1',
      name: 'calendar__create_event',
      argumentsJson: _create,
    ),
  ]),
  ScriptedTurn.text('Erledigt.'),
];

Future<void> _store(TestEnv env, {required bool on}) =>
    env.storage.settings.set(AppSettings.developerMode, on);

VoiceComponents _components(Transcript t) => VoiceComponents(
  audio: FakeAudioInput(frames: AudioFrames.pattern('S' * 10 + '.' * 30)),
  vad: FakeVoiceActivityDetector(),
  stt: FakeSpeechToText([t]),
  textToSpeech: (_) async => FakeTextToSpeech(),
  config: const VoicePipelineConfig(),
);

void main() {
  late List<String> lines;
  setUp(() {
    lines = [];
    devLogSink = lines.add;
  });

  List<String> only(String event) =>
      lines.where((l) => l.contains(' $event ')).toList();

  group('Tipp-Chat', () {
    Future<ProviderContainer> run(TestEnv env) async {
      final c = env.container();
      addTearDown(c.dispose);
      final controller = c.read(agentControllerProvider.notifier);
      await controller.send('Trag mir morgen um 10 Tauchen ein');
      await controller.idle;
      return c;
    }

    test('Flag nur in der Datenbank (anderer Prozess): Zeilen je einmal, '
        'Flag wird gelesen', () async {
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(_turns())));
      await _store(env, on: true);
      expect(devLogEnabled, isFalse);
      await run(env);
      expect(devLogEnabled, isTrue);
      expect(only('tool-call'), hasLength(1));
      expect(only('tool-call').single, contains('calendar__create_event'));
      expect(only('tool-call').single, contains('Tauchen'));
      expect(only('tool-result'), hasLength(1));
    });

    test('Flag ausgeschaltet ohne Neustart: nächste Anfrage schreibt nichts '
        'mehr', () async {
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(_turns())));
      await _store(env, on: false);
      devLogEnabled = true; // Zustand dieser Engine vom Start
      await run(env);
      expect(devLogEnabled, isFalse);
      expect(lines, isEmpty);
    });

    test('ohne Flag keine Zeile', () async {
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(_turns())));
      await run(env);
      expect(lines, isEmpty);
    });
  });

  group('Sprachweg', () {
    Future<void> speak(TestEnv env, {bool expectStarted = true}) async {
      final c = env.container();
      addTearDown(c.dispose);
      c.listen(agentControllerProvider, (_, _) {});
      final voice = c.read(voiceControllerProvider.notifier);
      expect(await voice.start(TriggerKind.pushToTalk), expectStarted);
      await voice.whenIdle;
    }

    test('Werkzeugzeilen genau einmal (kein Doppel durch zwei Wege), Flag '
        'aus der Datenbank', () async {
      final env = TestEnv(
        providerConfig: scripted(FakeLlmProvider(_turns())),
        extraOverrides: [
          activeVoiceProvider.overrideWith(
            (ref) async => _components(
              const Transcript(
                text: 'Trag mir morgen um 10 Tauchen ein',
                language: 'de',
                confidence: 0.9,
              ),
            ),
          ),
        ],
      );
      await _store(env, on: true);
      await speak(env);
      expect(only('tool-call'), hasLength(1));
      expect(only('tool-result'), hasLength(1));
    });

    test('unsichere Erkennung: stt-reject mit Text, nur mit Flag', () async {
      for (final on in [true, false]) {
        lines.clear();
        final env = TestEnv(
          providerConfig: scripted(FakeLlmProvider(_turns())),
          extraOverrides: [
            activeVoiceProvider.overrideWith(
              (ref) async => _components(
                const Transcript(
                  text: 'Wetter morgen',
                  language: 'de',
                  confidence: 0.18,
                ),
              ),
            ),
          ],
        );
        await _store(env, on: on);
        devLogEnabled = false;
        await speak(env);
        expect(only('stt-reject'), on ? hasLength(1) : isEmpty);
        if (on) expect(only('stt-reject').single, contains('Wetter morgen'));
      }
    });
  });
}
