import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import '../weather/weather_model.dart';
import '../weather/weather_service.dart';
import 'location_port.dart';

/// Feeds the weather with the device position: a [WeatherLocationPort] over
/// a [LocationPort]. Answers `null` (weather falls back to the home place)
/// without permission or without a fix, never an error.
final class LocationWeatherPort implements WeatherLocationPort {
  /// Creates the adapter.
  const LocationWeatherPort(this.port);

  /// The device position.
  final LocationPort port;

  @override
  Future<Place?> currentPlace({CancelToken? cancel}) async {
    try {
      if (!await port.hasPermission()) return null;
      final fix = await port.current();
      final name = fix.placeName?.trim();
      return Place(
        name: name == null || name.isEmpty ? 'Aktueller Standort' : name,
        latitude: fix.latitude,
        longitude: fix.longitude,
      );
    } on PortException {
      return null;
    }
  }
}
