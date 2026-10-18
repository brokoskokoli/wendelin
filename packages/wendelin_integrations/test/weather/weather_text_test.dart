import 'package:test/test.dart';
import 'package:wendelin_integrations/src/weather/weather_model.dart';
import 'package:wendelin_integrations/src/weather/weather_text.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'support.dart';

WeatherReport report({
  double gust = 35,
  List<ForecastDay>? daily,
  String condition = 'bedeckt',
}) => WeatherReport(
  place: hamburg,
  source: 'Test',
  current: CurrentWeather(
    temperatureC: 12,
    condition: condition,
    windKmh: 20,
    gustKmh: gust,
  ),
  hourly: const [],
  daily:
      daily ??
      [
        ForecastDay(
          date: DateTime.utc(2026, 10, 18),
          minC: 8,
          maxC: 14,
          condition: condition,
          windMaxKmh: 20,
          gustMaxKmh: gust,
        ),
      ],
);

void main() {
  group('describeForecast', () {
    test('Böen erst ab 15 km/h über dem Wind (Jetzt und Tage)', () {
      final at = describeForecast(report(gust: 35), request());
      expect('Böen bis 35 km/h'.allMatches(at).length, 2);
      final below = describeForecast(report(gust: 34), request());
      expect(below, isNot(contains('Böen')));
    });

    test('vergangene Tage werden ausgelassen', () {
      final text = describeForecast(
        report(
          daily: [
            ForecastDay(
              date: DateTime.utc(2026, 10, 17),
              minC: 1,
              maxC: 2,
              condition: 'Schnee',
            ),
            ForecastDay(
              date: DateTime.utc(2026, 10, 18),
              minC: 8,
              maxC: 14,
              condition: 'bedeckt',
            ),
          ],
        ),
        request(days: 2),
      );
      expect(text, isNot(contains('Sa 17.10.')));
      expect(text, isNot(contains('Schnee')));
      expect(text, contains('Heute: 8 bis 14 Grad'));
    });

    test('„unbekannt“ wird nicht gesprochen', () {
      final text = describeForecast(
        report(condition: 'unbekannt', gust: 20),
        request(),
      );
      expect(text, isNot(contains('unbekannt')));
      expect(text, contains('Jetzt: 12 Grad, Wind 20 km/h'));
    });

    test('Rest des Tages: nur noch Höchstwert', () {
      final text = describeForecast(
        report(
          daily: [
            ForecastDay(
              date: DateTime.utc(2026, 10, 18),
              minC: 11,
              maxC: 14,
              condition: 'bedeckt',
              remainingOnly: true,
            ),
          ],
        ),
        request(days: 1),
      );
      expect(text, contains('Heute: noch bis 14 Grad'));
      expect(text, isNot(contains('11 bis')));
    });
  });
}
