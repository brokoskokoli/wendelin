import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/voice/recognizer_config.dart';

import '../overlay/assistant_overlay_test.dart' show FakeAssistantPlatform;
import '../support/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container(FakeAssistantPlatform platform) {
    final env = TestEnv();
    final c = ProviderContainer(
      overrides: [
        ...env.overrides,
        assistantPlatformProvider.overrideWithValue(platform),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'Spiegel der Spracheinstellungen: beim Start und bei Änderungen',
    () async {
      final platform = FakeAssistantPlatform();
      final c = container(platform)
        ..listen(recognizerConfigSyncProvider, (_, _) {});
      await c.read(voiceSettingsProvider.future);
      await pumpEventQueue();
      // „Wie die App“ → app language (de).
      expect(platform.recognizerConfigs, [
        const RecognizerConfig(
          model: 'whisper-base',
          language: 'de',
          vadThreshold: 0.5,
          minSpeechMs: 200,
        ),
      ]);

      await c
          .read(voiceSettingsProvider.notifier)
          .change(
            (s) => s.copyWith(
              sttModel: 'whisper-small',
              sttLanguage: VoiceSettings.detect,
              vadThreshold: 0.6,
              minSpeechMs: 300,
            ),
          );
      await pumpEventQueue();
      expect(
        platform.recognizerConfigs.last,
        const RecognizerConfig(
          model: 'whisper-small',
          language: null,
          vadThreshold: 0.6,
          minSpeechMs: 300,
        ),
      );

      // App language follows when the setting is „Wie die App“.
      await c
          .read(voiceSettingsProvider.notifier)
          .change((s) => s.copyWith(sttLanguage: VoiceSettings.followApp));
      await c.read(languageProvider.notifier).set('fr');
      await pumpEventQueue();
      expect(platform.recognizerConfigs.last.language, 'fr');
      final count = platform.recognizerConfigs.length;

      // Unrelated changes are not sent again.
      await c
          .read(voiceSettingsProvider.notifier)
          .change((s) => s.copyWith(ttsRate: 1.2));
      await pumpEventQueue();
      expect(platform.recognizerConfigs, hasLength(count));
    },
  );

  test('Angebot für andere Apps lesen und schalten', () async {
    final platform = FakeAssistantPlatform()..recognizerOffered = false;
    final c = container(platform);
    expect(await c.read(recognizerOfferedProvider.future), isFalse);
    await c.read(recognizerOfferedProvider.notifier).set(offered: true);
    expect(platform.recognizerOffered, isTrue);
    expect(c.read(recognizerOfferedProvider).value, isTrue);
  });

  group('AssistantPlatform-Kanal', () {
    const channel = MethodChannel('test.assistant');
    final calls = <MethodCall>[];
    Object? answer;

    setUp(() {
      calls.clear();
      answer = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return answer;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('Erkenner-Methoden', () async {
      final platform = AssistantPlatform(channel: channel);
      answer = false;
      expect(await platform.isRecognizerOffered(), isFalse);
      await platform.setRecognizerOffered(offered: true);
      await platform.setRecognizerConfig(
        const RecognizerConfig(
          model: 'whisper-base',
          language: null,
          vadThreshold: 0.5,
          minSpeechMs: 200,
        ),
      );
      expect(calls.map((c) => c.method), [
        'isRecognizerOffered',
        'setRecognizerOffered',
        'setRecognizerConfig',
      ]);
      expect(calls[1].arguments, {'offered': true});
      expect(calls[2].arguments, {
        'model': 'whisper-base',
        'language': '',
        'vadThreshold': 0.5,
        'minSpeechMs': 200,
      });
    });

    test('ohne Plattform: angeboten (Standard)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(
        await AssistantPlatform(channel: channel).isRecognizerOffered(),
        isTrue,
      );
    });
  });

  test('RecognizerConfig: Gleichheit', () {
    const a = RecognizerConfig(
      model: 'whisper-base',
      language: 'de',
      vadThreshold: 0.5,
      minSpeechMs: 200,
    );
    const b = RecognizerConfig(
      model: 'whisper-base',
      language: 'de',
      vadThreshold: 0.5,
      minSpeechMs: 200,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(
      a ==
          const RecognizerConfig(
            model: 'whisper-base',
            language: 'de',
            vadThreshold: 0.5,
            minSpeechMs: 300,
          ),
      isFalse,
    );
  });
}
