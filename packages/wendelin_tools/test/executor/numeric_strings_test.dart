// WP150: models quote numbers (`"100"`); the executor turns strictly decimal
// strings into numbers before validating.
import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

final _ctx = ToolContext(
  sessionId: 's1',
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);

ToolCallBlock _call(String id, String tool, [String args = '{}']) =>
    ToolCallBlock(id: id, name: tool, argumentsJson: args);

Future<Map<String, ToolOutcome>> _outcomes(
  ToolInvoker invoker,
  List<ToolCallBlock> calls,
) async => {
  for (final e
      in (await invoker.invokeAll(calls, _ctx).toList())
          .whereType<ToolFinished>())
    e.call.id: e.outcome,
};

void main() {
  test('Zahl als String wird vor der Prüfung zur Zahl (WP150)', () async {
    final tool = FakeTool(
      name: 'p__s',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'pct': {'type': 'integer'},
          'temp': {'type': 'number'},
          'text': {'type': 'string'},
          'list': {
            'type': 'array',
            'items': {'type': 'integer'},
          },
          'either': {
            'type': ['string', 'integer'],
          },
        },
      },
    );
    final ex = ToolExecutor(catalog: FakeToolCatalog([tool]));
    final o = (await _outcomes(ex, [
      _call(
        '1',
        'p__s',
        '{"pct":" 70 ","temp":"21.5","text":"100","list":["1",2],'
            '"either":"7"}',
      ),
    ]))['1']!;
    expect(o.isError, isFalse);
    final args = tool.calls.single;
    expect(args['pct'], 70);
    expect(args['pct'], isA<int>());
    expect(args['temp'], 21.5);
    expect(args['text'], '100');
    expect(args['list'], [1, 2]);
    expect(args['either'], '7');
  });

  for (final bad in ['abc', '100%', '1.5', '1e3', '', '0x10']) {
    test('integer-Feld lehnt "$bad" weiterhin ab', () async {
      final tool = FakeTool(
        name: 'p__s',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'pct': {'type': 'integer'},
          },
        },
      );
      final ex = ToolExecutor(catalog: FakeToolCatalog([tool]));
      final o = (await _outcomes(ex, [
        _call('1', 'p__s', '{"pct":"$bad"}'),
      ]))['1']!;
      expect(o.isError, isTrue);
      expect(o.text, contains('erwartet integer, erhalten string'));
      expect(tool.callCount, 0);
    });
  }

  for (final (name, value) in [
    ('sehr lange Ziffernfolge', '1' * 40),
    ('sehr lange Dezimalzahl', '${'9' * 400}.5'),
  ]) {
    test('$name wirft nicht, sondern wird als Typfehler gemeldet', () async {
      final tool = FakeTool(
        name: 'p__s',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'pct': {'type': 'integer'},
          },
        },
      );
      final ex = ToolExecutor(catalog: FakeToolCatalog([tool]));
      final o = (await _outcomes(ex, [
        _call('1', 'p__s', '{"pct":"$value"}'),
      ]))['1']!;
      expect(o.isError, isTrue);
      expect(o.text, contains('erwartet integer, erhalten string'));
      expect(tool.callCount, 0);
    });
  }

  test('Zahl-String außerhalb von minimum/maximum wird abgelehnt', () async {
    final tool = FakeTool(
      name: 'p__s',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'pct': {'type': 'integer', 'minimum': 0, 'maximum': 100},
        },
      },
    );
    final ex = ToolExecutor(catalog: FakeToolCatalog([tool]));
    for (final v in ['150', '-1']) {
      final o = (await _outcomes(ex, [
        _call('1', 'p__s', '{"pct":"$v"}'),
      ]))['1']!;
      expect(o.isError, isTrue, reason: v);
      expect(tool.callCount, 0, reason: v);
    }
  });
}
