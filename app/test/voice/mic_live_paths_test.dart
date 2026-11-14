// WP198: „Ich höre zu“ (`micLive`) auf jedem Startweg, auf dem Ton für die
// Anfrage ankommt (Vorlauf des Weckworts), und nicht ohne Ton.

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

/// Mikrofon, das schon läuft (ein anderer Zuhörer hält es): wie alle echten
/// Eingänge wirft `start` dann busy.
final class BusyInput implements AudioInput {
  int starts = 0;
  int stops = 0;

  @override
  bool get isRunning => true;

  @override
  Stream<Int16List> start() {
    starts++;
    throw const VoiceException(VoiceErrorKind.busy, 'busy');
  }

  @override
  Future<void> stop() async => stops++;
}

void main() {
  late ProviderContainer c;
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

  group('WP198 Startwege: Ton kommt an -> „Ich höre zu“', () {
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

    test('Vorlauf, danach erster App-Block: mic-ready wird weiter gemessen und '
        'der Dienst beendet', () {
      fakeAsync((async) {
        final mic = GatedInput();
        setUpContainer(mic);
        var finished = 0;
        final pre = WakePreRoll(
          pcm: Int16List(1600)..fillRange(0, 1600, 3),
          wakeEnd: 0,
          finish: () async {
            finished++;
            return (pcm: Int16List(0), lastSampleAtMs: null);
          },
        );
        unawaited(
          voice().start(TriggerKind.wakeWord, takePreRoll: () async => pre),
        );
        async.elapse(const Duration(seconds: 1));
        expect(ui().micLive, isTrue, reason: 'Vorlauf');
        expect(finished, 0, reason: 'noch kein App-Block');
        mic.open();
        async.elapse(const Duration(milliseconds: 100));
        expect(finished, 1, reason: 'erster App-Block beendet den Dienst');
        async.elapse(const Duration(seconds: 3));
        expect(
          lines.where((l) => l.contains(' mic-ready ')),
          hasLength(1),
          reason: lines.join(' | '),
        );
      });
    });

    test(
      'Vorlauf ohne Ton (leer), App-Mikrofon still -> bleibt „Moment …“',
      () {
        fakeAsync((async) {
          final mic = GatedInput();
          setUpContainer(mic);
          final pre = WakePreRoll(pcm: Int16List(0), wakeEnd: 0);
          unawaited(
            voice().start(TriggerKind.wakeWord, takePreRoll: () async => pre),
          );
          async.elapse(const Duration(seconds: 1));
          expect(ui().preparing, isTrue);
          expect(ui().micLive, isFalse);
        });
      },
    );

    test('Mikrofon gehört einem anderen Zuhörer: prime() öffnet nichts und '
        'beendet es nicht, micLive bleibt false', () {
      fakeAsync((async) {
        final mic = BusyInput();
        setUpContainer(mic);
        unawaited(voice().start(TriggerKind.assistant));
        async.elapse(const Duration(seconds: 1));
        expect(ui().preparing, isTrue);
        expect(mic.starts, 0, reason: 'prime() lässt es in Ruhe');
        expect(mic.stops, 0, reason: 'fremdes Mikrofon nicht beendet');
        expect(ui().micLive, isFalse);
        expect(ui().error, isNull);
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
