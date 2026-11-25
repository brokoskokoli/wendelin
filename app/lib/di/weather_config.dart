import 'package:flutter/foundation.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../l10n/gen/app_localizations.dart';

/// Weather services the user can choose (all without key).
enum WeatherServiceKind {
  /// Open-Meteo (default, worldwide).
  openMeteo('Open-Meteo'),

  /// Bright Sky, data of the Deutscher Wetterdienst.
  brightSky('Bright Sky (DWD)'),

  /// MET Norway (yr.no).
  metNorway('MET Norway (yr.no)');

  const WeatherServiceKind(this.label);

  /// Display name.
  final String label;

  /// One line for the settings list.
  String detailOf(AppLocalizations l) => switch (this) {
    openMeteo => l.weatherKindOpenMeteoDetail,
    brightSky => l.weatherKindBrightSkyDetail,
    metNorway => l.weatherKindMetNorwayDetail,
  };
}

/// Choice of weather service, home place and whether the device position
/// is used (no secrets).
@immutable
final class WeatherConfig {
  /// Creates a configuration.
  const WeatherConfig({
    this.kind = WeatherServiceKind.openMeteo,
    this.home,
    this.useGps = false,
  });

  /// Decodes [toJson]; throws [FormatException].
  factory WeatherConfig.fromJson(Map<String, Object?> json) {
    final kind = WeatherServiceKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final home = json['home'];
    if (home != null && home is! Map<String, Object?>) {
      throw const FormatException('weather: home ist kein Objekt');
    }
    final useGps = json['useGps'];
    if (useGps != null && useGps is! bool) {
      throw const FormatException('weather: useGps must be a bool');
    }
    return WeatherConfig(
      kind: kind ?? WeatherServiceKind.openMeteo,
      home: home == null ? null : Place.fromJson(home as Map<String, Object?>),
      useGps: useGps as bool? ?? false,
    );
  }

  /// The chosen service.
  final WeatherServiceKind kind;

  /// Place used when the question names none and no location is known.
  final Place? home;

  /// Whether a question without a place uses the device position (before
  /// the home place). Independent of the `location` integration.
  final bool useGps;

  /// A copy with another [kind], [home] ([clearHome] removes it) or
  /// [useGps].
  WeatherConfig copyWith({
    WeatherServiceKind? kind,
    Place? home,
    bool clearHome = false,
    bool? useGps,
  }) => WeatherConfig(
    kind: kind ?? this.kind,
    home: clearHome ? null : home ?? this.home,
    useGps: useGps ?? this.useGps,
  );

  /// JSON for the settings.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'home': ?home?.toJson(),
    'useGps': useGps,
  };

  @override
  bool operator ==(Object other) =>
      other is WeatherConfig &&
      other.kind == kind &&
      other.home == home &&
      other.useGps == useGps;

  @override
  int get hashCode => Object.hash(kind, home, useGps);
}
