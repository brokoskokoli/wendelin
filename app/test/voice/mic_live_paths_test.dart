// WP198 (Analyse): Startwege, auf denen Ton für die Anfrage ankommt, aber
// `micLive` („Ich höre zu“) nicht gesetzt wird. Absichtlich ROT bis zum Fix.

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'early_capture_test.dart' show RecordingStt;

/// Mikrofon, das erst Ton liefert, wenn [open] gerufen wird (z. B. der
/// Dienst hält die Aufnahme, bis er beendet ist).
final class GatedInput implements AudioInput {
  bool _open = false;
  bool _running = false;
  int delivered = 0;

  void open() => _open = true;

  @override
  bool get isRunning => _running;

  @override
  Stream<Int16List> start() {
    _running = true;
    return Stream.periodic(const Duration(milliseconds: 30), (_) {
      delivered++;
      return Int16List(480)..fillRange(0, 480, 5000);
    }).where((_) => _open).takeWhile((_) => _running);
  }

  @override
  Future<void> stop() async => _running = false;
}

/// Mikrofon, das schon läuft (jemand anderes hat es geöffnet) und jedem
/// neuen Zuhörer Ton liefert.
final class AlreadyRunningInput implements AudioInput {
  int delivered = 0;
  int starts = 0;

  @override
  bool get isRunning => true;

  @override
  Stream<Int16List> start() {
    starts++;
    return Stream.periodic(const Duration(milliseconds: 30), (_) {
      delivered++;
      return Int16List(480)..fillRange(0, 480, 5000);
    });
  }

  @override
  Future<void> stop() async {}
}

void main() {
  late ProviderContainer c;

  tearDown(() => c.dispose());

  VoiceController voice() => c.read(voiceControllerProvider.notifier);
  VoiceUiState ui() => c.read(voiceControllerProvider);

  VoiceComponents components(AudioInput audio) => VoiceComponents(
    audio: audio,
    vad: FakeVoiceActivityDetector(),
    stt: RecordingStt('x'),
    textToSpeech: (_) async => null,
    config: const VoicePipelineConfig(),
  );

  void setUpContainer(
    AudioInput audio, {
    Duration load = const Duration(seconds: 3),
  }) {
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('Sonnig.')])),
      extraOverrides: [
        voiceReadyProvider.overrideWithValue(true),
        audioInputProvider.overrideWithValue(audio),
        activeVoiceProvider.overrideWith((ref) async {
          await Future<void>.delayed(load);
          return components(audio);
        }),
      ],
    );
    c = env.container();
    c
      ..read(voiceControllerProvider)
      ..read(agentControllerProvider);
  }

  group('WP198 Startwege: Ton kommt an, micLive fehlt', () {
    test('Weckwort-Übergabe: Dienst nimmt auf (keepOpen), das App-Mikrofon '
        'liefert erst nach Dienst-Ende -> „Ich höre zu“ schon beim Laden', () {
      fakeAsync((async) {
        final mic = GatedInput();
        setUpContainer(mic);
        final pre = WakePreRoll(
          pcm: Int16List(1600)..fillRange(0, 1600, 3),
          wakeEnd: 0,
          finish: () async {
            mic.open();
            return (pcm: Int16List(800), lastSampleAtMs: null);
          },
        );
        unawaited(
          voice().start(TriggerKind.wakeWord, takePreRoll: () async => pre),
        );
        async.elapse(const Duration(seconds: 1));
        expect(ui().preparing, isTrue, reason: 'Modelle laden noch');
        // Der Dienst nimmt Ton für diese Anfrage auf (Vorlauf + Rest).
        expect(
          ui().micLive,
          isTrue,
          reason: 'Ton der Anfrage kommt über den Dienst, Anzeige „Moment …“',
        );
      });
    });

    test('Vorlauf (Weckwort) liegt vor, App-Mikrofon still -> micLive', () {
      fakeAsync((async) {
        final mic = GatedInput(); // liefert nie
        setUpContainer(mic);
        final pre = WakePreRoll(
          pcm: Int16List(1600)..fillRange(0, 1600, 3),
          wakeEnd: 0,
        );
        unawaited(
          voice().start(TriggerKind.wakeWord, takePreRoll: () async => pre),
        );
        async.elapse(const Duration(seconds: 1));
        expect(ui().preparing, isTrue);
        expect(ui().micLive, isTrue, reason: 'Vorlauf-Ton ist angekommen');
      });
    });

    test('Mikrofon läuft schon (prime kehrt bei isRunning zurück): Ton wird '
        'beim Laden weder gepuffert noch gemeldet', () {
      fakeAsync((async) {
        final mic = AlreadyRunningInput();
        setUpContainer(mic);
        unawaited(voice().start(TriggerKind.assistant));
        async.elapse(const Duration(seconds: 1));
        expect(ui().preparing, isTrue);
        expect(mic.starts, 1, reason: 'prime() hat das Mikrofon geöffnet');
        expect(ui().micLive, isTrue, reason: 'Ton liegt an');
      });
    });
  });

  group('WP198 Gegenprobe (grün): ohne Ton bleibt „Moment …“', () {
    test('Mikrofon still, kein Vorlauf', () {
      fakeAsync((async) {
        final mic = GatedInput();
        setUpContainer(mic);
        unawaited(voice().start(TriggerKind.assistant));
        async.elapse(const Duration(seconds: 1));
        expect(ui().preparing, isTrue);
        expect(ui().micLive, isFalse);
      });
    });
  });
}
