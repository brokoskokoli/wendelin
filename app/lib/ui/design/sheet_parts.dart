import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'logo.dart';

/// Ziehgriff oben im Assistenten-Sheet (40 × 5, `line`).
class SheetDragHandle extends StatelessWidget {
  /// Erstellt den Ziehgriff.
  const SheetDragHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WColors.line,
          borderRadius: BorderRadius.circular(WRadius.chip),
        ),
        child: const SizedBox(
          width: WSize.dragHandleWidth,
          height: WSize.dragHandleHeight,
        ),
      ),
    ),
  );
}

/// Kopf des Assistenten-Sheets: Bildmarke + „Wendelin“, rechts ein Chip.
class SheetHeader extends StatelessWidget {
  /// Erstellt den Kopf; [trailing] ist meist ein `ProviderChip`.
  const SheetHeader({super.key, required this.trailing});

  /// Element rechts.
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: WSpace.m,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: WSpace.s10,
          children: [
            const WendelinMark(),
            Text('Wendelin', style: WText.label),
          ],
        ),
        Flexible(child: trailing),
      ],
    );
  }
}

/// Hinweis unten im Sheet mit Kobalt-Punkt („Sag einfach „ja“ oder …“).
class VoiceHint extends StatelessWidget {
  /// Erstellt einen Hinweis.
  const VoiceHint(this.text, {super.key, this.dot = true});

  /// Hinweistext.
  final String text;

  /// Zeigt den Punkt (Mikrofon hört mit).
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: WSpace.s,
      children: [
        if (dot)
          const ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WColors.accentLight,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(dimension: WSize.hintDot),
            ),
          ),
        Flexible(
          child: Text(
            text,
            style: dot ? WText.detail : WText.caption,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
