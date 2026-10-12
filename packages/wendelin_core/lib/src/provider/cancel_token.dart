import 'dart:async';

import 'provider_exception.dart';

/// Cooperative cancellation signal shared between caller and callee.
///
/// Cancelling is idempotent; listeners can poll [isCancelled] or await
/// [whenCancelled].
final class CancelToken {
  /// Creates an uncancelled token.
  CancelToken();

  final Completer<void> _completer = Completer<void>();

  /// Whether [cancel] has been called.
  bool get isCancelled => _completer.isCompleted;

  /// Completes (with no value) once [cancel] is called; never errors.
  Future<void> get whenCancelled => _completer.future;

  /// Requests cancellation. Further calls have no effect.
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Throws [CancelledException] if the token is cancelled.
  void throwIfCancelled() {
    if (isCancelled) throw const CancelledException();
  }
}
