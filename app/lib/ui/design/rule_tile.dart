import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../theme/app_theme.dart';
import 'dashed_border.dart';
import 'glyphs.dart';
import 'icons.dart';
import 'privacy_chip.dart';

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
    this.target,
    this.targetLevel,
    this.active = false,
    this.isDefault = false,
    this.reorderIndex,
    this.onTap,
    this.handleLabel,
  });

  /// Semantics-Label des Ziehgriffs (Standard „Verschieben“).
  final String? handleLabel;

  /// Name der Regel.
  final String name;

  /// Bedingung (`keyword "privat"`); ohne [target] auch mit Ziel.
  final String condition;

  /// Ziel der Regel (`Phala GLM`), erscheint als „→ Ziel“ hinter der
  /// Bedingung.
  final String? target;

  /// Datenschutzstufe des Ziels; zeigt das Form-Symbol vor dem Ziel
  /// (`→ ◆ Phala GLM`).
  final PrivacyLevel? targetLevel;

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
    // The grip area is the tile's left edge (padding, grip, gap): at least
    // 44 wide and as high as the tile, so it is easy to hit.
    Widget handle = ColoredBox(
      color: WColors.transparent,
      child: SizedBox(
        width: WSize.touchMin,
        child: Center(
          child: WIcon(
            isDefault ? WIcons.fixedHandle : WIcons.dragHandle,
            size: WSize.ruleHandleWidth,
            height: WSize.icon,
            color: WColors.lineSubtle,
          ),
        ),
      ),
    );
    final index = reorderIndex;
    if (!isDefault && index != null) {
      handle = ReorderableDragStartListener(
        index: index,
        child: Semantics(
          container: true,
          label: handleLabel ?? 'Verschieben',
          child: handle,
        ),
      );
    }
    final content = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          handle,
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                0,
                WSpace.m14,
                WSpace.m14,
                WSpace.m14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: WSpace.xxs3,
                children: [
                  Text(name, style: WText.label),
                  _conditionText(),
                ],
              ),
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

  Widget _conditionText() {
    final t = target;
    final level = targetLevel;
    if (t == null) return Text(condition, style: WText.mono);
    return Text.rich(
      TextSpan(
        style: WText.mono,
        children: [
          TextSpan(text: '$condition → '),
          if (level != null) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Glyph(
                GlyphShape.forPrivacy(level),
                color: WColors.textMuted,
              ),
            ),
            const TextSpan(text: ' '),
          ],
          TextSpan(text: t),
        ],
      ),
      semanticsLabel: [
        condition,
        '→',
        if (level != null) 'Datenschutzstufe ${level.label},',
        t,
      ].join(' '),
    );
  }
}
