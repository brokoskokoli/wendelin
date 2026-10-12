import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Sequential invoker with switchable defects. With no defect it is correct,
/// which proves the failures below come from the defect alone.
final class _DefectiveInvoker implements ToolInvoker {
  _DefectiveInvoker(
    this.catalog, {
    this.checksCancelOnlyAtStart = false,
    this.reportsFinishedAsCancelled = false,
  });

  final ToolCatalog catalog;

  /// Defect: reads `ctx.cancel` once at the start and keeps starting tools.
  final bool checksCancelOnlyAtStart;

  /// Defect: turns real outcomes of completed tools into `cancelled()`.
  final bool reportsFinishedAsCancelled;

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) async* {
    final cancelledAtStart = ctx.cancel.isCancelled;
    bool cancelled() =>
        checksCancelOnlyAtStart ? cancelledAtStart : ctx.cancel.isCancelled;
    for (final call in calls) {
      yield ToolStarted(call);
      final tool = catalog.lookup(call.name);
      final args = call.tryDecodeArguments();
      ToolOutcome outcome;
      if (cancelled()) {
        outcome = ToolOutcome.cancelled();
      } else if (tool == null || args == null) {
        outcome = ToolOutcome.error('ungültig');
      } else {
        var approved = true;
        if (tool.risk == RiskLevel.external) {
          final c = ConfirmationNeeded(
            call,
            tool.describeForConfirmation(args),
            Completer<bool>(),
          );
          yield c;
          approved = await Future.any([
            c.decision.future,
            ctx.cancel.whenCancelled.then((_) => false),
          ]);
          c.respond(false);
        }
        if (cancelled()) {
          outcome = ToolOutcome.cancelled();
        } else if (!approved) {
          outcome = ToolOutcome.declined();
        } else {
          try {
            outcome = await tool.execute(args, ctx);
            if (reportsFinishedAsCancelled && ctx.cancel.isCancelled) {
              outcome = ToolOutcome.cancelled();
            }
          } on CancelledException {
            outcome = ToolOutcome.cancelled();
          } on Object catch (e) {
            outcome = ToolOutcome.error('$e');
          }
        }
      }
      yield ToolFinished(call, outcome, Duration.zero);
    }
  }
}

/// Defect: asks all confirmations of a batch at once.
final class _EagerConfirmationsInvoker implements ToolInvoker {
  _EagerConfirmationsInvoker(this.catalog);

  final ToolCatalog catalog;

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) async* {
    final asks = <ToolCallBlock, ConfirmationNeeded>{};
    for (final call in calls) {
      yield ToolStarted(call);
      final tool = catalog.lookup(call.name)!;
      if (tool.risk == RiskLevel.external) {
        final c = ConfirmationNeeded(call, 'ok?', Completer<bool>());
        asks[call] = c;
        yield c;
      }
    }
    for (final call in calls) {
      final approved =
          await (asks[call]?.decision.future ?? Future.value(true));
      final tool = catalog.lookup(call.name)!;
      yield ToolFinished(
        call,
        approved
            ? await tool.execute(call.tryDecodeArguments()!, ctx)
            : ToolOutcome.declined(),
        Duration.zero,
      );
    }
  }
}

void main() {
  final Matcher fails = throwsA(isA<TestFailure>());

  group('toolInvokerContract erkennt', () {
    test('korrekte Variante besteht alle Prüfungen', () async {
      for (final check in toolInvokerContractChecks(
        _DefectiveInvoker.new,
      ).values) {
        await check();
      }
    });

    test('Start weiterer Tools nach Abbruch', () async {
      final checks = toolInvokerContractChecks(
        (c) => _DefectiveInvoker(c, checksCancelOnlyAtStart: true),
      );
      await expectLater(
        checks[ToolInvokerChecks.cancelDuringExecution]!(),
        fails,
      );
      await expectLater(
        checks[ToolInvokerChecks.cancelKeepsCompleted]!(),
        fails,
      );
      await expectLater(
        checks[ToolInvokerChecks.cancelDuringConfirmation]!(),
        fails,
      );
    });

    test('fertige Calls fälschlich als abgebrochen gemeldet', () async {
      final checks = toolInvokerContractChecks(
        (c) => _DefectiveInvoker(c, reportsFinishedAsCancelled: true),
      );
      await expectLater(
        checks[ToolInvokerChecks.cancelKeepsCompleted]!(),
        fails,
      );
    });

    test('gleichzeitige Bestätigungen', () async {
      final checks = toolInvokerContractChecks(_EagerConfirmationsInvoker.new);
      await expectLater(
        checks[ToolInvokerChecks.sequentialConfirmations]!(),
        fails,
      );
    });
  });
}
