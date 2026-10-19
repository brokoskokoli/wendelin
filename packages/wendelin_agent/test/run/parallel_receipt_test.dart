import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_agent/src/run/attestation_gate.dart';
import 'package:wendelin_agent/src/run/overlap_control.dart';
import 'package:wendelin_agent/src/run/run_state.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

/// Verifying provider with one pending receipt per model call, in call order
/// (WP81b: the next call starts while the previous receipt is open).
final class PerCallVerifying implements LlmProvider, AttestationAware {
  PerCallVerifying(this.inner, int calls)
    : receipts = [for (var i = 0; i < calls; i++) Completer()];

  final FakeLlmProvider inner;
  final List<Completer<AttestationReport?>> receipts;
  int _asked = 0;

  /// Cancel token each call was started with, in call order.
  final List<CancelToken?> tokens = [];

  /// Gate for the call with this index: it ignores cancellation and ends
  /// only when the gate completes (a provider that stops late).
  final Map<int, Completer<void>> lateCalls = {};

  @override
  ProviderType get type => inner.type;
  @override
  ProviderCapabilities get caps => inner.caps;
  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) async* {
    final index = tokens.length;
    tokens.add(cancel);
    final late = lateCalls[index];
    if (late == null) {
      yield* inner.chat(req, cancel: cancel);
      return;
    }
    final events = await inner.chat(req).toList();
    await late.future;
    for (final e in events) {
      yield e;
    }
  }

  @override
  Future<List<ModelInfo>> listModels() => inner.listModels();
  @override
  Future<HealthCheck> test() => inner.test();
  @override
  Stream<AttestationReport> get reports => const Stream.empty();
  @override
  Future<AttestationReport?> reportFor(ChatRequest request) =>
      receipts[_asked++].future;

  void settle(int i, AttestationStatus s) => receipts[i].complete(
    AttestationReport(logId: 'att-${i + 1}', status: s, detail: 'Hinweis'),
  );
}

/// Invoker with a risk policy: write tools run at once (like `ToolExecutor`).
final class PolicyInvoker implements ToolInvoker, ToolRiskAssessor {
  PolicyInvoker(this.inner);

  final FakeToolInvoker inner;

  @override
  RiskLevel effectiveRisk(Tool tool, String sessionId) => tool.risk;

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) => inner.invokeAll(calls, ctx);
}

/// Invoker that runs [onInvoke] when a round starts invoking.
final class HookInvoker implements ToolInvoker, ToolRiskAssessor {
  HookInvoker(this.inner, this.onInvoke);

  final PolicyInvoker inner;
  final void Function() onInvoke;

  @override
  RiskLevel effectiveRisk(Tool tool, String sessionId) =>
      inner.effectiveRisk(tool, sessionId);

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) async* {
    onInvoke();
    // Lets other calls of the run proceed before the tools answer.
    for (var i = 0; i < 50; i++) {
      await Future<void>.value();
    }
    yield* inner.invokeAll(calls, ctx);
  }
}

/// The text a listener shows: deltas, minus what a reset took back.
String shownText(List<AgentEvent> events) {
  final b = StringBuffer();
  for (final e in events) {
    if (e is AgentTextDelta) b.write(e.text);
    if (e is AgentTextReset) b.clear();
  }
  return '$b';
}

