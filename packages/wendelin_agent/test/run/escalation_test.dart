// Repeated calls and call ids, retries per model call (no hand-over: K28).

import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
  group('calls and retries', () {
    test('an abort during a failed call wins over the error', () async {
      // M6: the abort is checked before the error is handled (the retry is
      // already used up).
      late final Harness h;
      final (a, _) = scripted('a', [
        ScriptedTurn.error(const NetworkException('weg')),
      ]);
      final aborting = ProviderTarget(
        profileId: 'a',
        modelId: 'a-model',
        provider: _AbortOnCall(a.provider, 1, () => h.runner.cancel()),
        privacy: PrivacyLevel.standard,
      );
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      h = Harness(primary: aborting, chain: [b]);
      final events = await h.run('x');
      expect(events.whereType<Escalated>(), isEmpty);
      expect(pb.requests, isEmpty);
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.cancelled);
    });

    test('each model call gets its own retry', () async {
      final (a, pa) = scripted('a', [
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.toolCalls([call('a1', 'web__search')]),
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.text('A fertig.'),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      final h = Harness(
        primary: a,
        chain: [b],
        tools: [FakeTool(name: 'web__search')],
      );
      final events = await h.run('x');
      expect(pa.requests, hasLength(4));
      expect(pb.requests, isEmpty);
      expect((terminal(events) as AgentDone).finalText, 'A fertig.');
    });

    test('same call id with same content is not executed twice', () async {
      final tool = FakeTool(name: 'cal__create');
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'cal__create', '{"t":1}')]),
        ScriptedTurn.toolCalls([call('c1', 'cal__create', '{ "t": 1 }')]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      await h.run('x');
      expect(tool.calls, [
        {'t': 1},
      ]);
      final result = lastResults(provider.requests[2]).single;
      expect(result.callId, 'c1_dup1');
      expect((result.content.first as TextBlock).text, startsWith('Bereits'));
    });

    test('replacement ids match the strictest provider pattern', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([
          call('call:0', 'web__search', '{"n":1}'),
          call('call:0', 'web__search', '{"n":2}'),
          call('call_0', 'web__search', '{"n":3}'),
          call('', 'web__search', '{"n":4}'),
          call('ok-id_1', 'web__search', '{"n":5}'),
        ]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      await h.run('x');
      final ids = provider.requests[1].messages[1].toolCalls
          .map((c) => c.id)
          .toList();
      expect(ids, [
        'call_0',
        'call_0_dup1',
        'call_0_dup2',
        'call_dup1',
        'ok-id_1',
      ]);
      final anthropic = RegExp(r'^[a-zA-Z0-9_-]+$');
      expect(ids.every(anthropic.hasMatch), isTrue);
      expect(lastResults(provider.requests[1]).map((r) => r.callId), ids);
      expect(tool.callCount, 5);
    });

    test('empty ids never count as a repetition', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('', 'web__search', '{"q":"x"}')]),
        ScriptedTurn.toolCalls([call('', 'web__search', '{"q":"x"}')]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      await h.run('x');
      expect(tool.callCount, 2);
    });

    test(
      'id collision with other content is executed under a new id',
      () async {
        final create = FakeTool(name: 'cal__create');
        final search = FakeTool(name: 'web__search');
        final (a, provider) = scripted('a', [
          ScriptedTurn.toolCalls([call('call_0', 'cal__create', '{"t":1}')]),
          ScriptedTurn.toolCalls([
            call('call_0', 'cal__create', '{"t":2}'),
            call('call_0', 'web__search', '{"q":"x"}'),
            call('', 'web__search', '{"q":"y"}'),
            call('', 'web__search', '{"q":"z"}'),
          ]),
          ScriptedTurn.text('ok'),
        ]);
        final h = Harness(primary: a, tools: [create, search]);
        final events = await h.run('x');
        expect(create.calls, [
          {'t': 1},
          {'t': 2},
        ]);
        expect(search.callCount, 3);
        final messages = provider.requests[2].messages;
        final ids = messages[3].toolCalls.map((c) => c.id).toList();
        expect(ids, ['call_0_dup1', 'call_0_dup2', 'call_dup1', 'call_dup2']);
        expect(lastResults(provider.requests[2]).map((r) => r.callId), ids);
        expect(
          lastResults(provider.requests[2]).every((r) => !r.isError),
          isTrue,
        );
        expect(events.whereType<ToolCallFinished>().map((e) => e.call.id), [
          'call_0',
          ...ids,
        ]);
      },
    );

    test('the same provider may repeat an identical call', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'web__search', '{"q":"x"}')]),
        ScriptedTurn.toolCalls([call('c2', 'web__search', '{"q":"x"}')]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      await h.run('x');
      expect(tool.callCount, 2);
    });
  });
}

/// Delegates to [inner], but its call number [at] (0-based) aborts the run
/// via [abort] and then fails with a retryable error, ignoring the token.
final class _AbortOnCall implements LlmProvider {
  _AbortOnCall(this.inner, this.at, this.abort);

  final LlmProvider inner;
  final int at;
  final void Function() abort;
  var _calls = 0;

  @override
  ProviderType get type => inner.type;

  @override
  ProviderCapabilities get caps => inner.caps;

  @override
  Future<List<ModelInfo>> listModels() => inner.listModels();

  @override
  Future<HealthCheck> test() => inner.test();

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) async* {
    if (_calls++ == at) {
      abort();
      yield const ErrorEvent(NetworkException('weg'));
      return;
    }
    yield* inner.chat(req, cancel: cancel);
  }
}
