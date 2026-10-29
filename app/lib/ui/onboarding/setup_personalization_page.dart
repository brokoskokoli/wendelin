import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/setup_status.dart';
import '../../di/setup_wizard.dart';
import '../../di/voice_providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../routes.dart';
import '../settings/model_download_row.dart';
import '../settings/settings_page.dart';
import 'download_plan.dart';
import 'setup_optional_page.dart';

/// Page 6 of the setup wizard (WP174, optional): „Möchtest du, dass Wendelin
/// dich erkennt?“. First the speaker recognition model is downloaded (its
/// row shows progress, error and „Erneut versuchen“), then the button opens
/// the existing enrolling flow (Einstellungen → Sprache → Sprechererkennung).
/// Back from it shows whether a voice is enrolled. „Weiter“/„Überspringen“
/// always works, also while loading and after an error.
class SetupPersonalizationPage extends ConsumerStatefulWidget {
  /// Creates the page; [onNext] goes on.
  const SetupPersonalizationPage({super.key, required this.onNext});

  /// Goes on.
  final VoidCallback onNext;

  @override
  ConsumerState<SetupPersonalizationPage> createState() => _PersonalState();
}

class _PersonalState extends ConsumerState<SetupPersonalizationPage> {
  static const _model = SpeechModelCatalog.speakerCamPlus;

  @override
  void initState() {
    super.initState();
    // A download interrupted by closing the app continues here.
    unawaited(
      Future(() => ref.read(modelStatesProvider.notifier).resumePartial()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plan = DownloadPlan.of([_model], ref.watch(modelStatesProvider));
    final enrolled =
        ref.watch(setupFactsProvider).stateOf(SetupPage.personalization) ==
        PageState.met;
    return SettingsPage(
      title: l.setupPersonalizationTitle,
      intro: l.setupPersonalizationIntro,
      children: [
        const SectionCard(
          children: [ModelDownloadRow(model: _model, deletable: false)],
        ),
        StatusCard(
          key: const ValueKey('speakerStatus'),
          status: enrolled
              ? CheckStatus.ok
              : plan.error != null && !plan.busy
              ? CheckStatus.failed
              : CheckStatus.pending,
          title: enrolled
              ? l.setupSpeakerReady
              : plan.ready
              ? l.setupSpeakerMissing
              : plan.status(l),
          detail: !enrolled && plan.busy
              ? l.voiceDownloadLoadingPercent(
                  '${(plan.progress * 100).floor()}',
                )
              : null, // the failure text is shown in the model's row only
        ),
        if (plan.ready)
          OptionalActions(
            met: enrolled,
            openLabel: l.setupSpeakerOpen,
            onOpen: () => openFromWizard(context, AppRoutes.speaker),
            onNext: widget.onNext,
            nextLabel: l.setupSkip,
          )
        else ...[
          PrimaryButton(
            plan.loadLabel(l),
            onPressed: plan.canLoad
                ? () {
                    for (final m in plan.missing) {
                      unawaited(
                        ref.read(modelStatesProvider.notifier).download(m.id),
                      );
                    }
                  }
                : null,
          ),
          WideButton(l.setupSkip, onPressed: widget.onNext),
        ],
      ],
    );
  }
}
