import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin/platform/attest/attest_backend.dart';
import 'package:wendelin/platform/attest/generated/ehbp.dart';
import 'package:wendelin/platform/attest/generated/sigstore.dart';
import 'package:wendelin/platform/attest/generated/snp.dart';
import 'package:wendelin_providers/fakes.dart';

import 'tee_fixtures.g.dart';
import 'tee_gateway.dart' show fixtureGatewayCertificate;

/// Check time of the recorded report (2026-10-16 12:00 UTC): the AMD
/// certificates are valid then.
final tinfoilNow = DateTime.fromMillisecondsSinceEpoch(
  1792152000 * 1000,
  isUtc: true,
);

/// Release the recorded report belongs to, and the digest in its
/// `tinfoil.hash` (same values as `native/attest/tests/sigstore.rs`).
const tinfoilTag = 'v0.0.158';
const tinfoilDigest =
    '8daaecd40cd29b45d508d7250feadf5e3eff555cb6fadd58131c996598007e97';

const tinfoilBaseUrl = 'https://inference.tinfoil.sh/v1';

/// `format` of the router's attestation document (as the live service names it).
const tinfoilFormat = 'https://tinfoil.sh/predicate/sev-snp-guest/v2';

const tinfoilModelId = 'gpt-oss-120b';

/// Final answer of the fixture router.
const tinfoilAnswer = 'Ruhig: 0,4 m Welle.';

Uint8List _b64(String s) => base64.decode(s);

/// The recorded report.
final Uint8List tinfoilReportBytes = _b64(tinfoilReportBase64);

/// SPKI hash the recorded report binds (`report_data[0..32]`).
final Uint8List tinfoilRecordedPin = tinfoilReportBytes.sublist(0x50, 0x70);

const _toolCallSse =
    'data: {"id":"tf-1","object":"chat.completion.chunk","choices":[{"index":0,'
    '"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1",'
    '"type":"function","function":{"name":"memory__search",'
    '"arguments":"{\\"query\\":\\"Meer\\"}"}}]},"finish_reason":null}]}\n\n'
    'data: {"id":"tf-1","object":"chat.completion.chunk","choices":[{"index":0,'
    '"delta":{},"finish_reason":"tool_calls"}]}\n\n'
    'data: [DONE]\n\n';

const _answerSse =
    'data: {"id":"tf-2","object":"chat.completion.chunk","choices":[{"index":0,'
    '"delta":{"role":"assistant","content":"$tinfoilAnswer"},'
    '"finish_reason":null}]}\n\n'
    'data: {"id":"tf-2","object":"chat.completion.chunk","choices":[{"index":0,'
    '"delta":{},"finish_reason":"stop"}]}\n\n'
    'data: [DONE]\n\n';

/// Rust check module with two stand-ins: the fixture router's certificate
/// counts as the one with the recorded pin (or, with [wrongPin], as another
/// one), and requests are sealed to the fixture router's HPKE key instead of
/// the recorded one (nobody has its secret). Everything else (SNP report and
/// chain, Sigstore bundle, key binding, EHBP cipher) is the real Rust code.
final class TinfoilBackend implements AttestBackend {
  /// Creates the backend around the real [rust] module.
  TinfoilBackend(this.rust, this.service);

  /// The real module.
  final AttestBackend rust;

  /// The fixture router (key pair of the stand-in).
  final FakeEhbpService service;

  /// The router's certificate hashes to a pin the report does not bind.
  bool wrongPin = false;

  @override
  Uint8List spkiSha256(Uint8List der) {
    if (_same(der, fixtureGatewayCertificate)) {
      return wrongPin
          ? Uint8List.fromList(List.filled(32, 0x5a))
          : tinfoilRecordedPin;
    }
    return rust.spkiSha256(der);
  }

  @override
  (EhbpSealed, EhbpSession) ehbpBeginRequest(
    Uint8List keyConfig,
    Uint8List reportData,
    Uint8List plaintext,
  ) {
    // The caller checked the recorded key against the report; the sealing
    // goes to the router of the fixture.
    final recorded = _same(keyConfig, _b64(tinfoilHpkeKeysBase64));
    return rust.ehbpBeginRequest(
      recorded ? service.keyConfig : keyConfig,
      recorded ? service.reportData : reportData,
      plaintext,
    );
  }

  @override
  EhbpBinding ehbpBindKeyConfig(Uint8List k, Uint8List r) =>
      rust.ehbpBindKeyConfig(k, r);

  @override
  EhbpResponseDecoder ehbpResponseDecoder(EhbpSession s, Uint8List n) =>
      rust.ehbpResponseDecoder(s, n);

  @override
  Uint8List ehbpDecoderPush(EhbpResponseDecoder d, Uint8List data) =>
      rust.ehbpDecoderPush(d, data);

  @override
  void ehbpDecoderFinish(EhbpResponseDecoder d) => rust.ehbpDecoderFinish(d);

