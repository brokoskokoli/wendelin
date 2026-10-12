import 'dart:async';

import 'package:test/test.dart';

import '../wendelin_core.dart';
import 'fake_tools.dart';

/// Creates the invoker under test for a catalog of fake tools.
typedef ToolInvokerFactory = FutureOr<ToolInvoker> Function(
  ToolCatalog catalog,
);

/// Names of the checks in [toolInvokerContractChecks].
abstract final class ToolInvokerChecks {
  /// No calls: stream closes without events.
  static const empty = 'keine Calls: Stream schließt ohne Events';

  /// read/write run without confirmation.
  static const readWrite = 'read und write laufen ohne Bestätigung';

  /// Unknown tool, invalid JSON, throwing tool → error outcomes.
  static const errors = 'Fehlerfälle werden zu Fehler-Outcomes';

  /// external: confirmation before execution, yes executes.
  static const confirmYes =
      'external: Bestätigung vor Ausführung, ja führt aus';

  /// external: no does not execute and is no error.
  static const confirmNo =
      'external: nein führt nicht aus, kein Fehler-Outcome';

  /// First answer wins, no exception.
  static const idempotent = 'Antwort ist idempotent: erste gewinnt';

  /// Confirmations are asked one after another.
  static const sequentialConfirmations =
      'Bestätigungen nacheinander: zweite erst nach Antwort auf erste';

  /// Cancel while a confirmation is open.
  static const cancelDuringConfirmation =
      'Abbruch während Bestätigung: terminiert, Bestätigtes nie ausgeführt';

  /// Cancel while tools run.
  static const cancelDuringExecution =
      'Abbruch während Ausführung beendet offene Calls als Fehler';

  /// A tool that completes despite cancellation keeps its outcome.
  static const cancelKeepsCompleted =
      'Abbruch: trotzdem fertiger Call behält sein echtes Outcome';

  /// Already cancelled context executes nothing.
  static const preCancelled =
      'bereits abgebrochener Kontext führt kein Tool aus';
}

/// Reusable contract test suite for every [ToolInvoker] implementation
/// (`FakeToolInvoker`, `ToolExecutor` in `wendelin_tools`); registers one
/// test per entry of [toolInvokerContractChecks] in a group.
///
/// [create] receives a catalog of fake tools (all with input schema
/// `{"type": "object"}`) and must return an invoker that executes them with
/// its default policy (read/write without confirmation, external always
/// confirmed). The checks hold for sequential and parallel invokers.
/// [name] labels the group, [timeout] bounds each run.
void toolInvokerContract(
  ToolInvokerFactory create, {
  String name = 'ToolInvoker',
  Duration timeout = const Duration(seconds: 10),
}) {
  group('$name erfüllt ToolInvoker-Vertrag', () {
    toolInvokerContractChecks(create, timeout: timeout).forEach(test);
  });
}

