// Gerätetest (WP11): erster Start mit Onboarding, „Demo ohne Provider“
// (Debug-Build, Skript-Provider, In-Memory-Ports) und ein erster Befehl.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/onboarding/onboarding_screen.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'support/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Onboarding → Demo ohne Provider → Termin per Text', (
    tester,
  ) async {
    final app = E2eApp(
      startup: const StartupSettings(onboardingDone: false),
      clock: FixedClock(e2eNow),
    );
    final c = await app.pump(tester);
    await pumpUntil(tester, find.byType(OnboardingScreen));

    await tester.tap(find.text('Deutsch').first);
    await pumpFor(tester);
    await tester.tap(find.text('Weiter'));
    await pumpUntil(tester, find.text('Sprachmodell'));
    await pumpFor(tester);
    await tester.tap(find.text('Demo ohne Provider'));
    await pumpUntil(tester, find.byType(MainScreen));
    expect(c.read(demoModeProvider), isTrue);
    expect(await app.storage.settings.get(AppSettings.onboardingDone), isTrue);
    expect(await app.storage.settings.get(AppSettings.language), 'de');
    await pumpUntil(tester, find.text('Demo · Skript'));

    await send(tester, 'Trag mir morgen um 10 Tauchen ein');
    await pumpUntil(tester, find.textContaining('steht im Kalender'));
    expect(
      find.descendant(
        of: find.byType(ToolResultCard),
        matching: find.text('Termin angelegt'),
      ),
      findsOneWidget,
    );
    final demo = c.read(platformPortsProvider).calendar;
    final events = await demo.listEvents(
      TimeRange(e2eTomorrow, e2eTomorrow.add(const Duration(days: 1))),
    );
    expect(events.single.title, 'Tauchen', reason: 'Demo-Kalender im Speicher');
    expect(
      await auditText(app),
      contains('calendar__create_event'),
      reason: 'Audit-Log',
    );
  });
}
