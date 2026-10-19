import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/app_settings.dart';
import '../di/core_providers.dart';
import '../di/providers.dart';
import '../platform/assistant_platform.dart';
import '../platform/screen_protection.dart';
import 'station_data.dart';
import 'station_display.dart';
import 'station_host.dart';
import 'station_prefs.dart';

/// Device side of the station (overridden in tests).
final stationHostProvider = Provider<StationHost>(
  (ref) => DeviceStationHost(
    ref.watch(assistantPlatformProvider),
    const ScreenProtection(),
  ),
);

/// How the station looks: [StationLook.quiet] in quiet hours (nearly black),
/// [StationLook.dim] in a dark room, else [StationLook.normal].
enum StationLook {
  /// Normal brightness.
  normal,

  /// Dark room: muted colors.
  dim,

  /// Quiet hours: nearly black, only the clock.
  quiet,
}

/// Settings of the station mode.
final stationPrefsProvider =
    NotifierProvider<StationPrefsNotifier, StationPrefs>(
      StationPrefsNotifier.new,
    );

/// Station settings: start from the stored value, store every change.
final class StationPrefsNotifier extends Notifier<StationPrefs> {
  @override
  StationPrefs build() => ref.watch(startupProvider).station;

  /// Stores [prefs].
  Future<void> set(StationPrefs prefs) async {
    state = prefs;
    await ref.read(storageProvider).settings.set(AppSettings.station, prefs);
  }
}

/// How long a touch wakes the station in the modes that switch the screen off.
const stationAwakeFor = Duration(seconds: 30);

/// How often the clock is read again (display and screen plan).
const stationTick = Duration(seconds: 30);

/// How often weather, appointments and tasks are read again.
const stationRefreshEvery = Duration(minutes: 10);

/// State of the running station.
@immutable
final class StationState {
  /// Creates the state.
  const StationState({
    required this.now,
    this.awakeUntil,
    this.ending = false,
    this.ended = false,
    this.refreshEpoch = 0,
    this.dark = false,
  });

  /// Local time as of the last tick.
  final DateTime now;

  /// A touch keeps the screen on until then.
  final DateTime? awakeUntil;

  /// The unlock request of „Beenden“ is open.
  final bool ending;

  /// The station was ended after a successful unlock.
  final bool ended;

  /// Counts the refreshes of the data.
  final int refreshEpoch;

  /// The room is dark (ambient light sensor).
  final bool dark;

  /// Whether a touch recently woke the station.
  bool get awake => awakeUntil != null && now.isBefore(awakeUntil!);

  /// A copy.
  StationState copyWith({
    DateTime? now,
    Object? awakeUntil = _keep,
    bool? ending,
    bool? ended,
    int? refreshEpoch,
    bool? dark,
  }) => StationState(
    now: now ?? this.now,
    awakeUntil: identical(awakeUntil, _keep)
        ? this.awakeUntil
        : awakeUntil as DateTime?,
    ending: ending ?? this.ending,
    ended: ended ?? this.ended,
    refreshEpoch: refreshEpoch ?? this.refreshEpoch,
    dark: dark ?? this.dark,
  );
}

const _keep = Object();

/// The station: time, screen plan, wake by touch and the end.
///
/// The mode ends **only** in [end], and only after the device was unlocked
/// (K62/K63). Nothing else here ends it: not unplugging, not a voice command,
/// not leaving the screen.
final stationControllerProvider =
    NotifierProvider.autoDispose<StationController, StationState>(
      StationController.new,
    );

/// See [stationControllerProvider].
final class StationController extends Notifier<StationState> {
  Timer? _tick;
  Timer? _sleep;
  StationDisplay? _applied;
  DateTime _refreshedAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  StationState build() {
    final now = ref.read(clockProvider).now();
    _refreshedAt = now;
    _tick = Timer.periodic(stationTick, (_) => _onTick());
    ref.onDispose(() {
      _tick?.cancel();
      _sleep?.cancel();
    });
    ref.listen(stationPrefsProvider, (_, _) => _apply());
    final dark = ref
        .read(stationHostProvider)
        .ambientDark
        .listen((d) => state = state.copyWith(dark: d));
    ref.onDispose(dark.cancel);
    scheduleMicrotask(_apply);
    return StationState(now: now);
  }

  StationDisplay get plan {
    final prefs = ref.read(stationPrefsProvider);
    return planDisplay(
      mode: prefs.screenMode,
      quiet: prefs.quiet.contains(state.now),
      awake: state.awake,
    );
  }

  void _onTick() {
    final now = ref.read(clockProvider).now();
    final stale = now.difference(_refreshedAt) >= stationRefreshEvery;
    if (stale) _refreshedAt = now;
    state = state.copyWith(
      now: now,
      refreshEpoch: stale ? state.refreshEpoch + 1 : null,
    );
    _apply();
  }

  /// A touch: the screen stays on for [stationAwakeFor], in the modes that
  /// would switch it off or darken it.
  void touch() {
    if (state.ended) return;
    final now = ref.read(clockProvider).now();
    state = state.copyWith(now: now, awakeUntil: now.add(stationAwakeFor));
    _sleep?.cancel();
    _sleep = Timer(stationAwakeFor, _onTick);
    _apply();
  }

  void _apply() {
    if (state.ended) return;
    final next = plan;
    if (next == _applied) return;
    _applied = next;
    unawaited(ref.read(stationHostProvider).applyDisplay(next));
  }

  /// „Beenden“: asks to unlock; the station closes only if the device was
  /// unlocked. Returns whether it ended.
  Future<bool> end() async {
    if (state.ending || state.ended) return false;
    state = state.copyWith(ending: true);
    final host = ref.read(stationHostProvider);
    final unlocked = await host.requestUnlock();
    if (!unlocked) {
      state = state.copyWith(ending: false);
      return false;
    }
    state = state.copyWith(ending: false, ended: true);
    await host.finish();
    return true;
  }
}

/// Weather, appointments and tasks of the shown areas, read again every
/// [stationRefreshEvery].
final stationInfoProvider = FutureProvider.autoDispose<StationInfo>((ref) {
  ref.watch(stationControllerProvider.select((s) => s.refreshEpoch));
  final prefs = ref.watch(stationPrefsProvider);
  // Quiet look: only the clock is shown, so nothing is read.
  if (ref.watch(stationLookProvider) == StationLook.quiet) {
    return const StationInfo();
  }
  final now = ref.read(stationControllerProvider).now;
  return readStationInfo(ref.watch(stationDataProvider), prefs, now);
});

/// The look of the station right now.
final stationLookProvider = Provider.autoDispose<StationLook>((ref) {
  final s = ref.watch(stationControllerProvider);
  final prefs = ref.watch(stationPrefsProvider);
  final display = planDisplay(
    mode: prefs.screenMode,
    quiet: prefs.quiet.contains(s.now),
    awake: s.awake,
  );
  if (display.quietLook) return StationLook.quiet;
  return s.dark ? StationLook.dim : StationLook.normal;
});
