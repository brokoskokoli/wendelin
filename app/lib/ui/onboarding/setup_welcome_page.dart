import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../settings/settings_page.dart';

/// Page 1 of the setup wizard (WP174): what Wendelin is, one button on.
class SetupWelcomePage extends StatelessWidget {
  /// Creates the page; [onNext] goes to the provider page.
  const SetupWelcomePage({super.key, required this.onNext});

  /// Goes on.
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: context.l10n.onboardingWelcome,
    showBack: false,
    centered: true,
    intro: context.l10n.onboardingWelcomeIntro,
    children: [
      const Center(child: WendelinLockup()),
      PrimaryButton(context.l10n.setupWelcomeAction, onPressed: onNext),
    ],
  );
}
