import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/attestation_types.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/src/tee/e2ee_v2.dart';

import 'tee_support.dart';

/// The probe attestation with the E2EE key of [service] instead of the
/// gateway's (whose secret nobody has): keyset digest, `report_data` (also
/// inside the quote bytes) are recomputed for [nonce], so the fake crypto
/// accepts it just like the original.
Map<String, Object?> attestationFor(
  FakeE2eeService service, {
  Uint8List? nonce,
  void Function(Map<String, Object?> keyset)? editKeyset,
}) {
  final crypto = FakeAttestationCrypto();
  final doc = copyJson(teeJson('gateway_attestation'));
  final att = doc['attestation']! as Map<String, Object?>;
  final keyset = att['workload_keyset']! as Map<String, Object?>;
  keyset['e2ee_public_keys'] = [
    {
      'key_id': 'test-x25519',
      'algo': E2eeProtocolV2.algo,
      'public_key': service.publicKeyHex,
    },
  ];
  editKeyset?.call(keyset);
  final digest = AttestCodec.prefixed(
    crypto.sha256(AttestCodec.jcsBytes(keyset)),
  );
  doc['workload_keyset_digest'] = digest;
  final statement =
      '{"keyset_digest":"$digest","nonce":"${AttestCodec.hex(nonce ?? probeNonce)}",'
      '"purpose":"aci.report_data.v1"}';
  final reportData = AttestCodec.hex(
    crypto.sha256(Uint8List.fromList(utf8.encode(statement))),
  );
  att['report_data'] = reportData;
  final evidence = att['evidence']! as Map<String, Object?>;
  evidence['quote_report_data'] = '$reportData${'0' * 64}';
  final quote = evidence['quote']! as String;
  evidence['quote'] =
      '${quote.substring(0, 1136)}$reportData${'0' * 64}'
      '${quote.substring(1136 + 128)}';
  return doc;
}

/// A session whose E2EE key is the one of [service].
E2eeKey keyOf(FakeE2eeService service) => E2eeKey(
  keyId: 'test-x25519',
  algo: E2eeProtocolV2.algo,
  publicKey: service.key.public,
);

/// Puts the E2EE service in front of a plain chat [backend]: requests to
/// `chat/completions` are decrypted and forwarded in plain, SSE answers are
/// encrypted line by line while they stream; everything else (and error
/// answers) passes through.
http.Client e2eeFront(FakeE2eeService service, http.Client backend) =>
    _E2eeFront(service, backend);

final class _E2eeFront extends http.BaseClient {
  _E2eeFront(this._service, this._backend);

  final FakeE2eeService _service;
  final http.Client _backend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('chat/completions')) {
      return _backend.send(request);
    }
    final body = await request.finalize().toBytes();
    final FakeE2eeExchange exchange;
    try {
      exchange = _service.open(request.headers, body);
    } on E2eeRejection catch (e) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(e.body)),
        400,
        headers: {'content-type': 'application/json'},
      );
    }
    final forward = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..headers.removeWhere((k, _) => k.toLowerCase().contains('e2ee'))
      ..bodyBytes = exchange.plainBytes;
    final response = await _backend.send(forward);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return response;
    }
    final sealed = response.stream
        .transform(utf8.decoder)
        .transform(_lines())
        .map((line) => utf8.encode(exchange.sealSse(line)));
    return http.StreamedResponse(
      sealed,
      response.statusCode,
      headers: {...response.headers, ...exchange.responseHeaders},
      request: request,
    );
  }
}

/// Splits text into complete lines (with their `\n`).
StreamTransformer<String, String> _lines() =>
    StreamTransformer.fromBind((input) async* {
      var buffer = '';
      await for (final chunk in input) {
        buffer += chunk;
        var i = buffer.indexOf('\n');
        while (i >= 0) {
          yield buffer.substring(0, i + 1);
          buffer = buffer.substring(i + 1);
          i = buffer.indexOf('\n');
        }
      }
      if (buffer.isNotEmpty) yield buffer;
    });
