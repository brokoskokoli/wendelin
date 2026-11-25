import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/weather.dart';
import 'package:wendelin/di/weather_config.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/weather_screen.dart';
import 'package:wendelin/ui/voice/microphone_access.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart' show settle;
import 'lists_and_web_test.dart' show pumpPage;

const kiel = Place(
  name: 'Kiel',
  latitude: 54.32,
  longitude: 10.14,
  timeZone: 'Europe/Berlin',
);

void main() {
  testWidgets('Dienst wählen und Heimatort suchen → gespeichert', (
    tester,
  ) async {
    final env = TestEnv(
      enabled: const {'weather'},
      extraOverrides: [
        weatherGeocoderProvider.overrideWithValue(FakeGeocoder([kiel])),
      ],
    );
    final c = await pumpPage(tester, env, const WeatherScreen());
    expect(c.read(weatherConfigProvider), const WeatherConfig());

    await tester.tap(find.text('Bright Sky (DWD)'));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('weatherHome')), 'Kiel');
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    const expected = WeatherConfig(
      kind: WeatherServiceKind.brightSky,
      home: kiel,
    );
    expect(c.read(weatherConfigProvider), expected);
    expect(await env.storage.settings.get(AppSettings.weather), expected);
  });

  testWidgets('unbekannter Heimatort: Fehler, nichts gespeichert', (
    tester,
  ) async {
    final env = TestEnv(
      enabled: const {'weather'},
      extraOverrides: [
        weatherGeocoderProvider.overrideWithValue(FakeGeocoder(const [])),
      ],
    );
    final c = await pumpPage(tester, env, const WeatherScreen());
    await tester.enterText(find.byKey(const ValueKey('weatherHome')), 'Xyzzy');
    await tester.tap(find.text('Speichern'));
    await settle(tester);
    expect(find.text('Ort „Xyzzy“ nicht gefunden.'), findsOneWidget);
    expect(c.read(weatherConfigProvider), const WeatherConfig());
    expect(await env.storage.settings.get(AppSettings.weather), isNull);
  });

  testWidgets('Name unverändert: keine neue Suche, Ort bleibt', (tester) async {
    final geocoder = FakeGeocoder(const []);
    final env = TestEnv(
      enabled: const {'weather'},
      startup: const StartupSettings(
        enabledIntegrations: {'weather'},
        weather: WeatherConfig(home: kiel),
      ),
      extraOverrides: [weatherGeocoderProvider.overrideWithValue(geocoder)],
    );
    final c = await pumpPage(tester, env, const WeatherScreen());
    await tester.tap(find.text('Speichern'));
    await settle(tester);
    expect(geocoder.asked, isEmpty);
    expect(c.read(weatherConfigProvider).home, kiel);
  });

  testWidgets('leeres Feld entfernt den Heimatort', (tester) async {
    final env = TestEnv(
      enabled: const {'weather'},
      startup: const StartupSettings(
        enabledIntegrations: {'weather'},
        weather: WeatherConfig(home: kiel),
      ),
    );
    final c = await pumpPage(tester, env, const WeatherScreen());
    await tester.enterText(find.byKey(const ValueKey('weatherHome')), '');
    await tester.tap(find.text('Speichern'));
    await settle(tester);
    expect(c.read(weatherConfigProvider).home, isNull);
    expect((await env.storage.settings.get(AppSettings.weather))!.home, isNull);
  });

  group('Haken „GPS-Position verwenden“', () {
    Finder gpsSwitch() => find.byKey(const ValueKey('weatherUseGps'));
    bool gpsOn(WidgetTester tester) =>
        tester.widget<WSwitch>(gpsSwitch()).value;
    final denied = find.text('Kein Zugriff auf den Standort');

    testWidgets('Antippen schaltet um, Speichern schreibt useGps', (
      tester,
    ) async {
      final env = TestEnv(enabled: const {'weather'});
      final c = await pumpPage(tester, env, const WeatherScreen());
      expect(find.text('GPS-Position verwenden'), findsOneWidget);
      expect(
        find.text(
          'Nur für Fragen ohne Ortsangabe. Der Ort geht an den Wetterdienst.',
        ),
        findsOneWidget,
      );
      expect(gpsOn(tester), isFalse);

      await tester.tap(gpsSwitch());
      await settle(tester);
      expect(gpsOn(tester), isTrue);
      // Berechtigung schon erteilt: keine Erklärung, genau eine Anfrage.
      expect(find.text('Weiter'), findsNothing);
      expect(env.location.requests, 1);
      expect(denied, findsNothing);
      expect(c.read(weatherConfigProvider).useGps, isFalse);

      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(c.read(weatherConfigProvider), const WeatherConfig(useGps: true));
      expect(
        await env.storage.settings.get(AppSettings.weather),
        const WeatherConfig(useGps: true),
      );
    });

    testWidgets('verweigert: Haken bleibt an, Hinweis mit Einstellungen', (
      tester,
    ) async {
      final opened = <int>[];
      final env = TestEnv(
        enabled: const {'weather'},
        extraOverrides: [
          appSettingsOpenerProvider.overrideWithValue(
            () async => opened.add(1),
          ),
        ],
      );
      env.location
        ..permission = false
        ..grantOnRequest = false;
      final c = await pumpPage(tester, env, const WeatherScreen());

      await tester.tap(gpsSwitch());
      await settle(tester);
      // Erst die Erklärung, dann fragt Android.
      expect(find.textContaining('Standortzugriff'), findsOneWidget);
      expect(env.location.requests, 0);
      await tester.tap(find.text('Weiter'));
      await settle(tester);

      expect(env.location.requests, 1);
      expect(gpsOn(tester), isTrue);
      expect(denied, findsOneWidget);
      await tester.tap(find.text('Android-Einstellungen'));
      await settle(tester);
      expect(opened, [1]);

      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(c.read(weatherConfigProvider).useGps, isTrue);
    });

    testWidgets('erlaubt nach der Erklärung: kein Hinweis', (tester) async {
      final env = TestEnv(enabled: const {'weather'});
      env.location.permission = false;
      await pumpPage(tester, env, const WeatherScreen());
      await tester.tap(gpsSwitch());
      await settle(tester);
      await tester.tap(find.text('Weiter'));
      await settle(tester);
      expect(env.location.requests, 1);
      expect(gpsOn(tester), isTrue);
      expect(denied, findsNothing);
    });

    testWidgets('Erklärung abgebrochen: Haken bleibt aus, keine Anfrage', (
      tester,
    ) async {
      final env = TestEnv(enabled: const {'weather'});
      env.location.permission = false;
      await pumpPage(tester, env, const WeatherScreen());
      await tester.tap(gpsSwitch());
      await settle(tester);
      await tester.tap(find.text('Abbrechen'));
      await settle(tester);
      expect(env.location.requests, 0);
      expect(gpsOn(tester), isFalse);
    });

    testWidgets('Abhaken fragt nicht und speichert aus', (tester) async {
      final env = TestEnv(
        enabled: const {'weather'},
        startup: const StartupSettings(
          enabledIntegrations: {'weather'},
          weather: WeatherConfig(useGps: true),
        ),
      );
      final c = await pumpPage(tester, env, const WeatherScreen());
      expect(gpsOn(tester), isTrue);
      await tester.tap(gpsSwitch());
      await settle(tester);
      expect(gpsOn(tester), isFalse);
      expect(env.location.requests, 0);
      expect(find.text('Weiter'), findsNothing);
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(c.read(weatherConfigProvider).useGps, isFalse);
    });

    testWidgets('Berechtigung später entzogen: Hinweis beim Öffnen', (
      tester,
    ) async {
      final env = TestEnv(
        enabled: const {'weather'},
        startup: const StartupSettings(
          enabledIntegrations: {'weather'},
          weather: WeatherConfig(useGps: true),
        ),
      );
      env.location.permission = false;
      await pumpPage(tester, env, const WeatherScreen());
      expect(denied, findsOneWidget);
      expect(env.location.requests, 0);
    });
  });

  group('Verdrahtung', () {
    Future<(ToolRegistry, List<http.Request>)> registryWith(
      WeatherConfig config,
    ) async {
      final seen = <http.Request>[];
      final client = MockClient((request) async {
        seen.add(request);
        final body = request.url.host == 'geocoding-api.open-meteo.com'
            ? jsonEncode({
                'results': [
                  {
                    'name': 'Kiel',
                    'latitude': 54.32,
                    'longitude': 10.14,
                    'timezone': 'Europe/Berlin',
                  },
                ],
              })
            : '{}';
        return http.Response(body, 200);
      });
      final env = TestEnv(
        startup: StartupSettings(
          enabledIntegrations: const {'weather'},
          weather: config,
        ),
        extraOverrides: [httpClientProvider.overrideWithValue(client)],
      );
      final c = env.container();
      addTearDown(c.dispose);
      final registry = c.read(toolRegistryProvider);
      await registry.refresh();
      return (registry, seen);
    }

    ToolContext ctx() => ToolContext(
      sessionId: 's',
      clock: FixedClock(testNow),
      locale: 'de-DE',
      timeZone: 'Europe/Berlin',
    );

    test(
      'aktiv, nur lesende Tools; fehlender Heimatort ist optional',
      () async {
        final (registry, _) = await registryWith(const WeatherConfig());
        expect(registry.status('weather'), IntegrationStatus.active);
        expect(registry.info('weather').setup.missingSteps, ['home_place']);
        final specs = registry
            .catalogFor(PrivacyLevel.standard, sessionId: 's')
            .activeSpecs()
            .map((t) => t.name)
            .where((n) => n.startsWith('weather__'));
        expect(specs, ['weather__forecast', 'weather__marine']);
      },
    );

    for (final (kind, host, header) in [
      (WeatherServiceKind.openMeteo, 'api.open-meteo.com', null),
      (WeatherServiceKind.brightSky, 'api.brightsky.dev', null),
      (
        WeatherServiceKind.metNorway,
        'api.met.no',
        'Wendelin/$wendelinAppVersion github.com/brokoskokoli/wendelin',
      ),
    ]) {
      test('${kind.label}: Tool fragt den gewählten Dienst', () async {
        final (registry, seen) = await registryWith(WeatherConfig(kind: kind));
        final tool = registry
            .catalogFor(PrivacyLevel.standard, sessionId: 's')
            .lookup('weather__forecast')!;
        await tool.execute({'place': 'Kiel'}, ctx());
        expect(seen.map((r) => r.url.host), [
          'geocoding-api.open-meteo.com',
          host,
        ]);
        expect(seen.last.headers['User-Agent'], header);
      });
    }

    test('Heimatort aus den Einstellungen, wenn keine Frage-Ort', () async {
      final (registry, seen) = await registryWith(
        const WeatherConfig(home: kiel),
      );
      final tool = registry
          .catalogFor(PrivacyLevel.standard, sessionId: 's')
          .lookup('weather__forecast')!;
      await tool.execute({}, ctx());
      expect(seen.single.url.queryParameters['latitude'], '54.3200');
    });
  });

  test('wendelinAppVersion entspricht pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':').last.trim().split('+').first, wendelinAppVersion);
  });
}
