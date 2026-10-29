import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/attestation_hub.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_settings.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin/ui/overlay/overlay_sheet.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/host_calls.dart';
import '../support/tee_app_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart';
import '../voice/voice_controller_test.dart' show fakeVoice, utterance;

/// Stand-in for the Kotlin side of the assistant.
final class FakeAssistantPlatform extends AssistantPlatform
    with HostCallRecorder {
  bool locked = false;
  Completer<bool>? lockAnswer;
  bool unlockSucceeds = true;
  Future<void> Function()? closeHandler;
  bool isDefault = false;

  /// Audio of a wake word hit that opened the overlay (WP50), taken once.
  Int16List? wakeHandoff;
  int unlockRequests = 0;
  int settingsOpened = 0;
  final _triggers = StreamController<void>.broadcast(sync: true);

  void trigger() => _triggers.add(null);

  @override
  Stream<void> get triggers => _triggers.stream;

  @override
  Future<bool> isLocked() async {
    lockChecks++;
    if (lockError != null) throw lockError!;
    return lockAnswer?.future ?? Future.value(locked);
  }

  int lockChecks = 0;

  /// [isLocked] throws this, if set (WP158).
  Object? lockError;

  @override
  set onCloseRequested(Future<void> Function()? handler) =>
      closeHandler = handler;

  @override
  Future<bool> requestUnlock() async {
    unlockRequests++;
    final ok = await unlockGate?.future ?? unlockSucceeds;
    if (ok) locked = false;
    return ok;
  }

  /// Holds the unlock request open until completed (keyguard showing).
  Completer<bool>? unlockGate;

  @override
  Future<bool> hasWakeHandoff() async {
    await wakeGate?.future;
    return wakeHandoff != null;
  }

  /// Holds [hasWakeHandoff] back (the first trigger waits for it).
  Completer<void>? wakeGate;

  /// Moment ([hasWakeHandoff] .. take) for tests: how often it was taken.
  int wakeTakes = 0;

  /// Called at every take (tests record the order of messages).
  void Function()? onTake;

  /// Holds the take back (tests).
  Completer<void>? takeGate;

  @override
  Future<WakeHandoffAudio?> takeWakeHandoff({bool keepOpen = false}) async {
    wakeTakes++;
    if (keepOpen) wakeKeptOpen++;
    onTake?.call();
    await takeGate?.future;
    final audio = wakeHandoff;
    wakeHandoff = null;
    return audio == null
        ? null
        : WakeHandoffAudio(pcm: audio, wakeEnd: wakeEnd, capturedMs: 120);
  }

  /// Reports of the voice controller to the wake-word service (WP146).
  final appVoice = <bool>[];

  @override
  Future<void> appVoiceActive({required bool active}) async =>
      appVoice.add(active);

  /// Takes with `keepOpen` (WP146) and ends of such a handoff.
  int wakeKeptOpen = 0;
  int wakeFinishes = 0;

  /// What the service recorded between take and finish.
  WakeHandoffAudio? finishAudio;

  @override
  Future<WakeHandoffAudio?> finishWakeHandoff() async {
    wakeFinishes++;
    return finishAudio;
  }

  /// Where the wake word ends in [wakeHandoff].
  int? wakeEnd;

  @override
  Future<bool> isDefaultAssistant() async => isDefault;

  @override
  Future<bool> openAssistantSettings() async {
    settingsOpened++;
    return true;
  }

  /// „Als Spracherkennung für andere Apps anbieten“.
  bool recognizerOffered = true;

  /// System speech recognizer for other apps (B12).
  RecognitionServiceStatus recognition = RecognitionServiceStatus.unknown;

  /// Number of reads of [recognition].
  int recognitionChecks = 0;

  @override
  Future<RecognitionServiceStatus> recognitionService() async {
    recognitionChecks++;
    return recognition;
  }

  /// Mirrored speech settings (WP20).
  final recognizerConfigs = <RecognizerConfig>[];

  @override
  Future<bool> isRecognizerOffered() async => recognizerOffered;

  @override
  Future<void> setRecognizerOffered({required bool offered}) async =>
      recognizerOffered = offered;

  @override
  Future<void> setRecognizerConfig(RecognizerConfig config) async =>
      recognizerConfigs.add(config);

  @override
  void dispose() {}
}

