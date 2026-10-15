import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'tee_support.dart';

/// The recorded public NEAR AI attestation (2026-10-15, trimmed).
Map<String, Object?> nearReport() =>
    jsonDecode(File('test/fixtures/near/report.json').readAsStringSync())
        as Map<String, Object?>;

/// The recorded, really encrypted exchanges (streaming and plain) with the
/// throw-away client seed that opens them.
Map<String, Object?> nearExchange() =>
    jsonDecode(File('test/fixtures/near/exchange.json').readAsStringSync())
        as Map<String, Object?>;

/// Nonce of the recorded report.
final nearNonce = AttestCodec.unhex(
  'f3b426ddde16000e004951b8f083930703e5570e487eca22bf83cb84e7f338e0',
);

const nearModel = 'z-ai/glm-5.3-flash';

/// A [NearVerifier] against [server] with the recording's nonce.
NearVerifier nearVerifier(
  TeeServer server,
  AttestationCrypto crypto, {
  Set<String> trusted = const {},
  AttestationPinStore? pins,
  TlsPinGate? gate,
  String model = nearModel,
}) => NearVerifier(
  crypto: crypto,
  baseUrl: Uri.parse('https://cloud-api.test/v1'),
  model: model,
  profileId: 'near',
  headers: () async => {'authorization': 'Bearer test'},
  client: server.client,
  tlsPin: gate,
  pins: pins,
  trustedComposeHashes: trusted,
  nonceSource: () => nearNonce,
);

/// The report with the model key replaced by [serviceKeyHex] and the
/// `report_data` inside the model quote recomputed (nonce [nonce]), so the
/// fake crypto accepts it like the original. Other fields stay recorded.
Map<String, Object?> nearReportFor(String serviceKeyHex, {Uint8List? nonce}) {
  final crypto = FakeAttestationCrypto();
  final doc = copyJson(nearReport());
  final model =
      (doc['model_attestations']! as List<Object?>).first!
          as Map<String, Object?>;
  model['signing_public_key'] = serviceKeyHex;
  model['signing_address'] = serviceKeyHex;
  final fp = AttestCodec.unhex(model['tls_cert_fingerprint']! as String);
  final rd = Uint8List.fromList([
    ...crypto.sha256(
      Uint8List.fromList([...AttestCodec.unhex(serviceKeyHex), ...fp]),
    ),
    ...(nonce ?? nearNonce),
  ]);
  final quote = model['intel_quote']! as String;
  model['intel_quote'] =
      '${quote.substring(0, 1136)}${AttestCodec.hex(rd)}${quote.substring(1136 + 128)}';
  model['request_nonce'] = AttestCodec.hex(nonce ?? nearNonce);
  return doc;
}

/// Mutates the first model entry of [doc].
void editModel(
  Map<String, Object?> doc,
  void Function(Map<String, Object?>) f,
) => f(
  (doc['model_attestations']! as List<Object?>).first! as Map<String, Object?>,
);

/// Mutates the gateway entry of [doc].
void editGateway(
  Map<String, Object?> doc,
  void Function(Map<String, Object?>) f,
) => f(doc['gateway_attestation']! as Map<String, Object?>);

/// Flips one hex digit of the string at [key] (offset [at]).
String flipHex(String hex, int at) =>
    hex.replaceRange(at, at + 1, hex[at] == '0' ? '1' : '0');

/// Delegates to [inner] but reports [gatewayTcb] for the quote that starts
/// with [gatewayQuote] (the gateway's), otherwise [inner]'s status.
final class SplitTcbCrypto implements AttestationCrypto {
  /// Creates the wrapper.
  SplitTcbCrypto(this.inner, this.gatewayQuote, this.gatewayTcb);

  /// Real fake.
  final FakeAttestationCrypto inner;

  /// Quote bytes of the gateway.
  final Uint8List gatewayQuote;

  /// Status for the gateway quote.
  final TcbStatus gatewayTcb;

  @override
  Future<QuoteVerdict> verifyQuote(
    Uint8List quote,
    QuoteCollateral collateral,
    DateTime now,
  ) async {
    final v = await inner.verifyQuote(quote, collateral, now);
    final isGateway = AttestCodec.hex(quote) == AttestCodec.hex(gatewayQuote);
    return QuoteVerdict(
      tcbStatus: isGateway ? gatewayTcb : v.tcbStatus,
      reportData: v.reportData,
      rtmr3: v.rtmr3,
      advisoryIds: const ['INTEL-SA-01192'],
    );
  }

  @override
  Future<QuoteCollateral> collateralFor(Uint8List quote) =>
      inner.collateralFor(quote);

  @override
  bool verifyEd25519(Uint8List k, Uint8List m, Uint8List s) =>
      inner.verifyEd25519(k, m, s);

  @override
  Uint8List sha256(Uint8List d) => inner.sha256(d);

  @override
  Uint8List sha384(Uint8List d) => inner.sha384(d);

  @override
  Uint8List spkiSha256(Uint8List d) => inner.spkiSha256(d);

  @override
  E2eeKeypair e2eeGenerateKeypair() => inner.e2eeGenerateKeypair();

  @override
  String e2eeEncrypt(Uint8List r, Uint8List p, Uint8List a) =>
      inner.e2eeEncrypt(r, p, a);

  @override
  Uint8List e2eeDecrypt(Uint8List s, String w, Uint8List a) =>
      inner.e2eeDecrypt(s, w, a);
}
