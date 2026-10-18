import 'package:flutter/widgets.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'dashed_border.dart';
import 'glyphs.dart';

/// Darstellung einer [PrivacyLevel]: über Form/Füllung, nicht nur Farbe.
extension PrivacyLevelStyle on PrivacyLevel {
  /// Kurzname im Chip.
  String labelOf(AppLocalizations l) => switch (this) {
    PrivacyLevel.local => l.privacyLevelLocal,
    PrivacyLevel.tee => l.privacyLevelTee,
    PrivacyLevel.eu => l.privacyLevelEu,
    PrivacyLevel.standard => l.privacyLevelStandard,
  };

  /// Textfarbe im Chip.
  Color get chipForeground => switch (this) {
    PrivacyLevel.local => WColors.paperInk,
    PrivacyLevel.tee => WColors.paper,
    PrivacyLevel.eu || PrivacyLevel.standard => WColors.textSecondary,
  };

  /// Rahmen- bzw. Füllfarbe im Chip.
  Color get chipLine => switch (this) {
    PrivacyLevel.local || PrivacyLevel.tee => WColors.paper,
    PrivacyLevel.eu || PrivacyLevel.standard => WColors.lineSubtle,
  };
}

/// Pillen-Chip in der Form der Datenschutzstufe (Mono 12).
///
/// ● lokal: gefüllt (Papier); ◆ TEE: Rahmen Papier; ▲ EU: Rahmen
/// `lineSubtle`; ○ Standard: gestrichelter Rahmen `lineSubtle`.
class PrivacyChip extends StatelessWidget {
  /// Erstellt einen Chip; ohne [label] steht der Name der Stufe darin.
  const PrivacyChip(
    this.level, {
    super.key,
    this.label,
    this.trailing,
    this.semanticLabel,
  });

  /// Datenschutzstufe.
  final PrivacyLevel level;

  /// Text im Chip (Standard: [PrivacyLevelStyle.labelOf]).
  final String? label;

  /// Optionales Element rechts (z. B. Prüfstatus).
  final Widget? trailing;

  /// Überschreibt das Semantics-Label.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fg = level.chipForeground;
    final text = label ?? level.labelOf(context.l10n);
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WSpace.s10,
        vertical: WSpace.xs6,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(GlyphShape.forPrivacy(level), color: fg),
          const SizedBox(width: WSpace.xs6),
          Flexible(
            child: Text(
              text,
              style: WText.mono.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: WSpace.s), trailing!],
        ],
      ),
    );
    final Widget chip = switch (level) {
      PrivacyLevel.standard => DashedBorder(
        color: level.chipLine,
        radius: WRadius.chip,
        child: Padding(
          padding: const EdgeInsets.all(WSize.border),
          child: content,
        ),
      ),
      _ => Container(
        decoration: BoxDecoration(
          color: level == PrivacyLevel.local ? level.chipLine : null,
          borderRadius: BorderRadius.circular(WRadius.chip),
          border: Border.all(color: level.chipLine, width: WSize.border),
        ),
        child: content,
      ),
    };
    return Semantics(
      container: true,
      label:
          semanticLabel ??
          context.l10n.privacyLevelSemantics(text, level.labelOf(context.l10n)),
      child: ExcludeSemantics(child: chip),
    );
  }
}
