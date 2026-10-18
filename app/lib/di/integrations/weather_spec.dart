import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../weather.dart';
import '../weather_config.dart';
import 'integration_spec.dart';

/// What the weather spec prepares: everything that comes from settings.
typedef WeatherParts = ({
  WeatherServiceKind kind,
  Place? home,
  WeatherLocationPort? location,
  Geocoder geocoder,
});

/// Weather and sea state: service and home place from the settings.
final weatherSpec = IntegrationSpec(
  id: 'weather',
  prepare: (ref) {
    final config = ref.watch(weatherConfigProvider);
    return (
      kind: config.kind,
      home: config.home,
      location: ref.watch(weatherLocationPortProvider),
      geocoder: ref.watch(weatherGeocoderProvider),
    );
  },
  create: (d) {
    final parts = d.extra<WeatherParts>('weather');
    final kind = parts?.kind ?? WeatherServiceKind.openMeteo;
    final client = d.httpClient;
    return WeatherIntegration(
      service: switch (kind) {
        WeatherServiceKind.openMeteo => OpenMeteoWeather(client: client),
        WeatherServiceKind.brightSky => BrightSkyWeather(client: client),
        WeatherServiceKind.metNorway => MetNorwayWeather(
          client: client,
          userAgent: weatherUserAgent(wendelinAppVersion),
        ),
      },
      marine: OpenMeteoMarine(client: client),
      geocoder: parts?.geocoder ?? OpenMeteoGeocoder(client: client),
      home: parts?.home,
      location: parts?.location,
    );
  },
);
