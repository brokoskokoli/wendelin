import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'dashed_border.dart';
import 'icons.dart';

/// Routing-Regel in der Liste: Ziehgriff, Name, Bedingung in Mono.
///
/// Aktive Regel mit Kobalt-Rahmen; die Default-Regel gestrichelt und ohne
/// Ziehgriff (nicht verschiebbar).
class RuleTile extends StatelessWidget {
  /// Erstellt eine Regelzeile.
  const RuleTile({
    super.key,
    required this.name,
    required this.condition,
    this.active = false,
    this.isDefault = false,
    this.reorderIndex,
    this.onTap,
  });

  /// Name der Regel.
  final String name;

  /// Bedingung und Ziel („prefix "Claude" → Opus“).
  final String condition;

  /// Greift für den aktuellen Testsatz (Kobalt-Rahmen).
  final bool active;

  /// Default-Regel (gestrichelt, fest am Ende).
  final bool isDefault;

  /// Index in einer `ReorderableListView`; macht den Griff ziehbar.
  final int? reorderIndex;

  /// Öffnet die Regel.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget handle = WIcon(
      isDefault ? WIcons.fixedHandle : WIcons.dragHandle,
      size: WSize.ruleHandleWidth,
      height: WSize.icon,
      color: WColors.lineSubtle,
    );
    final index = reorderIndex;
    if (!isDefault && index != null) {
      handle = ReorderableDragStartListener(
        index: index,
        child: Semantics(label: 'Verschieben', child: handle),
      );
    }
    final content = Padding(
      padding: const EdgeInsets.all(WSpace.m14),
      child: Row(
        spacing: WSpace.m,
        children: [
          handle,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WSpace.xxs3,
              children: [
                Text(name, style: WText.label),
                Text(condition, style: WText.mono),
              ],
            ),
          ),
        ],
      ),
    );
    final radius = BorderRadius.circular(WRadius.buttonLarge);
    final tappable = Material(
      color: isDefault ? WColors.transparent : WColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: active
            ? const BorderSide(color: WColors.accent, width: WSize.border)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
    if (!isDefault) return tappable;
    return DashedBorder(
      color: WColors.line,
      radius: WRadius.buttonLarge,
      child: tappable,
    );
  }
}
