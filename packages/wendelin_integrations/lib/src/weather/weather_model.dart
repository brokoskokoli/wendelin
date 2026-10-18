import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wendelin_core/wendelin_core.dart';

/// A place on earth, resolved to coordinates.
@immutable
final class Place {
  /// Creates a place.
  const Place({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.timeZone,
  });

  /// Decodes [toJson]; throws [FormatException].
  factory Place.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final lat = json['lat'];
    final lon = json['lon'];
    final zone = json['tz'];
    if (name is! String || lat is! num || lon is! num) {
      throw const FormatException('Ort: name, lat und lon erwartet');
    }
    if (zone != null && zone is! String) {
      throw const FormatException('Ort: tz ist kein Text');
    }
    return Place(
      name: name,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      timeZone: zone as String?,
    );
  }

  /// Display name, e.g. `Hamburg`.
  final String name;

  /// Latitude in degrees.
  final double latitude;

  /// Longitude in degrees.
  final double longitude;

  /// IANA time zone of the place, if known.
  final String? timeZone;

  /// JSON for the settings.
  Map<String, Object?> toJson() => {
    'name': name,
    'lat': latitude,
    'lon': longitude,
    'tz': ?timeZone,
  };

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.name == name &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timeZone == timeZone;

  @override
  int get hashCode => Object.hash(name, latitude, longitude, timeZone);

  @override
  String toString() => 'Place($name, $latitude, $longitude)';
}

/// Conditions right now.
@immutable
final class CurrentWeather {
  /// Creates the value.
  const CurrentWeather({
    required this.temperatureC,
    required this.condition,
    this.apparentC,
    this.windKmh,
    this.gustKmh,
    this.windFromDeg,
    this.precipMm,
  });

  /// Air temperature in °C.
  final double temperatureC;

  /// Felt temperature in °C.
  final double? apparentC;

  /// German weather description, e.g. `leichter Regen`.
  final String condition;

  /// Wind speed in km/h.
  final double? windKmh;

  /// Gusts in km/h.
  final double? gustKmh;

  /// Direction the wind comes from, in degrees.
  final double? windFromDeg;

  /// Precipitation in the last hour in mm.
  final double? precipMm;
}

/// One forecast hour (or a longer step, see [hoursCovered]).
@immutable
final class ForecastHour {
  /// Creates the value.
  const ForecastHour({
    required this.time,
    required this.temperatureC,
    required this.condition,
    this.precipMm,
    this.precipProbability,
    this.windKmh,
    this.gustKmh,
    this.windFromDeg,
    this.hoursCovered = 1,
  });

  /// Start of the hour in the place's zone.
  final tz.TZDateTime time;

  /// Air temperature in °C.
  final double temperatureC;

  /// German weather description.
  final String condition;

  /// Precipitation in mm over [hoursCovered].
  final double? precipMm;

  /// Chance of precipitation in percent.
  final int? precipProbability;

  /// Wind speed in km/h.
  final double? windKmh;

  /// Gusts in km/h.
  final double? gustKmh;

  /// Direction the wind comes from, in degrees.
  final double? windFromDeg;

  /// How many hours [precipMm] covers (MET Norway steps by 6 hours later).
  final int hoursCovered;
}

/// Current conditions taken from the forecast hour that contains [now]
/// (services without a "current" part).
CurrentWeather currentFromHours(List<ForecastHour> hours, DateTime now) {
  final h = hours.lastWhere(
    (e) => !e.time.isAfter(now),
    orElse: () => hours.first,
  );
  return CurrentWeather(
    temperatureC: h.temperatureC,
    condition: h.condition,
    windKmh: h.windKmh,
    gustKmh: h.gustKmh,
    windFromDeg: h.windFromDeg,
    precipMm: h.precipMm,
  );
}