/// The individual checks of [toolInvokerContract], keyed by the names in
/// [ToolInvokerChecks]. Each check builds fresh tools and a fresh invoker and
/// throws a [TestFailure] on a contract violation, so tests can also run a
/// single check against a deliberately broken invoker.
///
/// Checks the contract documented at [ToolInvoker.invokeAll]: one
/// `ToolStarted` and one later `ToolFinished` per call, error outcomes
/// instead of stream errors, confirmation before external tools, one
/// confirmation at a time, declined calls not executed, idempotent answers,
/// and cancellation: open confirmations resolved, no tool **entered** after
/// cancellation (`FakeTool.startedAfterCancel`), calls cut short carry
/// exactly `ToolOutcome.cancelled()`, calls that really completed keep their
/// real outcome.
Map<String, Future<void> Function()> toolInvokerContractChecks(
  ToolInvokerFactory create, {
  Duration timeout = const Duration(seconds: 10),
}) {
  Future<_Fixture> fixture() async {
    final f = _Fixture(timeout);
    f.invoker = await create(FakeToolCatalog(f.tools));
    return f;
  }

  return {
    ToolInvokerChecks.empty: () async {
      final f = await fixture();
      expect(await f.run(const []), isEmpty);
    },
    ToolInvokerChecks.readWrite: () async {
      final f = await fixture();
      final events = await f.run([
        _call('1', 'contract__read'),
        _call('2', 'contract__write'),
      ]);
      expect(events.whereType<ConfirmationNeeded>(), isEmpty);
      expect(_outcomes(events).values.map((o) => o.isError), [false, false]);
      expect(f.read.callCount, 1);
      expect(f.write.callCount, 1);
    },
    ToolInvokerChecks.errors: () async {
      final f = await fixture();
      final events = await f.run([
        _call('1', 'contract__unknown'),
        _call('2', 'contract__read', '{kaputt'),
        _call('3', 'contract__fail'),
      ]);
      final o = _outcomes(events);
      expect(o['1']!.isError, isTrue, reason: 'unbekanntes Tool');
      expect(o['2']!.isError, isTrue, reason: 'ungültiges JSON');
      expect(o['3']!.isError, isTrue, reason: 'Exception im Tool');
      expect(f.read.callCount, 0);
    },
    ToolInvokerChecks.confirmYes: () async {
      final f = await fixture();
      var executedBeforeAnswer = -1;
      final events = await f.run(
        [_call('1', 'contract__send')],
        onEvent: (e) {
          if (e is ConfirmationNeeded) {
            executedBeforeAnswer = f.external.callCount;
            e.respond(true);
          }
        },
      );
      final asks = events.whereType<ConfirmationNeeded>().toList();
      expect(asks, hasLength(1));
      expect(asks.single.description, 'Nachricht senden');
      expect(executedBeforeAnswer, 0);
      expect(f.external.callCount, 1);
      expect(_outcomes(events)['1']!.isError, isFalse);
    },
    ToolInvokerChecks.confirmNo: () async {
      final f = await fixture();
      final events = await f.run(
        [_call('1', 'contract__send')],
        onEvent: (e) {
          if (e is ConfirmationNeeded) e.respond(false);
        },
      );
      expect(f.external.callCount, 0);
      expect(_outcomes(events)['1']!.isError, isFalse);
    },
    ToolInvokerChecks.idempotent: () async {
      final f = await fixture();
      final events = await f.run(
        [_call('1', 'contract__send')],
        onEvent: (e) {
          if (e is ConfirmationNeeded) {
            e
              ..respond(true)
              ..respond(false)
              ..respond(true);
          }
        },
      );
      expect(events.whereType<ConfirmationNeeded>().single.answered, isTrue);
      expect(f.external.callCount, 1);
      expect(_outcomes(events)['1']!.isError, isFalse);
    },
    ToolInvokerChecks.sequentialConfirmations: () async {
      final f = await fixture();
      final asked = <ConfirmationNeeded>[];
      var previousAnsweredWhenAsked = true;
      final events = await f.run(
        [_call('1', 'contract__send'), _call('2', 'contract__send2')],
        onEvent: (e) {
          if (e is! ConfirmationNeeded) return;
          if (asked.isNotEmpty && !asked.last.answered) {
            previousAnsweredWhenAsked = false;
          }
          asked.add(e);
          // Answer later, so a second question asked in parallel is visible.
          Timer(const Duration(milliseconds: 20), () => e.respond(true));
        },
      );
      expect(asked, hasLength(2));
      expect(
        previousAnsweredWhenAsked,
        isTrue,
        reason: 'zweite Bestätigung kam, bevor die erste beantwortet war',
      );
      expect(f.external.callCount + f.external2.callCount, 2);
      expect(_outcomes(events).values.map((o) => o.isError), [false, false]);
    },
    ToolInvokerChecks.cancelDuringConfirmation: () async {
      final f = await fixture();
      final cancel = CancelToken();
      final events = await f.run(
        [_call('1', 'contract__send'), _call('2', 'contract__slow')],
        ctx: _context(cancel),
        onEvent: (e) {
          if (e is ConfirmationNeeded) cancel.cancel();
        },
      );
      final asks = events.whereType<ConfirmationNeeded>().toList();
      expect(asks, hasLength(1));
      expect(asks.single.answered, isTrue, reason: 'Bestätigung aufgelöst');
      expect(f.external.callCount, 0);
      _expectIsCancelled(_outcomes(events)['1']!, 'unbestätigter Call');
      f.expectCancelledUnlessCompleted(events, {'1': f.external, '2': f.slow});
      f.expectNothingStartedAfterCancel();
    },
    ToolInvokerChecks.cancelDuringExecution: () async {
      final f = await fixture();
      final cancel = CancelToken();
      final events = await f.run(
        [_call('1', 'contract__slow'), _call('2', 'contract__slow2')],
        ctx: _context(cancel),
        onEvent: (e) {
          if (e is ToolStarted && e.call.id == '1') {
            Timer(const Duration(milliseconds: 20), cancel.cancel);
          }
        },
      );
      expect(f.slow.completedCount + f.slow2.completedCount, 0);
      for (final o in _outcomes(events).values) {
        _expectIsCancelled(o, 'abgebrochener Call');
      }
      f.expectNothingStartedAfterCancel();
    },
    ToolInvokerChecks.cancelKeepsCompleted: () async {
      final f = await fixture();
      final cancel = CancelToken();
      final events = await f.run(
        [_call('1', 'contract__stubborn'), _call('2', 'contract__slow')],
        ctx: _context(cancel),
        onEvent: (e) {
          if (e is ToolStarted && e.call.id == '1') {
            Timer(const Duration(milliseconds: 20), cancel.cancel);
          }
        },
      );
      expect(f.stubborn.completedCount, 1);
      final kept = _outcomes(events)['1']!;
      expect(kept.isError, isFalse, reason: 'fertiger Call: echtes Outcome');
      // Echte Tool-Inhalte darf der Invoker hüllen/kürzen (ADR 0002 §5).
      expect(kept.text, contains('stur fertig'));
      _expectIsCancelled(_outcomes(events)['2']!, 'abgebrochener Call');
      f.expectNothingStartedAfterCancel();
    },
    ToolInvokerChecks.preCancelled: () async {
      final f = await fixture();
      final events = await f.run([
        _call('1', 'contract__read'),
        _call('2', 'contract__send'),
      ], ctx: _context(CancelToken()..cancel()));
      expect(f.read.callCount + f.external.callCount, 0);
      expect(events.whereType<ConfirmationNeeded>(), isEmpty);
      for (final o in _outcomes(events).values) {
        _expectIsCancelled(o, 'abgebrochener Call');
      }
      f.expectNothingStartedAfterCancel();
    },
  };
}

