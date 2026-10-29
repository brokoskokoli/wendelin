import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/setup_status.dart';
import '../../di/setup_wizard.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../routes.dart';
import '../settings/settings_page.dart';

/// Opens the settings menu [route] from the wizard; back leads to the
/// wizard again (see `WizardBackScope`).
void openFromWizard(BuildContext context, String route) =>
    unawaited(Navigator.of(context).pushNamed<void>(route));

/// A way on that never depends on the page's state: the optional pages
/// never block „Weiter“, not even while loading or after an error.
class OptionalActions extends StatelessWidget {
  /// Creates the buttons: [primary] is the main action; [onNext] always
  /// works and is labelled [nextLabel] (or „Weiter“ when the goal is met).
  const OptionalActions({
    super.key,
    required this.met,
    required this.openLabel,
    required this.onOpen,
    required this.onNext,
    this.nextLabel,
  });

  /// The page's goal is reached: „Weiter“ is primary.
  final bool met;

  /// Label of the button that opens the menu.
  final String openLabel;

  /// Opens the menu.
  final VoidCallback? onOpen;

  /// Goes on.
  final VoidCallback onNext;

  /// Label of the way on while the goal is not met (default „Ohne
  /// fortfahren“).
  final String? nextLabel;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      spacing: WSpace.l18,
      children: [
        if (met) ...[
          PrimaryButton(l.next, onPressed: onNext),
          WideButton(openLabel, onPressed: onOpen),
        ] else ...[
          PrimaryButton(openLabel, onPressed: onOpen),
          WideButton(nextLabel ?? l.setupContinueWithout, onPressed: onNext),
        ],
      ],
    );
  }
}

/// Page 4 of the setup wizard (WP174, optional): the wake word. The button
/// opens the wake word menu (WP173), which trains it and switches it on only
/// with the loaded model. Back from it shows „eingerichtet und in Ordnung“
/// or „nicht eingerichtet“; the page can be left either way.
class SetupWakePage extends ConsumerWidget {
  /// Creates the page; [onNext] goes on.
  const SetupWakePage({super.key, required this.onNext});

  /// Goes on.
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final met =
        ref.watch(setupFactsProvider).stateOf(SetupPage.wakeWord) ==
        PageState.met;
    return SettingsPage(
      title: l.onboardingWakeWord,
      intro: l.onboardingWakeIntro,
      children: [
        StatusCard(
          key: const ValueKey('wakeStatus'),
          status: met ? CheckStatus.ok : CheckStatus.pending,
          title: met ? l.setupWakeReady : l.setupWakeMissing,
        ),
        OptionalActions(
          met: met,
          openLabel: l.onboardingLearnAndEnable,
          onOpen: () => openFromWizard(context, AppRoutes.wakeWord),
          onNext: onNext,
        ),
      ],
    );
  }
}

/// Page 5 of the setup wizard (WP174, optional): the button opens the
/// integrations menu; „Weiter“ always works.
class SetupIntegrationsPage extends StatelessWidget {
  /// Creates the page; [onNext] goes on.
  const SetupIntegrationsPage({super.key, required this.onNext});

  /// Goes on.
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SettingsPage(
      title: l.onboardingWhatMayWendelinDo,
      centered: true,
      intro: l.onboardingPermissionsIntro,
      children: [
        PrimaryButton(l.next, onPressed: onNext),
        WideButton(
          l.setupIntegrationsOpen,
          onPressed: () => openFromWizard(context, AppRoutes.integrations),
        ),
      ],
    );
  }
}