void main() {
  group('WP81b/c: nächster Modellaufruf parallel zur Quittung', () {
    late PerCallVerifying provider;
    late Harness h;
    late FakeTool undoable;
    late FakeTool second;
    late List<AgentEvent> events;

    void start(
      FakeAsync async,
      List<ScriptedTurn> turns, {
      List<Tool> Function(FakeTool undoable)? tools,
      int receipts = 3,
      AgentConfig config = const AgentConfig(),
      ToolInvoker Function(PolicyInvoker)? wrap,
      void Function(PerCallVerifying)? prepare,
    }) {
      undoable = FakeTool(
        name: 'calendar__create_event',
        risk: RiskLevel.write,
        withUndo: true,
      );
      second = FakeTool(
        name: 'calendar__delete_all',
        risk: RiskLevel.write,
        withUndo: true,
      );
      provider = PerCallVerifying(FakeLlmProvider(turns), receipts);
      prepare?.call(provider);
      final all = tools == null ? [undoable, second] : tools(undoable);
      final policy = PolicyInvoker(FakeToolInvoker(FakeToolCatalog(all)));
      h = Harness(
        config: config,
        invoker: wrap == null ? policy : wrap(policy),
        primary: ProviderTarget(
          profileId: 'tee',
          modelId: 'm',
          provider: provider,
          privacy: PrivacyLevel.tee,
        ),
        tools: all,
      );
      events = [];
      h.runner.run(UserInput(text: 'Hi')).listen(events.add);
      async.flushMicrotasks();
    }

    int indexOfStatus(String id, AttestationStatus s) => events.indexWhere(
      (e) => e is AttestationStatusChanged && e.stepId == id && e.status == s,
    );

    final toolTurn = ScriptedTurn.toolCalls([
      call('c1', 'calendar__create_event'),
    ]);

    test('Aufruf startet vor der Quittung, Ausgabe läuft sofort (WP81c)', () {
      fakeAsync((async) {
        start(async, [toolTurn, ScriptedTurn.text('Fertig.')]);
        expect(
          provider.inner.requests,
          hasLength(2),
          reason: 'zweiter Aufruf läuft, Quittung 1 ist offen',
        );
        expect(undoable.callCount, 1);
        expect(
          lastResults(provider.inner.requests.last).single.isError,
          isFalse,
        );
        // Text and speech events before the green receipt.
        expect(streamedText(events), 'Fertig.');
        expect(events.whereType<AgentTextComplete>(), hasLength(1));
        expect(indexOfStatus('s1:1', AttestationStatus.green), -1);
        expect(events.whereType<UsageReported>(), hasLength(2));
        final firstText = events.indexWhere((e) => e is AgentTextDelta);

        provider.settle(0, AttestationStatus.green);
        async.flushMicrotasks();
        final green = indexOfStatus('s1:1', AttestationStatus.green);
        expect(green, greaterThan(firstText), reason: 'Text vor Quittung 1');
        expect(events.whereType<AgentTextReset>(), isEmpty);
        expect(streamedText(events), 'Fertig.');
        expect(
          events.last,
          isNot(isA<AgentDone>()),
          reason: 'Quittung 2 offen',
        );

        provider.settle(1, AttestationStatus.green);
        async.flushMicrotasks();
        final done = events.last as AgentDone;
        expect(done.finalText, 'Fertig.');
        expect(indexOfStatus('s1:2', AttestationStatus.green), isNonNegative);
        expect(undoable.undoCount, 0);
        // Results recorded once, in order, with the answer after them.
        final roles = h.conversation.messages.map((m) => m.role).toList();
        expect(roles, [Role.user, Role.assistant, Role.tool, Role.assistant]);
      });
    });

    test('Rot nach fertigem Aufruf: verworfen, kein Tool, Undo, Meldung', () {
      fakeAsync((async) {
        start(async, [
          toolTurn,
          ScriptedTurn.toolCalls([
            call('c2', 'calendar__delete_all'),
          ], text: 'Verworfen'),
          ScriptedTurn.text('Zurückgenommen.'),
        ]);
        expect(provider.inner.requests, hasLength(2));
        provider.settle(0, AttestationStatus.red);
        async.flushMicrotasks();

        expect(second.callCount, 0, reason: 'Tool der neuen Runde nie');
        expect(undoable.undoCount, 1);
        // The text was shown at once, then taken back before the red status.
        expect(streamedText(events).startsWith('Verworfen'), isTrue);
        final reset = events.indexWhere((e) => e is AgentTextReset);
        final red = indexOfStatus('s1:1', AttestationStatus.red);
        expect(events.whereType<AgentTextReset>(), hasLength(1));
        expect(reset, isNonNegative);
        expect(red, greaterThan(reset), reason: 'Reset vor roter Quittung');
        expect(
          events.indexWhere((e) => e is ToolCallStarted && e.call.id == 'c2'),
          -1,
          reason: 'Tool-Events der verworfenen Runde nie',
        );
        expect(shownText(events), 'Zurückgenommen.');
        expect(provider.inner.requests, hasLength(3), reason: 'Neuaufruf');
        expect(
          lastResults(provider.inner.requests.last).single.isError,
          isTrue,
          reason: 'das Modell sieht das Rückgängig-Ergebnis',
        );
        expect(
          events.whereType<ToolCallFinished>().last.outcome.summary,
          contains('Rückgängig gemacht'),
        );
        // Exactly one result message for c1 (the provisional one is gone).
        final resultsOfC1 = provider.inner.requests.last.messages
            .where((m) => m.role == Role.tool)
            .expand((m) => m.content)
            .whereType<ToolResultBlock>()
            .where((r) => r.callId == 'c1');
        expect(resultsOfC1, hasLength(1));
        // The dropped call was cancelled, the sequential ones were not.
        expect(provider.tokens[1]!.isCancelled, isTrue);
        expect(provider.tokens[2]!.isCancelled, isFalse);
        // Paid tokens of the discarded call are still reported.
        expect(events.whereType<UsageReported>(), hasLength(3));

        provider.settle(2, AttestationStatus.green);
        async.flushMicrotasks();
        expect((events.last as AgentDone).finalText, 'Zurückgenommen.');
        final calls = h.conversation.messages
            .expand((m) => m.toolCalls)
            .map((c) => c.id);
        expect(calls, ['c1'], reason: 'verworfene Antwort nicht im Verlauf');
        expect(
          events
              .whereType<AttestationStatusChanged>()
              .where((e) => e.status != AttestationStatus.yellow)
              .map((e) => e.stepId),
          isNot(contains('s1:2')),
          reason: 'keine Quittung für den verworfenen Schritt',
        );
        final texts = h.conversation.messages
            .where((m) => m.role == Role.assistant)
            .map((m) => m.text)
            .join();
        expect(texts.contains('Verworfen'), isFalse);
      });
    });

    test('Rot ohne Text im verworfenen Aufruf: kein Reset', () {
      fakeAsync((async) {
        start(async, [
          toolTurn,
          ScriptedTurn.toolCalls([call('c2', 'calendar__delete_all')]),
          ScriptedTurn.text('Danach.'),
        ]);
        provider.settle(0, AttestationStatus.red);
        async.flushMicrotasks();
        expect(events.whereType<AgentTextReset>(), isEmpty);
        expect(second.callCount, 0);
        expect(undoable.undoCount, 1);
      });
    });

    const used = Usage(inputTokens: 40);

    test('Token-Budget gilt über die parallele Runde', () {
      fakeAsync((async) {
        start(async, [
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__create_event'),
          ], usage: used),
          ScriptedTurn.toolCalls([
            call('c2', 'calendar__delete_all'),
          ], usage: used),
          ScriptedTurn.text('nie'),
        ], config: const AgentConfig(maxTokensPerRequest: 70));
        provider.settle(0, AttestationStatus.green);
        async.flushMicrotasks();
        expect(second.callCount, 0, reason: '40 + 40 ≥ 70: Runde verweigert');
        expect((events.last as AgentFailed).error, AgentErrorKind.tokenBudget);
        expect(provider.inner.requests, hasLength(2));
      });
    });

    test('Token-Budget zählt auch den verworfenen Aufruf', () {
      fakeAsync((async) {
        start(async, [
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__create_event'),
          ], usage: used),
          ScriptedTurn.text('verworfen', usage: used),
          ScriptedTurn.text('nie'),
        ], config: const AgentConfig(maxTokensPerRequest: 70));
        provider.settle(0, AttestationStatus.red);
        async.flushMicrotasks();
        expect((events.last as AgentFailed).error, AgentErrorKind.tokenBudget);
        expect(provider.inner.requests, hasLength(2), reason: 'kein Neuaufruf');
        expect(events.whereType<UsageReported>(), hasLength(2));
      });
    });

    test('Ergebnisse stehen nach Grün im Verlauf, auch bei Abbruch danach', () {
      fakeAsync((async) {
        start(async, [toolTurn, ScriptedTurn.hang(partialText: 'halb')]);
        provider.settle(0, AttestationStatus.green);
        async.flushMicrotasks();
        h.runner.cancel();
        async.flushMicrotasks();
        expect((events.last as AgentFailed).error, AgentErrorKind.cancelled);
        final roles = h.conversation.messages.map((m) => m.role).toList();
        expect(roles, [Role.user, Role.assistant, Role.tool]);
      });
    });

    test(
      'verworfener Aufruf endet spät: externe Runde nutzt eigene Quittung',
      () {
        fakeAsync((async) {
          final sms = FakeTool(
            name: 'sms__send',
            risk: RiskLevel.external,
            confirmation: (_) => 'SMS',
          );
          start(
            async,
            [
              toolTurn,
              ScriptedTurn.text('Verworfen'),
              ScriptedTurn.toolCalls([
                call('c3', 'calendar__create_event'),
                call('c4', 'sms__send'),
              ]),
              ScriptedTurn.text('Fertig.'),
            ],
            tools: (undoable) => [undoable, sms],
            receipts: 4,
            prepare: (p) => p.lateCalls[1] = Completer<void>(),
            // The late call ends while the round of the sequential call runs.
            wrap: (policy) => HookInvoker(policy, () {
              final late = provider.lateCalls[1]!;
              if (provider.inner.requests.length >= 3 && !late.isCompleted) {
                late.complete();
              }
            }),
          );
          provider.settle(0, AttestationStatus.red);
          async.flushMicrotasks();
          // The late call has begun its step after the sequential one.
          expect(provider.inner.requests, hasLength(3));
          provider.settle(2, AttestationStatus.green);
          async.flushMicrotasks();
          for (final c in events.whereType<ConfirmationRequired>()) {
            c.respond(true);
          }
          async.flushMicrotasks();
          expect(sms.callCount, 0, reason: 'Quittung 2 gehört dem Neuaufruf');
          provider.settle(1, AttestationStatus.red);
          async.flushMicrotasks();
          for (final c in events.whereType<ConfirmationRequired>()) {
            c.respond(true);
          }
          async.flushMicrotasks();
          expect(sms.callCount, 0, reason: 'eigene Quittung rot');
          expect(
            events.whereType<UsageReported>(),
            hasLength(4),
            reason: 'auch der spät endende, verworfene Aufruf wird bezahlt',
          );
        });
      },
    );

    test('Rot bei hängendem Aufruf: Aufruf wird abgebrochen', () {
      fakeAsync((async) {
        start(async, [
          toolTurn,
          ScriptedTurn.hang(partialText: 'halb'),
          ScriptedTurn.text('Danach.'),
        ]);
        provider.settle(0, AttestationStatus.unconfirmed);
        async.flushMicrotasks();
        expect(undoable.undoCount, 1);
        expect(shownText(events), 'Danach.', reason: '„halb“ verworfen');
        expect(provider.inner.requests, hasLength(3));
        expect(provider.inner.remainingTurns, 0);
      });
    });

    test('external-Tool der parallelen Runde wartet auf Grün, bei Rot nie', () {
      for (final green in [true, false]) {
        fakeAsync((async) {
          final sms = FakeTool(
            name: 'sms__send',
            risk: RiskLevel.external,
            confirmation: (_) => 'SMS',
          );
          start(
            async,
            [
              toolTurn,
              ScriptedTurn.toolCalls([call('c2', 'sms__send')], text: 'Sende'),
              ScriptedTurn.text('Fertig.'),
            ],
            tools: (undoable) => [undoable, sms],
            receipts: 3,
          );
          expect(streamedText(events), 'Sende', reason: 'Text sofort');
          expect(events.whereType<ConfirmationRequired>(), isEmpty);
          expect(sms.callCount, 0);
          provider.settle(
            0,
            green ? AttestationStatus.green : AttestationStatus.red,
          );
          async.flushMicrotasks();
          if (green) {
            provider.settle(1, AttestationStatus.green);
            async.flushMicrotasks();
            for (final c in events.whereType<ConfirmationRequired>()) {
              c.respond(true);
            }
            async.flushMicrotasks();
            expect(sms.callCount, 1);
          } else {
            expect(events.whereType<ConfirmationRequired>(), isEmpty);
            expect(sms.callCount, 0);
            expect(events.whereType<AgentTextReset>(), hasLength(1));
          }
        });
      }
    });

    test('external-Runde bleibt sequentiell', () {
      fakeAsync((async) {
        final sms = FakeTool(
          name: 'sms__send',
          risk: RiskLevel.external,
          confirmation: (_) => 'SMS',
        );
        start(
          async,
          [
            ScriptedTurn.toolCalls([
              call('c1', 'calendar__create_event'),
              call('c2', 'sms__send'),
            ]),
            ScriptedTurn.text('Fertig.'),
          ],
          tools: (undoable) => [undoable, sms],
          receipts: 2,
        );
        expect(provider.inner.requests, hasLength(1));
        expect(sms.callCount, 0);
        provider.settle(0, AttestationStatus.green);
        async.flushMicrotasks();
        for (final c in events.whereType<ConfirmationRequired>()) {
          c.respond(true);
        }
        async.flushMicrotasks();
        expect(provider.inner.requests, hasLength(2));
        expect(sms.callCount, 1);
      });
    });

    test('Abbruch während Aufruf und Quittung beendet beides', () {
      fakeAsync((async) {
        start(async, [toolTurn, ScriptedTurn.hang(partialText: 'halb')]);
        expect(provider.inner.requests, hasLength(2));
        h.runner.cancel();
        async.flushMicrotasks();
        final failed = events.last as AgentFailed;
        expect(failed.error, AgentErrorKind.cancelled);
        expect(events.whereType<AgentTextReset>(), isEmpty);
        expect(undoable.callCount, 1, reason: 'keine doppelte Ausführung');
        expect(second.callCount, 0);
        expect(async.pendingTimers, isEmpty);
        // The late receipt after the abort changes nothing.
        provider.settle(0, AttestationStatus.green);
        async.flushMicrotasks();
        expect(events.last, same(failed));
      });
    });

    test('Aufruf ohne Prüfung (kein TEE) läuft wie bisher sequentiell', () {
      fakeAsync((async) {
        final (a, plain) = scripted('a', [
          toolTurn,
          ScriptedTurn.text('Fertig.'),
        ]);
        final tool = FakeTool(name: 'calendar__create_event');
        final plainH = Harness(primary: a, tools: [tool]);
        final out = <AgentEvent>[];
        plainH.runner.run(UserInput(text: 'Hi')).listen(out.add);
        async.flushMicrotasks();
        expect(plain.requests, hasLength(2));
        expect(out.last, isA<AgentDone>());
      });
    });
  });

  group('WP81b/c: Bausteine', () {
    test(
      'AttestationGate: spätere Schritte überschreiben den früheren nicht',
      () {
        fakeAsync((async) {
          final out = <AgentEvent>[];
          final real = _Recorder(out);
          final gate = AttestationGate(real, 's');
          final buffered = OverlapControl(real);
          final p1 = PerCallVerifying(FakeLlmProvider([]), 2);
          final request = ChatRequest(
            messages: const [],
            model: 'm',
            maxTokens: 1,
            systemPrompt: '',
          );
          final first = gate.begin(p1, request);
          final second = gate.begin(p1, request, sink: buffered);
          p1.settle(0, AttestationStatus.red);
          gate.settle(first);
          async.flushMicrotasks();
          final final1 = out.whereType<AttestationStatusChanged>().last;
          expect(final1.stepId, 's:1');
          expect(final1.status, AttestationStatus.red);
          expect(second.id, 's:2');
          // Step 2 goes through the overlap control to the run (yellow).
          expect(out.whereType<AttestationStatusChanged>(), hasLength(3));
          expect(out.whereType<AttestationStatusChanged>().last.stepId, 's:1');
        });
      },
    );

    test(
      'OverlapControl: reicht durch, discard setzt zurück und bricht ab',
      () {
        final out = <AgentEvent>[];
        final b = OverlapControl(_Recorder(out));
        b.emit(const AgentTextDelta('a'));
        expect(out, hasLength(1), reason: 'sofort durchgereicht');
        b.discard();
        b.discard();
        expect(out.last, isA<AgentTextReset>());
        expect(out.whereType<AgentTextReset>(), hasLength(1));
        b.emit(const AgentTextDelta('b'));
        b.emit(
          const UsageReported(
            profileId: 'p',
            modelId: 'm',
            usage: Usage(inputTokens: 1),
          ),
        );
        expect(out, hasLength(3), reason: 'nur Usage nach dem Verwerfen');
        expect(b.token.isCancelled, isTrue);
      },
    );

    test('OverlapControl: abandon bricht ohne Reset ab, verified schützt', () {
      final out = <AgentEvent>[];
      final b = OverlapControl(_Recorder(out))..emit(const AgentTextDelta('a'));
      b.abandon();
      expect(out.whereType<AgentTextReset>(), isEmpty);
      expect(b.token.isCancelled, isTrue);
      final ok = OverlapControl(_Recorder(out))..verified();
      ok.abandon();
      expect(ok.token.isCancelled, isFalse);
    });
  });
}

final class _Recorder implements RunControl {
  _Recorder(this.out);

  final List<AgentEvent> out;
  @override
  final token = CancelToken();
  @override
  bool get segmentStreamed => false;
  @override
  void emit(AgentEvent e) => out.add(e);
  @override
  void throwIfAborted() {}
}
