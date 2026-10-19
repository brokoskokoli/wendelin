import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_agent/src/run/attestation_gate.dart';
import 'package:wendelin_agent/src/run/buffered_control.dart';
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

  @override
  ProviderType get type => inner.type;
  @override
  ProviderCapabilities get caps => inner.caps;
  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) =>
      inner.chat(req, cancel: cancel);
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

void main() {
  group('WP81b: nächster Modellaufruf parallel zur Quittung', () {
    late PerCallVerifying provider;
    late Harness h;
    late FakeTool undoable;
    late FakeTool second;
    late List<AgentEvent> events;

    void start(
      FakeAsync async,
      List<ScriptedTurn> turns, {
      List<Tool>? tools,
      int receipts = 3,
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
      final all = tools ?? [undoable, second];
      h = Harness(
        invoker: PolicyInvoker(FakeToolInvoker(FakeToolCatalog(all))),
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

    test('Aufruf startet vor der Quittung, Ausgabe wartet auf Grün', () {
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
        expect(streamedText(events), isEmpty, reason: 'gepuffert');
        expect(indexOfStatus('s1:2', AttestationStatus.yellow), -1);
        expect(events.whereType<UsageReported>(), hasLength(1));

        provider.settle(0, AttestationStatus.green);
        async.flushMicrotasks();
        final green = indexOfStatus('s1:1', AttestationStatus.green);
        final yellow2 = indexOfStatus('s1:2', AttestationStatus.yellow);
        final firstText = events.indexWhere((e) => e is AgentTextDelta);
        expect(green, isNonNegative);
        expect(yellow2, greaterThan(green), reason: 'Schritt 2 nach Grün 1');
        expect(firstText, greaterThan(green));
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
        expect(events.whereType<UsageReported>(), hasLength(2));
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
        expect(streamedText(events).contains('Verworfen'), isFalse);
        expect(indexOfStatus('s1:2', AttestationStatus.yellow), -1);
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
        expect(streamedText(events), 'Zurückgenommen.');
        // The discarded call's tokens and usage are not counted.
        expect(events.whereType<UsageReported>(), hasLength(2));

        provider.settle(2, AttestationStatus.green);
        async.flushMicrotasks();
        expect((events.last as AgentDone).finalText, 'Zurückgenommen.');
        final calls = h.conversation.messages
            .expand((m) => m.toolCalls)
            .map((c) => c.id);
        expect(calls, ['c1'], reason: 'verworfene Antwort nicht im Verlauf');
        expect(
          events.whereType<AttestationStatusChanged>().map((e) => e.stepId),
          isNot(contains('s1:2')),
        );
      });
    });

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
        expect(streamedText(events), 'Danach.', reason: '„halb“ verworfen');
        expect(provider.inner.requests, hasLength(3));
        expect(provider.inner.remainingTurns, 0);
      });
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
          tools: [undoable, sms],
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
        expect(streamedText(events), isEmpty);
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

  group('WP81b: Bausteine', () {
    test(
      'AttestationGate: spätere Schritte überschreiben den früheren nicht',
      () {
        fakeAsync((async) {
          final out = <AgentEvent>[];
          final real = _Recorder(out);
          final gate = AttestationGate(real, 's');
          final buffered = BufferedControl(real);
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
          expect(gate.last, same(second));
          // Step 2 goes to the buffer, not to the run.
          expect(out.whereType<AttestationStatusChanged>(), hasLength(2));
          buffered.release();
          expect(out.whereType<AttestationStatusChanged>().last.stepId, 's:2');
        });
      },
    );

    test('BufferedControl: discard verwirft Gepuffertes und bricht ab', () {
      final out = <AgentEvent>[];
      final b = BufferedControl(_Recorder(out));
      b.emit(const AgentTextDelta('a'));
      expect(out, isEmpty);
      b.discard();
      b.release();
      b.emit(const AgentTextDelta('b'));
      expect(out, isEmpty);
      expect(b.token.isCancelled, isTrue);
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
