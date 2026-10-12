import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

ToolContext _ctx({CancelToken? cancel, String session = 's1', Clock? clock}) =>
    ToolContext(
      sessionId: session,
      clock: clock ?? const SystemClock(),
      locale: 'de-DE',
      timeZone: 'Europe/Berlin',
      cancel: cancel,
    );

ToolCallBlock _call(String id, String tool, [String args = '{}']) =>
    ToolCallBlock(id: id, name: tool, argumentsJson: args);

Map<String, ToolOutcome> _outcomes(List<ToolInvocationEvent> events) => {
  for (final e in events.whereType<ToolFinished>()) e.call.id: e.outcome,
};

final class _Audit implements ToolAuditSink {
  final entries = <ToolAuditEntry>[];
  @override
  void record(ToolAuditEntry entry) => entries.add(entry);
}

final class _ThrowingAudit implements ToolAuditSink {
  @override
  void record(ToolAuditEntry entry) => throw StateError('Platte voll');
}

/// Runs [calls]; [onEvent] may answer confirmations.
Future<List<ToolInvocationEvent>> _run(
  ToolInvoker invoker,
  List<ToolCallBlock> calls, {
  ToolContext? ctx,
  void Function(ToolInvocationEvent)? onEvent,
}) async {
  final events = <ToolInvocationEvent>[];
  await invoker.invokeAll(calls, ctx ?? _ctx()).forEach((
    ToolInvocationEvent e,
  ) {
    events.add(e);
    onEvent?.call(e);
  });
  expectWellFormedInvocation(calls, events);
  return events;
}

