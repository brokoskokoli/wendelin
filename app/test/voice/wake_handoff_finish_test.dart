// WP146: the service keeps recording after the take until the first frame of
// the app's microphone (no hole); `finish` is called exactly once, at that
// first frame (not after loading) and on every way out.

import 'dart:async';
import 'dart:typed_data';

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
import 'early_capture_test.dart' show RecordingStt;

void main() {
  late ProviderContainer c;
  late FakeAudioInput audio;
  final lines = <String>[];
  late void Function(String) savedSink;
  var finishes = 0;

  setUp(() {
    lines.clear();
    finishes = 0;
    savedSink = voiceLogSink;
    voiceLogSink = lines.add;
  });
  tearDown(() {
    voiceLogSink = savedSink;
    c.dispose();
  });

  VoiceController voice() => c.read(voiceControllerProvider.notifier);

  /// A hit whose service microphone still records (value 7 = its tail).
  WakePreRoll hit() => WakePreRoll(
    pcm: Int16List(1600)..fillRange(0, 1600, 3),
    wakeEnd: 0,
    finish: () async {
      finishes++;
      return (pcm: Int16List(800)..fillRange(0, 800, 7), lastSampleAtMs: null);
    },
  );

  VoiceComponents components(SpeechToText stt) => VoiceComponents(
    audio: audio,
    vad: FakeVoiceActivityDetector(),
    stt: stt,
    textToSpeech: (_) async => null,
    config: const VoicePipelineConfig(),
  );

  ProviderContainer container({
    required Future<VoiceComponents?> Function() load,
    bool ready = true,
  }) {
    audio = FakeAudioInput(
      frames: AudioFrames.pattern('S' * 10 + '.' * 40),
      frameInterval: const Duration(milliseconds: 30),
    );
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('Sonnig.')])),
      extraOverrides: [
        voiceReadyProvider.overrideWithValue(ready),
        audioInputProvider.overrideWithValue(audio),
        activeVoiceProvider.overrideWith((ref) => load()),
      ],
    );
    return c = env.container();
  }

  test(
    'finish beim ersten Frame, nicht erst nach dem Laden; Rest im Vorlauf',
    () {
      fakeAsync((async) {
        final stt = RecordingStt('Wetter?');
        container(
          load: () async {
            await Future<void>.delayed(const Duration(seconds: 2));
            return components(stt);
          },
        );
        c
          ..read(voiceControllerProvider)
          ..read(agentControllerProvider);
        unawaited(
          voice().start(TriggerKind.pushToTalk, takePreRoll: () async => hit()),
        );
        async.elapse(const Duration(milliseconds: 200));
        expect(audio.startCount, 1);
        expect(finishes, 1, reason: 'erster Frame da, Laden dauert noch');
        async.elapse(const Duration(seconds: 3));
        expect(finishes, 1, reason: 'genau einmal');
        for (var i = 0; i < 100; i++) {
          async.elapse(const Duration(milliseconds: 100));
        }
        final heard = stt.heard.single;
        expect(heard.where((s) => s == 3), hasLength(1600), reason: 'Vorlauf');
        expect(
          heard.where((s) => s == 7),
          hasLength(800),
          reason: 'Rest des Dienstes',
        );
        expect(heard.indexOf(7), greaterThan(heard.indexOf(3)));
      });
    },
  );

  test(
    'Modelle warm (Laden 0 ms): finish erst beim ersten Frame, Rest im Vorlauf',
    () {
      fakeAsync((async) {
        final stt = RecordingStt('Wetter?');
        container(load: () async => components(stt));
        c
          ..read(voiceControllerProvider)
          ..read(agentControllerProvider);
        unawaited(
          voice().start(TriggerKind.pushToTalk, takePreRoll: () async => hit()),
        );
        async.elapse(const Duration(milliseconds: 10));
        expect(audio.startCount, 1);
        expect(finishes, 0, reason: 'das App-Mikrofon hat noch keinen Frame');
        async.elapse(const Duration(milliseconds: 100));
        expect(finishes, 1, reason: 'erster Frame da');
        for (var i = 0; i < 100; i++) {
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(finishes, 1, reason: 'genau einmal');
        final heard = stt.heard.single;
        expect(heard.where((s) => s == 7), hasLength(800));
        expect(heard.indexOf(7), greaterThan(heard.indexOf(3)));
      });
    },
  );

  test('Abbruch während der Übernahme: Dienst-Aufnahme wird beendet', () async {
    container(load: () async => components(RecordingStt('x')));
    final take = Completer<WakePreRoll?>();
    final started = voice().start(
      TriggerKind.pushToTalk,
      takePreRoll: () => take.future,
    );
    await Future<void>.delayed(Duration.zero);
    await voice().cancel();
    take.complete(hit());
    expect(await started, isFalse);
    expect(audio.startCount, 0);
    expect(finishes, 1);
  });

  test(
    'Abbruch während close auf den ersten Frame wartet: Mikrofon aus',
    () {
      fakeAsync((async) {
        container(load: () async => components(RecordingStt('x')));
        c
          ..read(voiceControllerProvider)
          ..read(agentControllerProvider);
        bool? res;
        unawaited(
          voice()
              .start(TriggerKind.pushToTalk, takePreRoll: () async => hit())
              .then((v) => res = v),
        );
        async.elapse(const Duration(milliseconds: 10));
        expect(audio.startCount, 1);
        expect(finishes, 0, reason: 'close wartet noch auf den ersten Frame');
        unawaited(voice().cancel());
        async.elapse(const Duration(seconds: 5));
        expect(res, isFalse);
        expect(audio.isRunning, isFalse, reason: 'App-Mikrofon bleibt nicht an');
        expect(audio.stopCount, greaterThan(0));
        expect(finishes, 1);
      });
    },
  );

  test('Laden scheitert: Dienst-Aufnahme wird trotzdem beendet', () async {
    container(
      load: () async =>
          throw const VoiceException(VoiceErrorKind.failed, 'kaputt'),
    );
    expect(
      await voice().start(
        TriggerKind.pushToTalk,
        takePreRoll: () async => hit(),
      ),
      isFalse,
    );
    expect(finishes, 1);
  });

  test(
    'Modelle noch nicht bereit: beendet vor dem Start der Aufnahme',
    () async {
      final stt = RecordingStt('Wetter?');
      container(ready: false, load: () async => components(stt));
      expect(
        await voice().start(
          TriggerKind.pushToTalk,
          takePreRoll: () async => hit(),
        ),
        isTrue,
      );
      expect(finishes, 1);
      await voice().whenIdle;
      expect(stt.heard.single.where((s) => s == 7), hasLength(800));
    },
  );
}
