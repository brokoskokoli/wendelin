import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Pegelanzeige aus senkrechten Balken (4 breit, Abstand 4, Höhe 40).
///
/// [amplitudes] sind Werte von 0 bis 1 (außerhalb wird begrenzt), ein Balken
/// je Wert. Rein dekorativ; der Zustand steckt im Mikrofon-Button.
class Waveform extends StatelessWidget {
  /// Erstellt eine Wellenform.
  const Waveform({
    super.key,
    required this.amplitudes,
    this.height = WSize.waveHeight,
    this.color = WColors.accentLight,
  });

  /// Pegel je Balken, 0…1.
  final List<double> amplitudes;

  /// Gesamthöhe.
  final double height;

  /// Balkenfarbe.
  final Color color;

  /// Kleinste Balkenhöhe (bei Pegel 0).
  static const minBar = WSize.waveBar;

  @override
  Widget build(BuildContext context) {
    final n = amplitudes.length;
    final width = n == 0 ? 0.0 : n * WSize.waveBar + (n - 1) * WSize.waveGap;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width, height),
        painter: _WavePainter(amplitudes, color),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.amplitudes, this.color);

  final List<double> amplitudes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const radius = Radius.circular(WSize.waveBar / 2);
    for (var i = 0; i < amplitudes.length; i++) {
      final a = amplitudes[i].clamp(0.0, 1.0);
      final h = Waveform.minBar + a * (size.height - Waveform.minBar);
      final x = i * (WSize.waveBar + WSize.waveGap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, WSize.waveBar, h),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.color != color || !_listEquals(old.amplitudes, amplitudes);

  static bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
