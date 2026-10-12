import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Prüfstatus (Quittung, Attestierung, Tool-Lauf). Immer Farbe + Form.
enum CheckStatus {
  /// Geprüft: grüner Kreis mit Haken.
  ok,

  /// Ausstehend / Bestätigung nötig: gelbes Dreieck mit Ausrufezeichen.
  pending,

  /// Fehlgeschlagen: rotes Quadrat mit Kreuz.
  failed;

  /// Statusfarbe.
  Color get color => switch (this) {
    ok => WColors.ok,
    pending => WColors.warn,
    failed => WColors.error,
  };

  /// Deutsches Semantics-Label.
  String get label => switch (this) {
    ok => 'geprüft',
    pending => 'ausstehend',
    failed => 'fehlgeschlagen',
  };
}

/// Status-Symbol: Kreis mit Haken, Dreieck oder Quadrat mit Kreuz.
///
/// Geometrie aus docs/design/screens/pruefprotokoll.html (viewBox 20).
class CheckStatusIcon extends StatelessWidget {
  /// Erstellt ein Status-Symbol.
  const CheckStatusIcon(
    this.status, {
    super.key,
    this.size = WSize.statusIcon,
    this.semanticLabel,
  });

  /// Status.
  final CheckStatus status;

  /// Kantenlänge.
  final double size;

  /// Überschreibt das Semantics-Label (Standard: [CheckStatus.label]).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? status.label,
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _CheckStatusPainter(status),
      ),
    );
  }
}

class _CheckStatusPainter extends CustomPainter {
  _CheckStatusPainter(this.status);

  final CheckStatus status;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 20;
    canvas.scale(k);
    final fill = Paint()..color = status.color;
    final mark = Paint()
      ..color = WColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (status) {
      case CheckStatus.ok:
        canvas
          ..drawCircle(const Offset(10, 10), 9, fill)
          ..drawPath(
            Path()
              ..moveTo(6, 10.5)
              ..lineTo(9, 13)
              ..lineTo(14, 7.5),
            mark..strokeWidth = 2.2,
          );
      case CheckStatus.pending:
        canvas
          ..drawPath(
            Path()
              ..moveTo(10, 1.5)
              ..lineTo(18.5, 17.5)
              ..lineTo(1.5, 17.5)
              ..close(),
            fill,
          )
          ..drawLine(const Offset(10, 7.5), const Offset(10, 11.5), mark)
          ..drawLine(const Offset(10, 14.2), const Offset(10, 14.4), mark);
      case CheckStatus.failed:
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(1.5, 1.5, 17, 17),
              const Radius.circular(3),
            ),
            fill,
          )
          ..drawLine(const Offset(6.5, 6.5), const Offset(13.5, 13.5), mark)
          ..drawLine(const Offset(13.5, 6.5), const Offset(6.5, 13.5), mark);
    }
  }

  @override
  bool shouldRepaint(_CheckStatusPainter old) => old.status != status;
}
