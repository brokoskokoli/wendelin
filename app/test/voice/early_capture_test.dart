// B11 (Gerätetest 2026-10-13): the first tap after a pause took ~2 s until
// the microphone opened (Whisper loaded first), the start of the sentence
// was lost. The microphone now opens at once and buffers while the models
// load (WP30).

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/voice_usage.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';

/// [SpeechToText] that keeps the audio it got.
final class RecordingStt implements SpeechToText {
  RecordingStt(this.text);

  final String text;
  final heard = <Int16List>[];

  @override
  SpeechToTextEngineInfo get info => const SpeechToTextEngineInfo(
    name: 'Test',
    languages: {'de'},
    model: 'whisper-small',
  );

  @override
  Future<Transcript> transcribe(Int16List pcm, {String? language}) async {
    heard.add(pcm);
    return Transcript(text: text, language: 'de');
  }
}

int speechSamples(Int16List pcm) => pcm.where((s) => s != 0).length;

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

  /// Speech right after the tap: 0,3 s speech, then silence (30 ms frames
  /// in real time, like a microphone).
  FakeAudioInput microphone() => FakeAudioInput(
    frames: AudioFrames.pattern('S' * 10 + '.' * 40),
    frameInterval: const Duration(milliseconds: 30),
  );

  ProviderContainer container({
    required AudioInput audio,
    required Future<VoiceComponents?> Function() load,
    bool? ready = true,
  }) {
    env = TestEnv(
      providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('Sonnig.')])),
      extraOverrides: [
        if (ready != null) voiceReadyProvider.overrideWithValue(ready),
        audioInputProvider.overrideWithValue(audio),
        activeVoiceProvider.overrideWith((ref) => load()),
      ],
    );
    return c = env.container();
  }

  VoiceComponents components(AudioInput audio, SpeechToText stt) =>
      VoiceComponents(
        audio: audio,
        vad: FakeVoiceActivityDetector(),
        stt: stt,
        textToSpeech: (_) async => null,
        config: const VoicePipelineConfig(),
      );

  test(
    'Aufnahme startet sofort, Laden dauert 2 s: kein Satzanfang verloren',
    () {
      // Fake clock: the 2 s load and the 30 ms frames take no real time.
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
        // The screen is up (controllers built) before the tap.
        c
          ..read(voiceControllerProvider)
          ..read(agentControllerProvider);
        async.elapse(const Duration(milliseconds: 20));
        final tap = async.elapsed;
        var started = false;
        unawaited(
          voice().start(TriggerKind.pushToTalk).then((ok) => started = ok),
        );
        async.flushMicrotasks();
        expect(audio.startCount, 1, reason: 'Tipp → Mikrofon ohne Wartezeit');
        expect(async.elapsed - tap, Duration.zero);
        // While the models load: buffering, shown as preparing (WP31).
        final v = c.read(voiceControllerProvider);
        expect(v.preparing, isTrue);
        expect(v.listening, isTrue);
        expect(v.active, isTrue);

        async.elapse(const Duration(milliseconds: 1990));
        expect(started, isFalse, reason: 'Modelle laden noch');
        async.elapse(const Duration(milliseconds: 20));
        expect(started, isTrue);
        expect(c.read(voiceControllerProvider).preparing, isFalse);
        var idle = false;
        unawaited(voice().whenIdle.then((_) => idle = true));
        for (var i = 0; i < 100 && !idle; i++) {
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(idle, isTrue);

        // The whole utterance reached Whisper, from its first frame on.
        expect(stt.heard, hasLength(1));
        expect(speechSamples(stt.heard.single), 10 * 480);
        expect(
          c
              .read(agentControllerProvider)
              .entries
              .whereType<UserEntry>()
              .single
              .text,
          'Wie wird das Wetter?',
        );
        expect(audio.startCount, 1, reason: 'eine Aufnahme, kein Neustart');
        expect(audio.isRunning, isFalse);

        final ready = lines.singleWhere((l) => l.contains(' mic-ready '));
        final after = int.parse(RegExp(r'after=(\d+)').firstMatch(ready)![1]!);
        final load = int.parse(RegExp(r'load=(\d+)').firstMatch(ready)![1]!);
        expect(after, lessThanOrEqualTo(150), reason: ready);
        expect(load, greaterThanOrEqualTo(2000), reason: ready);
        expect(ready, contains('model=whisper-small'));
      });
    },
  );

  test('Sprachanfrage merkt sich nur den Zeitpunkt (Vorwärmen)', () async {
    final audio = microphone();
    final stt = RecordingStt('Hallo');
    container(audio: audio, load: () async => components(audio, stt));
    expect(await env.storage.settings.get(voiceLastUseKey), isNull);
    expect(await voice().start(TriggerKind.pushToTalk), isTrue);
    await voice().whenIdle;
    expect(await env.storage.settings.get(voiceLastUseKey), testNow.toUtc());
  });

  test('ohne installierte Modelle: keine Aufnahme, Hinweis', () async {
    final audio = microphone();
    container(audio: audio, ready: false, load: () async => null);
    expect(await voice().start(TriggerKind.pushToTalk), isFalse);
    expect(audio.startCount, 0);
    expect(c.read(voiceControllerProvider).error, voiceUnavailableHint);
    expect(c.read(voiceControllerProvider).active, isFalse);
  });

  test('Laden scheitert: Mikrofon wieder zu, Fehler', () async {
    final audio = microphone();
    container(
      audio: audio,
      load: () async =>
          throw const VoiceException(VoiceErrorKind.failed, 'kaputt'),
    );
    expect(await voice().start(TriggerKind.pushToTalk), isFalse);
    expect(audio.startCount, 1);
    expect(audio.isRunning, isFalse);
    final v = c.read(voiceControllerProvider);
    expect(v.error, 'kaputt');
    expect(v.preparing, isFalse);
    expect(v.active, isFalse);
  });

  test('Abbruch während des Ladens: Mikrofon zu, kein Start', () async {
    final audio = microphone();
    final gate = Completer<void>();
    final stt = RecordingStt('x');
    container(
      audio: audio,
      load: () async {
        await gate.future;
        return components(audio, stt);
      },
    );
    final started = voice().start(TriggerKind.pushToTalk);
    while (audio.startCount == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(c.read(voiceControllerProvider).active, isTrue);
    await voice().tap(); // tap while preparing = cancel
    expect(audio.isRunning, isFalse);
    gate.complete();
    expect(await started, isFalse);
    expect(stt.heard, isEmpty);
    expect(c.read(voiceControllerProvider).active, isFalse);
  });

  test(
    'Vorwärmen lädt die Modelle, der Tipp danach braucht kein Laden',
    () async {
      final audio = microphone();
      final stt = RecordingStt('Hallo');
      var loads = 0;
      var warm = 0;
      container(
        audio: audio,
        load: () async {
          loads++;
          return VoiceComponents(
            audio: audio,
            vad: FakeVoiceActivityDetector(),
            stt: stt,
            textToSpeech: (_) async => null,
            config: const VoicePipelineConfig(),
            warmUp: () async => warm++,
          );
        },
      );
      voice().prewarm();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(loads, 1);
      expect(warm, 1);
      expect(lines.any((l) => l.contains(' prewarm ')), isTrue);
      expect(await voice().start(TriggerKind.pushToTalk), isTrue);
      await voice().whenIdle;
      expect(loads, 1);
      expect(stt.heard, hasLength(1));
    },
  );

  test('Demo: kein Vorwärmen, kein frühes Mikrofon', () async {
    final audio = microphone();
    env = TestEnv(
      demo: true,
      extraOverrides: [audioInputProvider.overrideWithValue(audio)],
    );
    c = env.container();
    voice().prewarm();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(lines.where((l) => l.contains(' prewarm ')), isEmpty);
    expect(audio.startCount, 0);
  });

  test(
    'frische Engine (Overlay): Modelle erst prüfen, dann sofort aufnehmen',
    () async {
      final audio = microphone();
      final gate = Completer<void>();
      final stt = RecordingStt('Hallo');
      container(
        audio: audio,
        ready: null,
        load: () async {
          await gate.future;
          return components(audio, stt);
        },
      );
      env.speechModels.installed.addAll({
        const VoiceSettings().sttModel,
        SpeechModelCatalog.sileroVad.id,
      });
      final started = voice().start(TriggerKind.assistant);
      for (var i = 0; i < 100 && audio.startCount == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(audio.startCount, 1, reason: 'vor dem Laden der Modelle');
      gate.complete();
      expect(await started, isTrue);
      await voice().whenIdle;
      expect(speechSamples(stt.heard.single), 10 * 480);
    },
  );

  test(
    'Erklärung abgelehnt: Mikrofon zu, Puffer leer, nichts erkannt',
    () async {
      final audio = microphone();
      final stt = RecordingStt('Hallo');
      container(audio: audio, load: () async => components(audio, stt));
      // The explanation is open while the microphone already buffers.
      expect(
        await voice().start(
          TriggerKind.pushToTalk,
          prepare: () async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return false;
          },
        ),
        isFalse,
      );
      expect(audio.startCount, 1);
      expect(audio.isRunning, isFalse, reason: 'Mikrofon zu');
      final v = c.read(voiceControllerProvider);
      expect(v.error, microphoneDeniedHint);
      expect(v.preparing, isFalse);
      expect(v.active, isFalse);
      // A later request starts empty: no frame of the declined recording.
      expect(await voice().start(TriggerKind.pushToTalk), isTrue);
      await voice().whenIdle;
      expect(stt.heard, hasLength(1));
      expect(speechSamples(stt.heard.single), 10 * 480);
    },
  );

  test('Berechtigung erst jetzt erteilt: Mikrofon wird neu geöffnet', () async {
    final inner = microphone();
    final audio = _DeniedOnce(inner);
    final stt = RecordingStt('Hallo');
    container(audio: audio, load: () async => components(audio, stt));
    expect(
      await voice().start(TriggerKind.pushToTalk, prepare: () async => true),
      isTrue,
    );
    await voice().whenIdle;
    expect(audio.starts, 2);
    expect(stt.heard, hasLength(1));
  });
}

/// Microphone without permission on the first start (Android asks during
/// the explanation), then a working one.
final class _DeniedOnce implements AudioInput {
  _DeniedOnce(this.inner);

  final FakeAudioInput inner;
  int starts = 0;

  @override
  bool get isRunning => inner.isRunning;

  @override
  Stream<Int16List> start() {
    if (++starts == 1) {
      throw const VoiceException(VoiceErrorKind.permissionDenied, 'nein');
    }
    return inner.start();
  }

  @override
  Future<void> stop() => inner.stop();
}