void main() {
  group('Parallelität und Reihenfolge', () {
    test('zwei 100-ms-Tools laufen parallel (< 180 ms)', () async {
      final a = FakeTool(
        name: 'p__a',
        delay: const Duration(milliseconds: 100),
      );
      final b = FakeTool(
        name: 'p__b',
        delay: const Duration(milliseconds: 100),
      );
      final executor = ToolExecutor(catalog: FakeToolCatalog([a, b]));
      final watch = Stopwatch()..start();
      final events = await _run(executor, [
        _call('1', 'p__a'),
        _call('2', 'p__b'),
      ]);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 180)));
      expect(a.completedCount + b.completedCount, 2);
      expect(_outcomes(events).values.every((o) => !o.isError), isTrue);
    });

    test('ToolFinished in Call-Reihenfolge, auch wenn später fertig', () async {
      final slow = FakeTool(
        name: 'p__slow',
        delay: const Duration(milliseconds: 60),
      );
      final fast = FakeTool(name: 'p__fast');
      final executor = ToolExecutor(catalog: FakeToolCatalog([slow, fast]));
      final events = await _run(executor, [
        _call('1', 'p__slow'),
        _call('2', 'p__fast'),
        _call('3', 'p__fast'),
      ]);
      expect(
        [for (final e in events.whereType<ToolFinished>()) e.call.id],
        ['1', '2', '3'],
      );
      expect(
        [for (final e in events.take(3)) (e is ToolStarted, e.call.id)],
        [(true, '1'), (true, '2'), (true, '3')],
      );
    });

    test('read läuft weiter, während eine Bestätigung offen ist', () async {
      final read = FakeTool(name: 'p__read');
      final send = FakeTool(name: 'p__send', risk: RiskLevel.external);
      final executor = ToolExecutor(catalog: FakeToolCatalog([send, read]));
      var readDoneWhenAsked = false;
      await _run(
        executor,
        [_call('1', 'p__send'), _call('2', 'p__read')],
        onEvent: (e) {
          if (e is ConfirmationNeeded) {
            Timer(const Duration(milliseconds: 20), () {
              readDoneWhenAsked = read.completedCount == 1;
              e.respond(true);
            });
          }
        },
      );
      expect(readDoneWhenAsked, isTrue);
      expect(send.completedCount, 1);
    });

    test('Bestätigungen nacheinander in Call-Reihenfolge', () async {
      final tools = [
        for (final n in ['a', 'b', 'c'])
          FakeTool(name: 'p__$n', risk: RiskLevel.external),
      ];
      final executor = ToolExecutor(catalog: FakeToolCatalog(tools));
      final asked = <String>[];
      var open = 0;
      var maxOpen = 0;
      await _run(
        executor,
        [_call('1', 'p__a'), _call('2', 'p__b'), _call('3', 'p__c')],
        onEvent: (e) {
          if (e is! ConfirmationNeeded) return;
          asked.add(e.call.id);
          open++;
          if (open > maxOpen) maxOpen = open;
          Timer(const Duration(milliseconds: 10), () {
            open--;
            e.respond(e.call.id != '2');
          });
        },
      );
      expect(asked, ['1', '2', '3']);
      expect(maxOpen, 1);
      expect([for (final t in tools) t.callCount], [1, 0, 1]);
    });
  });

  group('Risiko und Bestätigung', () {
    test('external wird ohne Bestätigung nie ausgeführt, auch mit '
        'lockerndem Override', () async {
      final send = FakeTool(name: 'p__send', risk: RiskLevel.external);
      final policy = RiskPolicy(overrides: {'p__send': PolicyAction.allow});
      final executor = ToolExecutor(
        catalog: FakeToolCatalog([send]),
        policy: policy,
      );
      final events = await _run(
        executor,
        [_call('1', 'p__send')],
        onEvent: (e) {
          if (e is ConfirmationNeeded) {
            expect(send.callCount, 0, reason: 'vor der Antwort ausgeführt');
            e.respond(false);
          }
        },
      );
      expect(events.whereType<ConfirmationNeeded>(), hasLength(1));
      expect(send.callCount, 0);
      final o = _outcomes(events)['1']!;
      expect(o.isError, isFalse);
      expect(o.text, ToolOutcome.declinedText);
    });

    test('Override confirm auf read fragt nach', () async {
      final read = FakeTool(name: 'p__read');
      final executor = ToolExecutor(
        catalog: FakeToolCatalog([read]),
        policy: RiskPolicy(overrides: {'p__read': PolicyAction.confirm}),
      );
      final events = await _run(
        executor,
        [_call('1', 'p__read')],
        onEvent: (e) {
          if (e is ConfirmationNeeded) e.respond(true);
        },
      );
      expect(events.whereType<ConfirmationNeeded>(), hasLength(1));
      expect(read.callCount, 1);
    });

    test('gesperrte Session: external abgelehnt ohne Frage, andere Session '
        'nicht betroffen', () async {
      final send = FakeTool(name: 'p__send', risk: RiskLevel.external);
      final policy = RiskPolicy()..lockExternal('s1');
      final executor = ToolExecutor(
        catalog: FakeToolCatalog([send]),
        policy: policy,
      );
      final events = await _run(executor, [_call('1', 'p__send')]);
      expect(events.whereType<ConfirmationNeeded>(), isEmpty);
      expect(send.callCount, 0);
      final o = _outcomes(events)['1']!;
      expect(o.isError, isTrue);
      expect(o.text, RiskPolicy.lockedReason);

      final other = await _run(
        executor,
        [_call('2', 'p__send')],
        ctx: _ctx(session: 's2'),
        onEvent: (e) {
          if (e is ConfirmationNeeded) e.respond(true);
        },
      );
      expect(other.whereType<ConfirmationNeeded>(), hasLength(1));
      expect(send.callCount, 1);
    });

    test('Override deny sperrt read', () async {
      final read = FakeTool(name: 'p__read');
      final executor = ToolExecutor(
        catalog: FakeToolCatalog([read]),
        policy: RiskPolicy(overrides: {'p__read': PolicyAction.deny}),
      );
      final o = _outcomes(await _run(executor, [_call('1', 'p__read')]))['1']!;
      expect(o.isError, isTrue);
      expect(o.text, RiskPolicy.deniedReason);
      expect(read.callCount, 0);
    });

    test('Abbruch, während eine Bestätigung auf ihren Platz wartet', () async {
      final a = FakeTool(name: 'p__a', risk: RiskLevel.external);
      final b = FakeTool(name: 'p__b', risk: RiskLevel.external);
      final executor = ToolExecutor(catalog: FakeToolCatalog([a, b]));
      final cancel = CancelToken();
      final events = await _run(
        executor,
        [_call('1', 'p__a'), _call('2', 'p__b')],
        ctx: _ctx(cancel: cancel),
        onEvent: (e) {
          if (e is ConfirmationNeeded) {
            e.respond(true); // answered, but cancelled before execution
            cancel.cancel();
          }
        },
      );
      expect(events.whereType<ConfirmationNeeded>(), hasLength(1));
      expect(a.callCount + b.callCount, 0);
      for (final o in _outcomes(events).values) {
        expect(o.text, ToolOutcome.cancelledText);
      }
    });

    test(
      'Fehler in describeForConfirmation: nicht ausgeführt, Fehler-Outcome',
      () async {
        final send = FakeTool(
          name: 'p__send',
          risk: RiskLevel.external,
          confirmation: (_) => throw StateError('kein Text'),
        );
        final executor = ToolExecutor(catalog: FakeToolCatalog([send]));
        final o = _outcomes(
          await _run(executor, [_call('1', 'p__send')]),
        )['1']!;
        expect(o.isError, isTrue);
        expect(o.text, contains('Interner Fehler bei p__send'));
        expect(send.callCount, 0);
      },
    );
  });

  group('Argumente', () {
    final strict = FakeTool(
      name: 'p__strict',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
        },
        'required': ['title'],
      },
    );
    final executor = ToolExecutor(catalog: FakeToolCatalog([strict]));

    test('Schemaverletzung: lesbarer Fehler, Tool nicht ausgeführt', () async {
      final before = strict.callCount;
      final o = _outcomes(
        await _run(executor, [_call('1', 'p__strict', '{"title": 3}')]),
      )['1']!;
      expect(o.isError, isTrue);
      expect(
        o.text,
        'Ungültige Argumente für p__strict: Argument „title“: erwartet '
        'string, erhalten integer. Bitte korrigieren und erneut aufrufen.',
      );
      expect(strict.callCount, before);
    });

    test('ungültiges JSON und Nicht-Objekt', () async {
      final events = await _run(executor, [
        _call('1', 'p__strict', '{kaputt'),
        _call('2', 'p__strict', '[1]'),
      ]);
      for (final o in _outcomes(events).values) {
        expect(o.isError, isTrue);
        expect(o.text, ToolExecutor.invalidJsonText);
      }
    });

    test('leere Argumente gelten als {}', () async {
      final free = FakeTool(name: 'p__free');
      final o = _outcomes(
        await _run(ToolExecutor(catalog: FakeToolCatalog([free])), [
          _call('1', 'p__free', '  '),
        ]),
      )['1']!;
      expect(o.isError, isFalse);
      expect(free.calls.single, isEmpty);
    });

    test('gültige Argumente erreichen das Tool', () async {
      await _run(executor, [_call('1', 'p__strict', '{"title": "Tauchen"}')]);
      expect(strict.calls.last, {'title': 'Tauchen'});
    });

    test('unbekanntes Tool', () async {
      final o = _outcomes(await _run(executor, [_call('1', 'p__nix')]))['1']!;
      expect(o.isError, isTrue);
      expect(o.text, ToolExecutor.unknownToolText('p__nix'));
    });
  });

  group('Ausführung', () {
    test('Timeout: Fehler-Outcome, Tool bekommt Abbruchsignal', () async {
      CancelToken? seen;
      final hang = FakeTool(
        name: 'p__hang',
        handler: (args, ctx) async {
          seen = ctx.cancel;
          await ctx.cancel.whenCancelled;
          return ToolOutcome.text('zu spät');
        },
      );
      final executor = ToolExecutor(
        catalog: FakeToolCatalog([hang]),
        timeout: const Duration(milliseconds: 50),
      );
      final o = _outcomes(await _run(executor, [_call('1', 'p__hang')]))['1']!;
      expect(o.isError, isTrue);
      expect(
        o.text,
        'Zeitüberschreitung: p__hang hat nicht innerhalb von 50 ms '
        'geantwortet.',
      );
      expect(seen!.isCancelled, isTrue);
    });

    test('Timeout-Text in Sekunden; Standard 20 s', () async {
      expect(
        ToolExecutor(catalog: FakeToolCatalog(const [])).timeout,
        const Duration(seconds: 20),
      );
      final hang = FakeTool(
        name: 'p__hang',
        handler: (args, ctx) => Completer<ToolOutcome>().future,
      );
      final executor = ToolExecutor(
        catalog: FakeToolCatalog([hang]),
        timeout: const Duration(seconds: 1),
      );
      final o = _outcomes(await _run(executor, [_call('1', 'p__hang')]))['1']!;
      expect(o.text, contains('innerhalb von 1 s'));
    });

    test('Exception: lesbare erste Zeile, kein Stacktrace', () async {
      final fail = FakeTool(
        name: 'p__fail',
        throws: Exception('Server sagt nein\n#0 main (file.dart:1)'),
      );
      final o = _outcomes(
        await _run(ToolExecutor(catalog: FakeToolCatalog([fail])), [
          _call('1', 'p__fail'),
        ]),
      )['1']!;
      expect(o.isError, isTrue);
      expect(o.text, 'Fehler bei p__fail: Exception: Server sagt nein');
    });

    test('sehr lange Exception wird gekürzt', () async {
      final fail = FakeTool(name: 'p__fail', throws: StateError('x' * 500));
      final o = _outcomes(
        await _run(ToolExecutor(catalog: FakeToolCatalog([fail])), [
          _call('1', 'p__fail'),
        ]),
      )['1']!;
      expect(o.text.length, lessThan(240));
      expect(o.text, endsWith('…'));
    });

    test('synchron werfendes Tool', () async {
      final fail = FakeTool(
        name: 'p__fail',
        handler: (args, ctx) => throw ArgumentError('sync'),
      );
      final o = _outcomes(
        await _run(ToolExecutor(catalog: FakeToolCatalog([fail])), [
          _call('1', 'p__fail'),
        ]),
      )['1']!;
      expect(o.isError, isTrue);
      expect(o.text, contains('sync'));
    });

    test(
      'Tool, das nach Abbruch mit anderem Fehler endet → abgebrochen',
      () async {
        final cancel = CancelToken();
        final tool = FakeTool(
          name: 'p__net',
          handler: (args, ctx) async {
            await ctx.cancel.whenCancelled;
            throw Exception('Socket geschlossen');
          },
        );
        final events = await _run(
          ToolExecutor(catalog: FakeToolCatalog([tool])),
          [_call('1', 'p__net')],
          ctx: _ctx(cancel: cancel),
          onEvent: (e) {
            if (e is ToolStarted) Timer(Duration.zero, cancel.cancel);
          },
        );
        expect(_outcomes(events)['1']!.text, ToolOutcome.cancelledText);
      },
    );

    test('Dauer kommt von der Clock', () async {
      final clock = FixedClock(DateTime.utc(2026, 10, 14, 10));
      final tool = FakeTool(
        name: 'p__t',
        handler: (args, ctx) {
          clock.advance(const Duration(seconds: 3));
          return ToolOutcome.text('ok');
        },
      );
      final events = await _run(
        ToolExecutor(catalog: FakeToolCatalog([tool])),
        [_call('1', 'p__t')],
        ctx: _ctx(clock: clock),
      );
      expect(
        events.whereType<ToolFinished>().single.duration,
        const Duration(seconds: 3),
      );
    });

    test('Stream ist lazy: ohne Listener läuft nichts', () async {
      final tool = FakeTool(name: 'p__t');
      final executor = ToolExecutor(catalog: FakeToolCatalog([tool]));
      final stream = executor.invokeAll([_call('1', 'p__t')], _ctx());
      await Future<void>.delayed(Duration.zero);
      expect(tool.callCount, 0);
      await stream.drain<void>();
      expect(tool.callCount, 1);
    });
  });

  group('Ergebnisse: Hülle und Kürzung', () {
    test('Tool-Inhalt wird gehüllt, summary und undo bleiben', () async {
      final tool = FakeTool(
        name: 'p__w',
        risk: RiskLevel.write,
        withUndo: true,
        outcome: ToolOutcome.text('Termin angelegt', summary: 'Angelegt'),
      );
      final o = _outcomes(
        await _run(ToolExecutor(catalog: FakeToolCatalog([tool])), [
          _call('1', 'p__w'),
        ]),
      )['1']!;
      expect(o.text, '<tool_data tool="p__w">\nTermin angelegt\n</tool_data>');
      expect(o.summary, 'Angelegt');
      expect(o.undo, isNotNull);
      await o.undo!();
      expect(tool.undoCount, 1);
    });

    test('Fehler-Outcome eines Tools wird ebenfalls gehüllt', () async {
      final tool = FakeTool(
        name: 'p__e',
        outcome: ToolOutcome.error('Kalender nicht erreichbar'),
      );
      final o = _outcomes(
        await _run(ToolExecutor(catalog: FakeToolCatalog([tool])), [
          _call('1', 'p__e'),
        ]),
      )['1']!;
      expect(o.isError, isTrue);
      expect(o.text, contains('<tool_data tool="p__e">'));
    });

    test('lange Ergebnisse werden gekürzt (Standard 8000)', () async {
      final tool = FakeTool(
        name: 'p__big',
        outcome: ToolOutcome.text('a' * 9000),
      );
      final o = _outcomes(
        await _run(ToolExecutor(catalog: FakeToolCatalog([tool])), [
          _call('1', 'p__big'),
        ]),
      )['1']!;
      expect(o.text, contains('[gekürzt: 8000 von 9000 Zeichen]'));
      expect('a'.allMatches(o.text).length, 8000 + 4); // + 2 je „tool_data“-Tag
    });

    test('interne Outcomes bleiben unverändert', () async {
      final send = FakeTool(name: 'p__send', risk: RiskLevel.external);
      final executor = ToolExecutor(
        catalog: FakeToolCatalog([send]),
        shaper: const ResultShaper(maxChars: 3),
      );
      final o = _outcomes(
        await _run(
          executor,
          [
            _call('1', 'p__send'),
            _call('2', 'p__nix'),
            _call('3', 'p__send', '['),
          ],
          onEvent: (e) {
            if (e is ConfirmationNeeded) e.respond(false);
          },
        ),
      );
      expect(o['1']!.text, ToolOutcome.declinedText);
      expect(o['2']!.text, ToolExecutor.unknownToolText('p__nix'));
      expect(o['3']!.text, ToolExecutor.invalidJsonText);
    });

    test(
      'Abbruch: fertiger Call behält sein gehülltes echtes Outcome',
      () async {
        final stubborn = FakeTool(
          name: 'p__stubborn',
          delay: const Duration(milliseconds: 60),
          ignoresCancel: true,
          outcome: ToolOutcome.text('stur fertig'),
        );
        final cancel = CancelToken();
        final events = await _run(
          ToolExecutor(catalog: FakeToolCatalog([stubborn])),
          [_call('1', 'p__stubborn')],
          ctx: _ctx(cancel: cancel),
          onEvent: (e) {
            if (e is ToolStarted) {
              Timer(const Duration(milliseconds: 10), cancel.cancel);
            }
          },
        );
        final o = _outcomes(events)['1']!;
        expect(o.isError, isFalse);
        expect(
          o.text,
          '<tool_data tool="p__stubborn">\nstur fertig\n</tool_data>',
        );
      },
    );
  });

  group('Audit', () {
    test('ein Eintrag je Call mit Entscheidung und Status', () async {
      final audit = _Audit();
      final read = FakeTool(name: 'p__read');
      final send = FakeTool(name: 'p__send', risk: RiskLevel.external);
      final send2 = FakeTool(name: 'p__send2', risk: RiskLevel.external);
      final fail = FakeTool(name: 'p__fail', throws: Exception('x'));
      final err = FakeTool(name: 'p__err', outcome: ToolOutcome.error('e'));
      final hang = FakeTool(
        name: 'p__hang',
        handler: (args, ctx) => Completer<ToolOutcome>().future,
      );
      final executor = ToolExecutor(
        catalog: FakeToolCatalog([read, send, send2, fail, err, hang]),
        audit: audit,
        timeout: const Duration(milliseconds: 30),
        policy: RiskPolicy(overrides: {'p__err': PolicyAction.allow}),
      );
      await _run(
        executor,
        [
          _call('1', 'p__read', '{"a": 1}'),
          _call('2', 'p__send'),
          _call('3', 'p__send2'),
          _call('4', 'p__fail'),
          _call('5', 'p__nix'),
          _call('6', 'p__read', '{'),
          _call('7', 'p__err'),
          _call('8', 'p__hang'),
        ],
        onEvent: (e) {
          if (e is ConfirmationNeeded) e.respond(e.call.id == '2');
        },
      );
      expect(
        [
          for (final e
              in audit.entries..sort((a, b) => a.callId.compareTo(b.callId)))
            (e.callId, e.decision, e.status),
        ],
        [
          ('1', AuditDecision.allowed, AuditStatus.ok),
          ('2', AuditDecision.confirmed, AuditStatus.ok),
          ('3', AuditDecision.declined, AuditStatus.declined),
          ('4', AuditDecision.allowed, AuditStatus.error),
          ('5', AuditDecision.none, AuditStatus.unknownTool),
          ('6', AuditDecision.none, AuditStatus.invalidArguments),
          ('7', AuditDecision.allowed, AuditStatus.error),
          ('8', AuditDecision.allowed, AuditStatus.timeout),
        ],
      );
      final first = audit.entries.first;
      expect(first.sessionId, 's1');
      expect(first.tool, 'p__read');
      expect(first.argumentsJson, '{"a": 1}');
      expect(first.toString(), contains('allowed'));
    });

    test('Abbruch, Sperre und Abbruch während Bestätigung im Audit', () async {
      final audit = _Audit();
      final send = FakeTool(name: 'p__send', risk: RiskLevel.external);
      final policy = RiskPolicy()..lockExternal('locked');
      final executor = ToolExecutor(
        catalog: FakeToolCatalog([send]),
        audit: audit,
        policy: policy,
      );
      await _run(executor, [
        _call('1', 'p__send'),
      ], ctx: _ctx(session: 'locked'));
      await _run(executor, [
        _call('2', 'p__send'),
      ], ctx: _ctx(cancel: CancelToken()..cancel()));
      final cancel = CancelToken();
      await _run(
        executor,
        [_call('3', 'p__send')],
        ctx: _ctx(cancel: cancel),
        onEvent: (e) {
          if (e is ConfirmationNeeded) cancel.cancel();
        },
      );
      expect(
        [for (final e in audit.entries) (e.decision, e.status)],
        [
          (AuditDecision.denied, AuditStatus.denied),
          (AuditDecision.none, AuditStatus.cancelled),
          (AuditDecision.declined, AuditStatus.cancelled),
        ],
      );
    });

    test(
      'werfender Audit-Sink stört den Lauf nicht, Fehler geht an die Zone',
      () async {
        final errors = <Object>[];
        final tool = FakeTool(name: 'p__t');
        late List<ToolInvocationEvent> events;
        await runZonedGuarded(() async {
          events = await _run(
            ToolExecutor(
              catalog: FakeToolCatalog([tool]),
              audit: _ThrowingAudit(),
            ),
            [_call('1', 'p__t')],
          );
        }, (e, s) => errors.add(e));
        expect(_outcomes(events)['1']!.isError, isFalse);
        expect(errors.single, isA<StateError>());
      },
    );
  });
}
