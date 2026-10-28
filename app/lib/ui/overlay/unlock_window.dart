import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// How long after the keyguard result the lifecycle changes, taps outside
/// and close requests still belong to the unlock (WP114; same value as
/// `UnlockGuard.GRACE_MS` on the Android side).
const unlockGrace = Duration(milliseconds: 1500);

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

  /// Whether an unlock request is open right now (no grace).
  bool get open => _open;

  /// Whether an unlock runs or ended less than [unlockGrace] ago.
  bool get active {
    if (_open) return true;
    final ended = _ended;
    return ended != null && _clock.now().difference(ended) < unlockGrace;
  }
}

/// The unlock window plus what belongs to it (WP114, K85): the grace timer
/// that looks at the lifecycle again afterwards, and the wait for the
/// overlay to be visible again. The overlay only makes thin calls.
final class UnlockWatch {
  /// Creates the watch on [clock].
  UnlockWatch(Clock clock) : window = UnlockWindow(clock);

  /// The window itself.
  final UnlockWindow window;
  Timer? _grace;
  Completer<void>? _resumed;

  bool _offered = false;

  /// An unlock is offered, runs or its grace period is open: the overlay
  /// must not close itself meanwhile.
  bool get busy => _offered || window.active || window.open;

  /// Runs [offer] (the offer after a refusal) and counts as [busy] meanwhile;
  /// set synchronously, before the spoken hint ended.
  Future<void> offering(Future<void> Function() offer) async {
    _offered = true;
    try {
      await offer();
    } finally {
      _offered = false;
    }
  }

  /// Not on screen (home, screen off).
  bool get outOfSight {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == AppLifecycleState.hidden || s == AppLifecycleState.paused;
  }

  /// Runs the unlock [request] inside the window. Once the grace period
  /// is over the lifecycle is looked at again: what was ignored meanwhile
  /// (home, screen off) must not be lost, [close] runs then (if [alive]).
  Future<bool> run(
    Future<bool> Function() request, {
    required bool Function() alive,
    required void Function() close,
  }) async {
    _grace?.cancel();
    window.begin();
    try {
      return await request();
    } finally {
      window.end();
      _grace = Timer(unlockGrace, () {
        if (alive() && !window.open && outOfSight) close();
      });
    }
  }

  /// The app came back to the foreground.
  void resumed() {
    final r = _resumed;
    if (r != null && !r.isCompleted) r.complete();
  }

  /// The overlay is visible again, or the grace period ran out and it is
  /// not (false then; the caller closes). The keyguard transition may
  /// still hide the activity right after the result.
  Future<bool> visibleAfterUnlock(bool Function() mounted) async {
    if (!outOfSight) return true;
    final resumed = _resumed = Completer<void>();
    final timer = Timer(unlockGrace, () {
      if (!resumed.isCompleted) resumed.complete();
    });
    await resumed.future;
    timer.cancel();
    _resumed = null;
    return mounted() && !outOfSight;
  }

  /// Stops the timer and releases a waiting caller.
  void dispose() {
    _grace?.cancel();
    resumed();
  }
}
