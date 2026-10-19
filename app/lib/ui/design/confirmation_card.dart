import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../l10n/l10n.dart';
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
    this.detailWidget,
    this.yesLabel,
    this.noLabel,
    this.expand = false,
    this.compact = false,
  });

  /// Frage („Termin löschen?“).
  final String title;

  /// Einzelheiten zum betroffenen Objekt („Do 15.10. · 08:30–09:15 …“).
  final String detail;

  /// Betroffenes Objekt („Zahnarzt Dr. Weber“), optional.
  final String? subject;

  /// Ersetzt [detail] (z. B. ein Eingabefeld).
  final Widget? detailWidget;

  /// Tool-Name in Mono.
  final String toolName;

  /// Risikostufe des Tools.
  final RiskLevel risk;

  /// Bestätigen.
  final VoidCallback? onYes;

  /// Ablehnen.
  final VoidCallback? onNo;

  /// Beschriftung „Ja“-Button.
  final String? yesLabel;

  /// Beschriftung „Nein“-Button.
  final String? noLabel;

  /// Füllt die verfügbare Höhe; die Buttons rutschen nach unten
  /// (im Sheet). Braucht eine begrenzte Höhe.
  final bool expand;

  /// Kompakt (kleines Sheet): ohne Tool-/Stufenzeile.
  final bool compact;

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
                CheckStatusIcon(
                  CheckStatus.pending,
                  size: WSize.statusIconHeader,
                  semanticLabel: context.l10n.confirmCardWarning,
                ),
                Expanded(
                  child: Text(
                    context.l10n.confirmCardNeedsConfirm.toUpperCase(),
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
                    detailWidget ?? Text(detail, style: WText.detail),
                  ],
                ),
              ),
            ),
            if (!compact)
              Text(
                context.l10n.confirmCardToolLevel(toolName, risk.name),
                style: WText.mono,
              ),
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        if (expand) const Spacer() else const SizedBox(height: WSpace.l18),
        _buttons(context),
      ],
    );
  }

  Widget _buttons(BuildContext context) => Row(
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
          child: Text(noLabel ?? context.l10n.no),
        ),
      ),
      Expanded(
        child: FilledButton(
          onPressed: onYes,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(WSize.buttonHeightLarge),
            textStyle: WText.buttonLarge,
          ),
          child: Text(yesLabel ?? context.l10n.yes),
        ),
      ),
    ],
  );
}
