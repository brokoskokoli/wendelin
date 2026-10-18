import 'package:flutter/foundation.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Weather services the user can choose (all without key).
enum WeatherServiceKind {
  /// Open-Meteo (default, worldwide).
  openMeteo('Open-Meteo', 'Standard, weltweit'),

  /// Bright Sky, data of the Deutscher Wetterdienst.
  brightSky('Bright Sky (DWD)', 'Daten des Deutschen Wetterdienstes'),

  /// MET Norway (yr.no).
  metNorway('MET Norway (yr.no)', 'Norwegischer Wetterdienst, weltweit');

  const WeatherServiceKind(this.label, this.detail);

  /// Display name.
  final String label;

  /// One line for the settings list.
  final String detail;
}

/// Choice of weather service and the home place (no secrets).
@immutable
final class WeatherConfig {
  /// Creates a configuration.
  const WeatherConfig({this.kind = WeatherServiceKind.openMeteo, this.home});

  /// Decodes [toJson]; throws [FormatException].
  factory WeatherConfig.fromJson(Map<String, Object?> json) {
    final kind = WeatherServiceKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final home = json['home'];
    if (home != null && home is! Map<String, Object?>) {
      throw const FormatException('weather: home ist kein Objekt');
    }
    return WeatherConfig(
      kind: kind ?? WeatherServiceKind.openMeteo,
      home: home == null ? null : Place.fromJson(home as Map<String, Object?>),
    );
  }

  /// The chosen service.
  final WeatherServiceKind kind;

  /// Place used when the question names none and no location is known.
  final Place? home;

  /// A copy with another [kind] or [home] ([clearHome] removes it).
  WeatherConfig copyWith({
    WeatherServiceKind? kind,
    Place? home,
    bool clearHome = false,
  }) => WeatherConfig(
    kind: kind ?? this.kind,
    home: clearHome ? null : home ?? this.home,
  );

  /// JSON for the settings.
  Map<String, Object?> toJson() => {'kind': kind.name, 'home': ?home?.toJson()};

  @override
  bool operator ==(Object other) =>
      other is WeatherConfig && other.kind == kind && other.home == home;

  @override
  int get hashCode => Object.hash(kind, home);
}
