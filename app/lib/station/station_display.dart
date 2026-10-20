import 'station_prefs.dart';

/// How bright the window is (set natively without `WRITE_SETTINGS`).
enum StationBrightness {
  /// Follows the ambient light sensor (Kotlin side).
  ambient,

  /// Nearly black (quiet hours).
  quiet,
}

/// What the station asks of the screen right now.
final class StationDisplay {
  /// Creates a plan.
  const StationDisplay({required this.keepOn, required this.brightness});

  /// `FLAG_KEEP_SCREEN_ON`: only while the mode wants the screen on, never a
  /// wake lock.
  final bool keepOn;

  /// Window brightness.
  final StationBrightness brightness;

  /// The content is drawn in the quiet look.
  bool get quietLook => brightness == StationBrightness.quiet;

  @override
  bool operator ==(Object other) =>
      other is StationDisplay &&
      other.keepOn == keepOn &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(keepOn, brightness);

  @override
  String toString() => 'StationDisplay(keepOn: $keepOn, $brightness)';
}

/// The screen plan for [mode]. [quiet]: it is quiet time. [awake]: a touch
/// woke the station a short while ago.
StationDisplay planDisplay({
  required StationScreenMode mode,
  required bool quiet,
  required bool awake,
}) {
  final keepOn = switch (mode) {
    StationScreenMode.alwaysDimmed => true,
    StationScreenMode.touchOnly => awake,
    StationScreenMode.daytimeOnly => !quiet || awake,
  };
  return StationDisplay(
    keepOn: keepOn,
    brightness: quiet && !awake
        ? StationBrightness.quiet
        : StationBrightness.ambient,
  );
}
