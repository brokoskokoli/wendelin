// WP53: Abbruch geht unabhängig vom Sperrzustand an den inneren Lauf.
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/locked_agent_run.dart';
import 'package:wendelin_core/wendelin_core.dart';

final class _Inner implements AgentRun {
  int cancels = 0;

  @override
  Stream<AgentEvent> run(UserInput input) => const Stream.empty();

  @override
  void cancel() => cancels++;
}

void main() {
  for (final startLocked in [true, false]) {
    test('cancel erreicht den inneren Lauf (Start gesperrt=$startLocked)', () {
      final inner = _Inner();
      var locked = startLocked;
      final gate = LockGateAgentRun(
        inner: inner,
        locked: () => locked,
        runCommand: (_, _) async => true,
        onRefused: (_, _) {},
        trigger: () => 'assistant',
      );
      locked = !startLocked; // Sperrzustand wechselt vor dem Abbruch
      gate.cancel();
      locked = startLocked;
      gate.cancel();
      expect(inner.cancels, 2);
    });
  }
}
