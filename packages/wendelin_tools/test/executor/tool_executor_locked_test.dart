// WP154 L2: der Executor entscheidet gesperrt mit derselben Policy und
// demselben Timeout.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../policy/locked_tools.dart';

final class _Catalog implements ToolCatalog {
  _Catalog(this.tools);
  final List<Tool> tools;
  @override
  List<ToolSpec> activeSpecs() => [for (final t in tools) t.spec];
  @override
  Tool? lookup(String name) {
    for (final t in tools) {
      if (t.name == name) return t;
    }
    return null;
  }
}

final class _Audit implements ToolAuditSink {
  final entries = <ToolAuditEntry>[];
  @override
  void record(ToolAuditEntry entry) => entries.add(entry);
}

ToolContext _ctx() => ToolContext(
  sessionId: 's',
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);

Future<List<ToolInvocationEvent>> _run(ToolExecutor e, String tool) =>
    e.invokeAll([
      ToolCallBlock(id: 'c', name: tool, argumentsJson: '{}'),
    ], _ctx()).toList();

ToolOutcome _outcome(List<ToolInvocationEvent> events) =>
    events.whereType<ToolFinished>().single.outcome;

/// A tool marked [WorksOnlyUnlocked]; counts its executions.
final class _UnlockedOnly implements Tool, WorksOnlyUnlocked {
  _UnlockedOnly({required this.name, this.risk = RiskLevel.write});

  @override
  final String name;
  @override
  final RiskLevel risk;
  @override
  String get description => 'x';
  @override
  Map<String, Object?> get inputSchema => const {'type': 'object'};
  int callCount = 0;

  @override
  Future<ToolOutcome> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    callCount++;
    return ToolOutcome.text('ok');
  }

  @override
  String describeForConfirmation(Map<String, Object?> args) => name;
}

