import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

ChatRequest req(String text) =>
    ChatRequest(messages: [Message.user(text)], model: 'm', maxTokens: 10);

ToolContext ctx({CancelToken? cancel}) => ToolContext(
  sessionId: 's1',
  clock: FixedClock(DateTime.utc(2026, 10, 12)),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
  cancel: cancel,
);

void main() {
  group('ScriptedTurn', () {
    test('text splits into chunks, then usage and Done', () {
      final t = ScriptedTurn.text('abcdefghij', chunkSize: 4, thinking: 'hm');
      expect(t.events, [
        const ThinkingDelta('hm'),
        const TextDelta('abcd'),
        const TextDelta('efgh'),
        const TextDelta('ij'),
        const UsageEvent(ScriptedTurn.defaultUsage),
        const Done(StopReason.endTurn),
      ]);
      expect(t.hangs, isFalse);
    });

    test('toolCalls: deltas with id/name on first fragment only', () {
      const call = ToolCallBlock(
        id: 'c',
        name: 'a__b',
        argumentsJson: '{"x":1}',
      );
      final t = ScriptedTurn.toolCalls([call], text: 'ok', chunkSize: 4);
      expect(t.events, [
        const TextDelta('ok'),
        const ToolCallDelta(
          index: 0,
          id: 'c',
          name: 'a__b',
          argumentsFragment: '{"x"',
        ),
        const ToolCallDelta(index: 0, argumentsFragment: ':1}'),
        const ToolCallComplete(call),
        const UsageEvent(ScriptedTurn.defaultUsage),
        const Done(StopReason.toolUse),
      ]);
      expectWellFormedChatStream(t.events);
    });

    test('error and hang', () {
      expect(ScriptedTurn.error(const NetworkException('x')).events, [
        const ErrorEvent(NetworkException('x')),
      ]);
      final hang = ScriptedTurn.hang(partialText: 'ab');
      expect(hang.events, [const TextDelta('ab')]);
      expect(hang.hangs, isTrue);
      expect(ScriptedTurn.events(const [Done(StopReason.other)]).events, [
        const Done(StopReason.other),
      ]);
    });
  });

  group('FakeLlmProvider', () {
    test('plays turns in order and records requests', () async {
      final p = FakeLlmProvider([
        ScriptedTurn.text('eins'),
        ScriptedTurn.text('zwei'),
      ]);
      expect(p.remainingTurns, 2);
      final first = await p.chat(req('a')).toList();
      final second = await p.chat(req('b')).toList();
      expect(first.whereType<TextDelta>().map((e) => e.text).join(), 'eins');
      expect(second.whereType<TextDelta>().map((e) => e.text).join(), 'zwei');
      expect(p.requests.map((r) => r.messages.single.text), ['a', 'b']);
      expect(p.remainingTurns, 0);
    });

    test('exhausted script ends with InvalidRequestException', () async {
      final p = FakeLlmProvider([]);
      final events = await p.chat(req('a')).toList();
      expect(events.single, isA<ErrorEvent>());
      expect(
        (events.single as ErrorEvent).error,
        isA<InvalidRequestException>(),
      );
      p.enqueue(ScriptedTurn.text('jetzt'));
      expect(await p.chat(req('b')).last, const Done(StopReason.endTurn));
    });

    test('stops at a terminal event inside raw events', () async {
      final p = FakeLlmProvider([
        ScriptedTurn.events(const [Done(StopReason.endTurn), TextDelta('nie')]),
      ]);
      expect(await p.chat(req('a')).toList(), [const Done(StopReason.endTurn)]);
    });

    test('cancel during delay ends with CancelledException quickly', () async {
      final p = FakeLlmProvider([
        ScriptedTurn.text('a' * 100, chunkSize: 1),
      ], eventDelay: const Duration(seconds: 1));
      final cancel = CancelToken();
      final watch = Stopwatch()..start();
      final future = p.chat(req('a'), cancel: cancel).toList();
      Timer(const Duration(milliseconds: 20), cancel.cancel);
      final events = await future;
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 900)));
      expect(events.single, const ErrorEvent(CancelledException()));
    });

    test('metadata: type, caps, models, test()', () async {
      final p = FakeLlmProvider([]);
      expect(p.type, ProviderType.fake);
      expect(p.caps.tools, isTrue);
      expect(await p.listModels(), [const ModelInfo(id: 'fake-model')]);
      final health = await p.test();
      expect(health.ok, isTrue);
      final custom = HealthCheck(
        ok: false,
        latency: Duration.zero,
        message: 'kaputt',
      );
      expect(await FakeLlmProvider([], health: custom).test(), custom);
    });
  });

  group('FakeTool', () {
    test('records calls and returns default outcome', () async {
      final t = FakeTool(name: 'a__b');
      final o = await t.execute({'x': 1}, ctx());
      expect(o.text, 'ok');
      expect(t.callCount, 1);
      expect(t.calls.single, {'x': 1});
      expect(t.describeForConfirmation({}), 'a__b ausführen');
      expect(t.risk, RiskLevel.read);
    });

    test('handler beats outcome; confirmation text configurable', () async {
      final t = FakeTool(
        name: 'a__b',
        outcome: ToolOutcome.text('fix'),
        handler: (args, _) => ToolOutcome.text('handler ${args['x']}'),
        confirmation: (args) => 'Lösche ${args['x']}',
      );
      expect((await t.execute({'x': 2}, ctx())).text, 'handler 2');
      expect(t.describeForConfirmation({'x': 3}), 'Lösche 3');
      expect(
        (await FakeTool(
          name: 'n',
          outcome: ToolOutcome.text('fix'),
        ).execute({}, ctx())).text,
        'fix',
      );
    });

    test('throws configured error', () async {
      final t = FakeTool(name: 'a__b', throws: StateError('kaputt'));
      await expectLater(t.execute({}, ctx()), throwsStateError);
      expect(t.callCount, 1);
    });

    test('withUndo attaches undo that counts', () async {
      final t = FakeTool(name: 'a__b', risk: RiskLevel.write, withUndo: true);
      final o = await t.execute({}, ctx());
      await o.undo!();
      expect(t.undoCount, 1);
    });

    test('delay is cut short by cancellation', () async {
      final cancel = CancelToken();
      final t = FakeTool(name: 'a__b', delay: const Duration(seconds: 5));
      Timer(const Duration(milliseconds: 10), cancel.cancel);
      await expectLater(
        t.execute({}, ctx(cancel: cancel)),
        throwsA(isA<CancelledException>()),
      );
    });

    test('delay completes normally', () async {
      final t = FakeTool(name: 'a__b', delay: const Duration(milliseconds: 5));
      expect((await t.execute({}, ctx())).text, 'ok');
    });
  });

  group('FakeIntegration', () {
    test('exposes configuration and counts availability checks', () async {
      final tool = FakeTool(name: 'cal__list');
      final i = FakeIntegration(
        id: 'cal',
        tools: [tool],
        sensitive: true,
        setup: const [
          SetupStep(
            id: 'perm',
            kind: SetupStepKind.permission,
            label: 'Erlauben',
          ),
        ],
        missingSteps: ['perm'],
      );
      expect(i.displayName, 'cal');
      expect(i.iconId, 'extension');
      expect(i.platforms, {AppPlatform.android, AppPlatform.ios});
      expect(i.tools, [tool]);
      expect(i.setup.single.id, 'perm');
      expect(i.sensitive, isTrue);
      expect(await i.checkAvailability(), Availability.yes);
      expect(i.availabilityChecks, 1);
      expect((await i.setupState()).complete, isFalse);
      i.missingSteps = [];
      expect((await i.setupState()).complete, isTrue);
    });
  });

  group('FakeToolCatalog / FakeToolInvoker', () {
    final read = FakeTool(name: 'x__read');
    final ext = FakeTool(
      name: 'x__send',
      risk: RiskLevel.external,
      confirmation: (_) => 'Senden?',
    );
    final boom = FakeTool(name: 'x__boom', throws: Exception('kaputt'));
    final catalog = FakeToolCatalog([read, ext, boom]);

    test('catalog lists specs and looks up by name', () {
      expect(catalog.activeSpecs().map((s) => s.name), [
        'x__read',
        'x__send',
        'x__boom',
      ]);
      expect(catalog.lookup('x__send'), same(ext));
      expect(catalog.lookup('nope'), isNull);
    });

    test(
      'invoker: unknown, invalid json, exception, confirmation yes/no',
      () async {
        final invoker = FakeToolInvoker(catalog);
        const calls = [
          ToolCallBlock(id: '1', name: 'x__read', argumentsJson: '{}'),
          ToolCallBlock(id: '2', name: 'nope', argumentsJson: '{}'),
          ToolCallBlock(id: '3', name: 'x__read', argumentsJson: 'kaputt'),
          ToolCallBlock(id: '4', name: 'x__boom', argumentsJson: '{}'),
          ToolCallBlock(id: '5', name: 'x__send', argumentsJson: '{}'),
          ToolCallBlock(id: '6', name: 'x__send', argumentsJson: '{}'),
        ];
        var answers = [true, false];
        final events = <ToolInvocationEvent>[];
        await for (final e in invoker.invokeAll(calls, ctx())) {
          events.add(e);
          if (e is ConfirmationNeeded) {
            expect(e.description, 'Senden?');
            e.decision.complete(answers.first);
            answers = answers.sublist(1);
          }
        }
        final finished = {
          for (final e in events.whereType<ToolFinished>())
            e.call.id: e.outcome,
        };
        expect(finished['1']!.isError, isFalse);
        expect(finished['2']!.isError, isTrue);
        expect(finished['3']!.isError, isTrue);
        expect(finished['4']!.isError, isTrue);
        expect(finished['5']!.isError, isFalse);
        expect(finished['6']!.text, 'Nutzer hat abgelehnt');
        expect(ext.callCount, 1);
        expect(events.whereType<ToolStarted>(), hasLength(6));
        expect(invoker.received, calls);
        expect(events.first.toString(), contains('ToolStarted'));
        expect(
          events.whereType<ConfirmationNeeded>().first.toString(),
          contains('Senden?'),
        );
        expect(events.last.toString(), contains('ToolFinished'));
      },
    );
  });
}
