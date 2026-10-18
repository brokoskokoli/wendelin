import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'app_settings.dart';
import 'core_providers.dart';
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

/// The current location for the weather. `null` until the location
/// integration (WP86) overrides this provider; the weather then uses the
/// home place.
final weatherLocationPortProvider = Provider<WeatherLocationPort?>(
  (ref) => null,
);