/// One forecast day.
@immutable
final class ForecastDay {
  /// Creates the value.
  const ForecastDay({
    required this.date,
    required this.minC,
    required this.maxC,
    required this.condition,
    this.precipMm,
    this.precipProbability,
    this.windMaxKmh,
    this.gustMaxKmh,
  });

  /// The calendar day.
  final DateTime date;

  /// Lowest temperature in °C.
  final double minC;

  /// Highest temperature in °C.
  final double maxC;

  /// German weather description of the day.
  final String condition;

  /// Precipitation sum in mm.
  final double? precipMm;

  /// Highest chance of precipitation in percent.
  final int? precipProbability;

  /// Highest wind speed in km/h.
  final double? windMaxKmh;

  /// Highest gusts in km/h.
  final double? gustMaxKmh;
}

/// What a forecast request asks for.
@immutable
final class WeatherRequest {
  /// Creates a request.
  const WeatherRequest({
    required this.place,
    required this.zone,
    required this.now,
    this.days = 2,
    this.hours = 0,
    this.cancel,
  });

  /// Where.
  final Place place;

  /// Time zone for all times in the answer.
  final tz.Location zone;

  /// The current instant (from the tool context's clock).
  final DateTime now;

  /// Days to cover (1–7), counted from today.
  final int days;

  /// Hours from now on to cover (0–24).
  final int hours;

  /// Cancels the request.
  final CancelToken? cancel;

  /// Local calendar day of [now].
  tz.TZDateTime get today {
    final l = tz.TZDateTime.from(now, zone);
    return tz.TZDateTime(zone, l.year, l.month, l.day);
  }

  /// Days the service has to fetch so that both [days] and [hours] fit.
  int get fetchDays => days > (hours > 0 ? 2 : 1) ? days : (hours > 0 ? 2 : 1);
}

/// A forecast of one service.
@immutable
final class WeatherReport {
  /// Creates a report.
  const WeatherReport({
    required this.place,
    required this.source,
    required this.hourly,
    required this.daily,
    this.current,
  });

  /// Place of the request.
  final Place place;

  /// Name of the service.
  final String source;

  /// Conditions now, if the service has them.
  final CurrentWeather? current;

  /// Hourly steps (ascending), possibly including hours already past.
  final List<ForecastHour> hourly;

  /// Days (ascending, starting today).
  final List<ForecastDay> daily;
}

/// Sea state right now.
@immutable
final class MarineCurrent {
  /// Creates the value.
  const MarineCurrent({
    this.waveHeightM,
    this.wavePeriodS,
    this.waveFromDeg,
    this.swellHeightM,
    this.swellPeriodS,
    this.swellFromDeg,
    this.seaTemperatureC,
  });

  /// Significant wave height in m.
  final double? waveHeightM;

  /// Wave period in s.
  final double? wavePeriodS;

  /// Direction the waves come from, in degrees.
  final double? waveFromDeg;

  /// Swell height in m.
  final double? swellHeightM;

  /// Swell period in s.
  final double? swellPeriodS;

  /// Direction the swell comes from, in degrees.
  final double? swellFromDeg;

  /// Sea surface temperature in °C.
  final double? seaTemperatureC;
}

/// Highest sea state of one day.
@immutable
final class MarineDay {
  /// Creates the value.
  const MarineDay({
    required this.date,
    this.waveMaxM,
    this.swellMaxM,
    this.periodMaxS,
  });

  /// The calendar day.
  final DateTime date;

  /// Highest wave height in m.
  final double? waveMaxM;

  /// Highest swell height in m.
  final double? swellMaxM;

  /// Longest wave period in s.
  final double? periodMaxS;
}

/// A marine forecast.
@immutable
final class MarineReport {
  /// Creates a report.
  const MarineReport({
    required this.place,
    required this.source,
    required this.daily,
    this.current,
  });

  /// Place of the request.
  final Place place;

  /// Name of the service.
  final String source;

  /// Sea state now.
  final MarineCurrent? current;

  /// Days (ascending, starting today).
  final List<MarineDay> daily;
}