  @override
  Uint8List sha256(Uint8List data) => rust.sha256(data);

  @override
  Uint8List sha384(Uint8List data) => rust.sha384(data);

  @override
  SnpReportInfo snpReportInfo(Uint8List report) => rust.snpReportInfo(report);

  @override
  Future<SnpVerdict> verifySnp({
    required Uint8List report,
    required Uint8List vcekDer,
    required String chainPem,
    required int nowUnix,
    required SnpPolicy policy,
    required Uint8List tlsSpkiSha256,
    required Uint8List hpkeKey,
  }) => rust.verifySnp(
    report: report,
    vcekDer: vcekDer,
    chainPem: chainPem,
    nowUnix: nowUnix,
    policy: policy,
    tlsSpkiSha256: tlsSpkiSha256,
    hpkeKey: hpkeKey,
  );

  @override
  Future<SigstoreVerdict> verifyTinfoilRelease({
    required String bundleJson,
    required String repo,
    required String tag,
    required String digestHex,
    required String reportMeasurementHex,
  }) => rust.verifyTinfoilRelease(
    bundleJson: bundleJson,
    repo: repo,
    tag: tag,
    digestHex: digestHex,
    reportMeasurementHex: reportMeasurementHex,
  );

  // Not needed on the Tinfoil path.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} (Tinfoil-Fixture)');
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Fixture transport of Tinfoil: the router with the recorded attestation
/// document and key configuration, AMD KDS and GitHub with the recorded
/// certificate, chain and release bundle, and a router that decrypts EHBP
/// requests and seals its answers. No network.
final class TinfoilFixtureGateway {
  /// Creates the gateway.
  TinfoilFixtureGateway();

  /// The fixture router's HPKE key pair (see [TinfoilBackend]).
  final FakeEhbpService service = FakeEhbpService();

  /// Chat requests received.
  int chats = 0;

  /// Decrypted chat requests in order.
  final List<Map<String, Object?>> plainBodies = [];

  /// Request bodies as they were on the wire.
  final List<String> wires = [];

  /// Requests to hosts other than the router.
  final List<Uri> external = [];

  /// Tag GitHub names as the latest release.
  String latestTag = tinfoilTag;

  /// The attestation document of the router.
  String get _document => jsonEncode({
    'format': tinfoilFormat,
    'body': base64.encode(GZipCodec().encode(tinfoilReportBytes)),
  });

  /// The HTTP client.
  late final http.Client client = MockClient.streaming((request, body) async {
    final bytes = await body.toBytes();
    final url = request.url;
    http.StreamedResponse reply(
      List<int> data, {
      String type = 'application/json',
      Map<String, String> headers = const {},
    }) => http.StreamedResponse(
      Stream.value(data),
      200,
      headers: {'content-type': type, ...headers},
    );
    http.StreamedResponse text(String s) => reply(utf8.encode(s));

    if (url.host == 'kdsintf.amd.com') {
      external.add(url);
      if (!url.path.contains('/Genoa/')) {
        return http.StreamedResponse(const Stream.empty(), 404);
      }
      return url.path.endsWith('cert_chain')
          ? text(tinfoilChainPem)
          : reply(_b64(tinfoilVcekBase64), type: 'application/octet-stream');
    }
    if (url.host.contains('github')) {
      external.add(url);
      if (url.path.endsWith('/releases/latest')) {
        return text(jsonEncode({'tag_name': latestTag}));
      }
      if (url.path.endsWith('/tinfoil.hash')) return text('$tinfoilDigest\n');
      if (url.path.contains('/attestations/sha256:')) {
        return text(
          jsonEncode({
            'attestations': [
              {'bundle': jsonDecode(tinfoilBundle)},
            ],
          }),
        );
      }
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    final path = url.path;
    if (path.endsWith('/.well-known/tinfoil-attestation')) {
      return text(_document);
    }
    if (path.endsWith('/.well-known/hpke-keys')) {
      return reply(
        _b64(tinfoilHpkeKeysBase64),
        type: 'application/octet-stream',
      );
    }
    if (path.endsWith('/models')) {
      return text(
        jsonEncode({
          'object': 'list',
          'data': [
            {'id': tinfoilModelId, 'object': 'model'},
          ],
        }),
      );
    }
    chats++;
    wires.add(utf8.decode(bytes, allowMalformed: true));
    final exchange = service.open(request.headers, bytes);
    final plain = exchange.request;
    plainBodies.add(plain);
    final messages = plain['messages']! as List<Object?>;
    final hasToolResult = messages.any(
      (m) => (m! as Map<String, Object?>)['role'] == 'tool',
    );
    final sealed = exchange.sealText(hasToolResult ? _answerSse : _toolCallSse);
    return reply(
      sealed.body,
      type: 'text/event-stream',
      headers: {'Ehbp-Response-Nonce': sealed.nonceHex},
    );
  });
}
