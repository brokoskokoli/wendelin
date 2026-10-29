import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../di/core_providers.dart';
import '../../di/profiles.dart';
import '../../di/setup_status.dart';
import '../../di/setup_wizard.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../settings/provider_setup_screen.dart';
import '../settings/settings_page.dart';

/// Page 2 of the setup wizard (WP174, required): „KI-Anbieter“. The button
/// opens the existing provider dialog; back from it shows „Anbieter
/// eingerichtet: „Name““ or „noch keiner“. „Weiter“ only works while the
/// live state says a provider exists (unknown or an error blocks).
class SetupProviderPage extends ConsumerWidget {
  /// Creates the page; [onNext] goes on.
  const SetupProviderPage({super.key, required this.onNext});

  /// Goes on (the wizard checks the state again).
  final VoidCallback onNext;

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push<ProviderProfile>(
      MaterialPageRoute(builder: (_) => const ProviderSetupScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final profiles = ref.watch(profilesProvider).value?.profiles ?? const [];
    final facts = ref.watch(setupFactsProvider);
    final ready = facts.stateOf(SetupPage.provider) == PageState.met;
    return SettingsPage(
      title: l.setupProviderTitle,
      centered: true,
      intro: l.onboardingProviderIntro,
      children: [
        StatusCard(
          key: const ValueKey('providerStatus'),
          status: ready ? CheckStatus.ok : CheckStatus.pending,
          title: ready
              ? l.setupProviderReadyNamed(
                  profiles.map((p) => p.name).join(', '),
                )
              : l.setupProviderMissing,
        ),
        if (ready) ...[
          PrimaryButton(l.next, onPressed: onNext),
          WideButton(
            l.onboardingSetUpAnotherProvider,
            onPressed: () => unawaited(_open(context)),
          ),
        ] else ...[
          PrimaryButton(
            l.setupProviderOpen,
            onPressed: () => unawaited(_open(context)),
          ),
          WideButton(l.next, onPressed: null),
        ],
        if (kDebugMode && profiles.isEmpty)
          WideButton(
            l.onboardingDemoNoProvider,
            onPressed: () => unawaited(
              ref.read(demoModeProvider.notifier).set(enabled: true),
            ),
          ),
      ],
    );
  }
}
