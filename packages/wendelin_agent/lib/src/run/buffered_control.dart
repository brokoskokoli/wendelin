/// The event channel of a model call that overlaps the check of the previous
/// answer (WP81b). Internal to `wendelin_agent`, not exported.
library;

import 'package:wendelin_core/wendelin_core.dart';

import 'run_state.dart';

/// A [RunControl] for a model call started before the receipt of the
/// previous answer is known.
///
/// Invariants:
/// - Until [release] nothing reaches the run's listener: events are kept in
///   order. [release] replays them and passes later events through.
/// - [discard] drops everything kept and everything that follows, except
///   [UsageReported] (paid tokens are always reported), and cancels the call's own [token]. The run's abort cancels it too.
/// - An abort of the run is still thrown by [throwIfAborted].
final class BufferedControl implements RunControl {
  /// Buffers events for a call of the run behind [_parent].
  BufferedControl(this._parent) {
    _parent.token.whenCancelled.then((_) => token.cancel());
  }

  final RunControl _parent;
  List<AgentEvent>? _held = [];
  bool _discarded = false;

  @override
  final CancelToken token = CancelToken();

  @override
  bool get segmentStreamed => _parent.segmentStreamed;

  /// Whether [discard] was called.
  bool get discarded => _discarded;

  @override
  void emit(AgentEvent e) {
    if (_discarded) {
      // Paid tokens count in any case, also of a dropped call.
      if (e is UsageReported) _parent.emit(e);
      return;
    }
    final held = _held;
    if (held != null) {
      held.add(e);
    } else {
      _parent.emit(e);
    }
  }

  /// The previous answer is verified: replays the kept events.
  void release() {
    final held = _held;
    if (held == null || _discarded) return;
    _held = null;
    held.forEach(_parent.emit);
  }

  /// The previous answer is not verified: drops the call's events and
  /// cancels the call.
  void discard() {
    _discarded = true;
    _held?.whereType<UsageReported>().forEach(_parent.emit);
    _held = null;
    token.cancel();
  }

  /// [discard] unless [release] already passed the events on.
  void discardUnlessReleased() {
    if (_held != null) discard();
  }

  @override
  void throwIfAborted() => _parent.throwIfAborted();
}
