import 'dart:async';

/// Process-wide queues per file key: read-modify-write sequences of
/// parallel tool calls (and undos) on the same file never interleave, even
/// across integration instances (the app may rebuild an integration while
/// calls are running).
abstract final class FileQueue {
  static final Map<String, Future<void>> _tails = {};

  /// Number of keys with a pending queue (for tests; 0 when idle).
  static int get pending => _tails.length;

  /// Runs [body] exclusively for [key]. A failing [body] does not stop the
  /// queue; a hanging one blocks it, so ports should time out.
  static Future<T> run<T>(String key, Future<T> Function() body) {
    final previous = _tails[key] ?? Future<void>.value();
    final result = previous.then((_) => body());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _tails[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return result;
  }
}
