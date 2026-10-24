import 'package:wendelin/platform/assistant_platform.dart';

/// Records how the overlay releases its host (WP145): the order of
/// `releaseHost`, `teardownDone` and `finish`.
mixin HostCallRecorder on AssistantPlatform {
  /// Host calls in order.
  final calls = <String>[];

  /// The overlay was closed: the host was released (or finished).
  int get finished =>
      calls.where((c) => c == 'releaseHost' || c == 'finish').length;

  /// What [releaseHost] answers (`false`: a host that cannot hold the engine).
  bool canRelease = true;

  @override
  Future<bool> releaseHost() async {
    calls.add('releaseHost');
    return canRelease;
  }

  @override
  Future<void> teardownDone() async => calls.add('teardownDone');

  @override
  Future<bool> finish() async {
    calls.add('finish');
    return true;
  }
}
