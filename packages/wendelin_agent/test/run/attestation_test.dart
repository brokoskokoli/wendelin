import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

/// A scripted provider that verifies its answers afterwards, like the
/// `AttestedProvider` (WP46): [report] completes when the receipt check ends.
final class VerifyingFake implements LlmProvider, AttestationAware {
  VerifyingFake(this.inner, this.report);

  final FakeLlmProvider inner;
  final Completer<AttestationReport?> report;

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
  Future<AttestationReport?> reportFor(ChatRequest request) => report.future;
}

/// Invoker whose policy makes some tools confirm-only (effective
/// `external`), like `ToolExecutor` with user overrides.
final class AssessingInvoker implements ToolInvoker, ToolRiskAssessor {
  AssessingInvoker(this.inner, this.stricter);

  final FakeToolInvoker inner;
  final Set<String> stricter;

  @override
  RiskLevel effectiveRisk(Tool tool, String sessionId) =>
      stricter.contains(tool.name) ? RiskLevel.external : tool.risk;

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) => inner.invokeAll(calls, ctx);
}

AttestationReport _report(AttestationStatus s) => AttestationReport(
  logId: 'att-1',
  status: s,
  detail: 'Hinweis',
  reasonCode: s == AttestationStatus.red ? 'upstream_session_mismatch' : null,
);

