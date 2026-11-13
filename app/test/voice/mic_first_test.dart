// WP194: microphone first. The microphone opens before anything loads, the
// first block marks it live (`micLive`) even while the models still load,
// and a push-to-talk release during the loading processes the buffer.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'early_capture_test.dart' show RecordingStt, speechSamples;

void main() {
  late ProviderContainer c;
  late TestEnv env;
  final lines = <String>[];
  late void Function(String) savedSink;

  setUp(() {
    lines.clear();
    savedSink = voiceLogSink;
    voiceLogSink = lines.add;
  });
  tearDown(() {
    voiceLogSink = savedSink;
    c.dispose();
  });

  VoiceController voice() => c.read(voiceControllerProvider.notifier);
  VoiceUiState ui() => c.read(voiceControllerProvider);

  /// Speech right after the tap, then a long silence (30 ms frames).
  FakeAudioInput microphone() => FakeAudioInput(
    frames: AudioFrames.pattern('S' * 10 + '.' * 400),
    frameInterval: const Duration(milliseconds: 30),
  );

  VoiceComponents components(AudioInput audio, SpeechToText stt) =>
      VoiceComponents(
        audio: audio,
        vad: FakeVoiceActivityDetector(),
        stt: stt,
        textToSpeech: (_) async => null,
        config: const VoicePipelineConfig(),
      );

  ProviderContainer container({
    required AudioInput audio,
    required Future<VoiceComponents?> Function() load,
    bool ready = true,
    List<Object> extra = const [],
  }) {
    env = TestEnv(
      providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('Sonnig.')])),
      extraOverrides: [
        voiceReadyProvider.overrideWithValue(ready),
        audioInputProvider.overrideWithValue(audio),
        activeVoiceProvider.overrideWith((ref) => load()),
      ],
    );
    c = env.container();
    c
      ..read(voiceControllerProvider)
      ..read(agentControllerProvider);
    return c;
  }

  group('Anzeige: micLive mit dem ersten Mikrofonblock (Teil C)', () {
    test('wird während des Ladens true, nicht erst danach', () {
      fakeAsync((async) {
        final audio = microphone();
        final stt = RecordingStt('x');
        container(
          audio: audio,
          load: () async {
            await Future<void>.delayed(const Duration(seconds: 2));
            return components(audio, stt);
          },
        );
        unawaited(voice().start(TriggerKind.pushToTalk));
        async.flushMicrotasks();
        expect(ui().preparing, isTrue);
        expect(ui().micLive, isFalse, reason: 'noch kein Block');
        async.elapse(const Duration(milliseconds: 100));
        expect(ui().preparing, isTrue, reason: 'Modelle laden noch');
        expect(ui().micLive, isTrue, reason: 'erster Block da');
        final ready = lines.where((l) => l.contains(' mic-ready ')).toList();
        expect(ready, isEmpty, reason: 'Laden noch nicht fertig');
        async.elapse(const Duration(seconds: 2));
        unawaited(voice().cancel());
        async.flushMicrotasks();
        expect(ui().micLive, isFalse, reason: 'nach dem Ende zurückgesetzt');
        expect(ui().active, isFalse);
        final line = lines.singleWhere((l) => l.contains(' mic-ready '));
        expect(line, contains('open=0'));
      });
    });

    test('ohne Block bleibt micLive false, der Fehlerpfad greift', () {
      fakeAsync((async) {
        // A microphone that ends at once without any frame.
        final audio = FakeAudioInput(frames: const []);
        container(
          audio: audio,
          load: () async {
            await Future<void>.delayed(const Duration(seconds: 2));
            throw const VoiceException(VoiceErrorKind.failed, 'kaputt');
          },
        );
        var result = true;
        unawaited(
          voice().start(TriggerKind.pushToTalk).then((r) => result = r),
        );
        async.elapse(const Duration(seconds: 1));
        expect(ui().preparing, isTrue);
        expect(ui().micLive, isFalse, reason: 'kein Block, kein „hört zu“');
        async.elapse(const Duration(seconds: 2));
        expect(result, isFalse);
        expect(ui().error, 'kaputt');
        expect(ui().micLive, isFalse);
        expect(ui().preparing, isFalse);
      });
    });
  });

  group('Push-to-Talk während des Ladens (WP192-Folgepunkt, Teil D)', () {
    test('Loslassen vor Ende des Ladens: gepufferter Ton wird erkannt', () {
      fakeAsync((async) {
        final audio = microphone();
        final stt = RecordingStt('Wie wird das Wetter?');
        container(
          audio: audio,
          load: () async {
            await Future<void>.delayed(const Duration(seconds: 2));
            return components(audio, stt);
          },
        );
        unawaited(voice().pressDown());
        async.elapse(const Duration(milliseconds: 500));
        unawaited(voice().holdStart());
        async.elapse(const Duration(milliseconds: 500));
        // Released after 1 s, the models still load (until 2 s).
        unawaited(voice().pressUp(held: true));
        async.elapse(const Duration(milliseconds: 1200));
        expect(ui().preparing, isFalse);
        for (var i = 0; i < 50; i++) {
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(stt.heard, hasLength(1), reason: lines.join(' | '));
        expect(speechSamples(stt.heard.single), 10 * 480);
        expect(lines.any((l) => l.contains('nothing')), isFalse);
      });
    });
  });
}
