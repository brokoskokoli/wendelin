import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'assistant_overlay.dart' show OverlayPanel;

/// Frame of the overlay: transparent window, the sheet at the bottom, a tap
/// above it (or back) closes the overlay; the keyboard pushes the sheet up.
class OverlayFrame extends StatelessWidget {
  /// Creates the frame around [child] (the sheet content).
  const OverlayFrame({super.key, required this.onClose, required this.child});

  /// Closes the overlay.
  final VoidCallback onClose;

  /// Sheet content.
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onClose();
    },
    child: Material(
      type: MaterialType.transparency,
      // Keyboard (text input) pushes the sheet up.
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = math.min(
              WSize.overlaySheet,
              constraints.maxHeight * WSize.overlayMaxFraction,
            );
            return Column(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: context.l10n.overlayCloseAssistant,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onClose,
                    ),
                  ),
                ),
                SizedBox(
                  height: height,
                  child: OverlayPanel(child: child),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
