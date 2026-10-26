// WP157 review round 1, finding 1: a run holds its session at the invoker
// (SessionLockable) from start to end, also when it fails or is cancelled.
import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

final class _Holding implements ToolInvoker, SessionLockable {
  _Holding(this.inner, this.log);
  final ToolInvoker inner;
  final List<String> log;
  @override
  void lockExternal(String sessionId, {String? profileId}) {}
  @override
  void holdSession(String sessionId) => log.add('hold $sessionId');
  @override
  void releaseSession(String sessionId) => log.add('release $sessionId');
  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) => inner.invokeAll(calls, ctx);
}

void main() {
  Harness harness(List<ScriptedTurn> turns, List<String> log) {
    final (target, _) = scripted('p', turns);
    final catalog = FakeToolCatalog([]);
    return Harness(
      primary: target,
      invoker: _Holding(FakeToolInvoker(catalog), log),
    );
  }

  test('Lauf hält die Sitzung bis zum Ende', () async {
    final log = <String>[];
    final h = harness([ScriptedTurn.text('ok')], log);
    await h.run('hallo');
    expect(log, ['hold s1', 'release s1']);
  });

  test('Abbruch gibt die Sitzung ebenfalls frei', () async {
    final log = <String>[];
    final h = harness([ScriptedTurn.text('ok')], log);
    await h.run(
      'hallo',
      onEvent: (e) {
        if (e is AgentTextDelta) h.runner.cancel();
      },
    );
    expect(log.where((e) => e.startsWith('release')), ['release s1']);
  });

  test('Lauf mit Fehler gibt die Sitzung frei', () async {
    final log = <String>[];
    final h = harness([
      ScriptedTurn.error(const ServerException('x', statusCode: 500)),
    ], log);
    await h.run('hallo');
    expect(log.where((e) => e.startsWith('release')), ['release s1']);
  });
}
