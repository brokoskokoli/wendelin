import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/list_access.dart';
import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../../di/setup_status.dart';
import '../../di/setup_wizard.dart';
import '../../di/wake_service.dart';
import '../../voice/recognizer_config.dart';
import 'setup_done_page.dart';
import 'setup_optional_page.dart';
import 'setup_personalization_page.dart';
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
        SetupPage.wakeWord => SetupWakePage(onNext: _next),
        SetupPage.integrations => SetupIntegrationsPage(onNext: _next),
        SetupPage.personalization => SetupPersonalizationPage(onNext: _next),
        SetupPage.done => SetupDonePage(onFinish: _finish),
      },
    );
  }
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
