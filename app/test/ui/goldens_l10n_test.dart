@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/setup_status.dart';
import 'package:wendelin/ui/onboarding/onboarding_screen.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../screens/screen_goldens_test.dart' show mainScreenSample, phalaEnv;
import '../settings/integrations_screen_test.dart' show settle;
import '../support/test_env.dart';
import 'helpers.dart';

// Goldens of WP79: three central screens per UI language.
const _langs = ['de', 'en', 'fr'];

Future<void> _pump(WidgetTester tester, TestEnv env, {Widget? home}) async {
  setView(tester, screenSize);
  await tester.pumpWidget(
    RepaintBoundary(
      key: goldenKey,
      child: env.app(home: home),
    ),
  );
  await settle(tester);
}

void main() {
  for (final lang in _langs) {
    group('Sprache $lang', () {
      testWidgets('Einstellungen-Übersicht', (tester) async {
        final env = TestEnv(startup: StartupSettings(uiLanguage: lang));
        await _pump(tester, env, home: const SettingsScreen());
        await expectLater(
          find.byKey(goldenKey),
          matchesGoldenFile('goldens/l10n/einstellungen_$lang.png'),
        );
      });

      testWidgets('Hauptbildschirm', (tester) async {
        final base = phalaEnv();
        final env = TestEnv(
          providerConfig: base.providerConfig,
          startup: StartupSettings(uiLanguage: lang),
        );
        await _pump(tester, env, home: const MainScreen(restoreSession: false));
        ProviderScope.containerOf(tester.element(find.byType(MainScreen)))
            .read(agentControllerProvider.notifier)
            .seed(mainScreenSample());
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(goldenKey),
          matchesGoldenFile('goldens/l10n/hauptbildschirm_$lang.png'),
        );
      });

      // WP174 parts B and C: the pages of the setup wizard.
      for (final (page, file) in [
        ('welcome', 'onboarding'),
        ('provider', 'onboarding_anbieter'),
        ('speech', 'onboarding_sprache'),
        ('wakeWord', 'onboarding_aktivierungswort'),
        ('integrations', 'onboarding_integrationen'),
        ('personalization', 'onboarding_personalisierung'),
        ('done', 'onboarding_abschluss'),
      ]) {
        testWidgets('Einrichtungsassistent $page', (tester) async {
          final env = TestEnv(
            startup: StartupSettings(
              setupWizardDone: false,
              setupWizardPage: page,
              uiLanguage: lang,
            ),
            storedProfiles: true,
          );
          // Provider page: still without a provider; later pages need one and
          // the speech models.
          if (page != 'welcome' && page != 'provider') {
            await env.storage.providerProfiles.save(
              ProviderProfile(
                id: 'p1',
                name: 'Mein Claude',
                type: ProviderType.anthropic,
                defaultModel: 'claude-haiku-5-5',
                privacy: PrivacyLevel.standard,
                authMethod: const NoAuth(),
              ),
            );
          }
          if (SetupPage.parse(page).index > SetupPage.speech.index) {
            env.speechModels.installed.addAll(['whisper-small', 'silero-vad']);
          }
          await _pump(tester, env);
          expect(find.byType(OnboardingScreen), findsOneWidget);
          await expectLater(
            find.byKey(goldenKey),
            matchesGoldenFile('goldens/l10n/${file}_$lang.png'),
          );
        });
      }
    });
  }
}
