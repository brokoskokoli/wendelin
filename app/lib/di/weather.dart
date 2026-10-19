import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'app_settings.dart';
import 'providers.dart';
import 'weather_config.dart';

/// App version for the `User-Agent` of MET Norway (checked against
/// `pubspec.yaml` by a test).
const wendelinAppVersion = '0.1.0';

/// Chosen weather service and home place.
final weatherConfigProvider =
    NotifierProvider<WeatherConfigNotifier, WeatherConfig>(
      WeatherConfigNotifier.new,
    );

/// Weather setting.
final class WeatherConfigNotifier extends Notifier<WeatherConfig> {
  @override
  WeatherConfig build() => ref.watch(startupProvider).weather;

  /// Stores [config].
  Future<void> set(WeatherConfig config) async {
    state = config;
    await ref.read(storageProvider).settings.set(AppSettings.weather, config);
  }
}

/// Place search for the home place (settings) and place names in questions.
final weatherGeocoderProvider = Provider<Geocoder>(
  (ref) => OpenMeteoGeocoder(client: ref.watch(httpClientProvider)),
);

/// The current location for the weather: the device position while the
/// `location` integration is on (WP86); the port itself answers `null`
/// without the permission or a fix, and the weather then uses the home
/// place. `null` while the integration is off.
final weatherLocationPortProvider = Provider<WeatherLocationPort?>((ref) {
  if (!ref.watch(enabledIntegrationsProvider).contains('location')) return null;
  final port = ref.watch(platformPortsProvider).location;
  return port == null ? null : LocationWeatherPort(port);
});
