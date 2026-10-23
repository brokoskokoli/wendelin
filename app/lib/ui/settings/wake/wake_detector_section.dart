import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/voice_providers.dart';
import '../../../di/wake_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/wake/wake_detector.dart';
import '../../design/design.dart';
import '../model_download_row.dart';
import '../settings_page.dart';

/// Whether the trained classifier is needed for [choice] but not loaded
/// (WP129). `auto` counts: the station runs on the model. Enrolling and
/// trying out do not need it, so this does not block them.
final wakeClassifierMissingProvider = Provider<SpeechModel?>((ref) {
  final choice =
      ref.watch(wakeDetectorProvider).value ?? WakeDetectorChoice.auto;
  if (choice == WakeDetectorChoice.templates) return null;
  final m = ref
      .watch(speechModelCatalogProvider)
      .byId(SpeechModelCatalog.wakeClassifierWendelin.id);
  final phase = ref.watch(modelStatesProvider)[m?.id]?.phase;
  return m != null && phase != ModelPhase.installed ? m : null;
});

/// Settings → Aktivierungswort: „Erkennung“ (WP129): automatic, templates
/// of the learned voice or the trained model, with the model download.
class WakeDetectorSection extends ConsumerWidget {
  /// Creates the section.
  const WakeDetectorSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final choice =
        ref.watch(wakeDetectorProvider).value ?? WakeDetectorChoice.auto;
    final missing = ref.watch(wakeClassifierMissingProvider);
    final noVoice = (ref.watch(wakeSpeakersProvider).value ?? const []).isEmpty;
    Widget row(WakeDetectorChoice c, String title, String detail) =>
        SettingsRow(
          key: ValueKey('wakeDetector.${c.name}'),
          title: title,
          detail: detail,
          onTap: () =>
              unawaited(ref.read(wakeDetectorProvider.notifier).set(c)),
          trailing: choice == c
              ? CheckStatusIcon(CheckStatus.ok, semanticLabel: l.selected)
              : null,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.l18,
      children: [
        SettingsSection(
          title: l.wakeDetectorTitle,
          children: [
            row(
              WakeDetectorChoice.auto,
              l.wakeDetectorAuto,
              l.wakeDetectorAutoHint,
            ),
            row(
              WakeDetectorChoice.templates,
              l.wakeDetectorTemplates,
              l.wakeDetectorTemplatesHint,
            ),
            row(
              WakeDetectorChoice.model,
              l.wakeDetectorModel,
              l.wakeDetectorModelHint,
            ),
          ],
        ),
        if (choice != WakeDetectorChoice.templates) ...[
          if (missing != null)
            Text(
              key: const ValueKey('wakeClassifierMissing'),
              l.wakeDetectorModelNeeded(missing.displayName),
              style: WText.caption,
            ),
          // WP140: no model and no learned voice: nothing can listen.
          if (missing != null && noVoice)
            Text(
              key: const ValueKey('wakeNothingToHear'),
              l.wakeDetectorNothingToHear,
              style: WText.caption,
            ),
          ModelDownloadRow(model: SpeechModelCatalog.wakeClassifierWendelin),
        ],
      ],
    );
  }
}
