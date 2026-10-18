import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'weather_conditions.dart';
import 'weather_json.dart';
import 'weather_model.dart';
import 'weather_service.dart';

String _coord(double v) => v.toStringAsFixed(4);

/// Open-Meteo forecast (`api.open-meteo.com`, no key).
final class OpenMeteoWeather implements WeatherService {
  /// Creates the adapter.
  OpenMeteoWeather({required this.client, Uri? endpoint})
    : endpoint =
          endpoint ?? Uri.parse('https://api.open-meteo.com/v1/forecast');

  /// HTTP client.
  final http.Client client;

  /// Forecast endpoint.
  final Uri endpoint;

  @override
  String get id => 'open_meteo';

  @override
  String get displayName => 'Open-Meteo';

  @override
  Future<WeatherReport> forecast(WeatherRequest request) async {
    final json = await getJsonObject(
      client,
      endpoint.replace(
        queryParameters: {
          'latitude': _coord(request.place.latitude),
          'longitude': _coord(request.place.longitude),
          'current':
              'temperature_2m,apparent_temperature,precipitation,weather_code,'
              'wind_speed_10m,wind_gusts_10m,wind_direction_10m',
          'hourly':
              'temperature_2m,precipitation_probability,precipitation,'
              'weather_code,wind_speed_10m,wind_gusts_10m',
          'daily':
              'weather_code,temperature_2m_max,temperature_2m_min,'
              'precipitation_sum,precipitation_probability_max,'
              'wind_speed_10m_max,wind_gusts_10m_max',
          'timezone': request.zone.name,
          'forecast_days': '${request.fetchDays}',
          'wind_speed_unit': 'kmh',
        },
      ),
      service: displayName,
      cancel: request.cancel,
    );
    try {
      return _parse(json, request);
    } on FormatException {
      throw badAnswer(displayName);
    }
  }

  WeatherReport _parse(Map<String, Object?> json, WeatherRequest r) {
    final cur = json['current'];
    CurrentWeather? current;
    if (cur is Map<String, Object?> && num_(cur['temperature_2m']) != null) {
      current = CurrentWeather(
        temperatureC: num_(cur['temperature_2m'])!,
        apparentC: num_(cur['apparent_temperature']),
        condition: wmoCondition(num_(cur['weather_code'])?.round()),
        windKmh: num_(cur['wind_speed_10m']),
        gustKmh: num_(cur['wind_gusts_10m']),
        windFromDeg: num_(cur['wind_direction_10m']),
        precipMm: num_(cur['precipitation']),
      );
    }
    final h = json['hourly'];
    final d = json['daily'];
    if (h is! Map<String, Object?> || d is! Map<String, Object?>) {
      throw const FormatException('hourly/daily');
    }
    final hourly = <ForecastHour>[];
    for (final (i, t) in list_(h['time']).indexed) {
      final temp = numAt(h['temperature_2m'], i);
      if (t is! String || temp == null) continue;
      hourly.add(
        ForecastHour(
          time: parseLocal(t, r.zone),
          temperatureC: temp,
          condition: wmoCondition(numAt(h['weather_code'], i)?.round()),
          precipMm: numAt(h['precipitation'], i),
          precipProbability: numAt(h['precipitation_probability'], i)?.round(),
          windKmh: numAt(h['wind_speed_10m'], i),
          gustKmh: numAt(h['wind_gusts_10m'], i),
        ),
      );
    }
    final daily = <ForecastDay>[];
    for (final (i, t) in list_(d['time']).indexed) {
      final lo = numAt(d['temperature_2m_min'], i);
      final hi = numAt(d['temperature_2m_max'], i);
      if (t is! String || lo == null || hi == null) continue;
      daily.add(
        ForecastDay(
          date: dateOf(parseLocal(t, r.zone)),
          minC: lo,
          maxC: hi,
          condition: wmoCondition(numAt(d['weather_code'], i)?.round()),
          precipMm: numAt(d['precipitation_sum'], i),
          precipProbability: numAt(
            d['precipitation_probability_max'],
            i,
          )?.round(),
          windMaxKmh: numAt(d['wind_speed_10m_max'], i),
          gustMaxKmh: numAt(d['wind_gusts_10m_max'], i),
        ),
      );
    }
    if (daily.isEmpty) throw const FormatException('daily');
    return WeatherReport(
      place: r.place,
      source: displayName,
      current: current,
      hourly: hourly,
      daily: daily,
    );
  }
}

