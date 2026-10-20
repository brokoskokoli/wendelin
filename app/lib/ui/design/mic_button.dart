import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
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
    this.hearing = false,
  });

  /// Zustand.
  final MicState state;

  /// Aktion bei Tipp (wird bei [MicState.disabled] ignoriert).
  final VoidCallback? onPressed;

  /// 64 statt 72 (Hauptbildschirm).
  final bool compact;

  /// Wendelin hört während der Sprachausgabe auf „Stopp“/„Wendelin“
  /// (WP113): bei [MicState.speaking] liegt ein Ring um den Knopf.
  final bool hearing;

  /// Überschreibt das Standard-Label des Zustands.
  final String? semanticLabel;

  /// Standard-Label je Zustand.
  static String labelFor(AppLocalizations l, MicState state) => switch (state) {
    MicState.idle => l.mainMicSpeak,
    MicState.listening => l.mainMicStopListening,
    MicState.thinking => l.mainMicCancelAnswer,
    MicState.speaking => l.mainMicStopSpeech,
    MicState.preparing => l.momentPlease,
    MicState.disabled => l.mainMicUnavailable,
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
    final hearingRing = hearing && state == MicState.speaking;
    // Der Ring beim Zuhören liegt innerhalb der Fläche (72 bzw. 64): außen
    // der Ring, dann eine Lücke, innen die Kobalt-Scheibe. Kein Überstand,
    // kein Layout-Sprung zwischen den Zuständen.
    return CustomPaint(
      painter: listening || hearingRing
          ? _ListeningPainter(WColors.accentLight)
          : preparing
          ? _ListeningPainter(
              WColors.accentLight.withValues(alpha: WOpacity.inactive),
            )
          : null,
      child: IconButton(
        // Nur Tooltip: wird auch als Semantics-Tooltip vorgelesen; ein
        // zusätzliches Label würde doppelt angesagt.
        tooltip:
            semanticLabel ??
            (hearingRing
                ? context.l10n.mainMicHearing
                : labelFor(context.l10n, state)),
        onPressed: disabled ? null : onPressed,
        icon: content,
        style: IconButton.styleFrom(
          fixedSize: Size.square(extent),
          padding: EdgeInsets.zero,
          backgroundColor: listening || preparing || hearingRing
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
              offset: Offset(
                0,
                widget.animated ? -_bounce(i) * WSize.hintDot : 0,
              ),
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

  /// 0…1: a wave over the three dots, so the still image of „speaking“
  /// (animations off) differs from „thinking“ (dots in a row).
  double _bounce(int i) => (1 + math.sin(2 * math.pi * (_c.value - i / 3))) / 2;
}
