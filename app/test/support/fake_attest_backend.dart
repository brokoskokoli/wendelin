import 'dart:typed_data';

import 'package:wendelin/platform/attest/attest_backend.dart';
import 'package:wendelin/platform/attest/generated/collateral.dart';
import 'package:wendelin/platform/attest/generated/quote.dart';
import 'package:wendelin/platform/attest/generated/report.dart';

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
}
