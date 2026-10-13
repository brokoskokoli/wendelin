import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';
import 'support.dart';

/// Everything a user, the model, the audit log or an export could see.
List<String> visible(
  HttpCallResult r, {
  ToolOutcome? outcome,
  HttpToolTestResult? test,
}) => [
  r.text,
  '${r.error}',
  '$r',
  '${r.request}',
  jsonEncode(r.request?.toJson()),
  '${r.finalUrl}',
  '${r.contentType}',
  '${r.reason}',
  if (outcome != null) ...[outcome.text, '${outcome.summary}', '$outcome'],
  if (test != null) ...[test.preview, '${test.error}', '$test'],
];

void expectNoCanary(Iterable<String> texts) {
  final variants = {
    canary,
    'Bearer $canary',
    canary.substring(0, 12),
    Uri.encodeComponent(canary),
  };
  for (final t in texts) {
    for (final v in variants) {
      expect(t, isNot(contains(v)));
    }
  }
}

void main() {
  final echoes = <String, http.Response Function(http.Request)>{
    'Server spiegelt Header im Body': (r) =>
        http.Response('Du hast gesendet: ${r.headers['Authorization']}', 200),
    'Server spiegelt JSON-escaped': (r) => jsonResponse(
      jsonEncode({'auth': r.headers['Authorization'], 'k': canary}),
    ),
    'Server spiegelt URL-kodiert': (r) =>
        http.Response('token=${Uri.encodeQueryComponent(canary)}', 200),
    'Fehlerseite spiegelt Secret (401)': (r) => http.Response(
      'invalid token ${r.headers['Authorization']}',
      401,
      reasonPhrase: 'Unauthorized',
    ),
    'Fehlerseite spiegelt Secret (500)': (r) =>
        http.Response('crash $canary', 500, reasonPhrase: 'Bad $canary'),
    'Weiterleitung auf fremden Origin mit Secret': (r) => http.Response(
      '',
      302,
      headers: {'location': 'https://evil.example/?t=$canary'},
    ),
    'responsePath auf das Secret': (r) => jsonResponse(
      jsonEncode({
        'data': {'token': canary},
      }),
    ),
    'Text-Content-Type mit Secret': (r) =>
        http.Response('x', 200, headers: {'content-type': 'text/x-$canary'}),
    'Content-Type mit Secret': (r) => http.Response.bytes(
      [1, 2, 3],
      200,
      headers: {'content-type': 'image/x-$canary'},
    ),
  };

  for (final MapEntry(key: name, value: answer) in echoes.entries) {
    test('Kanarienwert: $name', () async {
      final m = mockRunner((r) async => answer(r));
      final d = def(
        responsePath: name.contains('responsePath') ? 'data' : null,
      );
      final args = {'id': '1'};
      final r = await m.runner.call(d, args);
      // Das Secret ging tatsächlich raus …
      expect(m.rec.requests.first.headers['Authorization'], 'Bearer $canary');
      // … erscheint aber nirgends sichtbar.
      final tool = HttpTool(d, m.runner);
      final outcome = await tool.execute(args, ctx());
      final tested = await HttpToolTester(m.runner).run(d, args);
      expectNoCanary(visible(r, outcome: outcome, test: tested));
      expectNoCanary([tool.describeForConfirmation(args), jsonEncode(args)]);
    });
  }

  group('zweiter Kanarienwert mit +/=" und Leerzeichen', () {
    final encodings = <String, String Function(String)>{
      'roh': (v) => v,
      'JSON-escaped': (v) {
        final e = jsonEncode(v);
        return e.substring(1, e.length - 1);
      },
      'URL-Komponente': Uri.encodeComponent,
      'URL-Query': Uri.encodeQueryComponent,
    };
    for (final MapEntry(key: name, value: encode) in encodings.entries) {
      for (final asJson in [false, true]) {
        test('Echo $name${asJson ? ' im JSON-Dokument' : ''}', () async {
          final m = mockRunner(
            (_) async => asJson
                ? jsonResponse(
                    jsonEncode({'echo': canary2, 'enc': encode(canary2)}),
                  )
                : http.Response('echo=${encode(canary2)};', 200),
            secrets: {'tok': canary2},
          );
          final r = await m.runner.call(def(), {'id': '1'});
          expect(
            m.rec.requests.single.headers['Authorization'],
            'Bearer $canary2',
          );
          final texts = visible(r);
          for (final t in texts) {
            for (final form in encodings.values) {
              expect(t, isNot(contains(form(canary2))), reason: name);
            }
          }
          expect(r.text, contains(scrubbedSecret));
        });
      }
    }
  });

  test('Kanarienwert: Definition, Export, toString, Fake', () async {
    final m = mockRunner((_) async => jsonResponse('{}'));
    final defs = [
      def(),
      def(name: 'custom', auth: CustomHeadersAuth({'X-Key': 'ref-key'})),
      def(
        name: 'n8n',
        auth: const ApiKeyAuth('tok', headerName: 'X-N8n-Api-Key'),
      ),
    ];
    for (final d in defs) {
      await m.runner.call(d, {'id': '1'});
    }
    final integrations = HttpToolsIntegration.all(defs, m.runner);
    expectNoCanary([
      jsonEncode(exportHttpTools(defs)),
      for (final d in defs) ...['$d', jsonEncode(d.toJson()), '${d.auth}'],
      '${m.secrets}',
      for (final i in integrations)
        for (final t in i.tools) ...[
          t.name,
          t.description,
          jsonEncode(t.inputSchema),
          t.describeForConfirmation({'id': '1'}),
          t.describeForConfirmation({}),
        ],
    ]);
  });

  test(
    'Kanarienwert: Secret mit Zeilenumbruch erscheint nicht im Fehler',
    () async {
      final m = mockRunner(
        (_) async => jsonResponse('{}'),
        secrets: {'tok': '$canary\r\nX: y'},
      );
      final r = await m.runner.call(def(), {'id': '1'});
      expect(r.isError, isTrue);
      expectNoCanary(visible(r));
    },
  );

  test('describeForConfirmation liest keine Secrets', () {
    final m = mockRunner((_) async => jsonResponse('{}'));
    HttpTool(def(), m.runner).describeForConfirmation({'id': '1'});
    expect(m.secrets.reads, isEmpty);
  });
}
