import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wendelin_providers/wendelin_providers.dart'
    show StageOutcome, StageResult;

import '../../../di/tee_restrictions.dart';
import '../../../l10n/l10n.dart';
import '../../attestation/attestation_texts.dart';
import '../../attestation/stage_line.dart';
import '../../design/design.dart';
import '../attestation_explain_screen.dart';
import '../settings_page.dart';

/// „Erste Attestierung“ of a TEE profile: result per stage (quote, nonce,
/// keyset, freshness, …) as the connection test found it.
///
/// WP65: only a status line and a button here; the stages are on their own
/// page ([AttestationStagesScreen]).
class AttestationStagesCard extends StatelessWidget {
  /// Creates the card.
  const AttestationStagesCard(this.stages, {super.key});

  /// Result per stage.
  final List<StageResult> stages;

  @override
  Widget build(BuildContext context) {
    final failedStages = [
      for (final s in stages)
        // A restriction of the provider (info, e.g. no GPU evidence, WP82)
        // is no failure.
        if (s.outcome != StageOutcome.pass && s.outcome != StageOutcome.info)
          stageLabel(context.l10n, s.stage.id),
    ];
    final failed = failedStages.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.s,
      children: [
        Text(context.l10n.attStagesCardFirst, style: WText.sectionLabel),
        SectionCard(
          children: [
            SettingsRow(
              key: const ValueKey('attestationSummary'),
              title: failed == 0
                  ? context.l10n.attStagesCardAllPassed(stages.length)
                  : context.l10n.attStagesCardSomePassed(
                      failed,
                      stages.length,
                      failedStages.join(', '),
                    ),
              trailing: CheckStatusIcon(
                failed == 0 ? CheckStatus.ok : CheckStatus.failed,
                semanticLabel: failed == 0
                    ? context.l10n.stageResultPass
                    : context.l10n.attStagesCardNotPassed,
              ),
            ),
          ],
        ),
        WideButton(
          context.l10n.details,
          onPressed: () => unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    AttestationExplainScreen(stages: stageViews(stages)),
              ),
            ),
          ),
        ),
        WideButton(
          context.l10n.attStagesCardViewLog,
          onPressed: () => unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => AttestationStagesScreen(stages),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Own page with the result per stage of the first attestation.
class AttestationStagesScreen extends StatelessWidget {
  /// Creates the page.
  const AttestationStagesScreen(this.stages, {super.key});

  /// Result per stage.
  final List<StageResult> stages;

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: context.l10n.attLogTitle,
    children: [
      SectionCard(
        children: [
          for (final s in stages)
            StageLine(
              label: stageLabel(context.l10n, s.stage.id),
              result: stageResultLabel(context.l10n, s.outcome.name),
              detail: s.outcome == StageOutcome.pass ? null : s.detail,
              status: stageResultStatus(s.outcome.name),
            ),
        ],
      ),
    ],
  );
}

/// [stages] in the form the restriction logic and the Details page use.
List<StageView> stageViews(List<StageResult> stages) => [
  for (final s in stages)
    (stage: s.stage.id, result: s.outcome.name, detail: s.detail),
];
