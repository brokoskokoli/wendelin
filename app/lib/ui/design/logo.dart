import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

/// Untergrund, auf dem ein Logo steht (wählt die SVG-Variante).
enum LogoOn {
  /// Dunkler Untergrund (Standard).
  dark,

  /// Heller Untergrund (Papier).
  light,

  /// Kobalt-Fläche (weiß).
  accent,
}

String _variant(String base, LogoOn on) => switch (on) {
  LogoOn.dark => 'assets/logo/$base-on-dark.svg',
  LogoOn.light => 'assets/logo/$base.svg',
  LogoOn.accent => 'assets/logo/$base-white.svg',
};

/// Bildmarke (Ohrmuschel-Spirale mit Punkt), mindestens 24 hoch.
class WendelinMark extends StatelessWidget {
  /// Erstellt die Bildmarke.
  const WendelinMark({
    super.key,
    this.size = WSize.markSheet,
    this.on = LogoOn.dark,
  });

  /// Kantenlänge.
  final double size;

  /// Untergrund.
  final LogoOn on;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    _variant('wendelin-mark', on),
    width: size,
    height: size,
    excludeFromSemantics: true,
  );
}

/// Schriftzug „wendelin“ (Buchstaben als Pfade), mindestens 26 hoch.
class WendelinWordmark extends StatelessWidget {
  /// Erstellt den Schriftzug.
  const WendelinWordmark({
    super.key,
    this.height = WSize.wordmarkHeader,
    this.on = LogoOn.dark,
  });

  /// Höhe.
  final double height;

  /// Untergrund.
  final LogoOn on;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'wendelin',
    image: true,
    child: SvgPicture.asset(
      _variant('wendelin-wordmark', on),
      height: height,
      excludeFromSemantics: true,
    ),
  );
}

/// Bildmarke + Schriftzug nebeneinander.
class WendelinLockup extends StatelessWidget {
  /// Erstellt das Lockup.
  const WendelinLockup({
    super.key,
    this.height = WSize.lockup,
    this.on = LogoOn.dark,
  });

  /// Höhe.
  final double height;

  /// Untergrund (hell oder dunkel; Kobalt nutzt die dunkle Variante).
  final LogoOn on;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'wendelin',
    image: true,
    child: SvgPicture.asset(
      on == LogoOn.light
          ? 'assets/logo/wendelin-lockup.svg'
          : 'assets/logo/wendelin-lockup-on-dark.svg',
      height: height,
      excludeFromSemantics: true,
    ),
  );
}
