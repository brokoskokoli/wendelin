import 'package:http/http.dart' as http;

import 'weather_aggregate.dart';
import 'weather_conditions.dart';
import 'weather_json.dart';
import 'weather_model.dart';
import 'weather_service.dart';

/// Bright Sky (`api.brightsky.dev`): DWD data for Germany, no key.
final class BrightSkyWeather implements WeatherService {
  /// Creates the adapter.
  BrightSkyWeather({required this.client, Uri? endpoint})
    : endpoint = endpoint ?? Uri.parse('https://api.brightsky.dev/weather');

  /// HTTP client.
  final http.Client client;

  /// Weather endpoint.
  final Uri endpoint;

  @override
  String get id => 'bright_sky';

  @override
  String get displayName => 'Bright Sky (DWD)';

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<WeatherReport> forecast(WeatherRequest request) async {
    final today = request.today;
    // `last_date` is exclusive in effect: n days ahead gives n full days.
    final last = DateTime.utc(
      today.year,
      today.month,
      today.day + request.fetchDays,
    );
    final json = await getJsonObject(
      client,
      endpoint.replace(
        queryParameters: {
          'lat': request.place.latitude.toStringAsFixed(4),
          'lon': request.place.longitude.toStringAsFixed(4),
          'date': _date(today),
          'last_date': _date(last),
          'tz': request.zone.name,
          'units': 'dwd',
        },
      ),
      service: displayName,
      cancel: request.cancel,
    );
    final hourly = <ForecastHour>[];
    try {
      for (final w in list_(json['weather'])) {
        if (w is! Map<String, Object?>) continue;
        final t = w['timestamp'];
        final temp = num_(w['temperature']);
        if (t is! String || temp == null) continue;
        hourly.add(
          ForecastHour(
            time: parseInstant(t, request.zone),
            temperatureC: temp,
            condition: brightSkyCondition(
              (w['icon'] ?? w['condition']) as String?,
            ),
            precipMm: num_(w['precipitation']),
            precipProbability: num_(w['precipitation_probability'])?.round(),
            windKmh: num_(w['wind_speed']),
            gustKmh: num_(w['wind_gust_speed']),
            windFromDeg: num_(w['wind_direction']),
          ),
        );
      }
    } on FormatException {
      throw badAnswer(displayName);
    } on TypeError {
      throw badAnswer(displayName);
    }
    if (hourly.isEmpty) throw badAnswer(displayName);
    return WeatherReport(
      place: request.place,
      source: displayName,
      current: currentFromHours(hourly, request.now),
      hourly: hourly,
      daily: aggregateDays(hourly),
    );
  }
}
