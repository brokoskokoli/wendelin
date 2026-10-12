import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Reference invoker in the style required by WP03: all calls start at once
/// and run in parallel, confirmations are asked one after another. Proves
/// that `toolInvokerContract` does not assume sequential execution.
final class ParallelToolInvoker implements ToolInvoker {
  ParallelToolInvoker(this.catalog);

  final ToolCatalog catalog;

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) {
    final out = StreamController<ToolInvocationEvent>();
    var confirmations = Future<void>.value();

    Future<void> runOne(ToolCallBlock call) async {
      final start = ctx.clock.now();
      final tool = catalog.lookup(call.name);
      final args = call.tryDecodeArguments();
      ToolOutcome outcome;
      if (ctx.cancel.isCancelled) {
        outcome = ToolOutcome.cancelled();
      } else if (tool == null) {
        outcome = ToolOutcome.error('Unbekanntes Tool ${call.name}');
      } else if (args == null) {
        outcome = ToolOutcome.error('Ungültige Argumente');
      } else {
        var approved = true;
        if (tool.risk == RiskLevel.external) {
          final previous = confirmations;
          final mine = Completer<void>();
          confirmations = mine.future;
          await previous;
          if (!ctx.cancel.isCancelled) {
            final c = ConfirmationNeeded(
              call,
              tool.describeForConfirmation(args),
              Completer<bool>(),
            );
            out.add(c);
            approved = await Future.any([
              c.decision.future,
              ctx.cancel.whenCancelled.then((_) => false),
            ]);
            c.respond(false);
          }
          mine.complete();
        }
        if (ctx.cancel.isCancelled) {
          outcome = ToolOutcome.cancelled();
        } else if (!approved) {
          outcome = ToolOutcome.declined();
        } else {
          try {
            outcome = await tool.execute(args, ctx);
          } on CancelledException {
            outcome = ToolOutcome.cancelled();
          } on Object catch (e) {
            outcome = ToolOutcome.error('Fehler: $e');
          }
        }
      }
      out.add(ToolFinished(call, outcome, ctx.clock.now().difference(start)));
    }

    () async {
      final running = <Future<void>>[];
      for (final call in calls) {
        out.add(ToolStarted(call));
        running.add(runOne(call));
      }
      await Future.wait(running);
      await out.close();
    }();
    return out.stream;
  }
}

void main() {
  toolInvokerContract(ParallelToolInvoker.new, name: 'ParallelToolInvoker');

  test('reference invoker really runs calls in parallel', () async {
    final a = FakeTool(name: 'p__a', delay: const Duration(milliseconds: 100));
    final b = FakeTool(name: 'p__b', delay: const Duration(milliseconds: 100));
    final invoker = ParallelToolInvoker(FakeToolCatalog([a, b]));
    final watch = Stopwatch()..start();
    await invoker.invokeAll(
      const [
        ToolCallBlock(id: '1', name: 'p__a', argumentsJson: '{}'),
        ToolCallBlock(id: '2', name: 'p__b', argumentsJson: '{}'),
      ],
      ToolContext(
        sessionId: 's',
        clock: const SystemClock(),
        locale: 'de',
        timeZone: 'UTC',
      ),
    ).toList();
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 180)));
  });
}
