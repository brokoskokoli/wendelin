// WP86: Verdrahtung der Integrationen „location“ und „maps“ und der
// Wetter-Standort (Haken „GPS-Position verwenden“). Eigene Datei (konfliktarm, wie media_wiring_test).
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin/di/app_requirements.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/integrations/location_spec.dart';
import 'package:wendelin/di/integrations/maps_spec.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/weather.dart';
import 'package:wendelin/di/weather_config.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/test_env.dart';

ToolContext _ctx() => ToolContext(
  sessionId: 's',
  clock: FixedClock(testNow),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);

void main() {
  test('Standort: Tools aktiv, sensibel, Maps optional', () async {
    final env = TestEnv(enabled: const {'location'});
    env.apps.uninstall(googleMapsPackage);
    final c = env.container();
    addTearDown(c.dispose);
    final registry = c.read(toolRegistryProvider);
    await registry.refresh();
    expect(registry.status('location'), IntegrationStatus.active);
    final catalog = registry.catalogFor(PrivacyLevel.local, sessionId: 's');
    final here = await catalog.lookup('location__current')!.execute({}, _ctx());
    expect(here.isError, isFalse, reason: here.text);
    // Ohne Google Maps geht die Navigation über geo:.
    final nav = await catalog.lookup('location__navigate_to')!.execute({
      'destination': 'Hafen',
    }, _ctx());
    expect(nav.isError, isFalse, reason: nav.text);
    expect(env.mapsLauncher.launched.single.uri.scheme, 'geo');
    expect(locationSpec.allowedWhileLocked, isFalse);
  });

  test('Standort ist sensibel: nicht an Anbieter unter der Stufe', () async {
    final env = TestEnv(enabled: const {'location'});
    final c = env.container();
    addTearDown(c.dispose);
    final registry = c.read(toolRegistryProvider);
    await registry.refresh();
    registry.sensitiveMinimum = PrivacyLevel.eu;
    expect(
      registry
          .catalogFor(PrivacyLevel.standard, sessionId: 's')
          .lookup('location__current'),
      isNull,
    );
    expect(
      registry
          .catalogFor(PrivacyLevel.local, sessionId: 's')
          .lookup('location__current'),
      isNotNull,
    );
  });

  test('Standort: Einschalten fragt die Berechtigung an', () async {
    final env = TestEnv();
    final deps = IntegrationDeps(
      ports: env.ports,
      device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
      httpClient: http.Client(),
    );
    env.location.permission = false;
    env.location.grantOnRequest = false;
    expect(await locationSpec.requestPermission!(deps), isFalse);
    env.location.grantOnRequest = true;
    expect(await locationSpec.requestPermission!(deps), isTrue);
    expect(env.location.requests, 2);
    expect(locationSpec.isSupported!(deps), isTrue);
  });

  test('Standort ohne Berechtigung: Schritt offen, Tool meldet es', () async {
    final env = TestEnv(enabled: const {'location'});
    env.location.permission = false;
    final c = env.container();
    addTearDown(c.dispose);
    final registry = c.read(toolRegistryProvider);
    await registry.refresh();
    expect(registry.info('location').setup.missingSteps, [
      LocationIntegration.permissionStep,
    ]);
  });

  test('Maps nur mit installierter App', () async {
    final env = TestEnv(enabled: const {'maps'});
    env.apps.uninstall(googleMapsPackage);
    final c = env.container();
    addTearDown(c.dispose);
    final registry = c.read(toolRegistryProvider);
    await registry.refresh();
    expect(registry.status('maps'), IntegrationStatus.unavailable);
    expect(
      registry
          .catalogFor(PrivacyLevel.local, sessionId: 's')
          .lookup('maps__navigate'),
      isNull,
    );
    env.apps.install(googleMapsPackage);
    await registry.refresh('maps');
    expect(registry.status('maps'), IntegrationStatus.active);
    final o = await registry
        .catalogFor(PrivacyLevel.local, sessionId: 's')
        .lookup('maps__search_place')!
        .execute({'query': 'Apotheke'}, _ctx());
    expect(o.isError, isFalse, reason: o.text);
    expect(env.mapsLauncher.launched.single.package, googleMapsPackage);
    expect(mapsSpec.requiredApp, same(KnownApps.googleMaps));
  });

  group('Wetter und Standort', () {
    // Wetter nutzt die Geräteposition nur mit dem Haken „GPS-Position
    // verwenden“, unabhängig von der Integration „Standort“.
    TestEnv gps({bool useGps = true, Set<String> enabled = const {}}) =>
        TestEnv(
          startup: StartupSettings(
            enabledIntegrations: enabled,
            weather: WeatherConfig(useGps: useGps),
          ),
        );

    test('ohne Haken kein Port, auch bei eingeschaltetem Standort', () async {
      for (final env in [
        TestEnv(),
        TestEnv(enabled: const {'location'}),
        gps(useGps: false, enabled: const {'location', 'weather'}),
      ]) {
        final c = env.container();
        addTearDown(c.dispose);
        expect(c.read(weatherLocationPortProvider), isNull);
      }
    });

    test('mit Haken ein Port, auch bei ausgeschaltetem Standort', () async {
      final on = gps();
      final c = on.container();
      addTearDown(c.dispose);
      expect(c.read(enabledIntegrationsProvider), isNot(contains('location')));
      final port = c.read(weatherLocationPortProvider)!;
      expect(
        (await port.currentPlace(level: PrivacyLevel.tee))!.name,
        'Hamburg',
      );
    });

    test('Haken umschalten baut den Port neu', () async {
      final env = gps(useGps: false);
      final c = env.container();
      addTearDown(c.dispose);
      expect(c.read(weatherLocationPortProvider), isNull);
      await c
          .read(weatherConfigProvider.notifier)
          .set(const WeatherConfig(useGps: true));
      expect(c.read(weatherLocationPortProvider), isNotNull);
      await c.read(weatherConfigProvider.notifier).set(const WeatherConfig());
      expect(c.read(weatherLocationPortProvider), isNull);
    });

    test('Ziel ab Mindeststufe bekommt die Geräteposition', () async {
      final on = gps();
      final c = on.container();
      addTearDown(c.dispose);
      final port = c.read(weatherLocationPortProvider)!;
      expect(
        (await port.currentPlace(level: PrivacyLevel.tee))!.name,
        'Hamburg',
      );
      expect(
        (await port.currentPlace(level: PrivacyLevel.local))!.name,
        'Hamburg',
      );
      on.location.permission = false;
      expect(await port.currentPlace(level: PrivacyLevel.local), isNull);
    });

    test('Position bei jeder Frage neu', () async {
      final on = gps();
      final c = on.container();
      addTearDown(c.dispose);
      final port = c.read(weatherLocationPortProvider)!;
      expect(
        (await port.currentPlace(level: PrivacyLevel.tee))!.name,
        'Hamburg',
      );
      on.location.fix = const GeoFix(
        latitude: 54.3233,
        longitude: 10.1228,
        placeName: 'Kiel',
      );
      final moved = (await port.currentPlace(level: PrivacyLevel.tee))!;
      expect(moved.name, 'Kiel');
      expect((moved.latitude, moved.longitude), (54.32, 10.12));
    });

    test('Standard-Ziel: Wetter ohne Geräteposition', () async {
      final on = gps();
      final c = on.container();
      addTearDown(c.dispose);
      final port = c.read(weatherLocationPortProvider)!;
      for (final level in [PrivacyLevel.standard, PrivacyLevel.eu, null]) {
        expect(await port.currentPlace(level: level), isNull, reason: '$level');
      }
      expect(on.location.methodCalls, isNot(contains('current')));
    });

    test('Abfluss-Schutz verweigert: Wetter nimmt den Heimatort', () async {
      const home = Place(name: 'Zuhause', latitude: 48.1, longitude: 11.6);
      final seen = <Uri>[];
      final env = TestEnv(
        startup: const StartupSettings(
          enabledIntegrations: {'weather'},
          weather: WeatherConfig(home: home, useGps: true),
        ),
        extraOverrides: [
          httpClientProvider.overrideWithValue(
            MockClient((r) async {
              seen.add(r.url);
              return http.Response('{}', 200);
            }),
          ),
        ],
      );
      final c = env.container();
      addTearDown(c.dispose);
      final registry = c.read(toolRegistryProvider);
      await registry.refresh();
      final tool = registry
          .catalogFor(PrivacyLevel.standard, sessionId: 's')
          .lookup('weather__forecast')!;
      await tool.execute(
        {},
        ToolContext(
          sessionId: 's',
          clock: FixedClock(testNow),
          locale: 'de-DE',
          timeZone: 'Europe/Berlin',
          privacyLevel: PrivacyLevel.standard,
        ),
      );
      expect(seen.single.queryParameters['latitude'], '48.1000');
      expect(env.location.methodCalls, isNot(contains('current')));
    });

    test(
      'Nutzer markiert Standort als nicht sensibel: auch Standard',
      () async {
        final on = gps();
        final c = on.container();
        addTearDown(c.dispose);
        await c
            .read(toolPrefsProvider.notifier)
            .set(const ToolPrefs(sensitive: {'location': false}));
        final port = c.read(weatherLocationPortProvider)!;
        expect(
          (await port.currentPlace(level: PrivacyLevel.standard))!.name,
          'Hamburg',
        );
      },
    );

    test('eigene Mindeststufe zählt', () async {
      final on = gps();
      final c = on.container();
      addTearDown(c.dispose);
      await c
          .read(toolPrefsProvider.notifier)
          .set(const ToolPrefs(sensitiveMinimum: PrivacyLevel.eu));
      final port = c.read(weatherLocationPortProvider)!;
      expect(await port.currentPlace(level: PrivacyLevel.standard), isNull);
      expect(
        (await port.currentPlace(level: PrivacyLevel.eu))!.name,
        'Hamburg',
      );
    });
  });
}
