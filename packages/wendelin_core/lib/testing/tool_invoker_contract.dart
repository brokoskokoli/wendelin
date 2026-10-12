import 'dart:async';

import 'package:test/test.dart';

import '../wendelin_core.dart';
import 'fake_tools.dart';

/// Reusable contract test suite for every [ToolInvoker] implementation
/// (`FakeToolInvoker`, `ToolExecutor` in `wendelin_tools`).
///
/// [create] receives a catalog of fake tools (all with input schema
/// `{"type": "object"}`) and must return an invoker that executes them with
/// its default policy (read/write without confirmation, external always
/// confirmed). [name] labels the group, [timeout] bounds each test.
///
/// Calls cut short by cancellation must carry `ToolOutcome.cancelled()`
/// (error, text exactly [ToolOutcome.cancelledText]).
///
/// Checks the contract documented at [ToolInvoker.invokeAll]: exactly one
/// `ToolStarted` and one later `ToolFinished` per call, error outcomes
/// instead of stream errors, confirmation before external tools, declined
/// calls are not executed, idempotent answers, and cancellation (open
/// confirmations resolved, nothing further executed, every call finished).
void toolInvokerContract(
  FutureOr<ToolInvoker> Function(ToolCatalog catalog) create, {
  String name = 'ToolInvoker',
  Duration timeout = const Duration(seconds: 10),
}) {
  late FakeTool read;
  late FakeTool write;
  late FakeTool external;
  late FakeTool failing;
  late FakeTool slow;
  late FakeTool slow2;
  late ToolInvoker invoker;

  ToolContext context([CancelToken? cancel]) => ToolContext(
    sessionId: 'contract',
    clock: const SystemClock(),
    locale: 'de-DE',
    timeZone: 'Europe/Berlin',
    cancel: cancel,
  );

  ToolCallBlock call(String id, String tool, [String args = '{}']) =>
      ToolCallBlock(id: id, name: tool, argumentsJson: args);

  /// Runs [calls]; [onEvent] may answer confirmations or cancel.
  Future<List<ToolInvocationEvent>> run(
    List<ToolCallBlock> calls, {
    ToolContext? ctx,
    void Function(ToolInvocationEvent event)? onEvent,
  }) async {
    final events = <ToolInvocationEvent>[];
    final done = Completer<void>();
    invoker
        .invokeAll(calls, ctx ?? context())
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

  Map<String, ToolOutcome> outcomes(List<ToolInvocationEvent> events) => {
    for (final e in events.whereType<ToolFinished>()) e.call.id: e.outcome,
  };

  void expectIsCancelled(ToolOutcome o, String reason) {
    expect(o.isError, isTrue, reason: '$reason: Fehler-Outcome erwartet');
    expect(
      o.text,
      ToolOutcome.cancelledText,
      reason: '$reason: ToolOutcome.cancelled() erwartet',
    );
  }

  void expectCancelled(Iterable<ToolOutcome> outcomes) {
    expect(outcomes, isNotEmpty);
    for (final o in outcomes) {
      expectIsCancelled(o, 'abgebrochener Call');
    }
  }

  /// Rule for cancellation that holds for sequential and parallel invokers:
  /// a call whose tool did not complete gets `cancelled()`; a call whose
  /// tool really completed keeps its real (here: successful) outcome.
  void expectCancelledUnlessCompleted(
    List<ToolInvocationEvent> events,
    Map<String, FakeTool> toolOf,
  ) {
    outcomes(events).forEach((id, o) {
      final tool = toolOf[id]!;
      if (tool.completedCount > 0) {
        expect(o.isError, isFalse, reason: 'Call $id lief, echtes Outcome');
      } else {
        expectIsCancelled(o, 'Call $id lief nicht zu Ende');
      }
    });
  }

  group('$name erfüllt ToolInvoker-Vertrag', () {
    setUp(() async {
      read = FakeTool(name: 'contract__read');
      write = FakeTool(name: 'contract__write', risk: RiskLevel.write);
      external = FakeTool(
        name: 'contract__send',
        risk: RiskLevel.external,
        confirmation: (_) => 'Nachricht senden',
      );
      failing = FakeTool(name: 'contract__fail', throws: StateError('kaputt'));
      slow = FakeTool(
        name: 'contract__slow',
        delay: const Duration(seconds: 30),
      );
      slow2 = FakeTool(
        name: 'contract__slow2',
        delay: const Duration(seconds: 30),
      );
      invoker = await create(
        FakeToolCatalog([read, write, external, failing, slow, slow2]),
      );
    });

    test('keine Calls: Stream schließt ohne Events', () async {
      expect(await run(const []), isEmpty);
    });

    test('read und write laufen ohne Bestätigung', () async {
      final events = await run([
        call('1', 'contract__read'),
        call('2', 'contract__write'),
      ]);
      expect(events.whereType<ConfirmationNeeded>(), isEmpty);
      expect(outcomes(events).values.map((o) => o.isError), [false, false]);
      expect(read.callCount, 1);
      expect(write.callCount, 1);
    });

    test('Fehlerfälle werden zu Fehler-Outcomes', () async {
      final events = await run([
        call('1', 'contract__unknown'),
        call('2', 'contract__read', '{kaputt'),
        call('3', 'contract__fail'),
      ]);
      final o = outcomes(events);
      expect(o['1']!.isError, isTrue, reason: 'unbekanntes Tool');
      expect(o['2']!.isError, isTrue, reason: 'ungültiges JSON');
      expect(o['3']!.isError, isTrue, reason: 'Exception im Tool');
      expect(read.callCount, 0);
    });

    test('external: Bestätigung vor Ausführung, ja führt aus', () async {
      var executedBeforeAnswer = -1;
      final events = await run(
        [call('1', 'contract__send')],
        onEvent: (e) {
          if (e is ConfirmationNeeded) {
            expect(e.description, 'Nachricht senden');
            executedBeforeAnswer = external.callCount;
            e.respond(true);
          }
        },
      );
      expect(events.whereType<ConfirmationNeeded>(), hasLength(1));
      expect(executedBeforeAnswer, 0);
      expect(external.callCount, 1);
      expect(outcomes(events)['1']!.isError, isFalse);
    });

    test('external: nein führt nicht aus, kein Fehler-Outcome', () async {
      final events = await run(
        [call('1', 'contract__send')],
        onEvent: (e) {
          if (e is ConfirmationNeeded) e.respond(false);
        },
      );
      expect(external.callCount, 0);
      expect(outcomes(events)['1']!.isError, isFalse);
    });

    test('Antwort ist idempotent: erste gewinnt, keine Exception', () async {
      final events = await run(
        [call('1', 'contract__send')],
        onEvent: (e) {
          if (e is ConfirmationNeeded) {
            e
              ..respond(true)
              ..respond(false)
              ..respond(true);
            expect(e.answered, isTrue);
          }
        },
      );
      expect(external.callCount, 1);
      expect(outcomes(events)['1']!.isError, isFalse);
    });

    test(
      'Abbruch während Bestätigung: terminiert, Bestätigtes nie ausgeführt',
      () async {
        final cancel = CancelToken();
        ConfirmationNeeded? open;
        final events = await run(
          [call('1', 'contract__send'), call('2', 'contract__slow')],
          ctx: context(cancel),
          onEvent: (e) {
            if (e is ConfirmationNeeded) {
              open = e;
              cancel.cancel();
            }
          },
        );
        expect(open, isNotNull);
        expect(open!.answered, isTrue, reason: 'offene Bestätigung aufgelöst');
        expect(external.callCount, 0);
        expectIsCancelled(outcomes(events)['1']!, 'unbestätigter Call');
        expectCancelledUnlessCompleted(events, {'1': external, '2': slow});
      },
    );

    test(
      'Abbruch während Ausführung beendet offene Calls als Fehler',
      () async {
        final cancel = CancelToken();
        final events = await run(
          [call('1', 'contract__slow'), call('2', 'contract__slow2')],
          ctx: context(cancel),
          onEvent: (e) {
            if (e is ToolStarted && e.call.id == '1') {
              Timer(const Duration(milliseconds: 20), cancel.cancel);
            }
          },
        );
        expect(slow.completedCount + slow2.completedCount, 0);
        expectCancelled(outcomes(events).values);
      },
    );

    test('Abbruch: fertiger Call behält sein echtes Outcome', () async {
      final cancel = CancelToken();
      final events = await run(
        [call('1', 'contract__read'), call('2', 'contract__slow')],
        ctx: context(cancel),
        onEvent: (e) {
          if (e is ToolStarted && e.call.id == '2') {
            Timer(const Duration(milliseconds: 50), cancel.cancel);
          }
        },
      );
      expect(read.completedCount, 1);
      expect(outcomes(events)['1']!.isError, isFalse);
      expectIsCancelled(outcomes(events)['2']!, 'abgebrochener Call');
    });

    test('bereits abgebrochener Kontext führt kein Tool aus', () async {
      final events = await run([
        call('1', 'contract__read'),
        call('2', 'contract__send'),
      ], ctx: context(CancelToken()..cancel()));
      expect(read.callCount + external.callCount, 0);
      expect(events.whereType<ConfirmationNeeded>(), isEmpty);
      expectCancelled(outcomes(events).values);
    });
  });
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
