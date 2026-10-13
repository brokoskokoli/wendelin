import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_requirements.dart';
import 'package:wendelin/di/sensitivity.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  const obsidian = 'md.obsidian';

  test('Cache: merkt die Antwort, vergisst sie bei einem Fehler', () async {
    final port = FakeAppPresencePort(installed: [obsidian]);
    final apps = InstalledApps(port);
    expect(apps[obsidian], isNull, reason: 'noch nicht geprüft');
    expect(await apps.check(obsidian), isTrue);
    expect(apps[obsidian], isTrue);

    port.failNext('isInstalled');
    await expectLater(apps.check(obsidian), throwsA(isA<PortException>()));
    expect(apps[obsidian], isNull, reason: 'altes Ergebnis vergessen');

    port.uninstall(obsidian);
    expect(await apps.check(obsidian), isFalse);
    expect(apps[obsidian], isFalse);
  });

  group('AppRequirementGuard', () {
    FakeIntegration inner() => FakeIntegration(
      id: 'x',
      tools: [FakeTool(name: 'x__y')],
      availability: const Availability(available: false, reason: 'innen'),
    );

    test(
      'Pflicht-App fehlt: nicht verfügbar mit Link, innen nicht gefragt',
      () async {
        final i = inner();
        final guard = AppRequirementGuard(
          i,
          KnownApps.spotify,
          InstalledApps(FakeAppPresencePort()),
        );
        expect(
          await guard.checkAvailability(),
          Availability(
            available: false,
            reason: appMissingReason,
            storeUrl: KnownApps.spotify.storeUrl,
          ),
        );
        expect(i.availabilityChecks, 0);
      },
    );

    test('Pflicht-App da: eigene Verfügbarkeit zählt', () async {
      final guard = AppRequirementGuard(
        inner(),
        KnownApps.spotify,
        InstalledApps(
          FakeAppPresencePort(installed: [KnownApps.spotify.androidPackage]),
        ),
      );
      expect((await guard.checkAvailability()).reason, 'innen');
    });

    test(
      'Pflicht-App, Abfrage scheitert: Fehler geht an die Registry',
      () async {
        final port = FakeAppPresencePort()..failNext('isInstalled');
        final guard = AppRequirementGuard(
          inner(),
          KnownApps.spotify,
          InstalledApps(port),
        );
        await expectLater(
          guard.checkAvailability(),
          throwsA(isA<PortException>()),
        );
      },
    );

    test(
      'optionale App, Abfrage scheitert: Integration bleibt nutzbar',
      () async {
        final port = FakeAppPresencePort()..failNext('isInstalled');
        final apps = InstalledApps(port);
        final i = FakeIntegration(id: 'obsidian', tools: const []);
        final guard = AppRequirementGuard(
          i,
          KnownApps.obsidian.optional('Hinweis'),
          apps,
        );
        expect(await guard.checkAvailability(), Availability.yes);
        expect(apps[obsidian], isNull);
      },
    );

    test('unwrapIntegration entfernt alle Hüllen', () {
      final i = inner();
      final wrapped = SensitivityOverride(
        AppRequirementGuard(
          i,
          KnownApps.spotify,
          InstalledApps(FakeAppPresencePort()),
        ),
        sensitive: true,
      );
      expect(unwrapIntegration(wrapped), same(i));
      expect(wrapped.tools.single.name, 'x__y');
      expect(wrapped.sensitive, isTrue);
    });
  });
}
