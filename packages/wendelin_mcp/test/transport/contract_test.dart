import 'package:test/test.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

void main() {
  mcpClientContract(
    'Streamable HTTP, JSON-Antworten',
    transport: McpTransportKind.streamable,
  );
  mcpClientContract(
    'Streamable HTTP, SSE-Antworten',
    transport: McpTransportKind.streamable,
    style: FakeResponseStyle.sse,
  );
  mcpClientContract(
    'Legacy-SSE',
    transport: McpTransportKind.sse,
    serverMode: FakeTransportMode.legacySse,
  );
  mcpClientContract(
    'auto → Legacy-SSE',
    transport: McpTransportKind.auto,
    serverMode: FakeTransportMode.legacySse,
  );
  mcpClientContract(
    'eigene Fabrik (Streamable)',
    transport: McpTransportKind.streamable,
    style: FakeResponseStyle.sse,
    transportFactory: (kind, url, deps) => StreamableHttpTransport(url, deps),
  );

  test('Vertrag ist für beide Transporte registriert', () {
    expect(McpTransportKind.values, hasLength(3));
  });
}
