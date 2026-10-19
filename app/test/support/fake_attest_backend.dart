import 'dart:typed_data';

import 'package:wendelin/platform/attest/attest_backend.dart';
import 'package:wendelin/platform/attest/generated/collateral.dart';
import 'package:wendelin/platform/attest/generated/e2ee.dart';
import 'package:wendelin/platform/attest/generated/ehbp.dart';
import 'package:wendelin/platform/attest/generated/near_e2ee.dart';
import 'package:wendelin/platform/attest/generated/quote.dart';
import 'package:wendelin/platform/attest/generated/report.dart';
import 'package:wendelin/platform/attest/generated/sigstore.dart';
import 'package:wendelin/platform/attest/generated/snp.dart';

/// Rust-Ersatz für Tests ohne native Bibliothek: feste Antworten, zählt Aufrufe.
final class FakeAttestBackend implements AttestBackend {
  FakeAttestBackend({this.nextUpdateIso = '2030-01-01T00:00:00Z'});

  String nextUpdateIso;
  var requests = 0;
  var builds = 0;
  CollateralParts? lastParts;
  QuoteInfo quoteResult = QuoteInfo(
    ok: true,
    tcbStatus: 'UpToDate',
    advisoryIds: const ['INTEL-SA-1'],
    mrTd: Uint8List(48),
    rtMr0: Uint8List(48),
    rtMr1: Uint8List(48),
    rtMr2: Uint8List(48),
    rtMr3: Uint8List.fromList(List.filled(48, 3)),
    reportData: Uint8List(64),
  );
  int? lastNow;
  var throwOnVerify = false;
  var throwOnSpki = false;

  /// Wird (falls gesetzt) bei jedem Aufruf geworfen, wie ein Rust-Panic.
  Object? panic;

  @override
  Future<CollateralRequest> collateralRequest(Uint8List quote) async {
    requests++;
    return const CollateralRequest(
      tee: 'tdx',
      fmspc: '00806F050000',
      ca: 'platform',
    );
  }

  @override
  Future<String> rootCrlUrl(String chain) async =>
      'https://certs.example/root.der';

  @override
  Future<String> buildCollateral(CollateralParts parts) async {
    builds++;
    lastParts = parts;
    return '{"built":$builds}';
  }

  @override
  Future<String> nextUpdate(String json) async => nextUpdateIso;

  @override
  Future<QuoteInfo> verifyQuote(
    Uint8List quote,
    String json,
    int nowUnix,
  ) async {
    lastNow = nowUnix;
    if (panic != null) throw panic!;
    if (throwOnVerify) throw StateError('x');
    return quoteResult;
  }

  @override
  Future<Verdict> verifyReport(String r, String n, String c, int now) =>
      throw UnimplementedError();

  @override
  Future<ReceiptVerdict> verifyReceipt(String r, String rep) =>
      throw UnimplementedError();

  @override
  bool ed25519(Uint8List pk, Uint8List msg, Uint8List sig) {
    if (panic != null) throw panic!;
    return pk.length == 32 && sig.isNotEmpty;
  }

  @override
  Uint8List sha256(Uint8List data) {
    if (panic != null) throw panic!;
    return Uint8List.fromList([data.length]);
  }

  @override
  Uint8List sha384(Uint8List data) {
    if (panic != null) throw panic!;
    return Uint8List.fromList([data.length, 384]);
  }

  @override
  Uint8List spkiSha256(Uint8List der) {
    if (throwOnSpki) throw StateError('x');
    return Uint8List.fromList([der.length, 1]);
  }

  @override
  E2eeKeypair e2eeGenerateKeypair() {
    if (panic != null) throw panic!;
    return E2eeKeypair(
      secret: Uint8List.fromList(List.filled(32, 1)),
      public: Uint8List.fromList(List.filled(32, 2)),
    );
  }

  @override
  String e2eeEncrypt(Uint8List pub, Uint8List plain, Uint8List aad) {
    if (panic != null) throw panic!;
    return 'ab' * (30 + plain.length);
  }

