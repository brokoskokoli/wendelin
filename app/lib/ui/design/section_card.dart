import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Karte auf `surface` (Radius 18) für Listen und Einstellungsgruppen.
///
/// Mit [dividers] stehen 1-px-Trenner (`surfaceRaised`) zwischen den
/// Kindern; [title] erscheint als kleine Überschrift über dem Inhalt.
class SectionCard extends StatelessWidget {
  /// Erstellt eine Karte.
  const SectionCard({
    super.key,
    required this.children,
    this.title,
    this.dividers = true,
    this.padding = EdgeInsets.zero,
    this.spacing = 0,
  });

  /// Inhalt (z. B. [IntegrationTile]s).
  final List<Widget> children;

  /// Optionale Überschrift.
  final String? title;

  /// Trenner zwischen den Kindern.
  final bool dividers;

  /// Innenabstand.
  final EdgeInsetsGeometry padding;

  /// Abstand zwischen Überschrift und Kindern (ohne Trenner).
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (title != null) Text(title!, style: WText.sectionTitle),
      for (var i = 0; i < children.length; i++) ...[
        if (dividers && i > 0) const Divider(),
        children[i],
      ],
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WColors.surface,
        borderRadius: BorderRadius.circular(WRadius.cardLarge),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: spacing,
          children: items,
        ),
      ),
    );
  }
}
