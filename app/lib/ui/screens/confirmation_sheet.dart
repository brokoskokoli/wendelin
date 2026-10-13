import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../agent/conversation_state.dart';
import '../design/design.dart';
import 'labels.dart';
import 'private_banner.dart';

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
    this.hint = ConfirmationHint.tap,
    this.privateSince,
  });

  /// Since when the conversation is private (hint at an escalation).
  final DateTime? privateSince;

  /// What to ask.
  final PendingQuestion question;

  /// Active provider (chip in the head).
  final String providerName;

  /// Its privacy level.
  final PrivacyLevel privacy;

  /// Risk level of the tool (tool questions).
  final RiskLevel toolRisk;

  /// Hint under the card (tap only, or „Sag einfach „ja“ oder „nein““
  /// while a voice request listens for the answer).
  final ConfirmationHint hint;

  @override
  Widget build(BuildContext context) {
    final quote = switch (question) {
      ToolQuestion(:final request) => request,
      EscalationQuestion() => null,
    };
    final card = confirmationCardFor(
      question,
      (yes) => Navigator.of(context).pop(yes),
      toolRisk: toolRisk,
      privateSince: privateSince,
    );
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
            // Langer Inhalt (z. B. ein Diff) scrollt statt überzulaufen.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: WSpace.l18,
                  children: [
                    if (quote != null && quote.isNotEmpty)
                      Text('„$quote“', style: WText.quote),
                    card,
                    hint.widget,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hint under a confirmation card.
enum ConfirmationHint {
  /// Only a tap answers (typed request).
  tap('Antworte per Tipp', listens: false),

  /// A voice request listens for „ja“/„nein“ (or a tap).
  voice('Sag einfach „ja“ oder „nein“', listens: true);

  const ConfirmationHint(this.text, {required this.listens});

  /// Hint text.
  final String text;

  /// Whether the microphone listens (cobalt dot).
  final bool listens;

  /// The hint as widget.
  Widget get widget => VoiceHint(text, dot: listens);
}

/// The confirmation card for [question]; [answer] gets `true` for yes. In
/// a private conversation ([privateSince]) the escalation question says
/// that the target would also see its private parts.
Widget confirmationCardFor(
  PendingQuestion question,
  void Function(bool yes) answer, {
  RiskLevel toolRisk = RiskLevel.external,
  DateTime? privateSince,
}) => switch (question) {
  ToolQuestion(:final event) => () {
    final texts = confirmationTexts(event.call.name);
    return ConfirmationCard(
      title: texts.title,
      detail: clampConfirmationDetail(event.description),
      toolName: event.call.name,
      risk: toolRisk,
      onYes: () => answer(true),
      onNo: () => answer(false),
      yesLabel: texts.yes,
      noLabel: texts.no,
    );
  }(),
  EscalationQuestion(:final fromName, :final toName) => ConfirmationCard(
    title: 'An $toName übergeben?',
    detail: [
      '$toName hat eine niedrigere Datenschutzstufe als $fromName. '
          'Deine Anfrage und der bisherige Verlauf gehen dann dorthin.',
      if (privateSince != null) privateEscalationHint(privateSince, toName),
    ].join('\n'),
    toolName: '$fromName → $toName',
    risk: RiskLevel.external,
    onYes: () => answer(true),
    onNo: () => answer(false),
    yesLabel: 'Ja, übergeben',
    noLabel: 'Nein',
  ),
};

/// Most lines of a confirmation detail shown in the sheet.
const maxDetailLines = 10;

/// Longest detail line shown in the sheet.
const maxDetailLineChars = 80;

/// Shortens a long confirmation [detail] (e.g. a diff) so the card and its
/// buttons fit on a phone: at most [maxDetailLines] lines of at most
/// [maxDetailLineChars] characters, the rest counted in a last line.
String clampConfirmationDetail(String detail) {
  final lines = [
    for (final l in detail.split('\n'))
      l.length <= maxDetailLineChars
          ? l
          : '${l.substring(0, maxDetailLineChars - 1)}…',
  ];
  if (lines.length <= maxDetailLines) return lines.join('\n');
  final rest = lines.length - (maxDetailLines - 1);
  return [
    ...lines.take(maxDetailLines - 1),
    '… $rest weitere Zeilen',
  ].join('\n');
}