/// Fresh tools and the invoker under test for one check.
final class _Fixture {
  _Fixture(this.timeout);

  final Duration timeout;
  late final ToolInvoker invoker;

  final read = FakeTool(name: 'contract__read');
  final write = FakeTool(name: 'contract__write', risk: RiskLevel.write);
  final external = FakeTool(
    name: 'contract__send',
    risk: RiskLevel.external,
    confirmation: (_) => 'Nachricht senden',
  );
  final external2 = FakeTool(name: 'contract__send2', risk: RiskLevel.external);
  final failing = FakeTool(
    name: 'contract__fail',
    throws: StateError('kaputt'),
  );
  final slow = FakeTool(
    name: 'contract__slow',
    delay: const Duration(seconds: 30),
  );
  final slow2 = FakeTool(
    name: 'contract__slow2',
    delay: const Duration(seconds: 30),
  );
  final stubborn = FakeTool(
    name: 'contract__stubborn',
    delay: const Duration(milliseconds: 100),
    ignoresCancel: true,
    outcome: ToolOutcome.text('stur fertig'),
  );

  List<FakeTool> get tools => [
    read,
    write,
    external,
    external2,
    failing,
    slow,
    slow2,
    stubborn,
  ];

  /// Runs [calls]; [onEvent] may answer confirmations or cancel.
  Future<List<ToolInvocationEvent>> run(
    List<ToolCallBlock> calls, {
    ToolContext? ctx,
    void Function(ToolInvocationEvent event)? onEvent,
  }) async {
    final events = <ToolInvocationEvent>[];
    final done = Completer<void>();
    invoker
        .invokeAll(calls, ctx ?? _context())
        .listen(
          (e) {
            events.add(e);
            onEvent?.call(e);
          },
          onError: (Object e, StackTrace s) {
            if (!done.isCompleted) {
              done.completeError(
                TestFailure('Stream darf keine Fehler senden, war: $e'),
                s,
              );
            }
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
    await done.future.timeout(timeout);
    expectWellFormedInvocation(calls, events);
    return events;
  }

  /// No tool may be entered after cancellation.
  void expectNothingStartedAfterCancel() {
    for (final t in tools) {
      expect(
        t.startedAfterCancel,
        0,
        reason: '${t.name} wurde nach dem Abbruch gestartet',
      );
    }
  }

  /// A call whose tool did not complete gets `cancelled()`; a call whose
  /// tool really completed keeps its real (here: successful) outcome.
  void expectCancelledUnlessCompleted(
    List<ToolInvocationEvent> events,
    Map<String, FakeTool> toolOf,
  ) {
    _outcomes(events).forEach((id, o) {
      if (toolOf[id]!.completedCount > 0) {
        expect(o.isError, isFalse, reason: 'Call $id lief, echtes Outcome');
      } else {
        _expectIsCancelled(o, 'Call $id lief nicht zu Ende');
      }
    });
  }
}

ToolContext _context([CancelToken? cancel]) => ToolContext(
  sessionId: 'contract',
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
  cancel: cancel,
);

ToolCallBlock _call(String id, String tool, [String args = '{}']) =>
    ToolCallBlock(id: id, name: tool, argumentsJson: args);

Map<String, ToolOutcome> _outcomes(List<ToolInvocationEvent> events) => {
  for (final e in events.whereType<ToolFinished>()) e.call.id: e.outcome,
};

void _expectIsCancelled(ToolOutcome o, String reason) {
  expect(o.isError, isTrue, reason: '$reason: Fehler-Outcome erwartet');
  expect(
    o.text,
    ToolOutcome.cancelledText,
    reason: '$reason: ToolOutcome.cancelled() erwartet',
  );
}

/// Asserts that [events] contain, for each of [calls], exactly one
/// `ToolStarted` followed later by exactly one `ToolFinished`, and that any
/// `ConfirmationNeeded` lies between them. Usable directly in tests.
void expectWellFormedInvocation(
  List<ToolCallBlock> calls,
  List<ToolInvocationEvent> events,
) {
  for (final call in calls) {
    final own = [
      for (final (i, e) in events.indexed)
        if (identical(e.call, call) || e.call == call) (i, e),
    ];
    final started = own.where((x) => x.$2 is ToolStarted).toList();
    final finished = own.where((x) => x.$2 is ToolFinished).toList();
    expect(started, hasLength(1), reason: 'ToolStarted für ${call.id}');
    expect(finished, hasLength(1), reason: 'ToolFinished für ${call.id}');
    for (final (i, e) in own) {
      if (e is ConfirmationNeeded) {
        expect(
          i > started.single.$1 && i < finished.single.$1,
          isTrue,
          reason: 'Bestätigung von ${call.id} außerhalb Start/Ende',
        );
      }
    }
    expect(
      started.single.$1 < finished.single.$1,
      isTrue,
      reason: 'ToolFinished vor ToolStarted bei ${call.id}',
    );
  }
  expect(
    events.length,
    events.where((e) => calls.contains(e.call)).length,
    reason: 'Events für unbekannte Calls',
  );
}
