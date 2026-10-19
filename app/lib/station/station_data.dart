import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../di/providers.dart';
import '../di/weather.dart';
import '../di/weather_config.dart';
import 'station_prefs.dart';

/// Weather as the station shows it.
@immutable
final class StationWeather {
  /// Creates the value.
  const StationWeather({
    required this.place,
    required this.temperatureC,
    required this.condition,
  });

  /// Place name.
  final String place;

  /// Temperature in degrees Celsius.
  final double temperatureC;

  /// Condition code of the weather model (`weather_conditions.dart`).
  final String condition;
}

/// One appointment with its title (shown on purpose, K62).
@immutable
final class StationEvent {
  /// Creates the value.
  const StationEvent({
    required this.title,
    required this.start,
    this.allDay = false,
  });

  /// Event title.
  final String title;

  /// Start (local time).
  final DateTime start;

  /// Whole-day event.
  final bool allDay;
}

/// One open task with its title (shown on purpose, K62).
@immutable
final class StationTask {
  /// Creates the value.
  const StationTask({required this.title, this.overdue = false, this.due});

  /// Task title.
  final String title;

  /// Due before today.
  final bool overdue;

  /// Due date, if any.
  final DateTime? due;
}

/// What the idle display reads. Each call fetches only its own area, and the
/// caller asks only for areas the user switched on: a hidden area is never
/// even read (titles are personal data).
abstract interface class StationData {
  /// Current weather at the home place, `null` if unknown.
  Future<StationWeather?> weather(DateTime now);

  /// The next appointments from [now] on, at most [limit].
  Future<List<StationEvent>> events(DateTime now, {int limit = 4});

  /// Tasks due today or overdue, at most [limit].
  Future<List<StationTask>> tasks(DateTime now, {int limit = 4});
}

/// What the display shows right now.
@immutable
final class StationInfo {
  /// Creates the value.
  const StationInfo({
    this.weather,
    this.events = const [],
    this.tasks = const [],
  });

  /// Weather, if the area is on and known.
  final StationWeather? weather;

  /// Next appointments (empty if the area is off).
  final List<StationEvent> events;

  /// Due tasks (empty if the area is off).
  final List<StationTask> tasks;
}

/// Reads [StationInfo] from [data] for the areas [prefs] shows. Errors of one
/// area leave that area empty.
Future<StationInfo> readStationInfo(
  StationData data,
  StationPrefs prefs,
  DateTime now,
) async {
  Future<T> safe<T>(Future<T> Function() f, T empty) async {
    try {
      return await f();
    } on Object {
      return empty;
    }
  }

  final weather = prefs.shows(StationSection.weather)
      ? safe(() => data.weather(now), null)
      : Future<StationWeather?>.value();
  final events = prefs.shows(StationSection.events)
      ? safe(() => data.events(now), const <StationEvent>[])
      : Future.value(const <StationEvent>[]);
  final tasks = prefs.shows(StationSection.tasks)
      ? safe(() => data.tasks(now), const <StationTask>[])
      : Future.value(const <StationTask>[]);
  return StationInfo(
    weather: await weather,
    events: await events,
    tasks: await tasks,
  );
}

/// The real data: weather service and home place of the settings, device
/// calendar, task lists. Only integrations the user switched on are read.
final class AppStationData implements StationData {
  /// Creates the reader.
  AppStationData(this._ref);

  final Ref _ref;

  bool _on(String id) => _ref.read(enabledIntegrationsProvider).contains(id);

  @override
  Future<StationWeather?> weather(DateTime now) async {
    if (!_on('weather')) return null;
    final config = _ref.read(weatherConfigProvider);
    final home = config.home;
    if (home == null) return null;
    final client = _ref.read(httpClientProvider);
    final service = switch (config.kind) {
      WeatherServiceKind.openMeteo => OpenMeteoWeather(client: client),
      WeatherServiceKind.brightSky => BrightSkyWeather(client: client),
      WeatherServiceKind.metNorway => MetNorwayWeather(
        client: client,
        userAgent: weatherUserAgent(wendelinAppVersion),
      ),
    };
    final report = await service.forecast(
      WeatherRequest(
        place: home,
        zone: timeZoneLocation(home.timeZone ?? 'Europe/Berlin'),
        now: now,
        days: 1,
      ),
    );
    final current = report.current;
    if (current == null) return null;
    return StationWeather(
      place: home.name,
      temperatureC: current.temperatureC,
      condition: current.condition,
    );
  }

  @override
  Future<List<StationEvent>> events(DateTime now, {int limit = 4}) async {
    if (!_on('calendar')) return const [];
    final calendar = _ref.read(platformPortsProvider).calendar;
    if (!await calendar.hasPermission()) return const [];
    final found = await calendar.listEvents(
      TimeRange(now, now.add(const Duration(days: 2))),
    );
    final upcoming = [
      for (final e in found)
        if (e.end.isAfter(now)) e,
    ]..sort((a, b) => a.start.compareTo(b.start));
    return [
      for (final e in upcoming.take(limit))
        StationEvent(
          title: e.title,
          start: e.start.toLocal(),
          allDay: e.allDay,
        ),
    ];
  }

  @override
  Future<List<StationTask>> tasks(DateTime now, {int limit = 4}) async {
    if (!_on('tasks')) return const [];
    final lists = _ref.read(platformPortsProvider).lists;
    if (lists == null) return const [];
    final env = ListsIntegration(
      lists.port,
      definitions: lists.definitions,
    ).env;
    final today = LocalDate(now.year, now.month, now.day);
    final rows = <(LocalDate, StationTask)>[];
    for (final def in env.definitions()) {
      final loaded = await env.load(def);
      for (final item in loaded.items) {
        if (item.done) continue;
        final info = TaskInfo.parse(item.text);
        final due = info.due;
        if (due == null || due.compareTo(today) > 0) continue;
        rows.add((
          due,
          StationTask(
            title: info.title,
            overdue: due.compareTo(today) < 0,
            due: DateTime(due.year, due.month, due.day),
          ),
        ));
      }
    }
    rows.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final r in rows.take(limit)) r.$2];
  }
}

/// Reader of the display (overridden in tests).
final stationDataProvider = Provider<StationData>(AppStationData.new);
