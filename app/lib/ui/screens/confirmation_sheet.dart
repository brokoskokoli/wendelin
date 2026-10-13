import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../agent/conversation_state.dart';
import '../design/design.dart';
import 'labels.dart';

/// Bottom sheet „Bestätigung“ (docs/design/screens/bestaetigung): asks
/// before an `external` tool or an escalation below the privacy level.
///
/// Pops with `true` (yes) or `false` (no); dismissing pops `null`, which
/// the main screen treats as „no“.
class ConfirmationSheet extends StatelessWidget {
  /// Creates the sheet content.
  const ConfirmationSheet({
    super.key,
    required this.question,
    required this.providerName,
    required this.privacy,
    this.toolRisk = RiskLevel.external,
  });

  /// What to ask.
  final PendingQuestion question;

  /// Active provider (chip in the head).
  final String providerName;

  /// Its privacy level.
  final PrivacyLevel privacy;

  /// Risk level of the tool (tool questions).
  final RiskLevel toolRisk;

  @override
  Widget build(BuildContext context) {
    void answer(bool yes) => Navigator.of(context).pop(yes);
    final (quote, card) = switch (question) {
      ToolQuestion(:final event, :final request) => (
        request,
        _toolCard(event, answer),
      ),
      EscalationQuestion(:final fromName, :final toName) => (
        null,
        ConfirmationCard(
          title: 'An $toName übergeben?',
          detail:
              '$toName hat eine niedrigere Datenschutzstufe als $fromName. '
              'Deine Anfrage und der bisherige Verlauf gehen dann dorthin.',
          toolName: '$fromName → $toName',
          risk: RiskLevel.external,
          onYes: () => answer(true),
          onNo: () => answer(false),
          yesLabel: 'Ja, übergeben',
          noLabel: 'Nein',
        ),
      ),
    };
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WSpace.screen,
          WSpace.m14,
          WSpace.screen,
          WSpace.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WSpace.l18,
          children: [
            const SheetDragHandle(),
            SheetHeader(
              trailing: ProviderChip(name: providerName, level: privacy),
            ),
            if (quote != null && quote.isNotEmpty)
              Text('„$quote“', style: WText.quote),
            card,
            const VoiceHint(
              'Antworte per Tipp – Sprache kommt in M2',
              dot: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolCard(ConfirmationRequired event, void Function(bool) answer) {
    final texts = confirmationTexts(event.call.name);
    return ConfirmationCard(
      title: texts.title,
      detail: event.description,
      toolName: event.call.name,
      risk: toolRisk,
      onYes: () => answer(true),
      onNo: () => answer(false),
      yesLabel: texts.yes,
      noLabel: texts.no,
    );
  }
}
