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
    startWithStricter(FakeTool tool, Set<String>? stricter) async {
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