/// Open-Meteo Marine (`marine-api.open-meteo.com`): waves, swell, sea
/// temperature. Only available for sea locations.
final class OpenMeteoMarine implements MarineService {
  /// Creates the adapter.
  OpenMeteoMarine({required this.client, Uri? endpoint})
    : endpoint =
          endpoint ?? Uri.parse('https://marine-api.open-meteo.com/v1/marine');

  /// HTTP client.
  final http.Client client;

  /// Marine endpoint.
  final Uri endpoint;

  @override
  String get displayName => 'Open-Meteo Marine';

  @override
  Future<MarineReport> marine(WeatherRequest request) async {
    final json = await getJsonObject(
      client,
      endpoint.replace(
        queryParameters: {
          'latitude': _coord(request.place.latitude),
          'longitude': _coord(request.place.longitude),
          'current':
              'wave_height,wave_direction,wave_period,swell_wave_height,'
              'swell_wave_period,swell_wave_direction,sea_surface_temperature',
          'daily': 'wave_height_max,swell_wave_height_max,wave_period_max',
          'timezone': request.zone.name,
          'forecast_days': '${request.days}',
        },
      ),
      service: displayName,
      cancel: request.cancel,
    );
    final cur = json['current'];
    final d = json['daily'];
    if (d is! Map<String, Object?>) {
      // Land locations answer 400 with a reason; an empty body is no sea.
      throw badAnswer(displayName);
    }
    MarineCurrent? current;
    if (cur is Map<String, Object?> && num_(cur['wave_height']) != null) {
      current = MarineCurrent(
        waveHeightM: num_(cur['wave_height']),
        wavePeriodS: num_(cur['wave_period']),
        waveFromDeg: num_(cur['wave_direction']),
        swellHeightM: num_(cur['swell_wave_height']),
        swellPeriodS: num_(cur['swell_wave_period']),
        swellFromDeg: num_(cur['swell_wave_direction']),
        seaTemperatureC: num_(cur['sea_surface_temperature']),
      );
    }
    final days = <MarineDay>[];
    try {
      for (final (i, t) in list_(d['time']).indexed) {
        if (t is! String) continue;
        days.add(
          MarineDay(
            date: dateOf(parseLocal(t, request.zone)),
            waveMaxM: numAt(d['wave_height_max'], i),
            swellMaxM: numAt(d['swell_wave_height_max'], i),
            periodMaxS: numAt(d['wave_period_max'], i),
          ),
        );
      }
    } on FormatException {
      throw badAnswer(displayName);
    }
    if (current == null && days.every((e) => e.waveMaxM == null)) {
      throw const PortException(
        PortErrorKind.notFound,
        'Open-Meteo Marine: für diesen Ort gibt es keine Meeresdaten '
        '(kein Meer in der Nähe)',
      );
    }
    return MarineReport(
      place: request.place,
      source: displayName,
      current: current,
      daily: days,
    );
  }
}

/// Open-Meteo geocoding (`geocoding-api.open-meteo.com`).
final class OpenMeteoGeocoder implements Geocoder {
  /// Creates the geocoder.
  OpenMeteoGeocoder({required this.client, Uri? endpoint})
    : endpoint =
          endpoint ??
          Uri.parse('https://geocoding-api.open-meteo.com/v1/search');

  /// HTTP client.
  final http.Client client;

  /// Search endpoint.
  final Uri endpoint;

  @override
  Future<Place?> find(
    String name, {
    String? language,
    CancelToken? cancel,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'darf nicht leer sein');
    }
    final json = await getJsonObject(
      client,
      endpoint.replace(
        queryParameters: {
          'name': name.trim(),
          'count': '1',
          'language': ?language,
          'format': 'json',
        },
      ),
      service: 'Open-Meteo Ortssuche',
      cancel: cancel,
    );
    for (final r in list_(json['results'])) {
      if (r is! Map<String, Object?>) continue;
      final n = r['name'];
      final lat = num_(r['latitude']);
      final lon = num_(r['longitude']);
      if (n is! String || lat == null || lon == null) continue;
      final zone = r['timezone'];
      return Place(
        name: n,
        latitude: lat,
        longitude: lon,
        timeZone: zone is String ? zone : null,
      );
    }
    return null;
  }
}
