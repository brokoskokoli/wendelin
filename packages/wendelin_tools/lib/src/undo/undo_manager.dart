import 'dart:async';

import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// State of an undo offer.
enum UndoState {
  /// Can still be undone; see [UndoUpdate.remaining].
  pending,

  /// Was undone.
  undone,

  /// The window has passed.
  expired,

  /// Running the undo failed (the offer is gone).
  failed,
}

/// Countdown event of [UndoManager.updates].
@immutable
final class UndoUpdate {
  /// Creates an update.
  const UndoUpdate({
    required this.callId,
    required this.label,
    required this.state,
    required this.remaining,
  });

  /// Tool call the undo belongs to.
  final String callId;

  /// Button text, e.g. „Termin entfernen“.
  final String label;

  /// Current state.
  final UndoState state;

  /// Time left ([Duration.zero] unless pending).
  final Duration remaining;

  @override
  bool operator ==(Object other) =>
      other is UndoUpdate &&
      other.callId == callId &&
      other.label == label &&
      other.state == state &&
      other.remaining == remaining;

  @override
  int get hashCode => Object.hash(callId, label, state, remaining);

  @override
  String toString() =>
      'UndoUpdate($callId, ${state.name}, ${remaining.inMilliseconds} ms)';
}

/// Keeps the [UndoAction]s of `write` tools for a short [window]
/// (default 10 s) and runs them on request.
///
/// Time comes from [clock] and `dart:async` timers, so tests can drive both
/// (e.g. with `fake_async`).
final class UndoManager {
  /// Creates a manager.
  UndoManager({
    required this.clock,
    this.window = const Duration(seconds: 10),
    this.tick = const Duration(seconds: 1),
  });

  /// Time source for the countdown.
  final Clock clock;

  /// How long an undo stays available.
  final Duration window;

  /// Interval of countdown updates.
  final Duration tick;

  final Map<String, _Pending> _pending = {};
  final StreamController<UndoUpdate> _updates =
      StreamController<UndoUpdate>.broadcast();

  /// Countdown, undo and expiry events of all offers.
  Stream<UndoUpdate> get updates => _updates.stream;

  /// Offers [action] for [callId] from now on for [window]; replaces an
  /// existing offer for the same call.
  void register(String callId, UndoAction action) {
    _pending.remove(callId)?.cancel();
    final p = _Pending(action, clock.now().add(window));
    _pending[callId] = p;
    p
      ..expiry = Timer(window, () => _expire(callId, p))
      ..ticker = Timer.periodic(tick, (_) => _emit(callId, p));
    _emit(callId, p);
  }

  /// Withdraws the offer for [callId] without running it (the action was
  /// undone elsewhere, e.g. automatically after a red TEE receipt).
  void discard(String callId) => _pending.remove(callId)?.cancel();

  /// Whether at least one undo action is currently pending.
  bool get hasPending => _pending.isNotEmpty;

  /// Whether [callId] can still be undone.
  bool canUndo(String callId) => remaining(callId) != null;

  /// Time left for [callId], or `null` if there is nothing to undo.
  Duration? remaining(String callId) {
    final p = _pending[callId];
    if (p == null) return null;
    final left = p.expiresAt.difference(clock.now());
    return left > Duration.zero ? left : null;
  }

  /// Runs the undo of [callId]. Returns `false` if there is none (unknown,
  /// expired or already undone). Emits [UndoState.undone] after the action
  /// succeeded; on failure emits [UndoState.failed] and rethrows. The offer
  /// is gone either way (no double undo while the action runs).
  Future<bool> undo(String callId) async {
    if (!canUndo(callId)) return false;
    final p = _pending.remove(callId)!..cancel();
    try {
      await p.action();
    } on Object {
      _emit(callId, p, UndoState.failed);
      rethrow;
    }
    _emit(callId, p, UndoState.undone);
    return true;
  }

  /// Drops all offers and closes [updates].
  Future<void> dispose() {
    for (final p in _pending.values) {
      p.cancel();
    }
    _pending.clear();
    return _updates.close();
  }

  void _expire(String callId, _Pending p) {
    if (!identical(_pending[callId], p)) return;
    _pending.remove(callId);
    p.cancel();
    _emit(callId, p, UndoState.expired);
  }

  void _emit(String callId, _Pending p, [UndoState state = UndoState.pending]) {
    if (_updates.isClosed) return;
    final left = p.expiresAt.difference(clock.now());
    _updates.add(
      UndoUpdate(
        callId: callId,
        label: p.action.label,
        state: state,
        remaining: state == UndoState.pending && left > Duration.zero
            ? left
            : Duration.zero,
      ),
    );
  }
}

final class _Pending {
  _Pending(this.action, this.expiresAt);

  final UndoAction action;
  final DateTime expiresAt;
  Timer? expiry;
  Timer? ticker;

  void cancel() {
    expiry?.cancel();
    ticker?.cancel();
  }
}
