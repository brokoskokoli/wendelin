/// Compute time of the developer-mode shadow detector per window (WP171):
/// what stage 1 costs extra when both detectors run. Reset after each
/// `wake-alive` line, so the line shows the interval.
final class WakeShadowCost {
  int _count = 0;
  int _sumUs = 0;
  int _maxUs = 0;

  /// Windows measured since the last [reset].
  int get count => _count;

  /// Mean time per window in microseconds (0 without a sample).
  int get meanUs => _count == 0 ? 0 : _sumUs ~/ _count;

  /// Longest time of one window in microseconds.
  int get maxUs => _maxUs;

  /// Adds the time of one window.
  void add(Duration time) {
    final us = time.inMicroseconds;
    _count++;
    _sumUs += us;
    if (us > _maxUs) _maxUs = us;
  }

  /// Starts a new interval.
  void reset() {
    _count = 0;
    _sumUs = 0;
    _maxUs = 0;
  }
}
