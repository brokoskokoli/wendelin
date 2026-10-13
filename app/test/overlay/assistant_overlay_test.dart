import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/voice_providers.dart';
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

import '../screens/main_screen_test.dart' show pumpUntil;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import '../voice/voice_controller_test.dart' show fakeVoice, utterance;

/// Stand-in for the Kotlin side of the assistant.
final class FakeAssistantPlatform extends AssistantPlatform {
  bool locked = false;
  Completer<bool>? lockAnswer;
  bool unlockSucceeds = true;
  Future<void> Function()? closeHandler;
  bool isDefault = false;
  int unlockRequests = 0;
  int finished = 0;
  int settingsOpened = 0;
  final _triggers = StreamController<void>.broadcast(sync: true);

  void trigger() => _triggers.add(null);

  @override
  Stream<void> get triggers => _triggers.stream;

  @override
  Future<bool> isLocked() => lockAnswer?.future ?? Future.value(locked);

  @override
  set onCloseRequested(Future<void> Function()? handler) =>
      closeHandler = handler;

  @override
  Future<bool> requestUnlock() async {
    unlockRequests++;
    if (unlockSucceeds) locked = false;
    return unlockSucceeds;
  }

  @override
  Future<void> finish() async => finished++;

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
            assistantPlatformProvider.overrideWithValue(platform),
            voiceReadyProvider.overrideWithValue(true),
            activeVoiceProvider.overrideWith(
              (ref) async => voice ?? fakeVoice(),
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

void main() {
  testWidgets('Golden: Overlay laut Entwurf (390 × 844)', (tester) async {
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

  testWidgets('Golden: Bestätigung im selben Sheet, Antwort per Stimme', (
    tester,
  ) async {
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider(const []), name: 'Claude Haiku'),
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
                call: call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
                description:
                    'Termin ‚Zahnarzt Dr. Weber‘ Do 15.10. 08:30–09:15 löschen',
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
  });

  testWidgets(
    'Assistent ausgelöst: hört zu (TriggerKind.assistant), Antwort im Sheet',
    (tester) async {
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

  testWidgets('Sperrbildschirm: nichts zeigen, erst entsperren, dann zuhören', (
    tester,
  ) async {
    final platform = FakeAssistantPlatform()
      ..locked = true
      ..unlockSucceeds = false;
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('x')])),
    );
    final c = await pumpOverlay(tester, env, platform);
    await tester.pump();
    expect(find.text(OverlaySheet.lockedTitle), findsOneWidget);
    expect(platform.unlockRequests, 1);
    expect(c.read(voiceControllerProvider).active, isFalse);
    expect(
      tester.widget<MicButton>(find.byType(MicButton)).state,
      MicState.disabled,
    );
    expect(find.byTooltip('Texteingabe'), findsOneWidget);

    // Zweiter Versuch über den Button gelingt: jetzt hört Wendelin zu.
    platform.unlockSucceeds = true;
    await tester.tap(find.text('Entsperren'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text(OverlaySheet.lockedTitle), findsNothing);
    expect(c.read(voiceControllerProvider).trigger, TriggerKind.assistant);
    await c.read(voiceControllerProvider.notifier).cancel();
  });

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
    expect(find.text(OverlaySheet.lockedTitle), findsNothing);
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

  group('Sprachmodelle im Overlay (B11/B14)', () {
    late int warm;
    late int released;
    VoiceComponents counting() => VoiceComponents(
      audio: FakeAudioInput(),
      vad: FakeVoiceActivityDetector(),
      stt: FakeSpeechToText(const []),
      textToSpeech: (_) async => null,
      config: const VoicePipelineConfig(),
      warmUp: () async => warm++,
      release: () async => released++,
    );
    setUp(() {
      warm = 0;
      released = 0;
    });

    testWidgets('Schließen gibt die Modelle frei', (tester) async {
      final platform = FakeAssistantPlatform();
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
      await pumpOverlay(
        tester,
        env,
        platform,
        autoStart: false,
        voice: counting(),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Beenden'));
      await tester.pump();
      await tester.pump();
      expect(released, 1);
      expect(platform.finished, 1);
    });

    testWidgets('gesperrt: kein Vorwärmen vor dem Entsperren', (tester) async {
      final platform = FakeAssistantPlatform()
        ..locked = true
        ..unlockSucceeds = false;
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
      final c = await pumpOverlay(tester, env, platform, voice: counting());
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text(OverlaySheet.lockedTitle), findsOneWidget);
      expect(warm, 0, reason: 'nicht vor dem Entsperren');

      platform.unlockSucceeds = true;
      await tester.tap(find.text('Entsperren'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(warm, greaterThan(0), reason: 'entsperrt: vorwärmen');
      await c.read(voiceControllerProvider.notifier).cancel();
    });
  });
}
