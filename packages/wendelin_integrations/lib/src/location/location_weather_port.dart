import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import '../weather/weather_model.dart';
import '../weather/weather_service.dart';
import 'location_port.dart';

/// Feeds the weather with the device position: a [WeatherLocationPort] over
/// a [LocationPort]. Answers `null` (weather falls back to the home place)
/// without permission, without a fix, after [timeout] or when cancelled,
/// never an error. The coordinates are rounded to two decimals (about one
/// kilometre): the weather needs no more, and the weather service learns no
/// more.
///
/// Whether the position may be used for a target of a given privacy level is
/// decided by the caller (wiring), not here.
final class LocationWeatherPort implements WeatherLocationPort {
  /// Creates the adapter.
  const LocationWeatherPort(this.port, {this.timeout = defaultTimeout});

  /// Upper bound for the whole lookup.
  static const defaultTimeout = Duration(seconds: 8);

  /// The device position.
  final LocationPort port;

  /// How long to wait for a fix before the home place is used.
  final Duration timeout;

  @override
  Future<Place?> currentPlace({
    CancelToken? cancel,
    PrivacyLevel? level,
  }) async {
    if (cancel?.isCancelled ?? false) return null;
    final lookup = _lookup();
    // A lookup that loses against cancel or timeout may still fail later.
    unawaited(lookup.then<void>((_) {}, onError: (Object _) {}));
    final result = await Future.any<Place?>([
      lookup,
      Future<Place?>.delayed(timeout),
      if (cancel != null) cancel.whenCancelled.then<Place?>((_) => null),
    ]);
    return result;
  }

  Future<Place?> _lookup() async {
    try {
      if (!await port.hasPermission()) return null;
      final fix = await port.current();
      final name = fix.placeName?.trim();
      return Place(
        name: name == null || name.isEmpty ? 'Aktueller Standort' : name,
        latitude: _round(fix.latitude),
        longitude: _round(fix.longitude),
      );
    } on PortException {
      return null;
    }
  }

  static double _round(double v) => (v * 100).round() / 100;
}
