import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../theme/app_theme.dart';

/// Kleine Form-Symbole vor Text (●, ◆, ▲, ○, ■, ✓, ✕).
///
/// Werden gezeichnet statt als Zeichen gesetzt, weil die gebündelten
/// Schriften diese Glyphen nicht enthalten.
enum GlyphShape {
  /// ● gefüllter Kreis.
  dot,

  /// ○ Kreisring.
  ring,

  /// ◆ Raute.
  diamond,

  /// ▲ Dreieck.
  triangle,

  /// ■ Quadrat.
  square,

  /// ✓ Haken (Linie).
  check,

  /// ✕ Kreuz (Linie).
  cross;

  /// Symbol der Datenschutzstufe (tokens.json → privacyLevel).
  static GlyphShape forPrivacy(PrivacyLevel level) => switch (level) {
    PrivacyLevel.local => dot,
    PrivacyLevel.tee => diamond,
    PrivacyLevel.eu => triangle,
    PrivacyLevel.standard => ring,
  };
}

/// Zeichnet ein [GlyphShape] in [color]; rein dekorativ (ohne Semantics).
class Glyph extends StatelessWidget {
  /// Erstellt ein Symbol.
  const Glyph(this.shape, {super.key, required this.color, this.size});

  /// Form.
  final GlyphShape shape;

  /// Farbe.
  final Color color;

  /// Kantenlänge, Standard [WSize.glyph].
  final double? size;

  @override
  Widget build(BuildContext context) {
    final s = size ?? WSize.glyph;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(s),
        painter: _GlyphPainter(shape, color),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.shape, this.color);

  final GlyphShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.17)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final c = size.center(Offset.zero);
    switch (shape) {
      case GlyphShape.dot:
        canvas.drawCircle(c, w / 2, fill);
      case GlyphShape.ring:
        canvas.drawCircle(c, w / 2 - stroke.strokeWidth / 2, stroke);
      case GlyphShape.diamond:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, 0)
            ..lineTo(w, c.dy)
            ..lineTo(c.dx, w)
            ..lineTo(0, c.dy)
            ..close(),
          fill,
        );
      case GlyphShape.triangle:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, w * 0.06)
            ..lineTo(w, w * 0.94)
            ..lineTo(0, w * 0.94)
            ..close(),
          fill,
        );
      case GlyphShape.square:
        canvas.drawRect(
          Rect.fromLTWH(w * 0.05, w * 0.05, w * 0.9, w * 0.9),
          fill,
        );
      case GlyphShape.check:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.1, w * 0.55)
            ..lineTo(w * 0.4, w * 0.85)
            ..lineTo(w * 0.92, w * 0.18),
          stroke,
        );
      case GlyphShape.cross:
        canvas
          ..drawLine(
            Offset(w * 0.15, w * 0.15),
            Offset(w * 0.85, w * 0.85),
            stroke,
          )
          ..drawLine(
            Offset(w * 0.85, w * 0.15),
            Offset(w * 0.15, w * 0.85),
            stroke,
          );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.shape != shape || old.color != color;
}
