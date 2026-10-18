import 'package:wendelin_core/wendelin_core.dart';

import '../src/weather/weather_model.dart';
import '../src/weather/weather_service.dart';

/// Scripted [WeatherService]: answers [report] (or throws [error]) and
/// records the requests.
final class FakeWeatherService implements WeatherService {
  /// Creates the fake.
  FakeWeatherService({this.report, this.error});

  /// Answer for every request.
  WeatherReport? report;

  /// If set, every request throws it.
  Object? error;

  /// Requests received, in order.
  final List<WeatherRequest> requests = [];

  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake-Wetter';

  @override
  Future<WeatherReport> forecast(WeatherRequest request) async {
    requests.add(request);
    if (error != null) throw error!;
    return report!;
  }
}

/// Scripted [MarineService].
final class FakeMarineService implements MarineService {
  /// Creates the fake.
  FakeMarineService({this.report, this.error});

  /// Answer for every request.
  MarineReport? report;

  /// If set, every request throws it.
  Object? error;

  /// Requests received, in order.
  final List<WeatherRequest> requests = [];

  @override
  String get displayName => 'Fake-Meer';

  @override
  Future<MarineReport> marine(WeatherRequest request) async {
    requests.add(request);
    if (error != null) throw error!;
    return report!;
  }
}

/// [Geocoder] with a fixed list of places (by lower-case name).
final class FakeGeocoder implements Geocoder {
  /// Creates the fake.
  FakeGeocoder(Iterable<Place> places)
    : _places = {for (final p in places) p.name.toLowerCase(): p};

  final Map<String, Place> _places;

  /// Names asked for, in order.
  final List<String> asked = [];

  @override
  Future<Place?> find(
    String name, {
    String? language,
    CancelToken? cancel,
  }) async {
    asked.add(name);
    return _places[name.trim().toLowerCase()];
  }
}

/// [WeatherLocationPort] that returns [place].
final class FakeWeatherLocationPort implements WeatherLocationPort {
  /// Creates the fake.
  FakeWeatherLocationPort(this.place);

  /// The current place, `null` = unknown.
  Place? place;

  @override
  Future<Place?> currentPlace({CancelToken? cancel}) async => place;
}
