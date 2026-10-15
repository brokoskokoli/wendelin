@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

// Live-Test gegen die NEAR AI Cloud, sparsam: ein Modell, wenige Tokens, drei
// kleine Anfragen. Der Key kommt nur aus der Umgebung und wird nie ausgegeben.
//   set -a; . ~/.wendelin-live.env; set +a; dart test -t live --run-skipped test/live/near_live_test.dart
//
// Die Quote-Signaturkette prüft hier nur die Fake-Krypto nicht; die echte
// DCAP-Prüfung gegen aufgezeichnete NEAR-Quotes läuft in
// native/attest/tests/near_quotes.rs. Dieser Test beweist die Bindungen
// (Schlüssel, TLS-Zertifikat, Nonce, RTMR3, Compose), E2EE mit Tools und die
// Quittung gegen den echten Dienst.

const _model = 'z-ai/glm-5.3-flash';
final _base = Uri.parse('https://cloud-api.near.ai/v1');
final _key = Platform.environment['NEAR_AI_API_KEY'];

const _tool = ToolSpec(
  name: 'timer__set',
  description: 'Stellt einen Timer in Minuten.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'minutes': {'type': 'integer', 'description': 'Minuten'},
    },
    'required': ['minutes'],
  },
);

ChatRequest _request() => ChatRequest(
  systemPrompt: 'Du bist Wendelin. Nutze Werkzeuge, wenn sie passen.',
  messages: [Message.user('Stell einen Timer auf 12 Minuten.')],
  tools: [_tool],
  model: _model,
  maxTokens: 300,
);

bool _skip() {
  final key = _key;
  if (key == null || key.isEmpty) {
    markTestSkipped('NEAR_AI_API_KEY nicht gesetzt');
    return true;
  }
  return false;
}

/// HTTP 402 (Konto ohne Guthaben/Limit) wird als Auth-/Guthabenfehler
/// gemeldet: der Lauf beweist dann nichts über den Antwortweg.
bool _noCredit(Object? error) {
  if (error is AuthException ||
      (error is ProviderException && '$error'.contains('402'))) {
    // ignore: avoid_print
    print(
      'übersprungen: kein Guthaben (HTTP 402, cloud.near.ai: Limit setzen)',
    );
    markTestSkipped('übersprungen: kein Guthaben');
    return true;
  }
  return false;
}

NearVerifier _verifier(http.Client client) => NearVerifier(
  crypto: FakeAttestationCrypto(),
  baseUrl: _base,
  model: _model,
  profileId: 'near-live',
  headers: () async => {'authorization': 'Bearer $_key'},
  client: client,
);

void main() {
  test(
    'Attestierung: Schlüssel, Nonce, Ereignisprotokoll, Gateway gebunden',
    () async {
      if (_skip()) return;
      final client = http.Client();
      final result = await _verifier(client).attest();
      client.close();
      // ignore: avoid_print
      print('Stufen: ${result.stages}');
      expect(
        result.status,
        AttestationStatus.green,
        reason: '${result.stages}',
      );
      expect(result.session!.workloadId, _model);
      expect(result.session!.e2eeKey!.publicKey, hasLength(32));
    },
  );

  test(
    'E2EE-Chat mit Werkzeugaufruf, Streaming, Quittung des Modells',
    () async {
      if (_skip()) return;
      final client = http.Client();
      const settings = HttpSettings();
      final provider = AttestedProvider(
        inner: OpenAiChatAdapter(
          baseUrl: _base,
          credentials: Credentials.apiKey(_key!, style: ApiKeyStyle.bearer),
          defaultModel: _model,
          client: client,
          settings: settings,
          wireCodec: NearE2eeChannel(crypto: NearReferenceCrypto()),
        ),
        verifier: _verifier(client),
        profileId: 'near-live',
        settings: settings,
        requireUpstreamEnforced: false,
      );
      final events = await provider.chat(_request()).toList();
      if (events.last is ErrorEvent &&
          _noCredit((events.last as ErrorEvent).error)) {
        client.close();
        return;
      }
      expect(events.whereType<ErrorEvent>(), isEmpty);
      final call = events.whereType<ToolCallComplete>().single.call;
      expect(call.name, 'timer__set');
      expect(jsonDecode(call.argumentsJson), {'minutes': 12});
      final report = await provider.pendingReport();
      // ignore: avoid_print
      print('Quittung: ${report?.status} ${report?.detail ?? ''}');
      expect(
        report!.status,
        AttestationStatus.green,
        reason: '${report.detail}',
      );
      client.close();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('E2EE-Chat mit Werkzeugaufruf ohne Streaming', () async {
    if (_skip()) return;
    final client = http.Client();
    final session = (await _verifier(client).attest()).session!;
    final wire = NearE2eeWire(
      crypto: NearReferenceCrypto(),
      key: session.e2eeKey!,
    );
    final sealed = wire.seal({
      'model': _model,
      'messages': [
        {'role': 'user', 'content': 'Stell einen Timer auf 12 Minuten.'},
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': _tool.name,
            'description': _tool.description,
            'parameters': _tool.inputSchema,
          },
        },
      ],
      'max_tokens': 300,
      'stream': false,
    });
    final response = await client.post(
      _base.replace(path: '${_base.path}/chat/completions'),
      headers: {
        'authorization': 'Bearer $_key',
        'content-type': 'application/json',
        ...wire.headers,
      },
      body: sealed.wire,
    );
    client.close();
    if (response.statusCode == 402) {
      _noCredit(const AuthException('HTTP 402'));
      return;
    }
    expect(response.statusCode, 200);
    expect(
      response.body,
      isNot(contains('timer__set')),
      reason: 'Klartext im Wire',
    );
    final opened = jsonDecode(
      wire.openJson(utf8.decode(response.bodyBytes)),
    ) as Map<String, Object?>;
    final msg = ((opened['choices']! as List).first as Map)['message']! as Map;
    final fn = ((msg['tool_calls']! as List).first as Map)['function']! as Map;
    expect(fn['name'], 'timer__set');
    expect(jsonDecode(fn['arguments']! as String), {'minutes': 12});
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Kaputtes Chiffrat wird vom Dienst abgelehnt (Wire-Kontrolle, kostenlos)', () async {
    if (_skip()) return;
    // Kein Chat nötig: eine Anfrage mit kaputtem Chiffrat, dann Auswertung der
    // Fehlerform (Wire-Kontrolle des Dienstes, kostet 0).
    final client = http.Client();
    final session = (await _verifier(client).attest()).session!;
    final wire = NearE2eeWire(
      crypto: NearReferenceCrypto(),
      key: session.e2eeKey!,
    );
    final response = await client.post(
      _base.replace(path: '${_base.path}/chat/completions'),
      headers: {
        'authorization': 'Bearer $_key',
        'content-type': 'application/json',
        ...wire.headers,
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'user', 'content': AttestCodec.hex(Uint8List(100))},
        ],
        'max_tokens': 5,
      }),
    );
    client.close();
    // ignore: avoid_print
    print('Kaputtes Chiffrat: HTTP ${response.statusCode}');
    expect(response.statusCode, isNot(200));
  });
}
