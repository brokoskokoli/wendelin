import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'voice_controller_test.dart' show utterance, waitConv, waitVoice;

/// Lead-in silence (200 frames, 200 ms real time at 1 ms per frame; below
/// the 8 s no-speech timeout of the audio time): the
/// gesture calls arrive long before any end by silence could fall due, so
/// the tests do not depend on the speed of the machine.
const _lead = 200;

/// Lead-in, 300 ms speech, 3 s pause, 300 ms speech (frames of 30 ms).
List<Int16List> longWithPause() =>
    AudioFrames.pattern('${'.' * _lead}${'S' * 10}${'.' * 100}${'S' * 10}');

/// Frames of the speech part (speech, pause, speech).
const _allFrames = 120;

/// All frames of [longWithPause].
const _total = _lead + _allFrames;

/// Hold gestures of the microphone button on the controller (WP192).
void main() {
  late FakeAudioInput audio;
  late FakeSpeechToText stt;
  late ProviderContainer c;

  VoiceController voice() => c.read(voiceControllerProvider.notifier);
  VoiceUiState ui() => c.read(voiceControllerProvider);

  void setup({
    required List<Int16List> frames,
    List<ScriptedTurn>? turns,
    int utterances = 1,
    EndpointConfig endpoint = const EndpointConfig(),
  }) {
    audio = FakeAudioInput(
      frames: frames,
      frameInterval: const Duration(milliseconds: 1),
    );
    stt = FakeSpeechToText([
      for (var i = 0; i < utterances; i++) Transcript(text: 'Satz $i'),
    ]);
    final components = VoiceComponents(
      audio: audio,
      vad: FakeVoiceActivityDetector(),
      stt: stt,
      textToSpeech: (_) async => FakeTextToSpeech(),
      config: VoicePipelineConfig(endpoint: endpoint),
    );
    c = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider(
          turns ??
              [for (var i = 0; i < utterances; i++) ScriptedTurn.text('Ok')],
        ),
      ),
      extraOverrides: [
        activeVoiceProvider.overrideWith((ref) async => components),
      ],
    ).container();
    addTearDown(c.dispose);
  }

  Future<void> played(int frames) async {
    for (var i = 0; i < 5000 && audio.deliveredFrames < frames; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(audio.deliveredFrames, greaterThanOrEqualTo(frames));
  }

  Future<void> opened(int starts) async {
    for (var i = 0; i < 5000 && audio.startCount < starts; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(audio.startCount, starts);
  }

  group('idle', () {
    test('Halten mit 3 s Pause: eine Äußerung mit allem Audio, '
        'erst Loslassen beendet', () async {
      setup(frames: longWithPause());
      await voice().pressDown();
      expect(ui().listening, isTrue);
      await opened(1);
      await voice().holdStart();
      await played(_total);
      // Without hold the 800 ms silence would have ended long ago.
      expect(ui().phase, VoiceState.listening);
      expect(stt.calls, isEmpty);
      await voice().pressUp(held: true);
      await voice().whenIdle;
      expect(stt.calls, hasLength(1));
      expect(stt.calls.single.samples, greaterThanOrEqualTo(_allFrames * 480));
      expect(audio.startCount, 1);
    });

    test('kurzer Tipp: normales Endpointing, kein Abbruch', () async {
      setup(frames: utterance());
      await voice().pressDown();
      await voice().pressUp(held: false);
      expect(ui().listening, isTrue, reason: 'Tipp bricht beim Start nicht ab');
      await voice().whenIdle;
      expect(stt.calls, hasLength(1));
      expect(stt.calls.single.samples, lessThan(60 * 480));
    });

    test('Start verweigert (prepare=false): Halten startet nichts', () async {
      setup(frames: longWithPause());
      await voice().pressDown(prepare: () async => false);
      await voice().holdStart();
      await voice().pressUp(held: true);
      expect(audio.startCount, 0);
      expect(ui().active, isFalse);
    });
  });

  group('Rennen während des Starts', () {
    test('holdStart während prepare kommt an, kein doppelter Start', () async {
      setup(frames: longWithPause());
      final gate = Completer<bool>();
      final down = voice().pressDown(prepare: () => gate.future);
      final hold = voice().holdStart();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(audio.startCount, 0, reason: 'wartet auf die Berechtigung');
      gate.complete(true);
      await down;
      await hold;
      await played(_total);
      expect(audio.startCount, 1);
      expect(ui().phase, VoiceState.listening, reason: 'gehalten');
      await voice().pressUp(held: true);
      await voice().whenIdle;
      expect(stt.calls, hasLength(1));
      expect(stt.calls.single.samples, greaterThanOrEqualTo(_allFrames * 480));
    });

    test(
      'pressUp(held) während prepare: nichts hängt, kein zweiter Start',
      () async {
        setup(frames: longWithPause());
        final gate = Completer<bool>();
        final down = voice().pressDown(prepare: () => gate.future);
        final hold = voice().holdStart();
        final up = voice().pressUp(held: true);
        gate.complete(true);
        await Future.wait([down, hold, up]);
        await voice().whenIdle;
        // Released before the recording began: nothing recorded, no second
        // start, nothing hangs.
        expect(audio.startCount, 0);
        expect(stt.calls, isEmpty);
        expect(ui().active, isFalse);
        expect(audio.isRunning, isFalse);
      },
    );
  });

  group('listening', () {
    test(
      'pressDown beendet nichts, Tipp (pressUp ohne Halten) bricht ab',
      () async {
        setup(frames: AudioFrames.pattern('S' * 300));
        await voice().start(TriggerKind.pushToTalk);
        await waitVoice(c, (v) => v.levels.isNotEmpty);
        await voice().pressDown();
        expect(
          ui().listening,
          isTrue,
          reason: 'pressDown allein beendet nichts',
        );
        expect(audio.startCount, 1);
        await voice().pressUp(held: false);
        await voice().whenIdle;
        expect(ui().phase, VoiceState.idle);
        expect(audio.isRunning, isFalse);
        expect(stt.calls, isEmpty);
      },
    );

    test(
      'Halten beim Zuhören: kein Ende durch Stille, Loslassen verarbeitet',
      () async {
        setup(frames: longWithPause());
        await voice().start(TriggerKind.pushToTalk);
        await waitVoice(c, (v) => v.levels.isNotEmpty);
        await voice().pressDown();
        await voice().holdStart();
        await played(_total);
        expect(ui().phase, VoiceState.listening);
        expect(stt.calls, isEmpty);
        await voice().pressUp(held: true);
        await voice().whenIdle;
        expect(stt.calls, hasLength(1));
        expect(
          stt.calls.single.samples,
          greaterThanOrEqualTo(_allFrames * 480),
        );
      },
    );
  });

  group('Zuhören, Fenster läuft während der Haltegrenze ab', () {
    test('pressDown hält sofort: kein Stille-Ende vor holdStart', () async {
      // Speech, then 100 frames of silence: the silence end falls due about
      // 37 frames after the start, long before the 450 ms of a real press.
      setup(
        frames: AudioFrames.pattern('${'.' * _lead}${'S' * 10}${'.' * 100}'),
      );
      await voice().start(TriggerKind.pushToTalk);
      await waitVoice(c, (v) => v.levels.isNotEmpty);
      await voice().pressDown();
      // No holdStart yet (the threshold has not passed): the whole audio
      // incl. the silence arrives; without the early hold it would end.
      await played(_lead + 110);
      expect(ui().phase, VoiceState.listening, reason: 'gehalten ab Druck');
      expect(stt.calls, isEmpty);
      await voice().holdStart();
      await voice().pressUp(held: true);
      await voice().whenIdle;
      expect(stt.calls, hasLength(1));
      expect(stt.calls.single.samples, greaterThanOrEqualTo(110 * 480));
    });
    test('pressAbort (Button vor der Haltegrenze entfernt): Halten wird '
        'aufgehoben, Zuhören endet normal, kein Abbruch', () async {
      setup(
        frames: AudioFrames.pattern('${'.' * _lead}${'S' * 10}${'.' * 100}'),
      );
      await voice().start(TriggerKind.pushToTalk);
      await waitVoice(c, (v) => v.levels.isNotEmpty);
      await voice().pressDown();
      await voice().pressAbort();
      // Without the abort the hold would keep the listening open for 2 min.
      await voice().whenIdle;
      expect(stt.calls, hasLength(1));
      expect(stt.calls.single.samples, lessThan(80 * 480));
    });

    test('pressAbort ohne Druck oder nach Loslassen: keine Wirkung', () async {
      setup(frames: utterance());
      await voice().pressAbort();
      await voice().pressDown();
      await voice().pressUp(held: false);
      await voice().pressAbort();
      expect(ui().listening, isTrue);
      await voice().whenIdle;
      expect(stt.calls, hasLength(1));
    });
  });

  group('getippte Agent-Anfrage', () {
    test('läuft: Drücken bricht ab, Halten startet eine gehaltene '
        'Aufnahme', () async {
      setup(
        frames: longWithPause(),
        // The cancelled typed request never reaches the model: its turn
        // stays for the voice request.
        turns: [ScriptedTurn.text('Ok')],
      );
      unawaited(c.read(agentControllerProvider.notifier).send('Hallo'));
      await waitConv(c, (s) => s.running);
      expect(ui().active, isFalse);
      await voice().pressDown();
      await voice().holdStart();
      await opened(1);
      await played(_total);
      expect(c.read(agentControllerProvider).running, isFalse);
      expect(ui().phase, VoiceState.listening, reason: 'gehalten');
      expect(stt.calls, isEmpty);
      await voice().pressUp(held: true);
      await voice().whenIdle;
      expect(stt.calls, hasLength(1));
      expect(stt.calls.single.samples, greaterThanOrEqualTo(_allFrames * 480));
    });
  });

  group('thinking', () {
    Future<void> thinking() async {
      await voice().start(TriggerKind.pushToTalk);
      await waitVoice(c, (v) => v.phase == VoiceState.thinking);
      await waitConv(
        c,
        (s) => s.entries.whereType<AssistantTextEntry>().isNotEmpty,
      );
    }

    test(
      'pressDown bricht ab wie ein Tipp, Loslassen ohne Halten bleibt idle',
      () async {
        setup(
          frames: utterance(),
          turns: [ScriptedTurn.hang(partialText: 'x')],
        );
        await thinking();
        await voice().pressDown();
        await voice().pressUp(held: false);
        await c.read(agentControllerProvider.notifier).idle;
        await voice().whenIdle;
        expect(ui().active, isFalse);
        expect(audio.startCount, 1, reason: 'keine neue Aufnahme');
      },
    );

    test(
      'Halten: Abbruch, dann neue Aufnahme; Loslassen verarbeitet',
      () async {
        setup(
          frames: longWithPause(),
          utterances: 2,
          turns: [
            ScriptedTurn.hang(partialText: 'x'),
            ScriptedTurn.text('Ok'),
          ],
        );
        await voice().start(TriggerKind.pushToTalk);
        await waitVoice(c, (v) => v.phase == VoiceState.thinking);
        await waitConv(
          c,
          (s) => s.entries.whereType<AssistantTextEntry>().isNotEmpty,
        );
        final before = audio.deliveredFrames;
        await voice().pressDown();
        await voice().holdStart();
        await opened(2); // new recording
        await waitVoice(c, (v) => v.phase == VoiceState.listening);
        await played(before + _total);
        expect(ui().phase, VoiceState.listening, reason: 'gehalten');
        expect(stt.calls, hasLength(1), reason: 'nur die erste Äußerung');
        await voice().pressUp(held: true);
        await voice().whenIdle;
        expect(stt.calls, hasLength(2));
        expect(stt.calls.last.samples, greaterThanOrEqualTo(_allFrames * 480));
      },
    );
  });

  group('Obergrenze', () {
    test('VoiceHoldLimitReached: Hinweis, Äußerung wird verarbeitet', () async {
      setup(
        frames: AudioFrames.pattern('S' * 100),
        endpoint: const EndpointConfig(holdMaxDuration: Duration(seconds: 1)),
      );
      await voice().pressDown();
      await voice().holdStart();
      final v = await waitVoice(c, (v) => v.hint == voiceHoldLimitHint);
      expect(
        voiceStatusText(AppLocalizationsDe(), v.hint!),
        contains('Maximale'),
      );
      await voice().whenIdle;
      expect(stt.calls, hasLength(1));
      await voice().pressUp(held: true); // after the end: no-op
      expect(ui().active, isFalse);
    });
  });
}
