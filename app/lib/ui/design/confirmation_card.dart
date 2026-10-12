import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../theme/app_theme.dart';
import 'check_status.dart';

/// Rückfrage vor einem Tool mit Bestätigungspflicht (Stufe `external`):
/// gelber Rahmen, Dreieck, Tool-Name + Stufe, darunter „Nein“ / „Ja“.
class ConfirmationCard extends StatelessWidget {
  /// Erstellt eine Bestätigungskarte.
  const ConfirmationCard({
    super.key,
    required this.title,
    required this.detail,
    required this.toolName,
    required this.risk,
    required this.onYes,
    required this.onNo,
    this.subject,
    this.yesLabel = 'Ja',
    this.noLabel = 'Nein',
    this.expand = false,
  });

  /// Frage („Termin löschen?“).
  final String title;

  /// Einzelheiten zum betroffenen Objekt („Do 15.10. · 08:30–09:15 …“).
  final String detail;

  /// Betroffenes Objekt („Zahnarzt Dr. Weber“), optional.
  final String? subject;

  /// Tool-Name in Mono.
  final String toolName;

  /// Risikostufe des Tools.
  final RiskLevel risk;

  /// Bestätigen.
  final VoidCallback? onYes;

  /// Ablehnen.
  final VoidCallback? onNo;

  /// Beschriftung „Ja“-Button.
  final String yesLabel;

  /// Beschriftung „Nein“-Button.
  final String noLabel;

  /// Füllt die verfügbare Höhe; die Buttons rutschen nach unten
  /// (im Sheet). Braucht eine begrenzte Höhe.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WRadius.cardLarge),
        border: Border.all(color: WColors.warn, width: WSize.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(WSpace.l18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WSpace.m14,
          children: [
            Row(
              spacing: WSpace.s,
              children: [
                const CheckStatusIcon(
                  CheckStatus.pending,
                  size: WSize.statusIconHeader,
                  semanticLabel: 'Warnung',
                ),
                Expanded(
                  child: Text(
                    'Braucht deine Bestätigung'.toUpperCase(),
                    style: WText.monoCaps,
                  ),
                ),
              ],
            ),
            Text(title, style: WText.cardTitle),
            DecoratedBox(
              decoration: BoxDecoration(
                color: WColors.surface,
                borderRadius: BorderRadius.circular(WRadius.button),
              ),
              child: Padding(
                padding: const EdgeInsets.all(WSpace.m14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: WSpace.xs,
                  children: [
                    if (subject != null) Text(subject!, style: WText.itemTitle),
                    Text(detail, style: WText.detail),
                  ],
                ),
              ),
            ),
            Text('$toolName · Stufe ${risk.name}', style: WText.mono),
          ],
        ),
      ),
    );
    final buttons = Row(
      spacing: WSpace.m,
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onNo,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(WSize.buttonHeightLarge),
              textStyle: WText.buttonLarge,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WRadius.buttonLarge),
              ),
            ),
            child: Text(noLabel),
          ),
        ),
        Expanded(
          child: FilledButton(
            onPressed: onYes,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(WSize.buttonHeightLarge),
              textStyle: WText.buttonLarge,
            ),
            child: Text(yesLabel),
          ),
        ),
      ],
    );
    return Column(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        if (expand) const Spacer() else const SizedBox(height: WSpace.l18),
        buttons,
      ],
    );
  }
}
