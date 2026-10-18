import 'dart:math' as math;

import 'weather_json.dart';
import 'weather_model.dart';

/// Builds days from [samples] (ascending): min/max temperature, precipitation
/// sum, highest chance and wind, and the condition at the sample nearest to
/// noon. Used by services that only deliver hourly data.
List<ForecastDay> aggregateDays(List<ForecastHour> samples) {
  final byDay = <DateTime, List<ForecastHour>>{};
  for (final s in samples) {
    byDay.putIfAbsent(dateOf(s.time), () => []).add(s);
  }
  double? maxOf(Iterable<double?> v) {
    final present = v.whereType<double>();
    return present.isEmpty ? null : present.reduce(math.max);
  }

  return [
    for (final MapEntry(key: date, value: hours) in byDay.entries)
      () {
        final noon = hours.reduce(
          (a, b) =>
              (a.time.hour - 12).abs() <= (b.time.hour - 12).abs() ? a : b,
        );
        final rain = hours.map((h) => h.precipMm).whereType<double>();
        final prob = hours.map((h) => h.precipProbability).whereType<int>();
        return ForecastDay(
          date: date,
          minC: hours.map((h) => h.temperatureC).reduce(math.min),
          maxC: hours.map((h) => h.temperatureC).reduce(math.max),
          condition: noon.condition,
          precipMm: rain.isEmpty ? null : rain.reduce((a, b) => a + b),
          precipProbability: prob.isEmpty ? null : prob.reduce(math.max),
          windMaxKmh: maxOf(hours.map((h) => h.windKmh)),
          gustMaxKmh: maxOf(hours.map((h) => h.gustKmh)),
        );
      }(),
  ];
}
