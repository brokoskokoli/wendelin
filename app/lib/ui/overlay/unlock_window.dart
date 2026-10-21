import 'package:wendelin_core/wendelin_core.dart';

/// How long after the keyguard result the lifecycle changes, taps outside
/// and close requests still belong to the unlock (WP114; same value as
/// `UnlockGuard.GRACE_MS` on the Android side).
const unlockGrace = Duration(milliseconds: 2500);

/// Tells whether the overlay is unlocking or just did (K85): the keyguard
/// transition is neither „leaving“ the overlay nor a tap.
final class UnlockWindow {
  /// Creates the window on [clock].
  UnlockWindow(this._clock);

  final Clock _clock;
  bool _open = false;
  DateTime? _ended;

  /// The unlock request starts.
  void begin() => _open = true;

  /// The unlock request ended, whatever the result.
  void end() {
    _open = false;
    _ended = _clock.now();
  }

  /// Whether an unlock runs or ended less than [unlockGrace] ago.
  bool get active {
    if (_open) return true;
    final ended = _ended;
    return ended != null && _clock.now().difference(ended) < unlockGrace;
  }
}