void main() {
  group('Agent-Schleife: Prüfstatus und externe Tools bei TEE-Antworten', () {
    Harness build(
      List<ScriptedTurn> turns,
      Completer<AttestationReport?> report,
      List<Tool> tools,
    ) {
      final provider = VerifyingFake(FakeLlmProvider(turns), report);
      return Harness(
        primary: ProviderTarget(
          profileId: 'tee',
          modelId: 'tee-model',
          provider: provider,
          privacy: PrivacyLevel.tee,
        ),
        tools: tools,
      );
    }

    test(
      'Antwort ohne Tools: Status kommt als Ereignis vor dem Ende',
      () async {
        final report = Completer<AttestationReport?>()
          ..complete(_report(AttestationStatus.green));
        final h = build([ScriptedTurn.text('Hallo')], report, []);
        final events = await h.run('Hi');
        final all = events.whereType<AttestationStatusChanged>().toList();
        expect(
          all.first.status,
          AttestationStatus.yellow,
          reason: 'zuerst „wird geprüft“ (ohne Protokoll-Id)',
        );
        expect(all.first.logId, isEmpty);
        expect(all.first.stepId, 's1:1');
        final status = all.last;
        expect(all, hasLength(2));
        expect(status.status, AttestationStatus.green);
        expect(status.logId, 'att-1');
        expect(status.detail, 'Hinweis');
        expect(status.reasonCode, isNull);
        expect(status.stepId, 's1:1');
        expect(
          events.indexOf(status),
          lessThan(events.indexOf(terminal(events))),
        );
      },
    );

    test(
      'WP81: AgentTextComplete kommt vor der Quittung, nicht danach',
      () async {
        final report = Completer<AttestationReport?>();
        final h = build([ScriptedTurn.text('Hallo.')], report, []);
        var receiptPending = false;
        final events = await h
            .run(
              'Hi',
              onEvent: (e) {
                // The receipt is only released after the text is complete.
                if (e is AgentTextComplete) {
                  receiptPending = !report.isCompleted;
                  report.complete(_report(AttestationStatus.green));
                }
              },
            )
            .timeout(const Duration(seconds: 5));
        expect(receiptPending, isTrue, reason: 'Quittung noch offen');
        final complete = events.indexWhere((e) => e is AgentTextComplete);
        final green = events.indexWhere(
          (e) =>
              e is AttestationStatusChanged &&
              e.status == AttestationStatus.green,
        );
        expect(complete, isNonNegative);
        expect(complete, lessThan(green));
      },
    );

    test(
      'WP81: mit Tool-Aufruf kein AgentTextComplete im Zwischenschritt',
      () async {
        final report = Completer<AttestationReport?>()
          ..complete(_report(AttestationStatus.green));
        final tool = FakeTool(name: 'light', risk: RiskLevel.read);
        final h = build(
          [
            ScriptedTurn.toolCalls([call('c1', 'light')]),
            ScriptedTurn.text('Fertig.'),
          ],
          report,
          [tool],
        );
        final events = await h.run('Licht');
        expect(events.whereType<AgentTextComplete>(), hasLength(1));
        expect(
          events.indexWhere((e) => e is AgentTextComplete),
          greaterThan(events.indexWhere((e) => e is ToolCallFinished)),
        );
      },
    );

    test('WP81: pauseTurn → kein AgentTextComplete', () async {
      final report = Completer<AttestationReport?>()
        ..complete(_report(AttestationStatus.green));
      final h = build(
        [
          ScriptedTurn.text('Teil eins.', stopReason: StopReason.pauseTurn),
          ScriptedTurn.text('Teil zwei.'),
        ],
        report,
        [],
      );
      final events = await h.run('Hi');
      expect(events.whereType<AgentTextComplete>(), hasLength(1));
      final lastText = events.lastIndexWhere((e) => e is AgentTextDelta);
      expect(
        events.indexWhere((e) => e is AgentTextComplete),
        greaterThan(lastText),
      );
    });

    test('WP81: Fehler nach Text → kein AgentTextComplete', () async {
      final report = Completer<AttestationReport?>()
        ..complete(_report(AttestationStatus.green));
      final h = build(
        [
          ScriptedTurn.error(
            const NetworkException('weg'),
            partialText: 'Halber Satz',
          ),
        ],
        report,
        [],
      );
      final events = await h.run('Hi');
      expect(events.whereType<AgentTextComplete>(), isEmpty);
    });

    test('toolsInvolved der Quittung gelangt ins Ereignis (WP63)', () async {
      final report = Completer<AttestationReport?>()
        ..complete(_report(AttestationStatus.green).withToolsInvolved(true));
      final h = build([ScriptedTurn.text('Hallo')], report, []);
      final events = await h.run('Hi');
      final all = events.whereType<AttestationStatusChanged>().toList();
      expect(all.first.toolsInvolved, isFalse, reason: 'gelb: noch unbekannt');
      expect(all.last.toolsInvolved, isTrue);
    });

    test('external-Tool wartet auf die Quittung und läuft bei Grün', () async {
      final sms = FakeTool(
        name: 'sms__send',
        risk: RiskLevel.external,
        confirmation: (_) => 'SMS senden',
      );
      final report = Completer<AttestationReport?>();
      final h = build(
        [
          ScriptedTurn.toolCalls([call('c1', 'sms__send')]),
          ScriptedTurn.text('Gesendet.'),
        ],
        report,
        [sms],
      );
      final events = <AgentEvent>[];
      final done = h.run(
        'Schreib',
        onEvent: (e) {
          events.add(e);
          if (e is ConfirmationRequired) e.respond(true);
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sms.callCount, 0, reason: 'Quittung noch nicht geprüft');
      expect(events.whereType<ToolCallStarted>(), isEmpty);
      report.complete(_report(AttestationStatus.green));
      final all = await done;
      expect(sms.callCount, 1);
      expect(
        all
            .whereType<AttestationStatusChanged>()
            .where((e) => e.logId.isNotEmpty)
            .map((e) => e.status),
        [AttestationStatus.green, AttestationStatus.green],
        reason: 'ein Endergebnis je Modellaufruf (Tool-Runde und Antwort)',
      );
      expect(terminal(all), isA<AgentDone>());
    });

    test('external-Tool startet bei roter Quittung gar nicht', () async {
      final sms = FakeTool(
        name: 'sms__send',
        risk: RiskLevel.external,
        confirmation: (_) => 'SMS senden',
      );
      final report = Completer<AttestationReport?>()
        ..complete(_report(AttestationStatus.red));
      final provider = VerifyingFake(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([call('c1', 'sms__send')]),
          ScriptedTurn.text('Nicht gesendet.'),
        ]),
        report,
      );
      final h = Harness(
        primary: ProviderTarget(
          profileId: 'tee',
          modelId: 'm',
          provider: provider,
          privacy: PrivacyLevel.tee,
        ),
        tools: [sms],
      );
      final events = await h.run(
        'Schreib',
        onEvent: (e) {
          if (e is ConfirmationRequired) fail('keine Bestätigung bei Rot');
        },
      );
      expect(sms.callCount, 0);
      final finished = events.whereType<ToolCallFinished>().single;
      expect(finished.outcome.isError, isTrue);
      expect(
        events
            .whereType<AttestationStatusChanged>()
            .where((e) => e.logId.isNotEmpty)
            .map((e) => e.stepId),
        ['s1:1', 's1:2'],
      );
      expect(
        events
            .whereType<AttestationStatusChanged>()
            .firstWhere((e) => e.logId.isNotEmpty)
            .status,
        AttestationStatus.red,
      );
      expect(
        events
            .whereType<AttestationStatusChanged>()
            .firstWhere((e) => e.logId.isNotEmpty)
            .reasonCode,
        'upstream_session_mismatch',
      );
      expect(
        provider.inner.requests,
        hasLength(2),
        reason: 'Ergebnis geht ans Modell',
      );
    });

    test('Lese-Tools laufen sofort, ohne auf die Quittung zu warten', () async {
      final read = FakeTool(name: 'cal__list', outcome: ToolOutcome.text('2'));
      final sms = FakeTool(
        name: 'sms__send',
        risk: RiskLevel.external,
        confirmation: (_) => 'SMS',
      );
      final report = Completer<AttestationReport?>();
      final h = build(
        [
          ScriptedTurn.toolCalls([
            call('c1', 'cal__list'),
            call('c2', 'sms__send'),
          ]),
          ScriptedTurn.text('Fertig.'),
        ],
        report,
        [read, sms],
      );
      final done = h.run(
        'Hi',
        onEvent: (e) {
          if (e is ConfirmationRequired) e.respond(true);
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(read.callCount, 1);
      expect(sms.callCount, 0);
      report.complete(_report(AttestationStatus.green));
      await done;
      expect(sms.callCount, 1);
    });

    test('Provider ohne Prüfung: externe Tools laufen wie bisher', () async {
      final sms = FakeTool(
        name: 'sms__send',
        risk: RiskLevel.external,
        confirmation: (_) => 'SMS',
      );
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'sms__send')]),
        ScriptedTurn.text('Gesendet.'),
      ]);
      final h = Harness(primary: a, tools: [sms]);
      final events = await h.run(
        'Hi',
        onEvent: (e) {
          if (e is ConfirmationRequired) e.respond(true);
        },
      );
      expect(sms.callCount, 1);
      expect(events.whereType<AttestationStatusChanged>(), isEmpty);
    });

    test(
      'kein Bericht (null): external-Tool erreicht den Invoker nie',
      () async {
        final sms = FakeTool(
          name: 'sms__send',
          risk: RiskLevel.external,
          confirmation: (_) => 'SMS',
        );
        final report = Completer<AttestationReport?>()..complete(null);
        final h = build(
          [
            ScriptedTurn.toolCalls([call('c1', 'sms__send')]),
            ScriptedTurn.text('Nicht gesendet.'),
          ],
          report,
          [sms],
        );
        final events = await h.run(
          'Hi',
          onEvent: (e) {
            if (e is ConfirmationRequired) {
              fail('keine Bestätigung ohne Bericht');
            }
          },
        );
        expect(sms.callCount, 0);
        expect(h.invoker is FakeToolInvoker, isTrue);
        expect((h.invoker as FakeToolInvoker).received, isEmpty);
        expect(
          events.whereType<ToolCallFinished>().single.outcome.isError,
          isTrue,
        );
      },
    );

    Future<(FakeTool, Completer<AttestationReport?>, Future<List<AgentEvent>>)>
    startWithStricter(
      FakeTool tool,
      Set<String>? stricter, {
      void Function(String, ToolCallBlock)? onUndoFailed,
    }) async {
      final report = Completer<AttestationReport?>();
      final provider = VerifyingFake(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([call('c1', tool.name)]),
          ScriptedTurn.text('Fertig.'),
        ]),
        report,
      );
      final catalog = FakeToolCatalog([tool]);
      final h = Harness(
        primary: ProviderTarget(
          profileId: 'tee',
          modelId: 'm',
          provider: provider,
          privacy: PrivacyLevel.tee,
        ),
        tools: [tool],
        invoker: stricter == null
            ? FakeToolInvoker(catalog)
            : AssessingInvoker(FakeToolInvoker(catalog), stricter),
        onUndoFailed: onUndoFailed,
      );
      final done = h.run('Hi');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return (tool, report, done);
    }

    test(
      'Nutzer-Verschärfung read zu confirm wartet auf die Quittung',
      () async {
        final read = FakeTool(
          name: 'cal__list',
          outcome: ToolOutcome.text('2'),
        );
        final (_, report, done) = await startWithStricter(read, {'cal__list'});
        expect(read.callCount, 0, reason: 'effektiv external: wartet');
        report.complete(_report(AttestationStatus.green));
        await done;
        expect(read.callCount, 1);
      },
    );

    test(
      'MCP-write ohne autoRun (effektiv external) wartet, bei Rot nie',
      () async {
        final write = FakeTool(
          name: 'mcp__notes__add',
          risk: RiskLevel.write,
          outcome: ToolOutcome.text('ok'),
        );
        final (_, report, done) = await startWithStricter(write, {write.name});
        expect(write.callCount, 0);
        report.complete(_report(AttestationStatus.red));
        await done;
        expect(write.callCount, 0);
      },
    );

    test(
      'Quittung nicht bestätigt (grau): external-Tool läuft nicht',
      () async {
        final write = FakeTool(
          name: 'mcp__notes__add',
          risk: RiskLevel.write,
          outcome: ToolOutcome.text('ok'),
        );
        final (_, report, done) = await startWithStricter(write, {write.name});
        report.complete(_report(AttestationStatus.unconfirmed));
        await done;
        expect(write.callCount, 0);
      },
    );

    test(
      'write-Tool mit Undo läuft sofort, Rot nimmt es zurück (WP77)',
      () async {
        final cal = FakeTool(
          name: 'calendar__create_event',
          risk: RiskLevel.write,
          withUndo: true,
        );
        final (_, report, done) = await startWithStricter(cal, {});
        expect(cal.callCount, 1, reason: 'läuft vor der Quittung');
        expect(cal.undoCount, 0, reason: 'noch nicht zurückgenommen');
        report.complete(_report(AttestationStatus.red));
        final all = await done;
        expect(cal.undoCount, 1, reason: 'Rot nimmt die Aktion zurück');
        final finished = all.whereType<ToolCallFinished>().toList();
        expect(finished, hasLength(2));
        expect(finished.first.outcome.undo, isNotNull);
        expect(finished.last.outcome.isError, isTrue);
        expect(finished.last.outcome.undo, isNull);
        expect(finished.last.outcome.summary, contains('Rückgängig gemacht'));
      },
    );

    test(
      'Quittung nicht bestätigt (grau): Undo-Tool wird zurückgenommen',
      () async {
        final cal = FakeTool(
          name: 'calendar__create_event',
          risk: RiskLevel.write,
          withUndo: true,
        );
        final (_, report, done) = await startWithStricter(cal, {});
        report.complete(_report(AttestationStatus.unconfirmed));
        await done;
        expect(cal.undoCount, 1, reason: 'alles außer Grün nimmt zurück');
      },
    );

    test('write-Tool mit Undo bleibt bei grüner Quittung bestehen', () async {
      final cal = FakeTool(
        name: 'calendar__create_event',
        risk: RiskLevel.write,
        withUndo: true,
      );
      final (_, report, done) = await startWithStricter(cal, {});
      report.complete(_report(AttestationStatus.green));
      final all = await done;
      expect(cal.callCount, 1);
      expect(cal.undoCount, 0);
      expect(all.whereType<ToolCallFinished>(), hasLength(1));
    });

    test('Undo schlägt fehl: Audit-Rückruf und gesprochener Hinweis', () async {
      final failed = <String>[];
      final cal = FakeTool(
        name: 'calendar__create_event',
        risk: RiskLevel.write,
        outcome: ToolOutcome.text(
          'ok',
          undo: UndoAction(label: 'x', run: () async => throw StateError('x')),
        ),
      );
      final (_, report, done) = await startWithStricter(
        cal,
        {},
        onUndoFailed: (session, call) => failed.add(call.name),
      );
      report.complete(_report(AttestationStatus.red));
      final all = await done;
      expect(failed, ['calendar__create_event']);
      expect(
        all.whereType<AgentTextDelta>().map((e) => e.text),
        contains(AgentRunnerTexts.undoFailedNotice),
      );
    });

    test('Undo schlägt fehl: Hinweis statt stillem Verschlucken', () async {
      final cal = FakeTool(
        name: 'calendar__create_event',
        risk: RiskLevel.write,
        outcome: ToolOutcome.text(
          'ok',
          undo: UndoAction(label: 'x', run: () async => throw StateError('x')),
        ),
      );
      final (_, report, done) = await startWithStricter(cal, {});
      report.complete(_report(AttestationStatus.red));
      final all = await done;
      final last = all.whereType<ToolCallFinished>().last;
      expect(last.outcome.isError, isTrue);
      expect(last.outcome.summary, contains('fehlgeschlagen'));
    });

    test('write-Tool ohne Undo bleibt bei Rot unberührt', () async {
      final write = FakeTool(
        name: 'notes__add',
        risk: RiskLevel.write,
        outcome: ToolOutcome.text('ok'),
      );
      final (_, report, done) = await startWithStricter(write, {});
      report.complete(_report(AttestationStatus.red));
      final all = await done;
      expect(all.whereType<ToolCallFinished>(), hasLength(1));
    });

    test('ohne Verschärfung läuft ein write-Tool sofort', () async {
      final write = FakeTool(
        name: 'notes__add',
        risk: RiskLevel.write,
        outcome: ToolOutcome.text('ok'),
      );
      final (_, report, done) = await startWithStricter(write, {});
      expect(write.callCount, 1);
      report.complete(_report(AttestationStatus.green));
      await done;
    });

    test('ohne ToolRiskAssessor: write wird wie external behandelt', () async {
      final write = FakeTool(
        name: 'notes__add',
        risk: RiskLevel.write,
        outcome: ToolOutcome.text('ok'),
      );
      final (_, report, done) = await startWithStricter(write, null);
      expect(write.callCount, 0, reason: 'fail-closed: wartet auf Quittung');
      report.complete(_report(AttestationStatus.red));
      await done;
      expect(write.callCount, 0);
    });

    test('ohne ToolRiskAssessor: read läuft sofort', () async {
      final read = FakeTool(name: 'cal__list', outcome: ToolOutcome.text('2'));
      final (_, report, done) = await startWithStricter(read, null);
      expect(read.callCount, 1);
      report.complete(_report(AttestationStatus.green));
      await done;
    });
  });
}