/// The overlay app over a grey stand-in for „some other app“.
Future<ProviderContainer> pumpOverlay(
  WidgetTester tester,
  TestEnv env,
  FakeAssistantPlatform platform, {
  bool autoStart = true,
  VoiceComponents? voice,
  bool Function()? voiceGone,
  List<Override> extra = const [],
}) async {
  setView(tester, screenSize);
  await tester.pumpWidget(
    RepaintBoundary(
      key: goldenKey,
      child: ColoredBox(
        color: WColors.line,
        child: ProviderScope(
          overrides: [
            ...env.overrides,
            ...extra,
            assistantPlatformProvider.overrideWithValue(platform),
            voiceReadyProvider.overrideWithValue(true),
            activeVoiceProvider.overrideWith(
              (ref) async =>
                  voiceGone?.call() ?? false ? null : (voice ?? fakeVoice()),
            ),
          ],
          retry: (_, _) => null,
          child: AssistantOverlayApp(autoStart: autoStart),
        ),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(AssistantOverlayScreen)),
  );
}

/// Sample of docs/design/screens/overlay.
ConversationState overlaySample() => ConversationState(
  entries: [
    SessionStartEntry('s', testNow),
    const UserEntry('u1', 'Trag mir morgen um zehn Tauchen ein.'),
    const ToolEntry(
      'c1',
      toolName: 'calendar__create_event',
      phase: ToolPhase.done,
      summary: 'Termin angelegt: Tauchen · Di 13.10. · 10:00–11:00 · Privat',
      undo: UndoPhase.pending,
      undoRemaining: Duration(seconds: 8),
    ),
    const AssistantTextEntry(
      'a1',
      'Erledigt. Tauchen steht morgen um 10 Uhr in deinem privaten Kalender.',
    ),
  ],
  activeProfileId: 'phala',
  verification: VerificationStatus.verified,
);

/// Stand-in that records the audio Whisper gets.
final class _CapturingStt implements SpeechToText {
  final heard = <Int16List>[];

  @override
  SpeechToTextEngineInfo get info => const SpeechToTextEngineInfo(
    name: 'Capture',
    languages: {'de'},
    model: 'fake',
  );

  @override
  Future<Transcript> transcribe(Int16List pcm, {String? language}) async {
    heard.add(pcm);
    return const Transcript(text: '');
  }
}

Future<int> _toneCalls(
  WidgetTester tester, {
  required bool tone,
  required bool wake,
}) async {
  var plays = 0;
  final platform = FakeAssistantPlatform();
  if (wake) platform.wakeHandoff = Int16List.fromList(List.filled(8000, 300));
  final env = TestEnv(
    providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('x')])),
  );
  await tester.runAsync(() async {
    await env.storage.settings.set(wakeToneKey, tone);
  });
  await pumpOverlay(
    tester,
    env,
    platform,
    extra: [wakeConfirmToneProvider.overrideWithValue(() async => plays++)],
  );
  await tester.pump(const Duration(milliseconds: 60));
  return plays;
}

