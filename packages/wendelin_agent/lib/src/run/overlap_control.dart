/// The event channel of a model call that overlaps the check of the previous
/// answer (WP81b, WP81c). Internal to `wendelin_agent`, not exported.
library;

import 'package:wendelin_core/wendelin_core.dart';

import 'run_state.dart';

/// A [RunControl] for a model call started before the receipt of the
/// previous answer is known.
///
/// Invariants:
/// - Text, speech and thinking events go to the run's listener at once
///   (WP81c): the answer is shown and read while the receipt is open. Tool
///   calls of the reply are run by the loop only after the green receipt.
/// - [discard] (the receipt is not green) cancels the call's own [token],
///   emits one `AgentTextReset` if the call showed anything (the listener
///   removes the section and clears the speech queue) and drops everything
///   that follows, including receipt events held back, except [UsageReported] (paid tokens are always reported).
/// - [abandon] (abort, error) stops the call like [discard] but emits no
///   reset: the run ends anyway.
/// - Final (not yellow) [AttestationStatusChanged] of the call are held back
///   until [verified]: the receipt of the previous step comes first, and a
///   discarded call never shows or audits a receipt.
/// - An abort of the run is still thrown by [throwIfAborted].
final class OverlapControl implements RunControl {
  /// Passes events of a call of the run behind [_parent] on.
  OverlapControl(this._parent) {
    _parent.token.whenCancelled.then((_) => token.cancel());
  }

  final RunControl _parent;
  bool _stopped = false;
  bool _shown = false;
  bool _verified = false;
  final List<AgentEvent> _held = [];

  @override
  final CancelToken token = CancelToken();

  @override
  bool get segmentStreamed => _parent.segmentStreamed;

  /// Whether the call was stopped by [discard] or [abandon].
  bool get discarded => _stopped;

  @override
  void emit(AgentEvent e) {
    if (_stopped) {
      // Paid tokens count in any case, also of a dropped call.
      if (e is UsageReported) _parent.emit(e);
      return;
    }
    if (e is AgentTextDelta ||
        e is AgentSpokenText ||
        e is AgentThinkingDelta) {
      _shown = true;
    }
    if (!_verified &&
        e is AttestationStatusChanged &&
        e.status != AttestationStatus.yellow) {
      _held.add(e);
      return;
    }
    _parent.emit(e);
  }

  /// The previous answer is verified: the call goes on, held receipts go out.
  void verified() {
    if (_stopped || _verified) return;
    _verified = true;
    final held = List.of(_held);
    _held.clear();
    held.forEach(_parent.emit);
  }

  /// The previous answer is not verified: takes back what the call showed
  /// and cancels it. Idempotent.
  void discard() {
    if (_stopped) return;
    _stopped = true;
    token.cancel();
    if (_shown) {
      _parent.emit(const AgentTextReset('Vorherige Antwort nicht bestätigt'));
    }
  }

  /// [discard] without reset unless [verified] was called (abort, error).
  void abandon() {
    if (_verified || _stopped) return;
    _stopped = true;
    token.cancel();
  }

  @override
  void throwIfAborted() => _parent.throwIfAborted();
}