void main() {
  const locked = AccessContext.lockedUnknownVoice;

  test(
    'gesperrt: Tool ohne A läuft nie, Ergebnis „Entsperren nötig“',
    () async {
      final tool = FakeTool(name: 't__write', risk: RiskLevel.write);
      final audit = _Audit();
      final e = ToolExecutor(
        catalog: _Catalog([tool]),
        audit: audit,
        access: locked,
      );
      final out = _outcome(await _run(e, 't__write'));
      expect(tool.callCount, 0, reason: 'nie ausgeführt');
      expect(out.isError, isTrue);
      expect(out.summary, ToolExecutor.unlockSummary);
      expect(audit.entries.single.whileLocked, isTrue);
      expect(audit.entries.single.status, AuditStatus.denied);
    },
  );

  test(
    'gesperrt: auch ein Tool auf B ohne erkannte Stimme (Eingabestruktur)',
    () async {
      final tool = FakeTool(name: 't__write', risk: RiskLevel.write);
      final policy = RiskPolicy()..setLevel('t__write', SecurityLevel.b);
      ToolExecutor with_(AccessContext a) =>
          ToolExecutor(catalog: _Catalog([tool]), policy: policy, access: a);
      expect(_outcome(await _run(with_(locked), 't__write')).isError, isTrue);
      expect(tool.callCount, 0);
      // WP157: erkannte Stimme → B läuft; dieselbe Eingabestruktur.
      final ok = _outcome(
        await _run(
          with_(const AccessContext(locked: true, speakerRecognized: true)),
          't__write',
        ),
      );
      expect(ok.isError, isFalse);
      expect(tool.callCount, 1);
    },
  );

  test('gesperrt: Stufe A läuft und das Tool sieht ctx.access', () async {
    AccessContext? seen;
    final tool = FakeTool(
      name: 't__write',
      risk: RiskLevel.write,
      handler: (_, ctx) {
        seen = ctx.access;
        return ToolOutcome.text('ok');
      },
    );
    final policy = RiskPolicy()..setLevel('t__write', SecurityLevel.a);
    final audit = _Audit();
    final e = ToolExecutor(
      catalog: _Catalog([tool]),
      policy: policy,
      audit: audit,
      access: locked,
    );
    expect(_outcome(await _run(e, 't__write')).isError, isFalse);
    expect(seen, locked);
    expect(audit.entries.single.whileLocked, isTrue);
  });

  test('entsperrt: kein whileLocked, ctx.access ist „entsperrt“', () async {
    AccessContext? seen;
    final tool = FakeTool(
      name: 't__write',
      risk: RiskLevel.write,
      handler: (_, ctx) {
        seen = ctx.access;
        return ToolOutcome.text('ok');
      },
    );
    final audit = _Audit();
    final e = ToolExecutor(catalog: _Catalog([tool]), audit: audit);
    await _run(e, 't__write');
    expect(seen, AccessContext.unlocked);
    expect(audit.entries.single.whileLocked, isFalse);
  });

  test('gesperrt: kein Kontext des Aufrufs überstimmt den Executor', () async {
    // Der Aufrufer behauptet „entsperrt“ (Default des ToolContext).
    final tool = FakeTool(name: 't__write', risk: RiskLevel.write);
    final e = ToolExecutor(catalog: _Catalog([tool]), access: locked);
    final out = _outcome(await _run(e, 't__write'));
    expect(out.summary, ToolExecutor.unlockSummary);
    expect(tool.callCount, 0);
  });

  test(
    'gesperrt: confirm wird nie gefragt (D → Entsperren statt Karte)',
    () async {
      final tool = FakeTool(name: 't__send', risk: RiskLevel.external);
      final e = ToolExecutor(catalog: _Catalog([tool]), access: locked);
      final events = await _run(e, 't__send');
      expect(events.whereType<ConfirmationNeeded>(), isEmpty);
      expect(tool.callCount, 0);
    },
  );

  test('gesperrt: hängendes Tool endet im Timeout, ohne zu blockieren', () {
    fakeAsync((async) {
      final tool = LevelFake(
        FakeTool(
          name: 'f__on',
          risk: RiskLevel.write,
          delay: const Duration(days: 1),
        ),
        SecurityLevel.a,
      );
      final e = ToolExecutor(
        catalog: _Catalog([tool]),
        access: locked,
        timeout: const Duration(seconds: 20),
      );
      ToolOutcome? out;
      unawaited(_run(e, 'f__on').then((ev) => out = _outcome(ev)));
      async.elapse(const Duration(seconds: 19));
      expect(out, isNull);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(out?.isError, isTrue);
      expect(out?.text, contains('Zeitüberschreitung'));
    });
  });

  test(
    'gesperrt: Tool mit Stufe je Gerät wird durchgelassen und prüft selbst',
    () async {
      AccessContext? seen;
      final tool = PerDeviceFake(
        FakeTool(
          name: 'h__call',
          risk: RiskLevel.write,
          handler: (_, ctx) {
            seen = ctx.access;
            return ctx.access.locked
                ? ToolOutcome.error('nein', summary: ToolExecutor.unlockSummary)
                : ToolOutcome.text('ok');
          },
        ),
      );
      final e = ToolExecutor(catalog: _Catalog([tool]), access: locked);
      final out = _outcome(await _run(e, 'h__call'));
      expect(seen, locked);
      expect(out.summary, ToolExecutor.unlockSummary);
    },
  );

  group('WP163 B: WorksOnlyUnlocked', () {
    ToolExecutor exec(Tool t, AccessContext a, _Audit audit) {
      final policy = RiskPolicy()..setLevel(t.name, SecurityLevel.a);
      return ToolExecutor(
        catalog: _Catalog([t]),
        policy: policy,
        audit: audit,
        access: a,
      );
    }

    test(
      'gesperrt + Stufe erlaubt: nicht ausgeführt, endet den Lauf',
      () async {
        final tool = _UnlockedOnly(name: 'm__nav');
        final audit = _Audit();
        final out = _outcome(await _run(exec(tool, locked, audit), 'm__nav'));
        expect(tool.callCount, 0, reason: 'nie ausgeführt');
        expect(out.summary, ToolExecutor.deferredSummary);
        expect(out.isError, isTrue);
        expect(out.endsRun, isTrue);
        expect(audit.entries.single.status, AuditStatus.denied);
        expect(audit.entries.single.whileLocked, isTrue);
      },
    );

    test('entsperrt: wird ausgeführt', () async {
      final tool = _UnlockedOnly(name: 'm__nav');
      final out = _outcome(
        await _run(exec(tool, AccessContext.unlocked, _Audit()), 'm__nav'),
      );
      expect(tool.callCount, 1);
      expect(out.isError, isFalse);
      expect(out.endsRun, isFalse);
    });

    test(
      'gesperrt + Stufe nicht erlaubt: alter Pfad „Entsperren nötig“',
      () async {
        final tool = _UnlockedOnly(name: 'm__nav');
        // Stufe C (Standard) ohne Freigabe gesperrt.
        final e = ToolExecutor(catalog: _Catalog([tool]), access: locked);
        final out = _outcome(await _run(e, 'm__nav'));
        expect(tool.callCount, 0);
        expect(out.summary, ToolExecutor.unlockSummary);
        expect(out.endsRun, isFalse);
      },
    );

    test('gesperrt, gewöhnliches Tool auf A: läuft (kein Marker)', () async {
      final tool = FakeTool(name: 't__x', risk: RiskLevel.write);
      final out = _outcome(await _run(exec(tool, locked, _Audit()), 't__x'));
      expect(tool.callCount, 1);
      expect(out.endsRun, isFalse);
    });
  });

  test('effectiveRisk berücksichtigt den Kontext', () {
    final tool = FakeTool(name: 't__write', risk: RiskLevel.write);
    final policy = RiskPolicy()..setLevel('t__write', SecurityLevel.d);
    final e = ToolExecutor(catalog: _Catalog([tool]), policy: policy);
    expect(e.effectiveRisk(tool, 's'), RiskLevel.external);
  });
}
