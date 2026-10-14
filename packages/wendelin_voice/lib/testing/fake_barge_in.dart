import 'dart:async';

import '../src/io/barge_in_detector.dart';

/// [BargeInDetector] fired by hand. Passes `bargeInDetectorContract`.
final class FakeBargeInDetector implements BargeInDetector {
  final _controller = StreamController<BargeInSignal>.broadcast(sync: true);
  bool _running = false;

  /// Number of effective [start] calls.
  int startCount = 0;

  /// Number of effective [stop] calls.
  int stopCount = 0;

  /// Thrown by [start] when set.
  Object? startError;

  @override
  Stream<BargeInSignal> get signals => _controller.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    final error = startError;
    if (error != null) throw error;
    if (_running) return;
    _running = true;
    startCount++;
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    stopCount++;
  }

  /// Emits [signal] (only while running, like a real detector).
  void emit(BargeInSignal signal) {
    if (_running) _controller.add(signal);
  }
}