  @override
  Uint8List e2eeDecrypt(Uint8List secret, String wire, Uint8List aad) {
    if (panic != null) throw panic!;
    if (wire.isEmpty) throw StateError('x');
    return Uint8List.fromList([wire.length]);
  }

  @override
  NearIdentity nearGenerateIdentity() {
    if (panic != null) throw panic!;
    return NearIdentity(
      secret: Uint8List.fromList(List.filled(32, 3)),
      public: Uint8List.fromList(List.filled(32, 4)),
    );
  }

  @override
  String nearEncrypt(Uint8List pub, Uint8List plain) {
    if (panic != null) throw panic!;
    return 'cd' * (72 + plain.length);
  }

  @override
  Uint8List nearDecrypt(Uint8List secret, String wire) {
    if (panic != null) throw panic!;
    if (wire.isEmpty) throw StateError('x');
    return Uint8List.fromList([wire.length]);
  }

  @override
  EhbpBinding ehbpBindKeyConfig(Uint8List keyConfig, Uint8List reportData) =>
      _noEhbp();

  @override
  (EhbpSealed, EhbpSession) ehbpBeginRequest(
    Uint8List keyConfig,
    Uint8List reportData,
    Uint8List plaintext,
  ) => _noEhbp();

  @override
  EhbpResponseDecoder ehbpResponseDecoder(
    EhbpSession session,
    Uint8List responseNonce,
  ) => _noEhbp();

  @override
  Uint8List ehbpDecoderPush(EhbpResponseDecoder decoder, Uint8List data) =>
      _noEhbp();

  @override
  void ehbpDecoderFinish(EhbpResponseDecoder decoder) => _noEhbp();

  Never _noEhbp() {
    if (panic != null) throw panic!;
    throw UnimplementedError('ehbp: Rust-Bibliothek nötig');
  }

  SnpReportInfo snpInfo = SnpReportInfo(
    version: 3,
    policy: BigInt.zero,
    vmpl: 0,
    reportedTcb: const SnpTcb(bootloader: 10, tee: 0, snp: 23, microcode: 84),
    signedWithVlek: false,
    measurementHex: 'aa',
    reportDataHex: 'bb',
    chipIdHex: 'cc',
  );
  SnpVerdict snpVerdict = const SnpVerdict(
    reportOk: true,
    chainOk: true,
    vcekMatchesReport: true,
    signatureOk: true,
    policyOk: true,
    tlsBound: true,
    hpkeBound: true,
    product: 'Genoa',
    errors: [],
  );
  SnpPolicy? lastSnpPolicy;
  int? lastSnpNow;

  @override
  SnpReportInfo snpReportInfo(Uint8List report) {
    if (panic != null) throw panic!;
    return snpInfo;
  }

  @override
  Future<SnpVerdict> verifySnp({
    required Uint8List report,
    required Uint8List vcekDer,
    required String chainPem,
    required int nowUnix,
    required SnpPolicy policy,
    required Uint8List tlsSpkiSha256,
    required Uint8List hpkeKey,
  }) async {
    if (panic != null) throw panic!;
    lastSnpPolicy = policy;
    lastSnpNow = nowUnix;
    return snpVerdict;
  }

  SigstoreVerdict sigstoreVerdict = SigstoreVerdict(
    dsseOk: true,
    chainOk: true,
    identityOk: true,
    rekorOk: true,
    measurementOk: true,
    snpMeasurementHex: 'cd',
    releaseTag: 'v1',
    integratedTime: BigInt.from(1792024828),
    errors: const [],
  );
  (String, String, String, String)? lastRelease;

  @override
  Future<SigstoreVerdict> verifyTinfoilRelease({
    required String bundleJson,
    required String repo,
    required String tag,
    required String digestHex,
    required String reportMeasurementHex,
  }) async {
    if (panic != null) throw panic!;
    lastRelease = (repo, tag, digestHex, reportMeasurementHex);
    return sigstoreVerdict;
  }
}
