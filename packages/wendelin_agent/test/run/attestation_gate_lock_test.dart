import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_agent/src/run/attestation_gate.dart';
import 'package:wendelin_agent/src/run/run_state.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'attestation_test.dart' show VerifyingFake;

final class _Control implements RunControl {
  @override
  final token = CancelToken();
  @override
  bool get segmentStreamed => false;
  @override
  void emit(AgentEvent e) {}
  @override
  void throwIfAborted() {}
}

/// Invoker that can lock sessions (like the `ToolExecutor`).
final class _PlainInvoker implements ToolInvoker {
  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) => const Stream.empty();
}

final class _LockingInvoker extends _PlainInvoker implements SessionLockable {
  final locks = <(String, String?)>[];
  @override
  void lockExternal(String sessionId, {String? profileId}) =>
      locks.add((sessionId, profileId));
}

void main() {
  group('AttestationGate sperrt die Sitzung (WP157)', () {
    Future<_LockingInvoker> run(
      AttestationStatus? status, {
      ToolInvoker? invoker,
    }) async {
      final locking = _LockingInvoker();
      final report = Completer<AttestationReport?>()
        ..complete(
          status == null
              ? null
              : AttestationReport(logId: 'l', status: status, detail: 'x'),
        );
      final provider = VerifyingFake(FakeLlmProvider([]), report);
      final gate = AttestationGate(_Control(), 'sess-1', invoker ?? locking);
      final request = ChatRequest(
        messages: const [],
        model: 'm',
        maxTokens: 1,
        systemPrompt: '',
      );
      await gate.settle(gate.begin(provider, request, profileId: 'phala'));
      return locking;
    }

    test('rot: lockExternal mit Sitzungs- und Profil-Id', () async {
      expect((await run(AttestationStatus.red)).locks, [('sess-1', 'phala')]);
    });

    test('grün, gelb und ohne Ergebnis sperren nicht', () async {
      for (final s in [
        AttestationStatus.green,
        AttestationStatus.yellow,
        null,
      ]) {
        expect((await run(s)).locks, isEmpty, reason: '$s');
      }
    });

    test('Invoker ohne SessionLockable: rot wirft nicht', () async {
      await run(AttestationStatus.red, invoker: _PlainInvoker());
    });
  });
}
