import 'package:flutter/material.dart';
import 'package:wendelin_providers/wendelin_providers.dart'
    show StageOutcome, StageResult;

import '../../attestation/attestation_texts.dart';
import '../../attestation/stage_line.dart';
import '../../design/design.dart';

/// „Erste Attestierung“ of a TEE profile: result per stage (quote, nonce,
/// keyset, freshness, …) as the connection test found it.
class AttestationStagesCard extends StatelessWidget {
  /// Creates the card.
  const AttestationStagesCard(this.stages, {super.key});

  /// Result per stage.
  final List<StageResult> stages;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: WSpace.s,
    children: [
      Text('Erste Attestierung', style: WText.sectionLabel),
      SectionCard(
        children: [
          for (final s in stages)
            StageLine(
              label: stageLabel(s.stage.id),
              result: stageResultLabel(s.outcome.name),
              detail: s.outcome == StageOutcome.pass ? null : s.detail,
              status: stageResultStatus(s.outcome.name),
            ),
        ],
      ),
    ],
  );
}
