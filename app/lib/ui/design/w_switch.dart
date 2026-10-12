import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Schalter 52 × 32 mit Daumen 26 (Kobalt wenn an), Trefferfläche ≥ 48.
///
/// Eigener Baustein statt [Switch], weil der Material-3-Schalter im
/// ausgeschalteten Zustand einen kleineren Daumen zeichnet als der Entwurf.
class WSwitch extends StatelessWidget {
  /// Erstellt einen Schalter.
  const WSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  /// An/aus.
  final bool value;

  /// Änderung; `null` deaktiviert.
  final ValueChanged<bool>? onChanged;

  /// Semantics-Label (z. B. „Kalender“).
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    const inset = (WSize.switchHeight - WSize.switchThumb) / 2;
    final VoidCallback? toggle = enabled ? () => onChanged!(!value) : null;
    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: enabled,
      onTap: toggle,
      child: InkResponse(
        onTap: toggle,
        radius: WSize.switchHeight,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kMinInteractiveDimension,
            minHeight: kMinInteractiveDimension,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: AnimatedContainer(
              duration: WMotion.fast,
              width: WSize.switchWidth,
              height: WSize.switchHeight,
              padding: const EdgeInsets.all(inset),
              alignment: value
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              decoration: BoxDecoration(
                color: value ? WColors.accent : WColors.line,
                borderRadius: BorderRadius.circular(WRadius.chip),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: value ? WColors.onAccent : WColors.textMuted,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: WSize.switchThumb),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
