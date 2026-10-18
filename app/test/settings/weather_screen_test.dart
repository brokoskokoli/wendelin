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
import 'package:wendelin/ui/settings/weather_screen.dart';
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
