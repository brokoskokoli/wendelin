@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

// WP83, sparsam: ein Berichtsabruf bei Phala (kostenlos, 1-GPU-Modell), ein
// NRAS-Aufruf und ein JWKS-Abruf. Der Key bleibt in der Umgebung.
//   set -a; . ~/.wendelin-live.env; set +a; dart test -t live --run-skipped test/live/nras_live_test.dart

const _model = 'qwen/qwen-2.5-7b-instruct';

void main() {
  final key = Platform.environment['PHALA_API_KEY'];

  test('echte NRAS-Antwort: Signatur gegen das Live-JWKS geprüft', () async {
    if (key == null || key.isEmpty) {
      markTestSkipped('PHALA_API_KEY nicht gesetzt');
      return;
    }
    final client = http.Client();
    addTearDown(client.close);
    final nonce = AttestCodec.hex(
      Uint8List.fromList(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      ),
    );
    final report = await client.get(
      Uri.parse(
        'https://api.redpill.ai/v1/attestation/report'
        '?model=$_model&nonce=$nonce',
      ),
      headers: {'authorization': 'Bearer $key'},
    );
    expect(report.statusCode, 200);
    final payload = NrasGpuVerifier.decodePayload(
      (jsonDecode(report.body) as Map<String, Object?>)['nvidia_payload'],
    );
    expect(payload, isNotNull);

    final verifier = NrasGpuVerifier(
      baseUrl: Uri.parse('https://api.redpill.ai/v1'),
      client: client,
      evidenceSource: () async => (payload: payload!, nonce: nonce),
    );
    final result = await verifier.verify(model: _model);
    expect(result.verdict, GpuVerdict.verified, reason: result.detail);
    expect(result.signatureChecked, isTrue);
  });
}
