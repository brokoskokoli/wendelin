import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/testing.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'fixture_suite.dart';
import 'tee_support.dart';

final _req = Uint8List.fromList(utf8.encode('{"model":"m"}'));
final _resp = Uint8List.fromList(
  utf8.encode('data: {"x":1}\n\ndata: [DONE]\n\n'),
);

Map<String, Object?> _receipt([void Function(Map<String, Object?>)? edit]) =>
    syntheticReceipt(_req, _resp, edit);

Future<ReceiptResult> _verify(
  Map<String, Object?> receipt, {
  FakeAttestationCrypto? crypto,
  Uint8List? req,
  Uint8List? resp,
  int status = 200,
  Map<String, Object?>? session,
}) async {
  final fake = crypto ?? FakeAttestationCrypto(ed25519Result: true);
  final server = TeeServer({
    'aci/attestation': jsonBody(teeJson('gateway_attestation')),
    'aci/receipts/': jsonBody(receipt, status: status),
    'aci/sessions/': jsonBody(session ?? upToDateSession()),
  });
  final v = probeVerifier(server, fake);
  final s = (await v.attest()).session!;
  return v.verifyReceipt(
    ReceiptRef(id: 'rcpt-1', session: s),
    req ?? _req,
    resp ?? _resp,
  );
}

void main() {
  group('PhalaVerifier.verifyReceipt (Probe-Quittung, Hashes angepasst)', () {
    test('grüner Pfad: alle Quittungsstufen bestehen', () async {
      final r = await _verify(_receipt());
      expect(r.status, AttestationStatus.green);
      expect(
        stagesWith(r.stages, StageOutcome.pass),
        hasLength(r.stages.length),
      );
      expect(r.pinChanged, isFalse);
      expect(r.receiptId, 'rcpt-1');
    });

    // Each manipulation turns exactly its stage red.
    final cases =
        <(String, AttestationStage, Future<ReceiptResult> Function())>[
          (
            'Signatur ungültig',
            AttestationStage.receiptSignature,
            () => _verify(
              _receipt(),
              crypto: FakeAttestationCrypto(ed25519Result: false),
            ),
          ),
          (
            'Anfrage-Bytes weichen vom body_hash ab',
            AttestationStage.requestHash,
            () => _verify(_receipt(), req: Uint8List.fromList([1])),
          ),
          (
            'Antwort-Bytes weichen vom body_hash ab',
            AttestationStage.responseHash,
            () => _verify(_receipt(), resp: Uint8List.fromList([1])),
          ),
          (
            'upstream.verified nicht verified',
            AttestationStage.upstream,
            () => _verify(
              _receipt((r) {
                final e = (r['event_log']! as List)
                    .cast<Map<String, Object?>>();
                e.firstWhere(
                  (x) => x['type'] == 'upstream.verified',
                )['result'] = 'failed';
              }),
            ),
          ),
          (
            'upstream.verified nicht erzwungen (required: false)',
            AttestationStage.upstream,
            () => _verify(
              _receipt((r) {
                final e = (r['event_log']! as List)
                    .cast<Map<String, Object?>>();
                e.firstWhere(
                  (x) => x['type'] == 'upstream.verified',
                )['required'] = false;
              }),
            ),
          ),
          (
            'Ereignis route.selected fehlt',
            AttestationStage.receiptEvents,
            () => _verify(
              _receipt(
                (r) => (r['event_log']! as List).removeWhere(
                  (x) => (x as Map)['type'] == 'route.selected',
                ),
              ),
            ),
          ),
          (
            'Quittung gehört zu anderem Keyset',
            AttestationStage.receiptBinding,
            () => _verify(
              _receipt(
                (r) => r['workload_keyset_digest'] = 'sha256:${'00' * 32}',
              ),
            ),
          ),
        ];
    for (final (name, stage, run) in cases) {
      test('$name → genau ${stage.id} rot', () async {
        final r = await run();
        expect(r.status, AttestationStatus.red);
        expectRedStages(r.stages, {stage});
      });
    }

    test('anderes Keyset: pinChanged verlangt neue Attestierung', () async {
      final r = await _verify(
        _receipt((r) => r['workload_keyset_digest'] = 'sha256:${'00' * 32}'),
      );
      expect(r.pinChanged, isTrue);
    });

    test('wire_hash hat Vorrang vor body_hash der Antwort', () async {
      final r = await _verify(
        _receipt((r) {
          final e = (r['event_log']! as List).cast<Map<String, Object?>>();
          final ret = e.firstWhere((x) => x['type'] == 'response.returned');
          ret['wire_hash'] = ret['body_hash'];
          ret['body_hash'] = 'sha256:${'11' * 32}';
        }),
      );
      expect(r.status, AttestationStatus.green);
    });

    test(
      'Quittung nicht abrufbar (404/500) → gelb, Stufe receipt.fetch',
      () async {
        for (final status in [404, 500]) {
          final r = await _verify(_receipt(), status: status);
          expect(r.status, AttestationStatus.yellow, reason: '$status');
          expect(stagesWith(r.stages, StageOutcome.unavailable), [
            AttestationStage.receiptFetch,
          ]);
        }
      },
    );

    test('Pflichtfeld der Quittung fehlt → rot mit Stufe', () async {
      final r = await _verify(_receipt((r) => r.remove('signature')));
      expect(r.status, AttestationStatus.red);
      expect(r.firstProblem?.stage, AttestationStage.receiptSignature);
    });

    test('unbekannte Felder der Quittung werden toleriert', () async {
      final r = await _verify(_receipt((r) => r['zukunft'] = {'a': 1}));
      expect(r.status, AttestationStatus.green);
    });
  });
}
