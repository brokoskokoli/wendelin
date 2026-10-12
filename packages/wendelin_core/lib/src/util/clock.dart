/// Injectable time source. Logic never calls `DateTime.now()` directly.
abstract interface class Clock {
  /// The current time.
  DateTime now();
}

/// The real wall clock.
final class SystemClock implements Clock {
  /// Creates a system clock.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// A manually controlled clock for tests: returns the same instant until
/// [set] or [advance] is called.
final class FixedClock implements Clock {
  /// Creates a clock frozen at [time].
  FixedClock(DateTime time) : _time = time;

  DateTime _time;

  @override
  DateTime now() => _time;

  /// Moves the clock to [time].
  void set(DateTime time) => _time = time;

  /// Moves the clock forward by [by] (negative durations move it back).
  void advance(Duration by) => _time = _time.add(by);
}
