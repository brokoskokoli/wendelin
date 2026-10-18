import 'package:wendelin_core/wendelin_core.dart';

import 'weather_model.dart';

/// A weather service without key (Open-Meteo, Bright Sky, MET Norway).
/// Must pass `weatherServiceContract`.
abstract interface class WeatherService {
  /// Stable id, e.g. `open_meteo`.
  String get id;

  /// Name for the UI and the answer.
  String get displayName;

  /// Forecast for [request].
  ///
  /// Throws `PortException(unavailable)` for unreachable or limited services,
  /// `PortException(failed)` for unreadable answers and [CancelledException]
  /// when `request.cancel` fires first.
  Future<WeatherReport> forecast(WeatherRequest request);
}

/// A service for sea state (only Open-Meteo Marine offers it without key).
abstract interface class MarineService {
  /// Name for the answer.
  String get displayName;

  /// Marine forecast for [request] (`days` counts, `hours` is ignored).
  Future<MarineReport> marine(WeatherRequest request);
}

/// Turns a place name into coordinates.
abstract interface class Geocoder {
  /// The best match for [name] or `null`. [language] (e.g. `de`) selects the
  /// language of the place name.
  Future<Place?> find(String name, {String? language, CancelToken? cancel});
}

/// Where the user is right now (optional; the location integration of WP86
/// provides it). Returns `null` if the position is unknown or not allowed.
abstract interface class WeatherLocationPort {
  /// The current place, named if possible.
  Future<Place?> currentPlace({CancelToken? cancel});
}
