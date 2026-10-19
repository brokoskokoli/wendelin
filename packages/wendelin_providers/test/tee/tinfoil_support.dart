import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

/// Check time of the Tinfoil tests.
final tinfoilNow = DateTime.utc(2026, 10, 19, 12);

/// The Tinfoil side of a test: a router (`FakeEhbpService`) whose SNP report
/// carries its real `report_data`, AMD KDS and GitHub as mocks, the fake Rust
/// ports. Everything that matters for the bindings is real: the HPKE key
/// config is bound by the reference cipher.
final class TinfoilFixture {
  /// Creates the fixture; the release is [tag] signed at [integratedTime].
  TinfoilFixture({
    this.tag = 'v0.0.158',
    this.integratedTime = 1789000000,
    Uint8List? tlsPin,
  }) : service = FakeEhbpService(tlsPin: tlsPin) {
    snp = FakeSnpCrypto(info: _info());
    sigstore = FakeSigstoreCrypto(verdict: _verdict());
  }

  /// Release tag GitHub names as the latest.
  String tag;

  /// Rekor time of the release.
  int integratedTime;

  /// The router's keys.
  final FakeEhbpService service;

  /// Fake SNP verification (flags are set per test).
  late final FakeSnpCrypto snp;

  /// Fake Sigstore verification.
  late final FakeSigstoreCrypto sigstore;

  /// Real reference cipher for the key binding.
  final EhbpReferenceCrypto ehbp = EhbpReferenceCrypto();

  /// Release floors.
  final InMemoryReleaseFloorStore floors = InMemoryReleaseFloorStore();

  /// Raw report bytes served by the router.
  Uint8List report = Uint8List.fromList(List.filled(1184, 7));

  /// Key config served at `/.well-known/hpke-keys`.
  late Uint8List keyConfig = service.keyConfig;

  /// `format` of the attestation document.
  String format = TinfoilPolicy.attestationFormat;

  /// Override of the document `body`.
  String? bodyOverride;

  /// Digest of `tinfoil.hash`.
  String digest = 'ab' * 32;

  /// Number of Sigstore bundles GitHub lists for the release.
  int bundles = 1;

  /// Products the KDS knows (others answer 404).
  Set<String> kdsProducts = {'Genoa'};

  /// HTTP status for a route key (substring of the URL path) -> status.
  final Map<String, int> failing = {};

  /// Requests received (all hosts).
  final List<http.Request> requests = [];

  /// Measurement of the report.
  static const measurement =
      'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd'
      'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd';

  /// The recorded chip id (fake).
  static final chipId = 'ab' * 64;

  SnpReportInfo _info() => SnpReportInfo(
    version: 3,
    vmpl: 0,
    reportedTcb: const SnpTcb(bootloader: 10, tee: 0, snp: 23, microcode: 84),
    measurementHex: measurement,
    reportDataHex: AttestCodec.hex(service.reportData),
    chipIdHex: chipId,
  );

  SigstoreVerdict _verdict() => SigstoreVerdict(
    dsseOk: true,
    chainOk: true,
    identityOk: true,
    rekorOk: true,
    measurementOk: true,
    snpMeasurementHex: measurement,
    releaseTag: tag,
    integratedTime: integratedTime,
  );

  /// Sets a Sigstore verdict for the current [tag] and time.
  void sigstoreGreen() => sigstore.verdict = _verdict();

  /// The attestation document body: base64 of gzip of [report].
  String get body => bodyOverride ?? base64.encode(GZipCodec().encode(report));

  /// The mock for router, KDS and GitHub.
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    for (final e in failing.entries) {
      if (request.url.toString().contains(e.key)) {
        return http.Response('{}', e.value);
      }
    }
    if (path.endsWith('/.well-known/tinfoil-attestation')) {
      return http.Response(
        jsonEncode({'format': format, 'body': body}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/.well-known/hpke-keys')) {
      return http.Response.bytes(keyConfig, 200);
    }
    if (request.url.host == 'kdsintf.amd.com') {
      final product = path.split('/')[3];
      if (!kdsProducts.contains(product)) return http.Response('', 404);
      return path.endsWith('cert_chain')
          ? http.Response('-----BEGIN CERTIFICATE-----\n', 200)
          : http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
    }
    if (path.endsWith('/releases/latest')) {
      return http.Response(jsonEncode({'tag_name': tag}), 200);
    }
    if (path.endsWith('/tinfoil.hash')) return http.Response('$digest\n', 200);
    if (path.contains('/attestations/sha256:')) {
      return http.Response(
        jsonEncode({
          'attestations': [
            for (var i = 0; i < bundles; i++)
              {
                'bundle': {'mediaType': 'bundle', 'n': i},
              },
          ],
        }),
        200,
      );
    }
    return http.Response('nicht gefunden', 404);
  });

  /// A verifier against this fixture. Without [gate] a gate is used that
  /// measures the certificate the router's report binds (the connection
  /// is green); with one, [router] must measure by itself.
  TinfoilVerifier verifier({
    TlsPinGate? gate,
    AttestationPinStore? pins,
    String profileId = 'tinfoil',
    http.Client? router,
    ReleaseFloorStore? floorStore,
    KdsCache? kdsCache,
    String host = 'inference.test',
  }) {
    final pin = service.tlsSpkiSha256;
    final TlsPinGate g;
    final http.Client r;
    if (gate == null) {
      g = TlsPinGate(spkiSha256: (_) => pin);
      r = observingClient(router ?? client, g, Uint8List(1));
    } else {
      g = gate;
      r = router ?? client;
    }
    return TinfoilVerifier(
      crypto: FakeAttestationCrypto(),
      snp: snp,
      sigstore: sigstore,
      ehbp: ehbp,
      floors: floorStore ?? floors,
      baseUrl: Uri.parse('https://$host/v1'),
      profileId: profileId,
      client: r,
      externalClient: client,
      settings: HttpSettings(clock: FixedClock(tinfoilNow)),
      tlsPin: g,
      pins: pins,
      kdsCache: kdsCache,
    );
  }
}

/// A client that measures a connection (certificate [der]) like the pinned
/// client does for every request to the router.
http.Client observingClient(
  http.Client base,
  TlsPinGate gate,
  Uint8List? der,
) => MockClient((request) async {
  gate.observe(der);
  return base.get(request.url, headers: request.headers);
});

/// A floor store whose entries cannot be read (damaged storage).
final class DamagedFloorStore implements ReleaseFloorStore {
  @override
  Future<ReleaseFloor?> load(String profileId) =>
      throw const FormatException('beschädigt');

  @override
  Future<void> save(String profileId, ReleaseFloor floor) async {}
}

/// The stage [s] of [r].
StageResult stageOf(AttestationResult r, AttestationStage s) =>
    r.stages.firstWhere((x) => x.stage == s);
