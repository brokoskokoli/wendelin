import 'package:http/http.dart' as http;

import 'weather_aggregate.dart';
import 'weather_conditions.dart';
import 'weather_json.dart';
import 'weather_model.dart';
import 'weather_service.dart';

/// MET Norway Locationforecast (`api.met.no`, yr.no data, no key). The terms
/// of use demand an identifying `User-Agent` ([userAgent]).
final class MetNorwayWeather implements WeatherService {
  /// Creates the adapter; [userAgent] is app name and repo URL, see
  /// [weatherUserAgent].
  MetNorwayWeather({
    required this.client,
    required this.userAgent,
    Uri? endpoint,
  }) : endpoint =
           endpoint ??
           Uri.parse(
             'https://api.met.no/weatherapi/locationforecast/2.0/compact',
           );

  /// HTTP client.
  final http.Client client;

  /// Sent as `User-Agent`.
  final String userAgent;

  /// Forecast endpoint.
  final Uri endpoint;

  @override
  String get id => 'met_norway';

  @override
  String get displayName => 'MET Norway (yr.no)';

  @override
  Future<WeatherReport> forecast(WeatherRequest request) async {
    final json = await getJsonObject(
      client,
      endpoint.replace(
        queryParameters: {
          'lat': request.place.latitude.toStringAsFixed(4),
          'lon': request.place.longitude.toStringAsFixed(4),
        },
      ),
      service: displayName,
      statusMessages: const {
        403: 'Anfrage abgelehnt (Kennung der App nicht akzeptiert)',
      },
      headers: {'User-Agent': userAgent},
      cancel: request.cancel,
    );
    final props = json['properties'];
    final series = props is Map<String, Object?>
        ? list_(props['timeseries'])
        : const <Object?>[];
    final all = <ForecastHour>[];
    try {
      for (final e in series) {
        if (e is! Map<String, Object?>) continue;
        final t = e['time'];
        final data = e['data'];
        if (t is! String || data is! Map<String, Object?>) continue;
        final inst = (data['instant'] as Map<String, Object?>?)?['details'];
        if (inst is! Map<String, Object?>) continue;
        final temp = num_(inst['air_temperature']);
        if (temp == null) continue;
        final one = data['next_1_hours'] as Map<String, Object?>?;
        final span = one ?? data['next_6_hours'] as Map<String, Object?>?;
        final summary = span?['summary'] as Map<String, Object?>?;
        final details = span?['details'] as Map<String, Object?>?;
        final wind = num_(inst['wind_speed']);
        final windKmh = wind == null ? null : wind * 3.6;
        final condition = metSymbolCondition(
          summary?['symbol_code'] as String?,
        );
        final precip = num_(details?['precipitation_amount']);
        final time = parseInstant(t, request.zone);
        all.add(
          ForecastHour(
            time: time,
            temperatureC: temp,
            condition: condition,
            precipMm: precip,
            windKmh: windKmh,
            windFromDeg: num_(inst['wind_from_direction']),
            hoursCovered: one == null ? 6 : 1,
          ),
        );
      }
    } on TypeError {
      throw badAnswer(displayName);
    }
    final hourly = [
      for (final h in all)
        if (h.hoursCovered == 1) h,
    ];
    if (hourly.isEmpty) throw badAnswer(displayName);
    return WeatherReport(
      place: request.place,
      source: displayName,
      current: currentFromHours(hourly, request.now),
      hourly: hourly,
      daily: aggregateDays(all, partialDay: dateOf(request.today)),
    );
  }
}
