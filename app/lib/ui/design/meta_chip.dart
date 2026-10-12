import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Neutraler Info-Chip in Mono 12 auf `surface` (z. B. „heute 0,03 €“).
class MetaChip extends StatelessWidget {
  /// Erstellt einen Info-Chip.
  const MetaChip(this.text, {super.key, this.semanticLabel});

  /// Inhalt.
  final String text;

  /// Optionales Semantics-Label (z. B. „Kosten heute 3 Cent“).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WColors.surface,
        borderRadius: BorderRadius.circular(WRadius.chip),
        // Unsichtbarer Rahmen: gleiche Höhe wie die Datenschutz-Chips.
        border: Border.all(color: WColors.transparent, width: WSize.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WSpace.s10,
          vertical: WSpace.xs6,
        ),
        child: Text(text, style: WText.mono, semanticsLabel: semanticLabel),
      ),
    );
  }
}
