import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../di/list_access.dart';
import '../../di/preferences.dart';
import '../../di/profiles.dart';
import '../../di/providers.dart';
import '../../voice/recognizer_config.dart';
import '../design/design.dart';
import '../settings/integrations_screen.dart';
import '../settings/provider_setup_screen.dart';
import '../settings/settings_page.dart';
import 'voice_download_step.dart';

/// First start: language, first provider, speech recognition download,
/// integrations (concept: „Onboarding“). Every step can be skipped;
/// settings can change it later. From step 2 on, the back arrow and the
/// system back gesture go one step back; on step 1 back leaves the app.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// Creates the onboarding.
  const OnboardingScreen({super.key});

  /// Languages offered (the UI is German for now).
  static const languages = [
    ('de', 'Deutsch'),
    ('fr', 'Français'),
    ('en', 'English'),
  ];

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  void _next() => setState(() => _step++);

  Future<void> _finish() =>
      ref.read(onboardingDoneProvider.notifier).complete();

  Future<void> _setUpProvider() async {
    final profile = await Navigator.of(context).push<ProviderProfile>(
      MaterialPageRoute(builder: (_) => const ProviderSetupScreen()),
    );
    if (profile != null) _next();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _step > 0) setState(() => _step--);
    },
    child: switch (_step) {
      0 => _language(),
      1 => _provider(),
      2 => VoiceDownloadStep(onNext: _next),
      _ => _integrations(),
    },
  );

  Widget _language() {
    final current = ref.watch(languageProvider);
    return SettingsPage(
      title: 'Willkommen',
      showBack: false,
      centered: true,
      intro:
          'Wendelin ist dein Sprachassistent. In vier Schritten ist er '
          'eingerichtet. Welche Sprache sprichst du mit ihm?',
      children: [
        const Center(child: WendelinLockup()),
        SectionCard(
          children: [
            for (final (code, name) in OnboardingScreen.languages)
              SettingsRow(
                title: name,
                onTap: () =>
                    unawaited(ref.read(languageProvider.notifier).set(code)),
                trailing: current == code
                    ? const CheckStatusIcon(
                        CheckStatus.ok,
                        semanticLabel: 'gewählt',
                      )
                    : null,
              ),
          ],
        ),
        Text('Die Oberfläche ist vorerst deutsch.', style: WText.caption),
        PrimaryButton('Weiter', onPressed: _next),
      ],
    );
  }

  Widget _provider() {
    final profiles = ref.watch(profilesProvider).value?.profiles ?? const [];
    return SettingsPage(
      title: 'Sprachmodell',
      centered: true,
      intro:
          'Wendelin braucht einen Provider, z. B. Claude mit deinem API-Key '
          'oder ein eigenes Modell auf dem Homeserver.',
      children: [
        if (profiles.isNotEmpty)
          SectionCard(
            children: [
              for (final p in profiles)
                SettingsRow(title: p.name, trailing: PrivacyChip(p.privacy)),
            ],
          ),
        PrimaryButton(
          profiles.isEmpty ? 'Provider einrichten' : 'Weiter',
          onPressed: profiles.isEmpty
              ? () => unawaited(_setUpProvider())
              : _next,
        ),
        WideButton(
          profiles.isEmpty ? 'Später' : 'Weiteren Provider einrichten',
          onPressed: profiles.isEmpty
              ? _next
              : () => unawaited(_setUpProvider()),
        ),
        if (kDebugMode && profiles.isEmpty)
          WideButton(
            'Demo ohne Provider',
            onPressed: () async {
              await ref.read(demoModeProvider.notifier).set(enabled: true);
              await _finish();
            },
          ),
      ],
    );
  }

  Widget _integrations() {
    final registry = ref.watch(toolRegistryProvider);
    return SettingsPage(
      title: 'Was darf Wendelin?',
      intro:
          'Schalte nur ein, was du brauchst. Berechtigungen fragt Android '
          'erst jetzt beim Einschalten.',
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
        PrimaryButton('Fertig', onPressed: () => unawaited(_finish())),
      ],
    );
  }
}

/// Shows the onboarding until it is done (outside the demo mode). On start
/// it also checks the grants of the list files (a lost grant marks the
/// lists integration „Datei neu auswählen“); on every return to the app it
/// checks the integrations again (installed apps).
class StartGate extends ConsumerStatefulWidget {
  /// Creates the gate around [home].
  const StartGate({super.key, required this.home});

  /// Screen after the onboarding.
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
    if (ref.read(listDefinitionsProvider).isNotEmpty) {
      unawaited(Future(() => checkListAccess(ref)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the system recognizer's copy of the speech settings current.
    ref.watch(recognizerConfigSyncProvider);
    return ref.watch(onboardingDoneProvider) || ref.watch(demoModeProvider)
        ? widget.home
        : const OnboardingScreen();
  }
}
