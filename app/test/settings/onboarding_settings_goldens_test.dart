// Goldens of WP32 (device test 2026-10-13): connection status (B2),
// download step (B3), provider step centred, microphone notice, assistant
// settings with the system speech recognizer elsewhere (B12).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/onboarding/onboarding_screen.dart';
import 'package:wendelin/ui/onboarding/voice_download_step.dart';
import 'package:wendelin/ui/screens/main_parts.dart';
import 'package:wendelin/ui/settings/assistant_screen.dart';
import 'package:wendelin/ui/settings/provider_setup_screen.dart';
import 'package:wendelin/ui/voice/microphone_access.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../di/provider_setup_test.dart' show RecordingFactory;
import '../overlay/assistant_overlay_test.dart' show FakeAssistantPlatform;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;
import 'onboarding_test.dart' show firstStart;

Future<void> pumpGoldenScreen(
  WidgetTester tester,
  TestEnv env,
  Widget screen,
) async {
  setView(tester, screenSize);
  await tester.pumpWidget(
    env.app(
      home: RepaintBoundary(key: goldenKey, child: screen),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('Golden Verbindung steht (B2)', tags: ['golden'], (tester) async {
    final f = RecordingFactory(
      models: const [
        ModelInfo(id: 'claude-haiku-5-5', displayName: 'Claude Haiku 5.5'),
        ModelInfo(id: 'claude-sonnet-5', displayName: 'Claude Sonnet 5'),
        ModelInfo(id: 'claude-opus-5', displayName: 'Claude Opus 5'),
      ],
    );
    final env = TestEnv(storedProfiles: true, llmFactory: f.call);
    await pumpGoldenScreen(tester, env, const ProviderSetupScreen());
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('apiKey')),
      'testschluessel',
    );
    await tester.tap(find.text('Verbindung testen'));
    await tester.pumpAndSettle();
    expect(find.text('Verbindung steht'), findsOneWidget);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/provider_verbindung_steht.png'),
    );
  });

  testWidgets('Golden Download-Schritt (B3)', tags: ['golden'], (tester) async {
    final env = TestEnv();
    final m = env.speechModels;
    await pumpGoldenScreen(tester, env, VoiceDownloadStep(onNext: () {}));
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/onboarding_download_noch_noetig.png'),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Laden'));
    await tester.pump();
    m
      ..progress('whisper-small', 0.42)
      ..finish('silero-vad');
    await settle(tester);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/onboarding_download_laedt.png'),
    );

    m.finish('whisper-small');
    await settle(tester);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/onboarding_download_bereit.png'),
    );
  });

  testWidgets('Golden Provider-Schritt mittig', tags: ['golden'], (
    tester,
  ) async {
    setView(tester, screenSize);
    await tester.pumpWidget(firstStart().app());
    await settle(tester);
    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(find.text('Sprachmodell'), findsOneWidget);
    await expectLater(
      find.byType(OnboardingScreen),
      matchesGoldenFile('goldens/onboarding_provider.png'),
    );
  });

  testWidgets('Golden Mikrofon-Hinweis', tags: ['golden'], (tester) async {
    Widget composer({required bool denied}) => SizedBox(
      width: screenSize.width - 2 * WSpace.screen,
      child: Composer(
        running: false,
        onSend: (_) => true,
        mic: MicState.idle,
        onMic: () {},
        notice: MicrophoneNotice(
          deniedByAndroid: denied,
          onAllow: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await pumpComponent(tester, [
      composer(denied: false),
      composer(denied: true),
    ]);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/mikrofon_hinweis.png'),
    );
  });

  testWidgets(
    'Golden Assistent: Spracherkennung nicht verfügbar (B12)',
    tags: ['golden'],
    (tester) async {
      final platform = FakeAssistantPlatform()
        ..isDefault = true
        ..recognition = const RecognitionServiceStatus(
          RecognitionServiceState.other,
          appName: 'Speech Services by Google',
        );
      setView(tester, screenSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...TestEnv().overrides,
            assistantPlatformProvider.overrideWithValue(platform),
          ],
          retry: (_, _) => null,
          child: themed(
            const RepaintBoundary(key: goldenKey, child: AssistantScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/assistent_spracherkennung.png'),
      );
    },
  );
}
