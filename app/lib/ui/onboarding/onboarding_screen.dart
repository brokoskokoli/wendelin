import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/list_access.dart';
import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../../di/setup_status.dart';
import '../../di/setup_wizard.dart';
import '../../di/wake_service.dart';
import '../../l10n/l10n.dart';
import '../../voice/recognizer_config.dart';
import '../design/design.dart';
import '../routes.dart';
import '../settings/integrations_screen.dart';
import '../settings/settings_page.dart';
import 'setup_provider_page.dart';
import 'setup_speech_page.dart';
import 'setup_welcome_page.dart';

/// The setup wizard (WP174), the frame of the first start and of the
/// update: seven pages (welcome, provider, speech, wake word, integrations,
/// personalization, done), see [SetupPage]. Required pages (provider,
/// speech) block „Weiter“ until the live state meets them; what is ticked
/// is derived each time ([setupFactsProvider]), never stored. The current
/// page is stored and continues after a restart. Back (arrow and system
/// gesture) goes one page back; on the first page it leaves the app.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// Creates the wizard.
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  SetupWizardPage get _wizard => ref.read(setupWizardPageProvider.notifier);

  void _next() => unawaited(_wizard.advance());

  void _finish() => unawaited(_wizard.finish());

  /// Opens a settings menu; back leads here again (see [WizardBackScope]).
  void _open(String route) =>
      unawaited(Navigator.of(context).pushNamed<void>(route));

  @override
  Widget build(BuildContext context) {
    final facts = ref.watch(setupFactsProvider);
    final page = facts.effectivePage(ref.watch(setupWizardPageProvider));
    return PopScope(
      canPop: page == SetupPage.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_wizard.back());
      },
      child: switch (page) {
        SetupPage.welcome => SetupWelcomePage(onNext: _next),
        SetupPage.provider => SetupProviderPage(onNext: _next),
        SetupPage.speech => SetupSpeechPage(onNext: _next),
        SetupPage.wakeWord => _wake(facts),
        SetupPage.integrations => _integrations(),
        SetupPage.personalization => _personalization(facts),
        SetupPage.done => _done(facts),
      },
    );
  }

  Widget _integrations() {
    final registry = ref.watch(toolRegistryProvider);
    return SettingsPage(
      title: context.l10n.onboardingWhatMayWendelinDo,
      intro: context.l10n.onboardingPermissionsIntro,
      children: [
        StreamBuilder<void>(
          stream: registry.changes,
          builder: (context, _) => SectionCard(
            children: [
              // Only this platform's integrations; missing apps greyed out
              // (concept: „Integrationen auswählen“).
              for (final info in displayOrder(selectableIntegrations(registry)))
                IntegrationRow(info),
            ],
          ),
        ),
        PrimaryButton(context.l10n.next, onPressed: _next),
      ],
    );
  }

  /// Optional page: the wake word (ADR 0005). The menu (WP173) trains and
  /// switches it on; the page shows the state and can be left either way.
  Widget _wake(SetupFacts facts) => _optionalPage(
    title: context.l10n.onboardingWakeWord,
    intro: context.l10n.onboardingWakeIntro,
    state: facts.stateOf(SetupPage.wakeWord),
    readyText: context.l10n.setupWakeReady,
    missingText: context.l10n.setupWakeMissing,
    openLabel: context.l10n.onboardingLearnAndEnable,
    route: AppRoutes.wakeWord,
  );

  /// Optional page: speaker recognition (who is speaking). The enrolling
  /// itself is the existing flow in Einstellungen → Sprache.
  Widget _personalization(SetupFacts facts) => _optionalPage(
    title: context.l10n.setupPersonalizationTitle,
    intro: context.l10n.setupPersonalizationIntro,
    state: facts.stateOf(SetupPage.personalization),
    readyText: context.l10n.setupSpeakerReady,
    missingText: context.l10n.setupSpeakerMissing,
    openLabel: context.l10n.setupSpeakerOpen,
    route: AppRoutes.speaker,
  );

  /// Page with a state, a button to the settings menu [route], and a way on
  /// that always works (primary when the state is met).
  Widget _optionalPage({
    required String title,
    required String intro,
    required PageState state,
    required String readyText,
    required String missingText,
    required String openLabel,
    required String route,
  }) {
    final ready = state == PageState.met;
    return SettingsPage(
      title: title,
      centered: true,
      intro: intro,
      children: [
        StatusCard(
          key: ValueKey('status-$route'),
          status: ready ? CheckStatus.ok : CheckStatus.pending,
          title: ready ? readyText : missingText,
        ),
        if (ready) ...[
          PrimaryButton(context.l10n.next, onPressed: _next),
          WideButton(openLabel, onPressed: () => _open(route)),
        ] else ...[
          PrimaryButton(openLabel, onPressed: () => _open(route)),
          WideButton(context.l10n.setupContinueWithout, onPressed: _next),
        ],
      ],
    );
  }

  Widget _done(SetupFacts facts) => SettingsPage(
    title: context.l10n.setupDoneTitle,
    centered: true,
    intro: context.l10n.setupDoneIntro,
    children: [
      const Center(child: WendelinLockup()),
      PrimaryButton(
        context.l10n.setupDoneAction,
        onPressed: facts.canFinish ? _finish : null,
      ),
    ],
  );
}

/// Shows the setup wizard until it is done (outside the demo mode). On start
/// it also checks the grants of the list files (a lost grant marks the
/// lists integration „Datei neu auswählen“); on every return to the app it
/// checks the integrations again (installed apps).
class StartGate extends ConsumerStatefulWidget {
  /// Creates the gate around [home].
  const StartGate({super.key, required this.home});

  /// Screen after the wizard.
  final Widget home;

  @override
  ConsumerState<StartGate> createState() => _StartGateState();
}

class _StartGateState extends ConsumerState<StartGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Back in the app: apps may have been installed or removed meanwhile
    // (concept: „App-Erkennung“). The start check is the registry's first
    // refresh.
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(ref.read(toolRegistryProvider).refresh()),
    );
    // The wake word service: adopt „Aus“ from the notification, send the
    // settings (also makes `wakeServiceProvider` listen to the verify
    // setting).
    unawaited(ref.read(wakeServiceProvider.notifier).sync());
    if (ref.read(listDefinitionsProvider).isNotEmpty) {
      unawaited(Future(() => checkListAccess(ref)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the system recognizer's copy of the speech settings current.
    ref.watch(recognizerConfigSyncProvider);
    return ref.watch(setupWizardDoneProvider) || ref.watch(demoModeProvider)
        ? widget.home
        : const OnboardingScreen();
  }
}
