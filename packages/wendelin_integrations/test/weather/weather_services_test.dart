import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/src/weather/weather_conditions.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'support.dart';

void main() {
  group('Open-Meteo', () {
    final seen = <http.Request>[];
    setUp(seen.clear);
    OpenMeteoWeather make() => OpenMeteoWeather(
      client: mock(seen, fixture('openmeteo_forecast.json')),
    );

    weatherServiceContract('OpenMeteoWeather', make, request: request());

    test('Anfrage: Koordinaten, Zeitzone, km/h, Tage', () async {
      await make().forecast(request(days: 3));
      final q = seen.single.url.queryParameters;
      expect(seen.single.url.host, 'api.open-meteo.com');
      expect(q['latitude'], '53.5507');
      expect(q['longitude'], '9.9930');
      expect(q['timezone'], 'Europe/Berlin');
      expect(q['wind_speed_unit'], 'kmh');
      expect(q['forecast_days'], '3');
    });

    test('Stunden verlangen mindestens zwei Tage', () async {
      await make().forecast(request(days: 1, hours: 12));
      expect(seen.single.url.queryParameters['forecast_days'], '2');
    });

    test('Werte aus der aufgezeichneten Antwort', () async {
      final r = await make().forecast(request());
      expect(r.current!.temperatureC, 12.3);
      expect(r.current!.condition, 'bedeckt');
      expect(r.current!.windKmh, 16.1);
      expect(r.current!.windFromDeg, 63);
      expect(r.hourly, hasLength(48));
      expect(r.hourly[13].time.hour, 13);
      expect(r.daily, hasLength(2));
      expect(r.daily.first.maxC, greaterThan(r.daily.first.minC));
    });

    test('Marine: Wellen, Dünung, Wassertemperatur', () async {
      final m = OpenMeteoMarine(
        client: mock(seen, fixture('openmeteo_marine.json')),
      );
      final r = await m.marine(request());
      expect(seen.single.url.host, 'marine-api.open-meteo.com');
      expect(r.current!.waveHeightM, 0.54);
      expect(r.current!.swellHeightM, 0.10);
      expect(r.current!.seaTemperatureC, 24.9);
      expect(r.current!.wavePeriodS, 3.05);
      expect(r.daily.map((d) => d.waveMaxM), [0.76, 0.82]);
    });

    test('Marine ohne Meeresdaten: notFound', () async {
      final m = OpenMeteoMarine(
        client: mock(
          seen,
          '{"daily":{"time":["2026-10-18"],'
          '"wave_height_max":[null]},"current":{"wave_height":null}}',
        ),
      );
      await expectLater(
        m.marine(request()),
        throwsA(
          isA<PortException>().having(
            (e) => e.kind,
            'kind',
            PortErrorKind.notFound,
          ),
        ),
      );
    });

    test('Geocoding: erster Treffer mit Zeitzone', () async {
      final g = OpenMeteoGeocoder(
        client: mock(seen, fixture('geocode_hamburg.json')),
      );
      final p = await g.find(' Hamburg ', language: 'de');
      expect(p!.name, 'Hamburg');
      expect(p.latitude, closeTo(53.55, 0.01));
      expect(p.timeZone, 'Europe/Berlin');
      final q = seen.single.url.queryParameters;
      expect(q['name'], 'Hamburg');
      expect(q['language'], 'de');
    });

    test('Geocoding ohne Treffer: null; leerer Name: ArgumentError', () async {
      final g = OpenMeteoGeocoder(
        client: mock(seen, fixture('geocode_empty.json')),
      );
      expect(await g.find('Nirgendwo'), isNull);
      expect(() => g.find('  '), throwsArgumentError);
    });
  });

  group('Bright Sky', () {
    final seen = <http.Request>[];
    setUp(seen.clear);
    BrightSkyWeather make() =>
        BrightSkyWeather(client: mock(seen, fixture('brightsky_weather.json')));

    weatherServiceContract('BrightSkyWeather', make, request: request());

    test('Anfrage: Datum, Zeitzone, DWD-Einheiten', () async {
      await make().forecast(request(days: 2));
      final q = seen.single.url.queryParameters;
      expect(seen.single.url.host, 'api.brightsky.dev');
      expect(q['date'], '2026-10-18');
      expect(q['last_date'], '2026-10-20');
      expect(q['tz'], 'Europe/Berlin');
      expect(q['units'], 'dwd');
    });

    test('404 außerhalb Deutschlands: klare Meldung', () async {
      final s = BrightSkyWeather(client: mock([], '{}', status: 404));
      await expectLater(
        s.forecast(request()),
        throwsA(
          isA<PortException>().having(
            (e) => e.message,
            'message',
            contains('nur Orte in Deutschland'),
          ),
        ),
      );
    });

    test('jetzt = Stunde 13 Uhr, Tage aus Stunden zusammengesetzt', () async {
      final r = await make().forecast(request());
      expect(r.current!.condition, isNot('unbekannt'));
      expect(r.current!.windFromDeg, isNotNull);
      expect(r.daily.first.precipMm, greaterThan(0));
      expect(r.daily.first.minC, lessThan(r.daily.first.maxC));
      expect(r.hourly.first.time.hour, 0);
    });
  });

  group('MET Norway', () {
    final seen = <http.Request>[];
    setUp(seen.clear);
    MetNorwayWeather make() => MetNorwayWeather(
      client: mock(seen, fixture('metno_compact.json')),
      userAgent: weatherUserAgent('0.1.0'),
    );

    weatherServiceContract('MetNorwayWeather', make, request: request());

    test('User-Agent mit App-Name und Repo-URL', () async {
      await make().forecast(request());
      expect(
        seen.single.headers['User-Agent'],
        'Wendelin/0.1.0 github.com/brokoskokoli/wendelin',
      );
      expect(seen.single.url.queryParameters['lat'], '53.5507');
    });

    test('Wind in km/h (m/s * 3,6), UTC auf Ortszeit', () async {
      final r = await make().forecast(request());
      // 10:00Z = 12:00 Berlin, wind_speed 6.3 m/s.
      expect(r.hourly.first.time.hour, 12);
      expect(r.hourly.first.windKmh, closeTo(22.68, 0.01));
      expect(r.current!.condition, 'bedeckt');
    });

    test('heute nur Rest des Tages, spätere Tage vollständig', () async {
      final r = await make().forecast(request(days: 3));
      expect(r.daily.first.remainingOnly, isTrue);
      expect(r.daily.skip(1).every((d) => !d.remainingOnly), isTrue);
    });

    test('403 nennt die App-Kennung, nicht den API-Schlüssel', () async {
      final s = MetNorwayWeather(
        client: mock([], '{}', status: 403),
        userAgent: 'x',
      );
      await expectLater(
        s.forecast(request()),
        throwsA(
          isA<PortException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('MET Norway'),
              contains('Kennung'),
              isNot(contains('Schlüssel')),
            ),
          ),
        ),
      );
    });

    test('Stunden nur mit 1-Stunden-Schritten, Tage nutzen auch 6-Stunden-Schritte', () async {
      final r = await make().forecast(request(days: 4));
      expect(r.hourly.every((h) => h.hoursCovered == 1), isTrue);
      expect(r.daily.length, greaterThanOrEqualTo(4));
    });
  });

  group('Fehler', () {
    for (final (status, text) in [
      (429, 'Anfragelimit'),
      (500, 'Status 500'),
      (403, 'ungültig'),
    ]) {
      test('Status $status wird zu unavailable', () async {
        final s = OpenMeteoWeather(client: mock([], '{}', status: status));
        await expectLater(
          s.forecast(request()),
          throwsA(
            isA<PortException>()
                .having((e) => e.kind, 'kind', PortErrorKind.unavailable)
                .having(
                  (e) => e.message,
                  'message',
                  allOf(contains('Open-Meteo'), contains(text)),
                ),
          ),
        );
      });
    }

    test(
      'Müll als Antwort wird zu failed, nie zu einem anderen Fehler',
      () async {
        for (final body in [
          'kein json',
          '[]',
          '{}',
          '{"hourly":{},"daily":{}}',
        ]) {
          for (final s in <WeatherService>[
            OpenMeteoWeather(client: mock([], body)),
            BrightSkyWeather(client: mock([], body)),
            MetNorwayWeather(client: mock([], body), userAgent: 'x'),
          ]) {
            await expectLater(
              s.forecast(request()),
              throwsA(
                isA<PortException>().having(
                  (e) => e.kind,
                  'kind',
                  PortErrorKind.failed,
                ),
              ),
              reason: '${s.id}: $body',
            );
          }
        }
      },
    );

    test('Abbruch während der Anfrage', () async {
      final cancel = CancelToken();
      final never = Completer<http.Response>();
      final s = OpenMeteoWeather(client: MockClient((_) => never.future));
      final req = WeatherRequest(
        place: hamburg,
        zone: request().zone,
        now: recordedAt,
        cancel: cancel,
      );
      final f = s.forecast(req);
      cancel.cancel();
      await expectLater(f, throwsA(isA<CancelledException>()));
    });
  });

  group('Wetterlagen auf Deutsch', () {
    test('WMO', () {
      expect(wmoCondition(0), 'klar');
      expect(wmoCondition(63), 'Regen');
      expect(wmoCondition(95), 'Gewitter');
      expect(wmoCondition(null), 'unbekannt');
    });
    test('MET-Symbole', () {
      expect(metSymbolCondition('clearsky_day'), 'klar');
      expect(metSymbolCondition('lightrain'), 'leichter Regen');
      expect(
        metSymbolCondition('heavyrainshowersandthunder_night'),
        'starke Regenschauer mit Gewitter',
      );
      expect(metSymbolCondition('snow'), 'Schnee');
      expect(metSymbolCondition('rainandthunder'), 'Regen mit Gewitter');
      expect(metSymbolCondition(null), 'unbekannt');
    });
    test('Bright Sky', () {
      expect(brightSkyCondition('partly-cloudy-night'), 'teils bewölkt');
      expect(brightSkyCondition('thunderstorm'), 'Gewitter');
      expect(brightSkyCondition(null), 'unbekannt');
    });
  });
}
