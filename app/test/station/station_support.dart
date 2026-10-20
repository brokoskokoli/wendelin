import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' show addTearDown;
import 'package:wendelin/di/core_providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/station/station_data.dart';
import 'package:wendelin/station/station_display.dart';
import 'package:wendelin/station/station_host.dart';
import 'package:wendelin/station/station_prefs.dart';
import 'package:wendelin/station/station_providers.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Clock the tests move by hand (together with `fakeAsync.elapse`).
final class MutableClock implements Clock {
  MutableClock(this.time);

  DateTime time;

  @override
  DateTime now() => time;
}

/// Device side of the station: records what the station asks for.
final class FakeStationHost implements StationHost {
  FakeStationHost() {
    addTearDown(() => dark.close());
  }

  final applied = <StationDisplay>[];
  var unlockAnswers = <bool>[];
  var unlockRequests = 0;
  var finishes = 0;
  var finishResult = true;

  /// When set, [requestUnlock] waits for it (unlock dialog still open).
  Future<bool>? unlockGate;
  final dark = StreamController<bool>.broadcast(sync: true);

  StationDisplay? get last => applied.lastOrNull;

  @override
  Future<void> applyDisplay(StationDisplay display) async =>
      applied.add(display);

  @override
  Future<bool> requestUnlock() async {
    unlockRequests++;
    if (unlockGate case final gate?) return gate;
    return unlockAnswers.isEmpty ? false : unlockAnswers.removeAt(0);
  }

  @override
  Future<bool> finish() async {
    finishes++;
    return finishResult;
  }

  @override
  Stream<bool> get ambientDark => dark.stream;
}

/// Data of the station; counts the reads per area.
final class FakeStationData implements StationData {
  FakeStationData({
    this.weatherNow,
    this.eventList = const [],
    this.taskList = const [],
  });

  StationWeather? weatherNow;
  List<StationEvent> eventList;
  List<StationTask> taskList;
  var weatherReads = 0;
  var eventReads = 0;
  var taskReads = 0;

  @override
  Future<StationWeather?> weather(DateTime now) async {
    weatherReads++;
    return weatherNow;
  }

  @override
  Future<List<StationEvent>> events(DateTime now, {int limit = 4}) async {
    eventReads++;
    return eventList;
  }

  @override
  Future<List<StationTask>> tasks(DateTime now, {int limit = 4}) async {
    taskReads++;
    return taskList;
  }
}

List<Override> stationOverrides({
  required MutableClock clock,
  required FakeStationHost host,
  StationPrefs prefs = const StationPrefs(),
  StationData? data,
}) => [
  clockProvider.overrideWithValue(clock),
  stationHostProvider.overrideWithValue(host),
  startupProvider.overrideWithValue(StartupSettings(station: prefs)),
  if (data != null) stationDataProvider.overrideWithValue(data),
];

ProviderContainer stationContainer({
  required MutableClock clock,
  required FakeStationHost host,
  StationPrefs prefs = const StationPrefs(),
  StationData? data,
}) => ProviderContainer(
  overrides: stationOverrides(
    clock: clock,
    host: host,
    prefs: prefs,
    data: data,
  ),
);
