import 'package:flutter/foundation.dart';

/// How the screen behaves while the station runs (WP99, K62/K63).
enum StationScreenMode {
  /// Always on, dimmed by ambient light (default); near black in quiet hours.
  alwaysDimmed,

  /// Off; on by wake word or touch (the system screen timeout turns it off).
  touchOnly,

  /// On by day, off in quiet hours; touch wakes it for a while.
  daytimeOnly,
}

/// Areas of the idle display that can be hidden one by one. Clock and date
/// are always shown.
enum StationSection {
  /// Weather (WP87).
  weather,

  /// Next appointments with titles (calendar).
  events,

  /// Tasks due today or overdue with titles (WP88).
  tasks,

  /// Playback slot (filled by WP100).
  playback,

  /// Smart home tiles slot (filled by WP100).
  tiles,
}

/// Quiet hours: [fromHour] up to [toHour] (local time, may span midnight).
/// Equal hours mean none.
@immutable
final class QuietHours {
  /// Creates quiet hours (default 22 to 7).
  const QuietHours({this.fromHour = 22, this.toHour = 7});

  /// First hour of the quiet time (0 to 23).
  final int fromHour;

  /// Hour when the quiet time ends (0 to 23).
  final int toHour;

  /// Whether [time] (local) lies in the quiet hours.
  bool contains(DateTime time) {
    if (fromHour == toHour) return false;
    final h = time.hour;
    return fromHour < toHour
        ? h >= fromHour && h < toHour
        : h >= fromHour || h < toHour;
  }

  @override
  bool operator ==(Object other) =>
      other is QuietHours &&
      other.fromHour == fromHour &&
      other.toHour == toHour;

  @override
  int get hashCode => Object.hash(fromHour, toHour);
}

/// Settings of the station mode (key `station.prefs`).
@immutable
final class StationPrefs {
  /// Creates the settings; the defaults are K63's.
  const StationPrefs({
    this.screenMode = StationScreenMode.alwaysDimmed,
    this.quiet = const QuietHours(),
    this.hidden = const {},
  });

  /// Decodes [toJson]; unknown values fall back to the default.
  factory StationPrefs.fromJson(Map<String, Object?> json) {
    int hour(Object? v, int fallback) =>
        v is int && v >= 0 && v <= 23 ? v : fallback;
    final hiddenRaw = json['hidden'];
    return StationPrefs(
      screenMode:
          StationScreenMode.values
              .where((m) => m.name == json['screenMode'])
              .firstOrNull ??
          StationScreenMode.alwaysDimmed,
      quiet: QuietHours(
        fromHour: hour(json['quietFrom'], 22),
        toHour: hour(json['quietTo'], 7),
      ),
      hidden: {
        if (hiddenRaw is List)
          for (final n in hiddenRaw)
            ...StationSection.values.where((s) => s.name == n),
      },
    );
  }

  /// Screen behaviour.
  final StationScreenMode screenMode;

  /// Quiet hours (display and, in WP101, sound).
  final QuietHours quiet;

  /// Sections the user switched off.
  final Set<StationSection> hidden;

  /// Whether [section] is shown.
  bool shows(StationSection section) => !hidden.contains(section);

  /// A copy with other values.
  StationPrefs copyWith({
    StationScreenMode? screenMode,
    QuietHours? quiet,
    Set<StationSection>? hidden,
  }) => StationPrefs(
    screenMode: screenMode ?? this.screenMode,
    quiet: quiet ?? this.quiet,
    hidden: hidden ?? this.hidden,
  );

  /// Without secrets.
  Map<String, Object?> toJson() => {
    'screenMode': screenMode.name,
    'quietFrom': quiet.fromHour,
    'quietTo': quiet.toHour,
    'hidden': [
      for (final s in StationSection.values)
        if (hidden.contains(s)) s.name,
    ],
  };
}
