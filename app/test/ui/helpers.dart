import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/theme/app_theme.dart';

/// Breite und Höhe der Screen-Vorlagen.
const screenSize = Size(390, 844);

/// Schlüssel der Fläche, die als Golden aufgenommen wird.
const goldenKey = ValueKey('golden');

/// Baut [child] im Wendelin-Theme in einer festen Fläche.
Widget themed(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildWendelinTheme(),
  home: child,
);

/// Setzt die Fläche auf [size] (logische Pixel) bei [dpr].
void setView(WidgetTester tester, Size size, {double dpr = 1}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = size * dpr;
  addTearDown(tester.view.reset);
}

/// Pumpt einen Baustein auf `ink` mit 20 Rand (390 breit) zur Aufnahme.
Future<void> pumpComponent(WidgetTester tester, List<Widget> items) async {
  setView(tester, const Size(390, 1400), dpr: 2);
  await tester.pumpWidget(
    themed(
      Scaffold(
        body: SingleChildScrollView(
          child: RepaintBoundary(
            key: goldenKey,
            child: ColoredBox(
              color: WColors.ink,
              child: Padding(
                padding: const EdgeInsets.all(WSpace.screen),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: WSpace.l,
                  children: [
                    for (final w in items)
                      Align(alignment: Alignment.centerLeft, child: w),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumpt einen Screen (390 × 844, DPR 1 wie die @1x-Vorlagen).
Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  setView(tester, screenSize);
  await tester.pumpWidget(
    themed(RepaintBoundary(key: goldenKey, child: screen)),
  );
  await tester.pumpAndSettle();
}
