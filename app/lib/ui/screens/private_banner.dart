import 'package:flutter/material.dart';

import '../design/design.dart';

/// „08:12“ (local time).
String clockLabel(DateTime at) {
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}

/// Name in the provider chip: the provider and, if a routing rule chose
/// it, the rule („Claude API · Starkes Modell“).
String providerLabel(String name, String? rule) =>
    rule == null || rule.isEmpty ? name : '$name · $rule';

/// Text of the hint while a conversation is private ([byRequest]: a
/// „privat“ request) or only confidential (a run used the memory).
String privateConversationText(DateTime since, {bool byRequest = true}) =>
    byRequest
    ? 'Unterhaltung privat (seit ${clockLabel(since)})'
    : 'Vertraulich: Gedächtnis genutzt (seit ${clockLabel(since)})';

/// Shown while the conversation is private (ADR 0009 §4, taint
/// propagation): after a private request every later answer of the
/// session is private too, until [onNewConversation] starts a new one.
class PrivateConversationBanner extends StatelessWidget {
  /// Creates the hint.
  const PrivateConversationBanner({
    super.key,
    required this.since,
    required this.onNewConversation,
    this.byRequest = true,
  });

  /// A „privat“ request (else only confidential: memory used).
  final bool byRequest;

  /// First private message of the conversation.
  final DateTime since;

  /// Ends the session („Neues Gespräch“); `null` while a request runs.
  final VoidCallback? onNewConversation;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: WColors.surface,
      borderRadius: BorderRadius.circular(WRadius.buttonLarge),
    ),
    padding: const EdgeInsetsDirectional.only(start: WSpace.m14),
    child: Row(
      spacing: WSpace.s,
      children: [
        const ExcludeSemantics(
          child: Glyph(GlyphShape.diamond, color: WColors.paper),
        ),
        Expanded(
          child: Text(
            privateConversationText(since, byRequest: byRequest),
            style: WText.detail.copyWith(color: WColors.text),
          ),
        ),
        TextButton(
          onPressed: onNewConversation,
          style: TextButton.styleFrom(
            minimumSize: const Size(WSize.touchMin, WSize.touchMin),
          ),
          child: const Text('Neues Gespräch'),
        ),
      ],
    ),
  );
}

/// Extra sentence of the escalation question in a private conversation.
String privateEscalationHint(
  DateTime since,
  String toName, {
  bool byRequest = true,
}) => byRequest
    ? 'Die Unterhaltung ist privat (seit ${clockLabel(since)}). Mit „Ja“ '
          'sieht $toName auch ihre privaten Teile.'
    : 'Die Unterhaltung nutzt dein Gedächtnis (seit ${clockLabel(since)}). '
          'Mit „Ja“ sieht $toName den bisherigen Verlauf, aber nicht das '
          'Gedächtnis selbst.';
