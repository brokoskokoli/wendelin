// WP165: the answer never runs in the call path (no audio mode
// `MODE_IN_COMMUNICATION`, no `USAGE_VOICE_COMMUNICATION`), also when the
// retired setting `voice.speechCommunication` is still stored as true.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/channel_audio_focus_port.dart';
import 'package:wendelin/platform/voice/ducking_tts.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/test_env.dart';
import 'tts_test.dart' show FakeSynthesizer;

final class _Focus implements AudioFocusPort {
  @override
  Stream<AudioFocusChange> get changes => const Stream.empty();

  @override
  Future<bool> acquire(AudioFocusKind kind) async => true;

  @override
  Future<void> release(AudioFocusKind kind) async {}
}

const _voice = SherpaVoice(
  id: 'tts-de-thorsten',
  language: 'de',
  name: 'Deutsch – Thorsten',
  files: PiperVoiceFiles(model: 'm', tokens: 't', dataDir: 'd'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'gespeichert voice.speechCommunication=true: Antwort im normalen Kontext',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final focusCalls = <String>[];
      final playerCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel(audioFocusChannelName),
        (call) async {
          focusCalls.add(call.method);
          return call.method == 'enterCommunication' ? 'speaker' : null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (call) async {
          playerCalls.add(call);
          return null;
        },
      );
      for (final name in const [
        'xyz.luan/audioplayers.global',
        'xyz.luan/audioplayers.global/events',
      ]) {
        messenger.setMockMethodCallHandler(
          MethodChannel(name),
          (_) async => null,
        );
      }
      addTearDown(() {
        for (final name in const [
          'xyz.luan/audioplayers.global',
          'xyz.luan/audioplayers.global/events',
        ]) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
        messenger.setMockMethodCallHandler(
          const MethodChannel(audioFocusChannelName),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          null,
        );
      });

      final env = TestEnv(
        extraOverrides: [
          audioFocusPortProvider.overrideWithValue(_Focus()),
          sherpaSynthesizerProvider.overrideWithValue(FakeSynthesizer()),
        ],
      );
      final c = env.container();
      addTearDown(c.dispose);
      await env.storage.settings.set(
        SettingKey.boolean('voice.speechCommunication'),
        true,
      );

      final real = Provider<TextToSpeech>(
        (ref) => createSherpaTts(ref, installed: () async => const [_voice]),
      );
      final tts = DuckingTextToSpeech(
        c.read(real),
        c.read(speechFocusProvider),
      );
      final spoken = tts.speak('Hallo', language: 'de');
      // The player starts after synthesis; the platform answers `null` to
      // everything, so the end comes from stop, not from the audio.
      for (
        var i = 0;
        i < 50 && !playerCalls.any((m) => m.method == 'setSourceBytes');
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        playerCalls.any((m) => m.method == 'setSourceBytes'),
        isTrue,
        reason: 'the answer must have started playing',
      );
      await tts.stop();
      unawaited(spoken.then((_) {}, onError: (_) {}));

      expect(focusCalls, isNot(contains('enterCommunication')));
      final contexts = [
        for (final m in playerCalls)
          if (m.method == 'setAudioContext') m.arguments as Map,
      ];
      for (final ctx in contexts) {
        expect(
          ctx['usageType'],
          isNot(AndroidUsageType.voiceCommunication.value),
          reason: 'USAGE_VOICE_COMMUNICATION',
        );
        expect(
          ctx['audioMode'],
          isNot(AndroidAudioMode.inCommunication.value),
          reason: 'MODE_IN_COMMUNICATION',
        );
      }
    },
  );
}
