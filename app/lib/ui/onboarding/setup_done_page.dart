import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/profiles.dart';
import '../../di/setup_status.dart';
import '../../di/setup_wizard.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../settings/settings_page.dart';

/// Page 7 of the setup wizard (WP174): a short summary with the steps
/// ticked as the live state says (never stored), and „Fertig“, which ends
/// the wizard. „Fertig“ works only when the required pages are met.
class SetupDonePage extends ConsumerWidget {
  /// Creates the page; [onFinish] ends the wizard.
  const SetupDonePage({super.key, required this.onFinish});

  /// Ends the wizard.
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final facts = ref.watch(setupFactsProvider);
    final names =
        ref.watch(profilesProvider).value?.profiles.map((p) => p.name) ??
        const <String>[];
    CheckStatus tick(SetupPage p) => facts.stateOf(p) == PageState.met
        ? CheckStatus.ok
        : CheckStatus.pending;
    return SettingsPage(
      title: l.setupDoneTitle,
      centered: true,
      intro: l.setupDoneIntro,
      children: [
        StatusCard(
          key: const ValueKey('done-provider'),
          status: tick(SetupPage.provider),
          title: facts.stateOf(SetupPage.provider) == PageState.met
              ? l.setupProviderReadyNamed(names.join(', '))
              : l.setupProviderMissing,
        ),
        StatusCard(
          key: const ValueKey('done-speech'),
          status: tick(SetupPage.speech),
          title: l.setupSpeechReady,
        ),
        StatusCard(
          key: const ValueKey('done-wake'),
          status: tick(SetupPage.wakeWord),
          title: facts.stateOf(SetupPage.wakeWord) == PageState.met
              ? l.setupWakeReady
              : l.setupWakeMissing,
        ),
        StatusCard(
          key: const ValueKey('done-speaker'),
          status: tick(SetupPage.personalization),
          title: facts.stateOf(SetupPage.personalization) == PageState.met
              ? l.setupSpeakerReady
              : l.setupSpeakerMissing,
        ),
        PrimaryButton(
          l.setupDoneAction,
          onPressed: facts.canFinish ? onFinish : null,
        ),
      ],
    );
  }
}
