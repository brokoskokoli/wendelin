import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/weather_config.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _kiel = Place(
  name: 'Kiel',
  latitude: 54.32,
  longitude: 10.14,
  timeZone: 'Europe/Berlin',
);

void main() {
  test('useGps ist standardmäßig aus', () {
    expect(const WeatherConfig().useGps, isFalse);
  });

  test('ältere Einstellungen ohne useGps lesen als aus', () {
    final config = WeatherConfig.fromJson(const {
      'kind': 'brightSky',
      'home': {'name': 'Kiel', 'lat': 54.32, 'lon': 10.14},
    });
    expect(config.useGps, isFalse);
    expect(config.kind, WeatherServiceKind.brightSky);
    expect(config.home?.name, 'Kiel');
  });

  test('Round-Trip über toJson/fromJson erhält useGps', () {
    for (final config in const [
      WeatherConfig(useGps: true),
      WeatherConfig(kind: WeatherServiceKind.metNorway, home: _kiel),
      WeatherConfig(home: _kiel, useGps: true),
    ]) {
      expect(WeatherConfig.fromJson(config.toJson()), config);
    }
    expect(const WeatherConfig(useGps: true).toJson()['useGps'], isTrue);
  });

  test('useGps kein bool: FormatException', () {
    expect(
      () => WeatherConfig.fromJson(const {'useGps': 'ja'}),
      throwsFormatException,
    );
  });

  test('copyWith, == und hashCode beachten useGps', () {
    const off = WeatherConfig(home: _kiel);
    final on = off.copyWith(useGps: true);
    expect(on.useGps, isTrue);
    expect(on.home, _kiel);
    expect(on, isNot(off));
    expect(on.copyWith(clearHome: true).useGps, isTrue);
    expect(on.copyWith(useGps: false), off);
    expect(on.copyWith(useGps: false).hashCode, off.hashCode);
    expect(
      on.hashCode,
      const WeatherConfig(home: _kiel, useGps: true).hashCode,
    );
  });
}
