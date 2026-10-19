// WP50 b: Goldens der Aktivierungswort-Seite und des Erklärdialogs (nur macOS
// aktualisieren).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';
import 'package:wendelin/ui/design/design.dart' show WSwitch;
import 'package:wendelin/ui/onboarding/onboarding_screen.dart';

import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;
import 'onboarding_test.dart' show firstStart, pumpApp;
import 'wake_service_section_test.dart' show Setup, pump;

Future<void> golden(WidgetTester tester, String name) =>
    expectLater(find.byKey(goldenKey), matchesGoldenFile('goldens/$name.png'));

void main() {
  testWidgets('Golden Aktivierungswort: Rolle fehlt', tags: ['golden'], (
    tester,
  ) async {
    await pump(tester, Setup(status: const WakeServiceStatus()), golden: true);
    await golden(tester, 'wake_dienst_rolle_fehlt');
  });

  testWidgets('Golden Aktivierungswort: läuft', tags: ['golden'], (
    tester,
  ) async {
    await pump(
      tester,
      Setup(status: const WakeServiceStatus(running: true, holdsRole: true)),
      enabled: true,
      golden: true,
    );
    await golden(tester, 'wake_dienst_laeuft');
  });

  testWidgets('Golden Aktivierungswort: vom System beendet', tags: ['golden'], (
    tester,
  ) async {
    await pump(
      tester,
      Setup(
        status: const WakeServiceStatus(holdsRole: true, lastStop: 'timeout'),
      ),
      enabled: true,
      condition: WakeCondition.always,
      golden: true,
    );
    await golden(tester, 'wake_dienst_beendet');
  });

  testWidgets('Golden Erklärdialog', tags: ['golden'], (tester) async {
    await pump(tester, Setup(), golden: true);
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is WSwitch && w.semanticLabel == 'Aktivierungswort einschalten',
      ),
    );
    await settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/wake_erklaerdialog.png'),
    );
  });

  testWidgets('Golden Onboarding-Schritt Aktivierungswort', tags: ['golden'], (
    tester,
  ) async {
    final env = firstStart();
    await pumpApp(tester, env);
    for (final label in ['Weiter', 'Später', 'Später']) {
      await tester.tap(find.text(label));
      await settle(tester);
    }
    await tester.tap(find.text('Ja, weiter zuhören'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Weiter'), 200);
    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    // The golden keeps its original frame.
    setView(tester, const Size(390, 1400));
    await settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/wake_onboarding_schritt.png'),
    );
  });
}
