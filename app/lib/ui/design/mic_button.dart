import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'icons.dart';

/// Zustand des Mikrofon-Buttons.
enum MicState {
  /// Bereit: Kobalt-Kreis mit Mikrofon.
  idle,

  /// Hört zu: Ring in `accentLight` am Rand, Scheibe etwas kleiner.
  listening,

  /// Verarbeitet: drei ruhende Punkte statt Mikrofon.
  thinking,

  /// Spricht: drei bewegte Punkte (Tipp stoppt die Sprachausgabe).
  speaking,

  /// Bereitet vor („Moment …“): Mikrofon mit gedämpftem Ring, solange die
  /// Sprachmodelle laden; das Mikrofon puffert schon.
  preparing,

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

  /// Text beim Vorbereiten.
  static const preparingLabel = 'Moment …';

  /// Standard-Label je Zustand.
  static String labelFor(MicState state) => switch (state) {
    MicState.idle => 'Sprechen',
    MicState.listening => 'Zuhören beenden',
    MicState.thinking => 'Antwort abbrechen',
    MicState.speaking => 'Sprachausgabe stoppen',
    MicState.preparing => preparingLabel,
    MicState.disabled => 'Mikrofon nicht verfügbar',
  };

  @override
  Widget build(BuildContext context) {
    final extent = compact ? WSize.micButtonCompact : WSize.micButton;
    final disabled = state == MicState.disabled;
    final Widget content = switch (state) {
      MicState.thinking => const _Dots(animated: false),
      MicState.speaking => const _Dots(animated: true),
      _ => WIcon(
        WIcons.mic,
        size: compact ? WSize.micIconCompact : WSize.micIcon,
        color: disabled ? WColors.textMuted : WColors.onAccent,
      ),
    };
    final listening = state == MicState.listening;
    final preparing = state == MicState.preparing;
    // Der Ring beim Zuhören liegt innerhalb der Fläche (72 bzw. 64): außen
    // der Ring, dann eine Lücke, innen die Kobalt-Scheibe. Kein Überstand,
    // kein Layout-Sprung zwischen den Zuständen.
    return CustomPaint(
      painter: listening
          ? _ListeningPainter(WColors.accentLight)
          : preparing
          ? _ListeningPainter(
              WColors.accentLight.withValues(alpha: WOpacity.inactive),
            )
          : null,
      child: IconButton(
        // Nur Tooltip: wird auch als Semantics-Tooltip vorgelesen; ein
        // zusätzliches Label würde doppelt angesagt.
        tooltip: semanticLabel ?? labelFor(state),
        onPressed: disabled ? null : onPressed,
        icon: content,
        style: IconButton.styleFrom(
          fixedSize: Size.square(extent),
          padding: EdgeInsets.zero,
          backgroundColor: listening || preparing
              ? WColors.transparent
              : WColors.accent,
          disabledBackgroundColor: WColors.surfaceRaised,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _ListeningPainter extends CustomPainter {
  _ListeningPainter(this.ring);

  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas
      ..drawCircle(
        c,
        r - WSize.micRing / 2,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = WSize.micRing,
      )
      ..drawCircle(
        c,
        r - WSize.micRing - WSize.micRingGap,
        Paint()..color = WColors.accent,
      );
  }

  @override
  bool shouldRepaint(_ListeningPainter oldDelegate) => oldDelegate.ring != ring;
}

/// Drei Punkte; [animated] lässt sie nacheinander hüpfen (Sprechen).
/// Ohne Bewegung, wenn die Animationen abgeschaltet sind.
class _Dots extends StatefulWidget {
  const _Dots({required this.animated});

  final bool animated;

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final move = widget.animated && !MediaQuery.disableAnimationsOf(context);
    if (move && !_c.isAnimating) {
      unawaited(_c.repeat());
    } else if (!move && _c.isAnimating) {
      _c.stop();
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: WSpace.xs,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(0, move ? -_bounce(i) * WSize.hintDot : 0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: WColors.onAccent,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(dimension: WSize.hintDot),
              ),
            ),
        ],
      ),
    );
  }

  /// 0…1: the dot [i] jumps in its third of the period.
  double _bounce(int i) {
    final t = (_c.value - i / 3) % 1.0;
    return t < 1 / 3 ? math.sin(t * 3 * math.pi) : 0;
  }
}
