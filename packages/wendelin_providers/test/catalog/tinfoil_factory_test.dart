import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../tee/tinfoil_support.dart';

ProviderProfile tinfoil({Map<String, Object?>? options}) => ProviderProfile(
  id: 'tf1',
  name: 'Tinfoil (TEE)',
  type: ProviderType.openaiCompatible,
  baseUrl: 'https://inference.tinfoil.sh/v1',
  defaultModel: 'gpt-oss-120b',
  privacy: PrivacyLevel.tee,
  authMethod: const ApiKeyAuth('ref'),
  options: options ?? const {'attestation': 'tinfoil'},
);

AttestationWiring wiring({
  SnpCrypto? snp,
  SigstoreCrypto? sigstore,
  EhbpCrypto? ehbp,
  ReleaseFloorStore? floors,
  http.Client Function(TlsPinGate, {required bool enforce})? pinned,
}) => AttestationWiring(
  crypto: FakeAttestationCrypto(),
  snpCrypto: snp,
  sigstoreCrypto: sigstore,
  ehbpCrypto: ehbp,
  releaseFloors: floors,
  gpuMode: GpuCheckMode.before,
  pinnedClient: pinned,
);

AttestationWiring complete({
  http.Client Function(TlsPinGate, {required bool enforce})? pinned,
}) => wiring(
  snp: FakeSnpCrypto(),
  sigstore: FakeSigstoreCrypto(),
  ehbp: EhbpReferenceCrypto(),
  floors: InMemoryReleaseFloorStore(),
  pinned: pinned,
);

void main() {
  test('Vorlage „Tinfoil (TEE)“: Stufe TEE, gemma4-31b, nur Chat-Modelle', () {
    final t = providerTemplates.firstWhere((t) => t.id == 'tinfoil');
    expect(t.name, 'Tinfoil (TEE)');
    expect(t.baseUrl, 'https://inference.tinfoil.sh/v1');
    expect(t.privacy, PrivacyLevel.tee);
    expect(t.suggestedModel, 'gemma4-31b');
    expect(t.options['attestation'], 'tinfoil');
    final profile = t.toProfile(id: 'x', secretRef: 'r');
    expect(attestationKind(profile), AttestationKind.tinfoil);
    expect(effectivePrivacy(profile), PrivacyLevel.tee);
  });

  test('„tee“ gilt nur mit Prüfung: ohne Option bleibt es Standard', () {
    final p = tinfoil(options: const {});
    expect(attestationKind(p), AttestationKind.none);
    expect(effectivePrivacy(p), PrivacyLevel.standard);
  });

  test(
    'Fabrik baut einen geprüften Anbieter mit EHBP-Kanal, ohne GPU-Prüfung',
    () {
      final p = ProviderFactory.create(
        tinfoil(),
        (_) async => 'k',
        attestation: complete(),
      );
      expect(p, isA<AttestedProvider>());
      final attested = p as AttestedProvider;
      expect(attested.verifier, isA<TinfoilVerifier>());
      expect(attested.inner.wireCodec, isA<TinfoilEhbpChannel>());
      expect(attested.caps.tee, isTrue);
      expect(attested.caps.tools, isTrue);
      expect(attested.toolsEncrypted, isTrue);
      // Das Profil (oder die Vorgabe) kann die GPU-Prüfung nicht einschalten:
      // Tinfoil liefert keinen Nachweis im Client-Pfad.
      expect(attested.gpuMode, GpuCheckMode.off);
    },
  );

  test('fehlt eine Prüfung, wird nichts gebaut (fail-closed)', () {
    expect(
      () => ProviderFactory.create(tinfoil(), (_) async => 'k'),
      throwsArgumentError,
    );
    final ok = complete();
    for (final broken in [
      wiring(
        sigstore: FakeSigstoreCrypto(),
        ehbp: EhbpReferenceCrypto(),
        floors: InMemoryReleaseFloorStore(),
      ),
      wiring(
        snp: FakeSnpCrypto(),
        ehbp: EhbpReferenceCrypto(),
        floors: InMemoryReleaseFloorStore(),
      ),
      wiring(
        snp: FakeSnpCrypto(),
        sigstore: FakeSigstoreCrypto(),
        floors: InMemoryReleaseFloorStore(),
      ),
      wiring(
        snp: FakeSnpCrypto(),
        sigstore: FakeSigstoreCrypto(),
        ehbp: EhbpReferenceCrypto(),
      ),
    ]) {
      expect(
        () => ProviderFactory.create(
          tinfoil(),
          (_) async => 'k',
          attestation: broken,
        ),
        throwsArgumentError,
      );
    }
    expect(ok.snpCrypto, isNotNull);
  });

  test('API-Key nie an AMD, GitHub oder den ungeprüften Router', () async {
    final f = TinfoilFixture();
    final seen = <String>[];
    http.Client record(String who) => MockClient((r) async {
      seen.add('$who|${r.url.host}|${r.headers['authorization']}');
      return f.client.get(r.url, headers: r.headers);
    });
    final p = ProviderFactory.create(
      tinfoil(),
      (_) async => 'geheim',
      attestation: AttestationWiring(
        crypto: FakeAttestationCrypto(),
        snpCrypto: f.snp,
        sigstoreCrypto: f.sigstore,
        ehbpCrypto: f.ehbp,
        releaseFloors: f.floors,
        pinnedClient: (gate, {required enforce}) =>
            record(enforce ? 'pinned' : 'open'),
      ),
      client: record('extern'),
    ) as AttestedProvider;
    final result = await p.verifier.attest();
    expect(seen.where((e) => e.contains('geheim')), isEmpty);
    expect(seen.where((e) => e.contains('Bearer')), isEmpty);
    // Router-Dokumente über den ungepinnten Client, AMD/GitHub extern.
    expect(
      seen.where((e) => e.startsWith('open|inference.tinfoil.sh')),
      hasLength(2),
    );
    expect(
      seen.where((e) => e.startsWith('extern|kdsintf.amd.com')),
      isNotEmpty,
    );
    expect(
      seen.where((e) => e.startsWith('extern|api.github.com')),
      isNotEmpty,
    );
    expect(seen.where((e) => e.startsWith('pinned|')), isEmpty);
    expect(result.status, AttestationStatus.red, reason: 'Pin nicht messbar');
  });

  test('Modellliste: nur Chat-Modelle mit Werkzeugen', () async {
    final list = {
      'data': [
        {'id': 'gpt-oss-120b', 'type': 'chat', 'tool_calling': true},
        {
          'id': 'whisper-large-v3-turbo',
          'type': 'audio',
          'tool_calling': false,
        },
        {
          'id': 'gpt-oss-safeguard-120b',
          'type': 'safety',
          'tool_calling': true,
        },
        {'id': 'gemma4-31b', 'type': 'chat', 'tool_calling': true},
        {'id': 'chat-ohne-tools', 'type': 'chat', 'tool_calling': false},
      ],
    };
    final p = ProviderFactory.create(
      tinfoil(
        options: const {
          'attestation': 'tinfoil',
          'modelType': 'chat',
          'toolsOnly': true,
        },
      ),
      (_) async => 'k',
      attestation: complete(
        pinned: (gate, {required enforce}) =>
            MockClient((r) async => http.Response(jsonEncode(list), 200)),
      ),
    ) as AttestedProvider;
    final models = await p.inner.listModels();
    expect(models.map((m) => m.id), ['gpt-oss-120b', 'gemma4-31b']);
  });
}
