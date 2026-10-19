import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

final class _Audit implements ToolAuditSink {
  final entries = <ToolAuditEntry>[];
  @override
  void record(ToolAuditEntry entry) => entries.add(entry);
}

/// Message-like tool: its arguments hold a private text.
final class _MessageTool implements Tool, AuditArgumentsRedactor {
  _MessageTool({this.failRedaction = false});

  final bool failRedaction;

  @override
  String get name => 'msg__send';
  @override
  String get description => 'Test';
  @override
  Map<String, Object?> get inputSchema => const {'type': 'object'};
  @override
  RiskLevel get risk => RiskLevel.read;
  @override
  Future<ToolOutcome> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolOutcome.text('ok');
  @override
  String describeForConfirmation(Map<String, Object?> args) => 'x';
  @override
  Future<String> redactedArguments(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    if (failRedaction) throw StateError('kaputt');
    return '{"recipient":"Anna"}';
  }
}

ToolContext _ctx() => ToolContext(
  sessionId: 's1',
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);

Future<ToolAuditEntry> _audited(Tool tool) async {
  final audit = _Audit();
  final executor = ToolExecutor(catalog: FakeToolCatalog([tool]), audit: audit);
  await executor.invokeAll([
    ToolCallBlock(
      id: '1',
      name: tool.name,
      argumentsJson: '{"to":"1","text":"Geheimer Text"}',
    ),
  ], _ctx()).drain<void>();
  return audit.entries.single;
}

void main() {
  test(
    'Audit: Werkzeug mit AuditArgumentsRedactor speichert nur die Kurzform',
    () async {
      final e = await _audited(_MessageTool());
      expect(e.argumentsJson, '{"recipient":"Anna"}');
    },
  );

  test('Audit: scheitert die Kurzform, steht nie der Rohtext darin', () async {
    final e = await _audited(_MessageTool(failRedaction: true));
    expect(e.argumentsJson, '{}');
  });

  test('Audit: gewöhnliche Werkzeuge behalten ihre Argumente', () async {
    final e = await _audited(FakeTool(name: 'plain__x'));
    expect(e.argumentsJson, contains('Geheimer Text'));
  });
}
