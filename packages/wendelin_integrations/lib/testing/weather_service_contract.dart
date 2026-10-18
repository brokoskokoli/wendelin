import 'package:test/test.dart';

import '../src/weather/weather_model.dart';
import '../src/weather/weather_service.dart';

/// Contract every [WeatherService] must pass. [create] returns a service
/// that answers [request] with a normal forecast (recorded or fake).
void weatherServiceContract(
  String name,
  WeatherService Function() create, {
  required WeatherRequest request,
}) {
  group('weatherServiceContract($name)', () {
    late WeatherReport report;

    setUp(() async => report = await create().forecast(request));

    test('names place and source, has a stable id', () {
      expect(report.place, request.place);
      expect(report.source, create().displayName);
      expect(create().id, isNotEmpty);
    });

    test('has current conditions with a temperature', () {
      expect(report.current, isNotNull);
      expect(report.current!.temperatureC, inInclusiveRange(-60, 60));
      expect(report.current!.condition, isNotEmpty);
    });

    test('hourly steps ascend and are 1 hour long', () {
      expect(report.hourly, isNotEmpty);
      for (var i = 1; i < report.hourly.length; i++) {
        expect(
          report.hourly[i].time.isAfter(report.hourly[i - 1].time),
          isTrue,
        );
      }
      expect(report.hourly.every((h) => h.hoursCovered == 1), isTrue);
    });

    test('days ascend, start today and cover the requested days', () {
      expect(report.daily.length, greaterThanOrEqualTo(request.days));
      final today = DateTime.utc(
        request.today.year,
        request.today.month,
        request.today.day,
      );
      expect(report.daily.first.date, today);
      for (var i = 1; i < report.daily.length; i++) {
        expect(report.daily[i].date.isAfter(report.daily[i - 1].date), isTrue);
      }
      for (final d in report.daily) {
        expect(d.minC, lessThanOrEqualTo(d.maxC));
        expect(d.condition, isNotEmpty);
      }
    });
  });
}
