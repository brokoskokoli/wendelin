import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../agent/conversation_state.dart';
import '../../agent/outgoing_preview.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'labels.dart';
import 'outgoing_preview_card.dart';
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
    this.privateByRequest = true,
  });

  /// Whether the private state comes from a „privat“ request.
  final bool privateByRequest;

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
      EscalationQuestion() || RetryOfferQuestion() => null,
    };
    final outgoing = outgoingPreviewOf(question);
    final card = confirmationCardFor(
      context.l10n,
      question,
      (yes) => Navigator.of(context).pop(yes),
      toolRisk: toolRisk,
      privateSince: privateSince,
      privateByRequest: privateByRequest,
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
                    hint.widget(context.l10n, outgoing: outgoing?.kind),
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
  tap(listens: false),

  /// A voice request listens for „ja“/„nein“ (or a tap).
  voice(listens: true);

  const ConfirmationHint({required this.listens});

  /// Hint text; a preview before an SMS or call (WP85) names its own words.
  String text(AppLocalizations l, {OutgoingKind? outgoing}) => switch (this) {
    tap => l.confHintTap,
    voice => switch (outgoing) {
      OutgoingKind.sms => l.confHintVoiceSms,
      OutgoingKind.call => l.confHintVoiceCall,
      null => l.confHintVoice,
    },
  };

  /// Whether the microphone listens (cobalt dot).
  final bool listens;

  /// The hint as widget.
  Widget widget(AppLocalizations l, {OutgoingKind? outgoing}) =>
      VoiceHint(text(l, outgoing: outgoing), dot: listens);
}

/// The confirmation card for [question]; [answer] gets `true` for yes. In
/// a private conversation ([privateSince]) the escalation question says
/// that the target would also see its private parts.
Widget confirmationCardFor(
  AppLocalizations l,
  PendingQuestion question,
  void Function(bool yes) answer, {
  RiskLevel toolRisk = RiskLevel.external,
  DateTime? privateSince,
  bool privateByRequest = true,
}) => switch (question) {
  ToolQuestion(:final event) when outgoingPreviewOf(question) != null =>
    OutgoingPreviewCard(
      key: ValueKey('outgoing-${event.call.id}'),
      preview: outgoingPreviewOf(question)!,
      answer: answer,
    ),
  ToolQuestion(:final event) => () {
    final texts = confirmationTexts(l, event.call.name);
    return ConfirmationCard(
      title: texts.title,
      detail: clampConfirmationDetail(l, event.description),
      toolName: event.call.name,
      risk: toolRisk,
      onYes: () => answer(true),
      onNo: () => answer(false),
      yesLabel: texts.yes,
      noLabel: texts.no,
    );
  }(),
  EscalationQuestion(:final fromName, :final toName) => ConfirmationCard(
    title: l.confHandOverTitle(toName),
    detail: [
      l.confHandOverDetail(toName, fromName),
      if (privateSince != null)
        privateEscalationHint(
          l,
          privateSince,
          toName,
          byRequest: privateByRequest,
        ),
    ].join('\n'),
    toolName: '$fromName → $toName',
    risk: RiskLevel.external,
    onYes: () => answer(true),
    onNo: () => answer(false),
    yesLabel: l.confYesHandOver,
    noLabel: l.no,
  ),
  RetryOfferQuestion(:final fromName, :final toName) => ConfirmationCard(
    title: l.retryOfferTitle(toName),
    detail: l.retryOfferDetail(fromName, toName),
    toolName: '$fromName → $toName',
    risk: RiskLevel.write,
    onYes: () => answer(true),
    onNo: () => answer(false),
    yesLabel: l.retryOfferYes(toName),
    noLabel: l.no,
  ),
};

/// Most lines of a confirmation detail shown in the sheet.
const maxDetailLines = 10;

/// Longest detail line shown in the sheet.
const maxDetailLineChars = 80;

/// Shortens a long confirmation [detail] (e.g. a diff) so the card and its
/// buttons fit on a phone: at most [maxDetailLines] lines of at most
/// [maxDetailLineChars] characters, the rest counted in a last line.
String clampConfirmationDetail(AppLocalizations l, String detail) {
  final lines = [
    for (final l in detail.split('\n'))
      l.length <= maxDetailLineChars
          ? l
          : '${l.substring(0, maxDetailLineChars - 1)}…',
  ];
  if (lines.length <= maxDetailLines) return lines.join('\n');
  final rest = lines.length - (maxDetailLines - 1);
  return [...lines.take(maxDetailLines - 1), l.confMoreLines(rest)].join('\n');
}
