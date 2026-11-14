// WP200: which failures of the executor are transient (`retryable`).
import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

ToolCallBlock _call(String id, String tool) =>
    ToolCallBlock(id: id, name: tool, argumentsJson: '{}');

void main() {
  test('Timeout ist retryable, Tool-Fehler und -Ausnahme nicht', () async {
    final hang = FakeTool(
      name: 'p__hang',
      handler: (args, ctx) async {
        await ctx.cancel.whenCancelled;
        return ToolOutcome.text('zu spät');
      },
    );
    final fails = FakeTool(
      name: 'p__fails',
      handler: (args, ctx) async => ToolOutcome.error('kaputt'),
    );
    final throws = FakeTool(name: 'p__throws', throws: StateError('x'));
    final executor = ToolExecutor(
      catalog: FakeToolCatalog([hang, fails, throws]),
      timeout: const Duration(milliseconds: 50),
    );
    final events = await executor.invokeAll([
      _call('1', 'p__hang'),
      _call('2', 'p__fails'),
      _call('3', 'p__throws'),
    ], _ctx()).toList();
    final o = {
      for (final e in events.whereType<ToolFinished>()) e.call.id: e.outcome,
    };
    expect(o['1']!.retryable, isTrue);
    expect(o['2']!.isError, isTrue);
    expect(o['2']!.retryable, isFalse);
    expect(o['3']!.isError, isTrue);
    expect(o['3']!.retryable, isFalse);
  });
}

ToolContext _ctx() => ToolContext(
  sessionId: 's1',
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);
