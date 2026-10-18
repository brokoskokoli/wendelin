import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'near_support.dart';
import 'tee_support.dart';

/// WP77 Nachbesserung: the GPU check runs in parallel to the NEAR session
/// attestation and must find the evidence of that attestation (not the
/// state cleared at its start), also after a rebuilt provider took over the
/// session.
void main() {
  final crypto = FakeAttestationCrypto(ed25519Result: true);
  final base = Uri.parse('https://cloud-api.test/v1');

  late FakeNearService service;
  late TeeServer server;
  late FixedClock clock;

  setUp(() {
    service = FakeNearService();
    clock = FixedClock(probeNow);
    server = TeeServer({
      'attestation/report': (_) {
        final doc = nearReportFor(service.publicKeyHex);
        editModel(doc, (m) {
          m['nvidia_payload'] = jsonEncode({
            'nonce': AttestCodec.hex(nearNonce),
            'evidence_list': [
              {'x': 1},
            ],
          });
        });
        return http.Response(
          jsonEncode(doc),
          200,
          headers: {'content-type': 'application/json'},
        );
      },
    });
  });

  AttestedProvider build(GpuCheckMode mode) {
    final settings = HttpSettings(clock: clock);
    final verifier = NearVerifier(
      crypto: crypto,
      baseUrl: base,
      model: nearModel,
      profileId: 'near',
      headers: () async => {'authorization': 'Bearer test'},
      client: server.client,
      settings: settings,
      nonceSource: () => nearNonce,
    );
    return AttestedProvider(
      inner: OpenAiChatAdapter(
        baseUrl: base,
        credentials: Credentials.apiKey('test', style: ApiKeyStyle.bearer),
        defaultModel: nearModel,
        client: server.client,
        settings: settings,
        wireCodec: NearE2eeChannel(crypto: NearReferenceCrypto()),
      ),
      verifier: verifier,
      profileId: 'near',
      sessionScope: 'near|$nearModel',
      gpuVerifier: NrasGpuVerifier(
        tokenChecker: FakeNrasTokenChecker(),
        baseUrl: base,
        // NRAS is down: a found evidence ends in nras_http_503, a missing
        // one in no_evidence.
        client: MockClient((_) async {
          return http.Response('', 503);
        }),
        evidenceSource: verifier.gpuEvidence,
      ),
      gpuMode: mode,
      settings: settings,
      retryDelay: Duration.zero,
      requireUpstreamEnforced: false,
    );
  }

  ChatRequest request() => ChatRequest(
    systemPrompt: 's',
    messages: [Message.user('u')],
    model: nearModel,
    maxTokens: 5,
  );

  Future<String> firstError(AttestedProvider p) async {
    final events = await p.chat(request()).toList();
    return events.whereType<ErrorEvent>().first.error.toString();
  }

  for (final mode in [GpuCheckMode.before, GpuCheckMode.after]) {
    test('${mode.name}: parallel zur Sitzung findet die GPU-Prüfung die '
        'Evidenz', () async {
      final p = build(mode);
      final message = await firstError(p);
      if (mode == GpuCheckMode.before) {
        expect(message, contains('nras_http_503'));
      }
      expect(message, isNot(contains('no_evidence')));
    });

    test(
      '${mode.name}: nach Übernahme der Sitzung bleibt die Evidenz',
      () async {
        final a = build(GpuCheckMode.off);
        await a.warmUp();
        expect(a.session, isNotNull);
        final b = build(mode);
        expect(b.adoptSessionOf(a), isTrue);
        final message = await firstError(b);
        expect(message, isNot(contains('no_evidence')));
        if (mode == GpuCheckMode.before) {
          expect(message, contains('nras_http_503'));
        }
        expect(
          server.count('attestation/report'),
          1,
          reason: 'keine neue Prüfung',
        );
      },
    );
  }
}
