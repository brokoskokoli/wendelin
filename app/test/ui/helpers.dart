import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/theme/app_theme.dart';

/// Breite und Höhe der Screen-Vorlagen.
const screenSize = Size(390, 844);

/// Schlüssel der Fläche, die als Golden aufgenommen wird.
const goldenKey = ValueKey('golden');

/// Baut [child] im Wendelin-Theme in einer festen Fläche. Ohne
/// [animations] sind die Animationen abgeschaltet (ruhige Goldens,
/// `pumpAndSettle` endet).
Widget themed(Widget child, {bool animations = false}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildWendelinTheme(),
  builder: (context, home) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: !animations),
    child: home!,
  ),
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

Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

/// Pumps until [cond] holds (a `bool Function()` or a [Finder] that finds
/// something), giving real time to work outside the fake clock
/// (database, isolates, real streams). Fails after [timeout] (real time).
/// Replaces fixed `runAsync(Future.delayed)` waits: fast when the work is
/// quick, patient when the machine is loaded.
Future<void> pumpUntil(
  WidgetTester tester,
  Object cond, {
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 5),
  Duration pump = const Duration(milliseconds: 50),
  String? reason,
}) async {
  assert(cond is Finder || cond is bool Function());
  bool holds() =>
      cond is Finder ? cond.evaluate().isNotEmpty : (cond as bool Function())();
  final deadline = DateTime.now().add(timeout);
  while (!holds()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure(reason ?? 'pumpUntil: Zustand nicht erreicht ($cond)');
    }
    await tester.runAsync(() => _realDelay(step));
    await tester.pump(pump);
  }
}

/// Gives work outside the fake clock a fixed number of real [rounds] to
/// run, for absence checks ("nothing happened") that cannot be awaited.
Future<void> pumpReal(
  WidgetTester tester, {
  int rounds = 5,
  Duration step = const Duration(milliseconds: 10),
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => _realDelay(step));
    await tester.pump();
  }
}
