import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../src/client.dart';
import '../src/config.dart';
import '../src/errors.dart';
import '../src/protocol.dart';
import '../src/transport/http_call.dart';
import 'fake_mcp_server.dart';
import 'fakes.dart';

/// Contract every MCP transport must pass, run through [McpClient] against
/// a [FakeMcpServer] in [serverMode]/[style]: lifecycle, pagination, tool
/// calls and errors, notifications and server requests in the stream (when
/// the transport can carry them), time limit, cancellation, size limit.
///
/// [transportFactory] injects the implementation under test; `null` uses
/// the built-in one for [transport].
void mcpClientContract(
  String name, {
  required McpTransportKind transport,
  FakeTransportMode serverMode = FakeTransportMode.streamable,
  FakeResponseStyle style = FakeResponseStyle.json,
  McpTransportFactory? transportFactory,
}) {
  final streams =
      serverMode == FakeTransportMode.legacySse ||
      style == FakeResponseStyle.sse;

  group('MCP-Client-Vertrag: $name', () {
    late FakeMcpServer server;
    late http.Client httpClient;
    final clients = <McpClient>[];

    setUp(() async {
      server = await FakeMcpServer.start(
        mode: serverMode,
        style: style,
        tools: [
          for (var i = 1; i <= 5; i++)
            FakeMcpTool(
              'tool_$i',
              description: 'Tool $i',
              annotations: {'readOnlyHint': i.isOdd},
              handler: (args) => {
                'content': [
                  {'type': 'text', 'text': 'Ergebnis $i: ${args['q']}'},
                ],
              },
            ),
          FakeMcpTool(
            'broken',
            handler: (_) => {
              'content': [
                {'type': 'text', 'text': 'kaputt'},
              ],
              'isError': true,
            },
          ),
        ],
      );
      httpClient = http.Client();
    });

    tearDown(() async {
      for (final c in clients) {
        await c.dispose();
      }
      clients.clear();
      httpClient.close();
      await server.close();
    });

    McpClient client({McpTimeouts timeouts = const McpTimeouts()}) {
      final c = McpClient(
        config: McpServerConfig(
          id: 'contract',
          name: 'Vertrag',
          slug: 'vertrag',
          url: server.url,
          transport: transport,
        ),
        httpClient: httpClient,
        secrets: FakeMcpSecrets(),
        timeouts: timeouts,
        transportFactory: transportFactory,
      );
      clients.add(c);
      return c;
    }

    test('initialize handelt die Version aus und meldet initialized', () async {
      final info = await client().initialize();
      expect(info.name, 'fake-mcp');
      expect(mcpProtocolVersions, contains(info.protocolVersion));
      expect(server.clientNotifications, contains('notifications/initialized'));
    });

    test('tools/list sammelt alle Seiten (Paginierung)', () async {
      server.pageSize = 2;
      final tools = await client().listTools();
      expect(tools.map((t) => t.name), [
        'tool_1',
        'tool_2',
        'tool_3',
        'tool_4',
        'tool_5',
        'broken',
      ]);
      expect(
        server.requests.where((r) => r.rpcMethod == 'tools/list').length,
        greaterThanOrEqualTo(3),
      );
    });

    test('tools/call liefert Inhalt und isError', () async {
      final c = client();
      final ok = await c.callTool('tool_2', {'q': 'x'});
      expect(ok.isError, isFalse);
      expect(ok.content.single['text'], 'Ergebnis 2: x');
      final failed = await c.callTool('broken', const {});
      expect(failed.isError, isTrue);
    });

    test('JSON-RPC-Fehler wird zur McpException mit Code', () async {
      await expectLater(
        client().callTool('gibt_es_nicht', const {}),
        throwsA(
          isA<McpException>()
              .having((e) => e.kind, 'kind', McpErrorKind.server)
              .having((e) => e.rpcCode, 'rpcCode', -32602),
        ),
      );
    });

    test('ping', () async {
      await client().ping();
    });

    test('Zeitlimit beendet den Aufruf mit timeout', () async {
      final c = client(
        timeouts: const McpTimeouts(response: Duration(milliseconds: 400)),
      );
      await c.initialize();
      server.hang = true;
      await expectLater(
        c.callTool('tool_1', const {}),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.timeout,
          ),
        ),
      );
    });

    test('Abbruch über CancelToken endet sofort mit cancelled', () async {
      final c = client();
      await c.initialize();
      server.hang = true;
      final cancel = CancelToken();
      final watch = Stopwatch()..start();
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 100), cancel.cancel),
      );
      await expectLater(
        c.callTool('tool_1', const {}, cancel: cancel),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.cancelled,
          ),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('zu große Antwort wird abgewiesen', () async {
      final c = client(timeouts: const McpTimeouts(maxResponseBytes: 4000));
      await c.initialize();
      server.padding = 8000;
      await expectLater(
        c.callTool('tool_1', const {}),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.tooLarge,
          ),
        ),
      );
    });

    if (streams) {
      test('Benachrichtigungen im Stream: list_changed', () async {
        final c = client();
        final changed = c.toolsChanged.first;
        server.sendListChanged = true;
        final result = await c.callTool('tool_1', {'q': 1});
        expect(result.content.single['text'], 'Ergebnis 1: 1');
        await changed.timeout(const Duration(seconds: 5));
      });

      test(
        'Server-Anfragen: ping beantwortet, Rest „nicht unterstützt“',
        () async {
          final c = client();
          server.sendServerRequests = true;
          await c.callTool('tool_1', const {});
          for (var i = 0; i < 250 && server.clientAnswers.length < 2; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          final errors = server.clientAnswers.where((a) => a['error'] != null);
          expect(
            (errors.single['error']! as Map<String, Object?>)['code'],
            rpcMethodNotFound,
          );
          expect(
            server.clientAnswers.where((a) => a['result'] != null),
            hasLength(1),
          );
        },
      );
    }
  });
}
