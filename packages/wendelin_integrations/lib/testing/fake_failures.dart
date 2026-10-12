import '../src/common/port_exception.dart';

/// Failure injection shared by the fake ports.
mixin FakeFailures {
  final Map<String, Object> _failures = {};

  /// Names of all port methods called so far, in order.
  final List<String> methodCalls = [];

  /// The next call of [method] (e.g. `'createEvent'`) throws [error]
  /// instead of running; default is a generic [PortException].
  void failNext(
    String method, [
    Object error = const PortException(
      PortErrorKind.failed,
      'Simulierter Fehler',
    ),
  ]) => _failures[method] = error;

  /// Records [method] and throws an injected failure, if any.
  void enter(String method) {
    methodCalls.add(method);
    final error = _failures.remove(method);
    if (error != null) throw error;
  }
}