void toneTests() {
  group('Bestätigungston (WP50 b)', () {
    testWidgets('Wake Word + Ton an: Ton', (tester) async {
      expect(await _toneCalls(tester, tone: true, wake: true), 1);
    });
    testWidgets('anderer Auslöser: kein Ton', (tester) async {
      expect(await _toneCalls(tester, tone: true, wake: false), 0);
    });
    testWidgets('Ton aus: kein Ton', (tester) async {
      expect(await _toneCalls(tester, tone: false, wake: true), 0);
    });

    testWidgets('der Ton wird aus der Aufnahme geschnitten (exakt)', (
      tester,
    ) async {
      final platform = FakeAssistantPlatform()
        ..wakeHandoff = Int16List.fromList(List.filled(8000, 300));
      final stt = _CapturingStt();
      final env = TestEnv(
        providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('x')])),
      );
      // 10 frames of quiet noise (the tone leaking in), then speech, silence.
      Int16List quiet() => Int16List.fromList(List.filled(480, 100));
      final frames = [
        for (var i = 0; i < 10; i++) quiet(),
        ...AudioFrames.pattern('S' * 10 + '.' * 30),
      ];
      await pumpOverlay(
        tester,
        env,
        platform,
        extra: [wakeConfirmToneProvider.overrideWithValue(() async {})],
        voice: VoiceComponents(
          audio: FakeAudioInput(
            frames: frames,
            frameInterval: const Duration(milliseconds: 30),
          ),
          vad: FakeVoiceActivityDetector(),
          stt: stt,
          textToSpeech: (_) async => null,
          config: const VoicePipelineConfig(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await pumpUntil(tester, find.byType(OverlaySheet));
      for (var i = 0; i < 80 && stt.heard.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      final pcm = stt.heard.single;
      // Of the quiet 4800 samples (all inside the endpointer's pre-roll)
      // the first 3200 (tone 2400 + 800) are zero, the last 1600 stay.
      expect(pcm.where((s) => s == 100).length, 4800 - wakeToneMuteSamples);
      final first = pcm.indexOf(100);
      expect(
        pcm.sublist(first - wakeToneMuteSamples, first).every((s) => s == 0),
        isTrue,
      );
    });
  });
}

void main() {
  toneTests();
  testWidgets('App-Sprache gilt auch im Overlay (Einstellung English)', (
    tester,
  ) async {
    final env = TestEnv(startup: const StartupSettings(uiLanguage: 'en'));
    await pumpOverlay(tester, env, FakeAssistantPlatform(), autoStart: false);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Text input'), findsOneWidget);
    expect(find.byTooltip('Texteingabe'), findsNothing);
  });

  testWidgets('Golden: Overlay laut Entwurf (390 × 844)', tags: ['golden'], (
    tester,
  ) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider(const []),
        id: 'phala',
        name: 'Phala · GLM klein',
        privacy: PrivacyLevel.tee,
      ),
    );
    final c = await pumpOverlay(
      tester,
      env,
      FakeAssistantPlatform(),
      autoStart: false,
    );
    c.read(agentControllerProvider.notifier).seed(overlaySample());
    // Balkenhöhen der Vorlage: 10, 22, 34, 18, 26, 12 von 40.
    c
        .read(voiceControllerProvider.notifier)
        .seed(
          const VoiceUiState(
            levels: [1 / 6, 0.5, 5 / 6, 7 / 18, 11 / 18, 2 / 9],
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text('„Trag mir morgen um zehn Tauchen ein.“'), findsOneWidget);
    expect(find.text('Rückgängig · 8 s'), findsOneWidget);
    expect(find.byTooltip('Weiter sprechen'), findsOneWidget);
    expect(find.byTooltip('Texteingabe'), findsOneWidget);
    expect(find.byTooltip('Beenden'), findsOneWidget);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/overlay.png'),
    );
  });

  testWidgets(
    'Golden: Overlay gesperrt mit Anfrage und Antwort (WP163)',
    tags: ['golden'],
    (tester) async {
      final env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider(const []),
          name: 'Claude Haiku',
        ),
      );
      final platform = FakeAssistantPlatform()..locked = true;
      final c = await pumpOverlay(tester, env, platform, autoStart: false);
      c.read(agentControllerProvider.notifier).seed(overlaySample());
      c.read(lockedExchangeProvider.notifier)
        ..begin('Mach die Wohnzimmerlampe an.')
        ..answer('Die Wohnzimmerlampe ist an.');
      await tester.pumpAndSettle();
      expect(find.text('Entsperren'), findsOneWidget);
      expect(find.text('„Mach die Wohnzimmerlampe an.“'), findsOneWidget);
      expect(find.text('Die Wohnzimmerlampe ist an.'), findsOneWidget);
      expect(find.textContaining('Tauchen'), findsNothing);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/overlay_gesperrt.png'),
      );
    },
  );

  testWidgets(
    'Golden: Bestätigung im selben Sheet, Antwort per Stimme',
    tags: ['golden'],
    (tester) async {
      final env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider(const []),
          name: 'Claude Haiku',
        ),
      );
      final c = await pumpOverlay(
        tester,
        env,
        FakeAssistantPlatform(),
        autoStart: false,
      );
      c
          .read(agentControllerProvider.notifier)
          .seed(
            ConversationState(
              entries: [
                SessionStartEntry('s', testNow),
                const UserEntry('u', 'Lösch den Zahnarzttermin am Donnerstag.'),
                const ToolEntry(
                  'c1',
                  toolName: 'calendar__delete_event',
                  phase: ToolPhase.awaitingConfirmation,
                ),
              ],
              running: true,
              activeProfileId: 'claude',
              pending: ToolQuestion(
                ConfirmationRequired(
                  call: call(
                    'c1',
                    'calendar__delete_event',
                    '{"event_id":"e1"}',
                  ),
                  description: 'Termin ‚Zahnarzt Dr. Weber‘ Do 15.10. 08:30–09:15 löschen',
                  respond: (_) {},
                ),
                request: 'Lösch den Zahnarzttermin am Donnerstag.',
              ),
            ),
          );
      c
          .read(voiceControllerProvider.notifier)
          .seed(
            const VoiceUiState(
              phase: VoiceState.thinking,
              awaitingAnswer: true,
              levels: [0.2, 0.4, 0.3, 0.1, 0.0, 0.0],
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('Sag einfach „ja“ oder „nein“'), findsOneWidget);
      expect(find.text('Termin löschen?'), findsOneWidget);
      expect(
        tester.widget<MicButton>(find.byType(MicButton)).state,
        MicState.listening,
      );
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/overlay_bestaetigung.png'),
      );
    },
  );

  testWidgets(
    'Assistent ausgelöst: hört zu (TriggerKind.assistant), Antwort im Sheet',
    (tester) async {
      AssistantOverlayScreen.closeWhenIdle = false; // the test reads the sheet after the answer (WP172: it would close)
      final tts = FakeTextToSpeech();
      final env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider([ScriptedTurn.text('Es ist 8 Uhr 12.')]),
        ),
      );
      final c = await pumpOverlay(
        tester,
        env,
        FakeAssistantPlatform(),
        voice: fakeVoice(
          audio: FakeAudioInput(
            frames: utterance(),
            frameInterval: const Duration(milliseconds: 30),
          ),
          tts: tts,
          script: const [Transcript(text: 'Wie spät ist es?')],
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(c.read(voiceControllerProvider).trigger, TriggerKind.assistant);
      expect(find.text('Ich höre zu …'), findsOneWidget);
      await pumpUntil(tester, find.text('„Wie spät ist es?“'));
      await pumpUntil(tester, find.text('Es ist 8 Uhr 12.'));
      await c.read(auditRecorderProvider).flush();
      final request = (await env.storage.audit.query()).firstWhere(
        (e) => e.kind == AuditKind.request,
      );
      expect(request.payload['trigger'], 'assistant');
      expect(request.payload['source'], 'voice');
    },
  );

  testWidgets(
    'Wake Word (WP50): TriggerKind.wakeWord; ohne wakeEnd wird der Pre-Roll '
    'verworfen (WP73)',
    (tester) async {
      AssistantOverlayScreen.closeWhenIdle = false; // the test reads the sheet after the answer (WP172: it would close)
      final platform = FakeAssistantPlatform()
        ..wakeHandoff = Int16List.fromList(List.filled(8000, 300));
      final stt = FakeSpeechToText(const [
        Transcript(text: 'Wie spät ist es?'),
      ]);
      final env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider([ScriptedTurn.text('Es ist 8 Uhr 12.')]),
        ),
      );
      // Ohne Ton: nichts wird aus der Aufnahme geschnitten.
      await tester.runAsync(() => env.storage.settings.set(wakeToneKey, false));
      final c = await pumpOverlay(
        tester,
        env,
        platform,
        voice: VoiceComponents(
          audio: FakeAudioInput(
            frames: utterance(),
            frameInterval: const Duration(milliseconds: 30),
          ),
          vad: FakeVoiceActivityDetector(),
          stt: stt,
          textToSpeech: (_) async => FakeTextToSpeech(),
          config: const VoicePipelineConfig(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(c.read(voiceControllerProvider).trigger, TriggerKind.wakeWord);
      await pumpUntil(tester, find.text('Es ist 8 Uhr 12.'));
      // Without wakeEnd nothing of the pre-roll (0.5 s) reaches Whisper
      // (privacy): the same 17760 samples as without a pre-roll.
      expect(stt.calls.single.samples, 17760);
      expect(platform.wakeHandoff, isNull);
      await c.read(auditRecorderProvider).flush();
      final request = (await env.storage.audit.query()).firstWhere(
        (e) => e.kind == AuditKind.request,
      );
      expect(request.payload['trigger'], 'wakeWord');
    },
  );

  testWidgets(
    'Wake Word ohne Pause, Gerätepegel (WP73): Pre-Roll nur das Wort, '
    'Sprache mit normalem Pegel: kein Ton',
    (tester) async {
      AssistantOverlayScreen.closeWhenIdle = false; // the test reads the sheet after the answer (WP172: it would close)
      var plays = 0;
      Int16List level(int ms, int amp) =>
          Int16List.fromList(List.filled(ms * 16, amp));
      final platform = FakeAssistantPlatform()
        // As on the device: only 300 ms of the loud word in front of the end,
        // then the request at a normal level (not 3x the word).
        ..wakeHandoff = Int16List.fromList([
          ...level(300, 1500),
          ...level(1200, 1200),
          ...level(600, 40),
        ])
        ..wakeEnd = 300 * 16;
      final stt = FakeSpeechToText(const [
        Transcript(text: 'Wendelin, wie spät ist es?'),
      ]);
      final env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider([ScriptedTurn.text('Es ist 8 Uhr 12.')]),
        ),
      );
      await pumpOverlay(
        tester,
        env,
        platform,
        extra: [wakeConfirmToneProvider.overrideWithValue(() async => plays++)],
        voice: VoiceComponents(
          audio: FakeAudioInput(
            frames: AudioFrames.pattern('.' * 30),
            frameInterval: const Duration(milliseconds: 30),
          ),
          vad: FakeVoiceActivityDetector(),
          stt: stt,
          textToSpeech: (_) async => FakeTextToSpeech(),
          config: const VoicePipelineConfig(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await pumpUntil(tester, find.text('Es ist 8 Uhr 12.'));
      expect(plays, 0);
    },
  );

  testWidgets(
    'Wake Word ohne Pause (WP68): Anfrage steckt im Handoff, kein Ton, '
    'Wake Word nicht im Audio',
    (tester) async {
      AssistantOverlayScreen.closeWhenIdle = false; // the test reads the sheet after the answer (WP172: it would close)
      var plays = 0;
      Int16List cat(List<Int16List> parts) =>
          Int16List.fromList([for (final p in parts) ...p]);
      final platform = FakeAssistantPlatform()
        // Wake word 600 ms, then 900 ms of request, then 900 ms of silence.
        ..wakeHandoff = cat([
          AudioFrames.speech(const Duration(milliseconds: 600)),
          AudioFrames.speech(const Duration(milliseconds: 900)),
          AudioFrames.silence(const Duration(milliseconds: 900)),
        ])
        ..wakeEnd = 600 * 16;
      final stt = FakeSpeechToText(const [
        Transcript(text: 'Wendelin, wie spät ist es?'),
      ]);
      final env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider([ScriptedTurn.text('Es ist 8 Uhr 12.')]),
        ),
      );
      final c = await pumpOverlay(
        tester,
        env,
        platform,
        extra: [wakeConfirmToneProvider.overrideWithValue(() async => plays++)],
        voice: VoiceComponents(
          audio: FakeAudioInput(
            frames: AudioFrames.pattern('.' * 30),
            frameInterval: const Duration(milliseconds: 30),
          ),
          vad: FakeVoiceActivityDetector(),
          stt: stt,
          textToSpeech: (_) async => FakeTextToSpeech(),
          config: const VoicePipelineConfig(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await pumpUntil(tester, find.text('Es ist 8 Uhr 12.'));
      expect(platform.wakeTakes, 1);
      expect(plays, 0); // the speaker is already talking: no tone
      // 4 margin chunks + 26 speech + 27 silence; the wake word is not in it.
      expect(stt.calls.single.samples, 57 * 480);
      final input = c.read(agentControllerProvider).entries;
      expect(
        input.map((e) => '$e').join(' '),
        isNot(contains('Wendelin, wie')),
      );
    },
  );

  testWidgets('Wake Word bei laufendem Agenten: Übergabe wird abgenommen und '
      'verworfen (Dienst-Mikrofon schließt)', (tester) async {
    final platform = FakeAssistantPlatform()
      ..wakeHandoff = AudioFrames.speech(const Duration(milliseconds: 600))
      ..wakeEnd = 600 * 16
      ..wakeGate = Completer<void>();
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('x')])),
    );
    final c = await pumpOverlay(tester, env, platform);
    c
        .read(agentControllerProvider.notifier)
        .seed(ConversationState(running: true));
    platform.wakeGate!.complete();
    await tester.pump(const Duration(milliseconds: 60));
    expect(platform.wakeTakes, 1);
    expect(platform.wakeHandoff, isNull);
    expect(c.read(voiceControllerProvider).active, isFalse);
  });

  testWidgets(
    'Sperrbildschirm: nichts zeigen, nur Taschenlampe, dann entsperren',
    (tester) async {
      final platform = FakeAssistantPlatform()
        ..locked = true
        ..unlockSucceeds = false;
      final env = TestEnv(
        providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('x')])),
      );
      final c = await pumpOverlay(tester, env, platform);
      await tester.pump();
      expect(find.text('Entsperren'), findsOneWidget);
      // WP53: kein automatisches Entsperren; Wendelin hört gesperrt zu.
      expect(platform.unlockRequests, 0);
      expect(c.read(voiceControllerProvider).trigger, TriggerKind.assistant);
      await c.read(voiceControllerProvider.notifier).cancel();
      await tester.pump();
      expect(
        tester.widget<MicButton>(find.byType(MicButton)).state,
        MicState.disabled,
      );
      expect(find.byTooltip('Texteingabe'), findsOneWidget);

      // Zweiter Versuch über den Button gelingt: jetzt hört Wendelin zu.
      platform.unlockSucceeds = true;
      await tester.tap(find.text('Entsperren'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Entsperren'), findsNothing);
      expect(c.read(voiceControllerProvider).trigger, TriggerKind.assistant);
      await c.read(voiceControllerProvider.notifier).cancel();
    },
  );

  testWidgets('gesperrt: keine Inhalte aus dem Verlauf', (tester) async {
    final platform = FakeAssistantPlatform()
      ..locked = true
      ..unlockSucceeds = false;
    final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
    final c = await pumpOverlay(tester, env, platform);
    c.read(agentControllerProvider.notifier).seed(overlaySample());
    await tester.pump();
    expect(find.textContaining('Tauchen'), findsNothing);
    expect(find.byType(ToolResultCard), findsNothing);
  });

  testWidgets(
    'Overlay-Start wärmt die Attestierung des TEE-Profils vor (WP77)',
    (tester) async {
      final platform = FakeAssistantPlatform();
      final verifier = ScriptedVerifier();
      final hub = AttestationHub(notifier: RecordingNotifier())
        ..register(
          'phala',
          scriptedTee(verifier: verifier, gateway: ScriptedGateway()),
        );
      addTearDown(hub.dispose);
      final env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider(const []),
          id: 'phala',
          privacy: PrivacyLevel.tee,
        ),
      );
      await pumpOverlay(
        tester,
        env,
        platform,
        autoStart: false,
        extra: [attestationHubProvider.overrideWithValue(hub)],
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(verifier.attests, 1, reason: 'läuft, während der Nutzer spricht');
      // Another hit later: the session is valid, nothing is checked again.
      platform.trigger();
      await tester.pump(const Duration(milliseconds: 50));
      expect(verifier.attests, 1);
    },
  );

  testWidgets('Beenden schließt das Overlay', (tester) async {
    final platform = FakeAssistantPlatform();
    final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
    await pumpOverlay(tester, env, platform, autoStart: false);
    await tester.tap(find.byTooltip('Beenden'));
    await tester.pump();
    expect(platform.finished, 1);
  });

  testWidgets('Tipp neben das Sheet schließt das Overlay', (tester) async {
    final platform = FakeAssistantPlatform();
    final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
    await pumpOverlay(tester, env, platform, autoStart: false);
    await tester.tap(find.bySemanticsLabel('Assistent schließen'));
    await tester.pump();
    expect(platform.finished, 1);
  });

  testWidgets('erneut ausgelöst: neuer Durchgang', (tester) async {
    final platform = FakeAssistantPlatform();
    final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
    final c = await pumpOverlay(
      tester,
      env,
      platform,
      autoStart: false,
      voice: fakeVoice(
        audio: FakeAudioInput(
          frames: utterance(),
          frameInterval: const Duration(milliseconds: 30),
        ),
      ),
    );
    expect(c.read(voiceControllerProvider).active, isFalse);
    platform.trigger();
    await tester.pump(const Duration(milliseconds: 10));
    expect(c.read(voiceControllerProvider).listening, isTrue);
    await c.read(voiceControllerProvider.notifier).cancel();
  });

  testWidgets('Tastatur: Text statt Sprache', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([ScriptedTurn.text('Notiert.')]),
      ),
    );
    await pumpOverlay(tester, env, FakeAssistantPlatform(), autoStart: false);
    await tester.tap(find.byTooltip('Texteingabe'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Merk dir Tauchen');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await pumpUntil(tester, find.text('Notiert.'));
    expect(find.text('„Merk dir Tauchen“'), findsOneWidget);
  });

  testWidgets('Bestätigung im selben Sheet, Tipp auf „Ja“', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
          ]),
          ScriptedTurn.text('Gelöscht.'),
        ]),
      ),
    );
    await env.calendar.createEvent(zahnarztDraft());
    final c = await pumpOverlay(
      tester,
      env,
      FakeAssistantPlatform(),
      autoStart: false,
    );
    unawaited(
      c.read(agentControllerProvider.notifier).send('Lösch den Termin'),
    );
    await pumpUntil(tester, find.text('Termin löschen?'));
    expect(find.text('Antworte per Tipp'), findsOneWidget);
    await tester.tap(find.text('Ja, löschen'));
    await pumpUntil(tester, find.text('Gelöscht.'));
    expect(env.calendar.events, isEmpty);
  });

  testWidgets('jeder Aufruf beginnt ein neues Gespräch (WP67)', (tester) async {
    AssistantOverlayScreen.closeWhenIdle = false; // the test reads the sheet after the answer (WP172: it would close)
    final provider = FakeLlmProvider([
      ScriptedTurn.text('Eins'),
      ScriptedTurn.text('Zwei'),
    ]);
    final env = TestEnv(providerConfig: scripted(provider));
    final platform = FakeAssistantPlatform();
    final first = await pumpOverlay(tester, env, platform);
    unawaited(first.read(agentControllerProvider.notifier).send('Glocken'));
    await pumpUntil(tester, find.text('Eins'));
    // Overlay schließen und innerhalb der Inaktivitätsfrist neu auslösen.
    await tester.pumpWidget(const SizedBox());
    final second = await pumpOverlay(tester, env, platform);
    unawaited(second.read(agentControllerProvider.notifier).send('Wetter'));
    await pumpUntil(tester, find.text('Zwei'));
    final users = [
      for (final m in provider.requests.last.messages)
        if (m.role == Role.user) m,
    ];
    expect(users, hasLength(1));
    expect(users.single.toJson().toString(), contains('Wetter'));
    expect(
      provider.requests.last.messages.toString(),
      isNot(contains('Glocken')),
    );
  });

  test('Ausschnitt: nur die letzte Anfrage, ohne Denken', () {
    final x = OverlayExchange.of([
      const UserEntry('u1', 'alt'),
      const AssistantTextEntry('a1', 'alte Antwort'),
      const UserEntry('u2', 'neu'),
      const ThinkingEntry('t', 'geheim'),
      const ToolEntry('c', toolName: 'memory__save', phase: ToolPhase.done),
      const AssistantTextEntry('a2', 'Teil 1'),
      const AssistantTextEntry('a3', 'Teil 2'),
      const NoticeEntry('n', NoticeKind.info, 'Abgebrochen.'),
    ]);
    expect(x.request, 'neu');
    expect(x.tools.single.toolName, 'memory__save');
    expect(x.answer, 'Teil 1\n\nTeil 2');
    expect(x.notice, 'Abgebrochen.');
    expect(OverlayExchange.of(const []).request, isNull);
  });

  testWidgets('bis die Sperre bekannt ist: gesperrt, nichts aus dem Verlauf', (
    tester,
  ) async {
    final platform = FakeAssistantPlatform()..lockAnswer = Completer<bool>();
    final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
    final c = await pumpOverlay(tester, env, platform, autoStart: false);
    c.read(agentControllerProvider.notifier).seed(overlaySample());
    await tester.pump();
    expect(find.textContaining('Tauchen'), findsNothing);
    expect(find.text('Entsperren'), findsNothing);
    expect(
      tester.widget<MicButton>(find.byType(MicButton)).state,
      MicState.disabled,
    );
    platform.lockAnswer!.complete(false);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Tauchen'), findsWidgets);
  });

  testWidgets('gesperrt: Tastatur sichtbar deaktiviert, Tipp ohne Wirkung', (
    tester,
  ) async {
    final platform = FakeAssistantPlatform()
      ..locked = true
      ..unlockSucceeds = false;
    await pumpOverlay(tester, TestEnv(), platform);
    await tester.pump();
    final button = tester.widget<WIconButton>(
      find.ancestor(
        of: find.byTooltip('Texteingabe'),
        matching: find.byType(WIconButton),
      ),
    );
    expect(button.onPressed, isNull);
    final icon = tester.widget<WIcon>(
      find.descendant(
        of: find.byTooltip('Texteingabe'),
        matching: find.byType(WIcon),
      ),
    );
    expect(icon.color, WColors.textMuted);
    await tester.tap(find.byTooltip('Texteingabe'), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'Android verlässt das Overlay: erst Dart-Schließpfad, dann finish',
    (tester) async {
      final platform = FakeAssistantPlatform();
      final tts = FakeTextToSpeech(manual: true);
      final audio = FakeAudioInput(
        frames: AudioFrames.pattern('S' * 500),
        frameInterval: const Duration(milliseconds: 10),
      );
      final c = await pumpOverlay(
        tester,
        TestEnv(providerConfig: scripted(FakeLlmProvider(const []))),
        platform,
        voice: fakeVoice(audio: audio, tts: tts),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(audio.isRunning, isTrue);
      await platform.closeHandler!();
      await tester.pump();
      expect(audio.isRunning, isFalse);
      expect(c.read(voiceControllerProvider).active, isFalse);
      expect(platform.finished, 1);
    },
  );

  testWidgets('Overlay im Hintergrund (paused): Mikrofon aus', (tester) async {
    final audio = FakeAudioInput(
      frames: AudioFrames.pattern('S' * 500),
      frameInterval: const Duration(milliseconds: 10),
    );
    await pumpOverlay(
      tester,
      TestEnv(providerConfig: scripted(FakeLlmProvider(const []))),
      FakeAssistantPlatform(),
      voice: fakeVoice(audio: audio),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(audio.isRunning, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 50));
    expect(audio.isRunning, isFalse);
  });
}
