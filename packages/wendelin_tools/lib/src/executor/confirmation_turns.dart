import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

/// Lets confirmations of one run be asked strictly one after another, in
/// the order [ask] is called. Never two confirmation cards at once.
final class ConfirmationTurns {
  /// Creates turns for a run cancelled by [cancel].
  ConfirmationTurns(this.cancel);

  /// Cancellation of the run: open and waiting questions resolve as
  /// declined.
  final CancelToken cancel;

  Future<void> _previous = Future<void>.value();

  /// Waits for its turn, emits [question] and returns the user's answer.
  ///
  /// Returns `false` without asking if the run is cancelled while waiting,
  /// and `false` if it is cancelled while the question is open. In any case
  /// [question] is answered afterwards (`respond(false)` is a no-op if the
  /// user already answered), so no card stays open.
  Future<bool> ask(
    FutureOr<ConfirmationNeeded> Function() question,
    void Function(ToolInvocationEvent) emit,
  ) async {
    final previous = _previous;
    final mine = Completer<void>();
    _previous = mine.future;
    ConfirmationNeeded? asked;
    try {
      await Future.any([previous, cancel.whenCancelled]);
      if (cancel.isCancelled) return false;
      // Built inside the turn: the text may be looked up live and reflects
      // the effect of earlier confirmed calls.
      asked = await question();
      if (cancel.isCancelled) return false;
      emit(asked);
      return await Future.any([
        asked.decision.future,
        cancel.whenCancelled.then((_) => false),
      ]);
    } finally {
      asked?.respond(false);
      mine.complete();
    }
  }
}
