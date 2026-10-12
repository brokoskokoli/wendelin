import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'icons.dart';

/// Zustand des Mikrofon-Buttons.
enum MicState {
  /// Bereit: Kobalt-Kreis mit Mikrofon.
  idle,

  /// Hört zu: zusätzlicher Ring in `accentLight`.
  listening,

  /// Verarbeitet: drei Punkte statt Mikrofon.
  thinking,

  /// Nicht verfügbar: gedämpft, nicht antippbar.
  disabled,
}

/// Runder Mikrofon-Button (72, kompakt 64) – der einzige Kobalt-Akzent.
class MicButton extends StatelessWidget {
  /// Erstellt einen Mikrofon-Button.
  const MicButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.compact = false,
    this.semanticLabel,
  });

  /// Zustand.
  final MicState state;

  /// Aktion bei Tipp (wird bei [MicState.disabled] ignoriert).
  final VoidCallback? onPressed;

  /// 64 statt 72 (Hauptbildschirm).
  final bool compact;

  /// Überschreibt das Standard-Label des Zustands.
  final String? semanticLabel;

  /// Standard-Label je Zustand.
  static String labelFor(MicState state) => switch (state) {
    MicState.idle => 'Sprechen',
    MicState.listening => 'Zuhören beenden',
    MicState.thinking => 'Antwort abbrechen',
    MicState.disabled => 'Mikrofon nicht verfügbar',
  };

  @override
  Widget build(BuildContext context) {
    final extent = compact ? WSize.micButtonCompact : WSize.micButton;
    final disabled = state == MicState.disabled;
    final Widget content = state == MicState.thinking
        ? const _ThinkingDots()
        : WIcon(
            WIcons.mic,
            size: compact ? WSize.micIconCompact : WSize.micIcon,
            color: disabled ? WColors.textMuted : WColors.onAccent,
          );
    final label = semanticLabel ?? labelFor(state);
    return CustomPaint(
      foregroundPainter: state == MicState.listening ? _RingPainter() : null,
      child: IconButton(
        tooltip: label,
        onPressed: disabled ? null : onPressed,
        icon: Semantics(label: label, child: content),
        style: IconButton.styleFrom(
          fixedSize: Size.square(extent),
          padding: EdgeInsets.zero,
          backgroundColor: WColors.accent,
          disabledBackgroundColor: WColors.surfaceRaised,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2 + WSize.micRingGap + WSize.micRing / 2;
    canvas.drawCircle(
      size.center(Offset.zero),
      radius,
      Paint()
        ..color = WColors.accentLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = WSize.micRing,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => false;
}

class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: WSpace.xs,
      children: [
        for (var i = 0; i < 3; i++)
          const DecoratedBox(
            decoration: BoxDecoration(
              color: WColors.onAccent,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: WSize.hintDot),
          ),
      ],
    );
  }
}
