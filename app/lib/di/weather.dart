import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'app_settings.dart';
import 'preferences.dart';
import 'providers.dart';
import 'weather_config.dart';

/// App version for the `User-Agent` of MET Norway (checked against
/// `pubspec.yaml` by a test).
const wendelinAppVersion = '0.1.2';

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
///
/// The place name ends up in the answer text and so at the provider, like
/// the `location` tools: the position is only used for a target that meets
/// the sensitive minimum (default `tee` if none is set), or if the user
/// marked `location` as not sensitive. Any other target gets `null`.
final weatherLocationPortProvider = Provider<WeatherLocationPort?>((ref) {
  if (!ref.watch(enabledIntegrationsProvider).contains('location')) return null;
  final port = ref.watch(platformPortsProvider).location;
  if (port == null) return null;
  return _GatedWeatherLocation(LocationWeatherPort(port), () {
    final prefs = ref.read(toolPrefsProvider);
    return (
      minimum: prefs.sensitiveMinimum ?? PrivacyLevel.tee,
      notSensitive: prefs.sensitive['location'] == false,
    );
  });
});

/// Hands the device position only to targets that may see it.
final class _GatedWeatherLocation implements WeatherLocationPort {
  const _GatedWeatherLocation(this._inner, this._rules);

  final WeatherLocationPort _inner;
  final ({PrivacyLevel minimum, bool notSensitive}) Function() _rules;

  @override
  Future<Place?> currentPlace({
    CancelToken? cancel,
    PrivacyLevel? level,
  }) async {
    final rules = _rules();
    final allowed =
        rules.notSensitive || (level != null && level.isAtLeast(rules.minimum));
    return allowed ? _inner.currentPlace(cancel: cancel, level: level) : null;
  }
}
