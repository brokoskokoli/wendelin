import 'dart:async';

import 'port_exception.dart';

/// Thrown by a save step when the file changed since it was read (an
/// optimistic lock failed); [FileQueue.run] then runs the step again.
final class WriteConflict implements Exception {
  /// Creates the exception.
  const WriteConflict();

  @override
  String toString() => 'WriteConflict';
}

/// Process-wide queues per file key: read-modify-write sequences of
/// parallel tool calls (and undos) on the same file never interleave, even
/// across integration instances (the app may rebuild an integration while
/// calls are running).
abstract final class FileQueue {
  static final Map<String, Future<void>> _tails = {};

  /// Number of keys with a pending queue (for tests; 0 when idle).
  static int get pending => _tails.length;

  /// Attempts per [run] when [body] reports a [WriteConflict].
  static const attempts = 3;

  /// Runs [body] exclusively for [key]. A failing [body] does not stop the
  /// queue; a hanging one blocks it, so ports should time out.
  ///
  /// [body] must read the file itself (it is repeated): on a
  /// [WriteConflict] it runs again, up to [attempts] times, then the run
  /// fails with `PortException(unavailable)`.
  static Future<T> run<T>(String key, Future<T> Function() body) {
    final previous = _tails[key] ?? Future<void>.value();
    final result = previous.then((_) => _retrying(body));
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _tails[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return result;
  }

  static Future<T> _retrying<T>(Future<T> Function() body) async {
    for (var i = 1; ; i++) {
      try {
        return await body();
      } on WriteConflict {
        if (i >= attempts) {
          throw const PortException(
            PortErrorKind.unavailable,
            'Die Datei wird gerade von außen geändert (z. B. Sync); nichts '
            'geschrieben. Bitte gleich noch einmal versuchen.',
          );
        }
      }
    }
  }
}
