import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Gestrichelter, abgerundeter Rahmen (Standard-Chip, Default-Regel).
class DashedBorder extends StatelessWidget {
  /// Erstellt einen gestrichelten Rahmen um [child].
  const DashedBorder({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
    this.width = WSize.border,
  });

  /// Inhalt.
  final Widget child;

  /// Strichfarbe.
  final Color color;

  /// Eckenradius.
  final double radius;

  /// Strichstärke.
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashedPainter(color, radius, width),
    child: child,
  );
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color, this.radius, this.width);

  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final r = radius.clamp(0.0, rect.shortestSide / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final dash = width * 2.5;
    final gap = width * 2;
    for (final ui.PathMetric m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius || old.width != width;
}
