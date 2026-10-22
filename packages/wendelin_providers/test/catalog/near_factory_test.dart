import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

ProviderProfile near({Map<String, Object?>? options, String? url}) =>
    ProviderProfile(
      id: 'near1',
      name: 'NEAR AI (TEE)',
      type: ProviderType.openaiCompatible,
      baseUrl: url ?? 'https://cloud-api.near.ai/v1',
      defaultModel: 'z-ai/glm-5.3-flash',
      privacy: PrivacyLevel.tee,
      authMethod: const ApiKeyAuth('ref'),
      options: options ?? const {'attestation': 'near'},
    );

void main() {
  test('Vorlage „NEAR AI (TEE)“: nur eigene E2EE-Flotte mit Werkzeugen', () {
    final t = providerTemplates.firstWhere((t) => t.id == 'near');
    expect(t.name, 'NEAR AI (TEE)');
    expect(t.baseUrl, 'https://cloud-api.near.ai/v1');
    expect(t.privacy, PrivacyLevel.tee);
    expect(t.suggestedModel, 'Qwen/Qwen3.6-35B-A3B-FP8');
    expect(t.options, {
      'attestation': 'near',
      'ownedBy': 'nearai',
      'toolsOnly': true,
    });
    expect(
      attestationKind(t.toProfile(id: 'x', secretRef: 'r')),
      AttestationKind.near,
    );
  });

  test('attestationKind unterscheidet die Anbieter', () {
    expect(attestationKind(near()), AttestationKind.near);
    expect(
      attestationKind(near(options: const {'attestation': 'phala'})),
      AttestationKind.phala,
    );
    expect(
      attestationKind(
        near(options: const {}, url: 'https://api.redpill.ai/v1'),
      ),
      AttestationKind.phala,
    );
    expect(
      attestationKind(
        near(options: const {}, url: 'https://api.openai.com/v1'),
      ),
      AttestationKind.none,
    );
    expect(needsAttestation(near()), isTrue);
  });

  test('Fabrik baut einen geprüften Anbieter, ohne Prüfmodul gar keinen', () {
    final wiring = AttestationWiring(
      crypto: FakeAttestationCrypto(),
      nearCrypto: NearReferenceCrypto(),
      gpuMode: GpuCheckMode.before,
    );
    final p = ProviderFactory.create(
      near(),
      (_) async => 'k',
      attestation: wiring,
    );
    expect(p, isA<AttestedProvider>());
    final attested = p as AttestedProvider;
    expect(attested.caps.tee, isTrue);
    expect(attested.caps.tools, isTrue);
    expect(attested.gpuMode, GpuCheckMode.before);
    expect(attested.inner.wireCodec, isA<NearE2eeChannel>());
    expect(
      () => ProviderFactory.create(near(), (_) async => 'k'),
      throwsArgumentError,
    );
    expect(
      () => ProviderFactory.create(
        near(),
        (_) async => 'k',
        attestation: AttestationWiring(crypto: FakeAttestationCrypto()),
      ),
      throwsArgumentError,
    );
  });

  test('API-Schlüssel nie über einen Client außerhalb des Pin-Gates', () async {
    final viaGate = <String>[]; // 'enforce|path'
    final viaOther = <http.BaseRequest>[];
    http.Client record(bool enforce) => MockClient((r) async {
      viaGate.add('$enforce|${r.url.path}|${r.headers['authorization']}');
      return http.Response('{}', 500);
    });
    final wiring = AttestationWiring(
      crypto: FakeAttestationCrypto(),
      nearCrypto: NearReferenceCrypto(),
      gpuMode: GpuCheckMode.before,
      pinnedClient: (gate, {required enforce}) => record(enforce),
    );
    final p = ProviderFactory.create(
      near(),
      (_) async => 'geheim',
      attestation: wiring,
      client: MockClient((r) async {
        viaOther.add(r);
        return http.Response('{}', 500);
      }),
    ) as AttestedProvider;
    final v = p.verifier as NearVerifier;
    await v.attest();
    await v.verifyReceipt(
      ReceiptRef(
        id: 'chatcmpl-1',
        session: AttestedSession(
          keysetDigest: 'a',
          notAfter: DateTime(2100),
          receiptKeys: const {},
          repoCommit: null,
          composeHash: '',
          attestedAt: DateTime(2026),
          workloadId: 'm',
        ),
      ),
      Uint8List(1),
      Uint8List(1),
    );
    // der Bericht (noch ungeprüft) darf den Schlüssel tragen, die Quittung
    // nur über die erzwungene, gepinnte Verbindung
    expect(
      viaGate.where((e) => e.contains('/signature/')),
      everyElement(startsWith('true|')),
    );
    expect(viaGate.any((e) => e.contains('/signature/')), isTrue);
    expect(viaGate.where((e) => e.startsWith('false|')), hasLength(1));
    expect(
      viaGate.firstWhere((e) => e.startsWith('false|')),
      contains('/attestation/report'),
    );
    // nichts mit dem Schlüssel über den fremden Client (NRAS)
    expect(
      viaOther.where((r) => r.headers.containsKey('authorization')),
      isEmpty,
    );
  });

  test('Modellliste: nur eigene Flotte (nearai) mit Werkzeugen', () async {
    final body = jsonEncode({
      'data': [
        {
          'id': 'z-ai/glm-5.3-flash',
          'owned_by': 'nearai',
          'supported_features': ['tools', 'reasoning'],
        },
        {
          'id': 'Qwen/Qwen3-Embedding-0.6B',
          'owned_by': 'nearai',
          'supported_features': <String>[],
        },
        {
          'id': 'moonshotai/Kimi-K3',
          'owned_by': 'attested 3p',
          'supported_features': ['tools'],
        },
        {
          'id': 'openai/gpt-5',
          'owned_by': 'openai',
          'supported_features': ['tools'],
        },
      ],
    });
    final adapter = OpenAiChatAdapter(
      baseUrl: Uri.parse('https://cloud-api.near.ai/v1'),
      credentials: Credentials.apiKey('k', style: ApiKeyStyle.bearer),
      defaultModel: 'm',
      client: MockClient((_) async => http.Response(body, 200)),
      options: OpenAiOptions.fromMap(
        near(
          options: const {
            'attestation': 'near',
            'ownedBy': 'nearai',
            'toolsOnly': true,
          },
        ).options,
      ),
    );
    final models = await adapter.listModels();
    expect(models.map((m) => m.id), ['z-ai/glm-5.3-flash']);
  });
}
