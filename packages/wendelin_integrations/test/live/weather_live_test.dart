@Tags(['live'])
library;

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Live-Test ohne Schlüssel, je Dienst eine Anfrage. Start:
//   dart test -t live --run-skipped test/live/weather_live_test.dart

void main() {
  final client = http.Client();
  tearDownAll(client.close);

  const place = Place(
    name: 'Palma',
    latitude: 39.57,
    longitude: 2.65,
    timeZone: 'Europe/Madrid',
  );
  WeatherRequest request(Place p) => WeatherRequest(
    place: p,
    zone: timeZoneLocation(p.timeZone!),
    now: DateTime.now().toUtc(),
    days: 2,
    hours: 3,
  );

  void check(WeatherReport r) {
    expect(r.current, isNotNull);
    expect(r.hourly, isNotEmpty);
    expect(r.daily.length, greaterThanOrEqualTo(2));
    expect(r.daily.first.minC, lessThanOrEqualTo(r.daily.first.maxC));
  }

  test('Open-Meteo Ortssuche', () async {
    final found = await OpenMeteoGeocoder(client: client)
        .find('Hamburg', language: 'de');
    expect(found!.name, 'Hamburg');
    expect(found.timeZone, 'Europe/Berlin');
  });

  test('Open-Meteo Vorhersage', () async {
    check(await OpenMeteoWeather(client: client).forecast(request(place)));
  });

  test('Open-Meteo Marine', () async {
    final r = await OpenMeteoMarine(client: client).marine(request(place));
    expect(r.current?.seaTemperatureC, isNotNull);
  });

  test('Bright Sky (DWD)', () async {
    const berlin = Place(
      name: 'Berlin',
      latitude: 52.52,
      longitude: 13.4,
      timeZone: 'Europe/Berlin',
    );
    check(await BrightSkyWeather(client: client).forecast(request(berlin)));
  });

  test('MET Norway', () async {
    check(
      await MetNorwayWeather(
        client: client,
        userAgent: weatherUserAgent('live-test'),
      ).forecast(request(place)),
    );
  });
}
