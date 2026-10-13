import 'dart:async';
import 'dart:isolate';

/// An isolate together with the notice that it has exited (its `onExit`
/// port), so a shutdown can wait for the isolate to free native memory.
final class WorkerIsolate {
  WorkerIsolate._(this.isolate, ReceivePort exitPort)
    : exited = exitPort.first.then<void>(
        (_) => exitPort.close(),
        onError: (Object _) {},
      );

  /// Spawns [entry] with [message]; its exit completes [exited].
  static Future<WorkerIsolate> spawn<T>(
    void Function(T) entry,
    T message, {
    String? debugName,
  }) async {
    final exitPort = ReceivePort();
    try {
      final isolate = await Isolate.spawn(
        entry,
        message,
        onExit: exitPort.sendPort,
        debugName: debugName,
      );
      return WorkerIsolate._(isolate, exitPort);
    } on Object {
      exitPort.close();
      rethrow;
    }
  }

  /// The isolate.
  final Isolate isolate;

  /// Completes when the isolate has exited (by itself or killed).
  final Future<void> exited;

  /// Whether the isolate had to be killed.
  bool get killed => _killed;
  bool _killed = false;

  /// Waits up to [grace] for the isolate to exit by itself (after it was
  /// asked to shut down); only then kills it as a safety net. Returns
  /// whether it exited on its own.
  Future<bool> awaitExit({Duration grace = const Duration(seconds: 5)}) async {
    try {
      await exited.timeout(grace);
      return true;
    } on TimeoutException {
      kill();
      await exited;
      return false;
    }
  }

  /// Kills the isolate right away.
  void kill() {
    _killed = true;
    isolate.kill(priority: Isolate.immediate);
  }
}
