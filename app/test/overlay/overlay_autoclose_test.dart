// WP172: the overlay closes itself when listening ended and nothing is left
// to do (`overlay-close by=idle`), releases the host (the wake word listens
// again) and stays open while the user interacts or waits for an answer.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import '../voice/voice_controller_test.dart' show utterance;
import 'assistant_overlay_test.dart'
    show FakeAssistantPlatform, overlaySample, pumpOverlay;

Future<void> _pump(WidgetTester t, {int steps = 100, int ms = 100}) async {
  for (var i = 0; i < steps; i++) {
    await t.pump(Duration(milliseconds: ms));
  }
}

void main() {
  late FakeAssistantPlatform platform;
  late List<String> logs;
  late FakeLlmProvider llm;
  late List<VoiceState> phases;
  late void Function(String) savedSink;

  setUp(() {
    AssistantOverlayScreen.tearDownEngine = (_, _) async {};
    AssistantOverlayScreen.closeWhenIdle = true;
    platform = FakeAssistantPlatform();
    llm = FakeLlmProvider([ScriptedTurn.text('Es ist 8 Uhr 12.')]);
    logs = [];
    phases = [];
    savedSink = voiceLogSink;
    voiceLogSink = logs.add;
  });
  tearDown(() => voiceLogSink = savedSink);

  bool closedBy(String by) =>
      logs.any((l) => l.contains('overlay-close') && l.contains('by=$by'));

  bool closedByIdle() =>
      logs.any((l) => l.contains('overlay-close') && l.contains('by=idle'));

  VoiceComponents voice({
    required List<Transcript> script,
    bool conversation = false,
    Duration speak = Duration.zero,
  }) => VoiceComponents(
    audio: FakeAudioInput(
      frames: utterance(),
      frameInterval: const Duration(milliseconds: 30),
    ),
    vad: FakeVoiceActivityDetector(),
    stt: FakeSpeechToText(script),
    textToSpeech: (_) async => FakeTextToSpeech(utteranceDuration: speak),
    config: VoicePipelineConfig(conversationMode: conversation),
  );

  // Opens the overlay; `autoStart` fires the first trigger only after the
  // phase recorder listens (the first start must not be missed).
  Future<ProviderContainer> open(
    WidgetTester tester, {
    List<Transcript> script = const [
      Transcript(text: 'Wie spät ist es?', language: 'de'),
    ],
    bool conversation = false,
    bool autoStart = true,
    Duration speak = Duration.zero,
  }) async {
    final c = await pumpOverlay(
      tester,
      TestEnv(providerConfig: scripted(llm)),
      platform,
      autoStart: false,
      voice: voice(script: script, conversation: conversation, speak: speak),
    );
    c.listen(voiceControllerProvider.select((v) => v.phase), (_, p) {
      phases.add(p);
    });
    if (autoStart) platform.trigger();
    return c;
  }

  // Seeds „listening ended“ the way the pipeline reports it.
  Future<void> endListening(WidgetTester t, ProviderContainer c) async {
    final v = c.read(voiceControllerProvider.notifier);
    v.seed(const VoiceUiState(phase: VoiceState.listening));
    await t.pump();
    v.seed(const VoiceUiState());
    await t.pump();
  }

  testWidgets('Antwort fertig, kein Gespraechsmodus: Overlay schliesst', (
    tester,
  ) async {
    await open(tester);
    await _pump(tester);
    expect(phases, containsAll([VoiceState.thinking, VoiceState.speaking]));
    expect(
      llm.requests,
      hasLength(1),
      reason: 'die Anfrage lief durch den Agenten',
    );
    expect(closedByIdle(), isTrue);
    // releaseHost -> Kotlin sends overlayClosed -> the wake word listens.
    expect(platform.calls.where((x) => x == 'releaseHost'), hasLength(1));
  });

  testWidgets('nichts gesagt (leeres Transkript): Overlay schliesst', (
    tester,
  ) async {
    await open(tester, script: const [Transcript(text: '')]);
    await _pump(tester);
    expect(phases, contains(VoiceState.listening));
    expect(llm.requests, isEmpty);
    expect(closedByIdle(), isTrue);
    expect(platform.calls, contains('releaseHost'));
  });

  testWidgets(
    'Gespraechsmodus: Folge-Zuhoeren ohne Aeusserung (Timeout) -> zu',
    (tester) async {
      await open(
        tester,
        conversation: true,
        script: const [
          Transcript(text: 'Wie spät ist es?', language: 'de'),
          Transcript(text: ''),
        ],
      );
      await _pump(tester, steps: 600, ms: 500);
      expect(phases.where((p) => p == VoiceState.speaking), isNotEmpty);
      expect(llm.requests, hasLength(1));
      expect(closedByIdle(), isTrue);
      expect(platform.calls, contains('releaseHost'));
    },
  );

  group('bleibt offen', () {
    Future<void> expectOpen(WidgetTester t) async {
      await _pump(t, steps: 30);
      expect(platform.calls, isNot(contains('releaseHost')));
      expect(logs.any((l) => l.contains('overlay-close')), isFalse);
    }

    testWidgets('offene Rueckfrage/Bestaetigung (pending)', (tester) async {
      final c = await open(tester, autoStart: false);
      c
          .read(agentControllerProvider.notifier)
          .seed(
            ConversationState(
              pending: ToolQuestion(
                ConfirmationRequired(
                  call: call(
                    'c1',
                    'calendar__delete_event',
                    '{"event_id":"e1"}',
                  ),
                  description: 'Termin löschen',
                  respond: (_) {},
                ),
                request: 'Lösch den Termin',
              ),
            ),
          );
      await endListening(tester, c);
      await expectOpen(tester);
    });

    testWidgets('Antwort laeuft noch (agent running)', (tester) async {
      final c = await open(tester, autoStart: false);
      c
          .read(agentControllerProvider.notifier)
          .seed(ConversationState(running: true));
      await endListening(tester, c);
      await expectOpen(tester);
    });

    testWidgets('GPU-Block wartet auf Tipp', (tester) async {
      final c = await open(tester, autoStart: false);
      c
          .read(agentControllerProvider.notifier)
          .seed(
            ConversationState(
              gpuBlock: const GpuBlock(
                profileId: 'p',
                request: 'Frage',
                reason: 'GPU',
              ),
            ),
          );
      await endListening(tester, c);
      await expectOpen(tester);
    });

    testWidgets('Tippen/Tastatur', (tester) async {
      final c = await open(tester, autoStart: false);
      c
          .read(voiceControllerProvider.notifier)
          .seed(const VoiceUiState(phase: VoiceState.listening));
      await tester.pump();
      await tester.tap(find.byTooltip(AppLocalizationsDe().overlayTextInput));
      await endListening(tester, c);
      await expectOpen(tester);
    });

    testWidgets('Entsperr-Abfrage (gesperrt, Anfrage wartet)', (tester) async {
      platform.locked = true;
      final c = await open(tester, autoStart: false);
      c.read(lockedPendingProvider.notifier).keep('Wie spät ist es');
      await endListening(tester, c);
      await expectOpen(tester);
    });
  });

  testWidgets(
    'Rennen: Trigger und zweites Schliessen waehrend des Schliessens',
    (tester) async {
      final c = await open(tester, autoStart: false);
      await endListening(tester, c); // closing starts here (synchronously)
      final lockChecks = platform.lockChecks;
      platform.trigger();
      unawaited(platform.closeHandler!());
      await _pump(tester, steps: 30);
      expect(tester.takeException(), isNull);
      expect(platform.lockChecks, lockChecks, reason: 'Trigger ignoriert');
      expect(platform.calls.where((x) => x == 'releaseHost'), hasLength(1));
      expect(
        c.read(voiceControllerProvider).active,
        isFalse,
        reason: 'der Trigger startet nach dem Schliessen kein Zuhoeren',
      );
    },
  );

  testWidgets('Retrigger waehrend des Zuhoerens schliesst nicht', (
    tester,
  ) async {
    await open(tester);
    for (var i = 0; i < 100 && !phases.contains(VoiceState.listening); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(phases, contains(VoiceState.listening));
    platform.trigger(); // cancels the running listen (retrigger), starts anew
    await tester.pump(const Duration(milliseconds: 50));
    expect(logs.any((l) => l.contains('overlay-close')), isFalse);
    expect(platform.calls, isNot(contains('releaseHost')));
  });

  testWidgets('Gesperrt, teils erledigt: das Entsperr-Angebot geht nicht '
      'durch das Schliessen verloren', (tester) async {
    platform.locked = true;
    final c = await open(tester, autoStart: false);
    await _pump(tester, steps: 3);
    final v = c.read(voiceControllerProvider.notifier)
      ..seed(const VoiceUiState(phase: VoiceState.speaking));
    await tester.pump();
    // The refusal and the end of the spoken hint come in the same moment;
    // lockedPending stays empty (onPartlyDone, WP154).
    v.seed(const VoiceUiState()); // idle is reported before the refusal
    c.read(lockedRefusalsProvider.notifier).bump();
    await _pump(tester, steps: 10);
    expect(platform.unlockRequests, 1, reason: 'die Abfrage wurde gestellt');
    expect(closedByIdle(), isFalse);
  });

  // Keyboard opened and closed again without sending (WP172).
  group('Tastatur auf und wieder zu', () {
    Future<void> openClose(WidgetTester t) async {
      final tip = find.byTooltip(AppLocalizationsDe().overlayTextInput);
      expect(tip, findsOneWidget);
      await t.tap(tip);
      await t.pump();
      expect(logs.any((l) => l.contains('overlay-close')), isFalse);
      await t.tap(tip);
      await _pump(t, steps: 30);
    }

    testWidgets('nichts offen: schliesst by=idle', (tester) async {
      await open(tester, autoStart: false);
      await openClose(tester);
      expect(closedByIdle(), isTrue);
      expect(platform.calls.where((x) => x == 'releaseHost'), hasLength(1));
    });

    testWidgets('offene Rueckfrage: bleibt offen', (tester) async {
      final c = await open(tester, autoStart: false);
      c
          .read(agentControllerProvider.notifier)
          .seed(
            ConversationState(
              pending: ToolQuestion(
                ConfirmationRequired(
                  call: call('c1', 'calendar__delete_event', '{}'),
                  description: 'Termin löschen',
                  respond: (_) {},
                ),
                request: 'Lösch den Termin',
              ),
            ),
          );
      await openClose(tester);
      expect(logs.any((l) => l.contains('overlay-close')), isFalse);
    });

    // (Locked, the keyboard button is disabled: no unlock case here.)
    testWidgets('Antwort laeuft noch: bleibt offen', (tester) async {
      final c = await open(tester, autoStart: false);
      c
          .read(agentControllerProvider.notifier)
          .seed(ConversationState(running: true));
      await openClose(tester);
      expect(logs.any((l) => l.contains('overlay-close')), isFalse);
    });
  });

  // Mic tap while listening or during the answer acts like a stop: short
  // „Abgebrochen.“, then the stop path closes (by=stop, releaseHost).
  for (final during in [
    VoiceState.listening,
    VoiceState.thinking,
    VoiceState.speaking,
  ]) {
    testWidgets('Mikro-Tipp waehrend ${during.name}: wie Stopp, schliesst '
        'by=stop', (tester) async {
      if (during == VoiceState.thinking) {
        llm = FakeLlmProvider([ScriptedTurn.hang()]);
      }
      await open(tester, speak: const Duration(minutes: 5));
      for (var i = 0; i < 300 && !phases.contains(during); i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(phases.last, during);
      await tester.tap(find.byType(MicButton));
      await tester.pump();
      expect(find.text('Abgebrochen.'), findsOneWidget);
      expect(closedBy('stop'), isFalse, reason: 'erst nach der Meldung');
      await tester.pump(
        AssistantOverlayScreen.stopCloseDelay +
            const Duration(milliseconds: 50),
      );
      await _pump(tester, steps: 5);
      expect(closedBy('stop'), isTrue);
      expect(closedByIdle(), isFalse);
      expect(platform.calls.where((x) => x == 'releaseHost'), hasLength(1));
    });
  }

  testWidgets('Tastatur waehrend des echten Zuhoerens: kein Schliessen', (
    tester,
  ) async {
    await open(tester);
    for (var i = 0; i < 100 && !phases.contains(VoiceState.listening); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(phases, contains(VoiceState.listening));
    await tester.tap(find.byTooltip(AppLocalizationsDe().overlayTextInput));
    await _pump(tester, steps: 30);
    expect(phases.last, VoiceState.idle, reason: 'Zuhoeren wurde beendet');
    // Well past stopCloseDelay: no closing at all (neither idle nor stop).
    final closes = logs.where((l) => l.contains('overlay-close')).toList();
    expect(closes, isEmpty, reason: 'Tastatur: das Overlay bleibt offen');
    expect(platform.calls, isNot(contains('releaseHost')));
  });

  testWidgets('Rueckgaengig bei Sprachausgabe: das Fenster bleibt', (
    tester,
  ) async {
    final c = await open(tester, speak: const Duration(seconds: 3));
    for (var i = 0; i < 200 && phases.lastOrNull != VoiceState.speaking; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(phases.last, VoiceState.speaking, reason: 'echte Sprachausgabe');
    // An undoable entry (the answer itself is not undoable).
    c.read(agentControllerProvider.notifier).seed(overlaySample());
    await tester.pump();
    // The undo cancels the running output itself (idle inside `undo`).
    await tester.tap(find.textContaining('Rückgängig'));
    await _pump(tester, steps: 10);
    expect(phases.last, VoiceState.idle, reason: 'die Ausgabe wurde beendet');
    expect(logs.any((l) => l.contains('overlay-close')), isFalse);
    expect(platform.calls, isNot(contains('releaseHost')));
  });

  testWidgets('Erkennungsfehler: Meldung bleibt kurz sichtbar, dann zu', (
    tester,
  ) async {
    final c = await open(tester, autoStart: false);
    final v = c.read(voiceControllerProvider.notifier)
      ..seed(const VoiceUiState(phase: VoiceState.listening));
    await tester.pump();
    v.seed(const VoiceUiState(error: 'Erkennung fehlgeschlagen'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Erkennung fehlgeschlagen'), findsOneWidget);
    expect(logs.any((l) => l.contains('overlay-close')), isFalse);
    await tester.pump(
      AssistantOverlayScreen.stopCloseDelay + const Duration(milliseconds: 50),
    );
    await _pump(tester, steps: 5);
    expect(closedBy('idle-error'), isTrue);
    expect(platform.calls, contains('releaseHost'));
  });
  // A stop or error message arms a delayed close; later activity of the user
  // (trigger, microphone, keyboard) must cancel it (review round 2, no. 3/4).
  group('Schliess-Timer nach Stopp/Fehler wird abgebrochen', () {
    final messages = <String, VoiceUiState>{
      'Fehler': const VoiceUiState(error: 'Erkennung fehlgeschlagen'),
      'Stopp': const VoiceUiState(stopCount: 1),
    };
    for (final m in messages.entries) {
      // Arms the timer: listening ended with the message.
      Future<ProviderContainer> arm(WidgetTester tester) async {
        final c = await open(tester, autoStart: false);
        final v = c.read(voiceControllerProvider.notifier)
          ..seed(const VoiceUiState(phase: VoiceState.listening));
        await tester.pump();
        v.seed(m.value);
        await tester.pump();
        await tester.pump();
        return c;
      }

      Future<void> afterDelay(WidgetTester tester) async {
        await tester.pump(
          AssistantOverlayScreen.stopCloseDelay +
              const Duration(milliseconds: 50),
        );
        await _pump(tester, steps: 5);
      }

      testWidgets('${m.key}: Trigger bricht den Timer ab', (tester) async {
        await arm(tester);
        platform.trigger();
        await tester.pump();
        await afterDelay(tester);
        // The new request may end by itself (idle), but never by the timer.
        expect(closedBy(m.key == 'Stopp' ? 'stop' : 'idle-error'), isFalse);
      });

      testWidgets('${m.key}: neues Zuhoeren (Mikro-Tipp) schliesst nicht', (
        tester,
      ) async {
        final c = await arm(tester);
        c
            .read(voiceControllerProvider.notifier)
            .seed(const VoiceUiState(phase: VoiceState.listening));
        await tester.pump();
        await afterDelay(tester);
        expect(logs.any((l) => l.contains('overlay-close')), isFalse);
      });

      testWidgets('${m.key}: Tastatur oeffnen schliesst nicht', (tester) async {
        await arm(tester);
        await tester.tap(find.byTooltip(AppLocalizationsDe().overlayTextInput));
        await tester.pump();
        await afterDelay(tester);
        expect(logs.any((l) => l.contains('overlay-close')), isFalse);
      });
    }
  });

  testWidgets('Stopp-Meldung, Zuhoeren laeuft weiter: Trigger bricht den '
      'Timer ab', (tester) async {
    final c = await open(tester, autoStart: false);
    // Stop message while the phase stays active: no listening edge later.
    final v = c.read(voiceControllerProvider.notifier)
      ..seed(const VoiceUiState(phase: VoiceState.listening));
    await tester.pump();
    v.seed(const VoiceUiState(phase: VoiceState.listening, stopCount: 1));
    await tester.pump();
    platform.trigger();
    await _pump(tester, steps: 3);
    await tester.pump(
      AssistantOverlayScreen.stopCloseDelay + const Duration(milliseconds: 50),
    );
    await _pump(tester, steps: 5);
    expect(closedBy('stop'), isFalse);
  });

  testWidgets('Tastaturwechsel: kein „Abgebrochen.“, kein Stopp-Zaehler, '
      'ein echtes Stoppwort danach schliesst', (tester) async {
    final c = await open(tester);
    for (var i = 0; i < 100 && !phases.contains(VoiceState.listening); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.tap(find.byTooltip(AppLocalizationsDe().overlayTextInput));
    await _pump(tester, steps: 30);
    expect(phases.last, VoiceState.idle);
    expect(c.read(voiceControllerProvider).stopCount, 0);
    expect(find.text('Abgebrochen.'), findsNothing);
    expect(logs.any((l) => l.contains('overlay-close')), isFalse);
    // A real stop word with the keyboard open acts as usual.
    c
        .read(voiceControllerProvider.notifier)
        .seed(const VoiceUiState(stopCount: 1));
    await tester.pump();
    await tester.pump(
      AssistantOverlayScreen.stopCloseDelay + const Duration(milliseconds: 50),
    );
    await _pump(tester, steps: 5);
    expect(closedBy('stop'), isTrue);
  });
}
