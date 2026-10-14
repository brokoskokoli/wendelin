import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'tee_support.dart';

/// Expects that exactly [stages] failed in [results].
void expectRedStages(
  Iterable<StageResult> results,
  Set<AttestationStage> stages,
) {
  expect(
    stagesWith(results, StageOutcome.fail).toSet(),
    stages,
    reason: results.toString(),
  );
}

Map<String, Object?> _attestation(Map<String, Object?> doc) =>
    doc['attestation']! as Map<String, Object?>;

Map<String, Object?> _evidence(Map<String, Object?> doc) =>
    _attestation(doc)['evidence']! as Map<String, Object?>;

/// Tests against the real probe data of 2026-10-14. [create] makes the
/// crypto under test: the fake (WP46) or the Rust implementation (WP47, via
/// `real_crypto_hook_test.dart`). A manipulation must turn exactly the
/// expected stage red.
void gatewayFixtureTests(
  AttestationCrypto Function() create, {
  required String name,
  bool verifiesQuoteSignature = false,
}) {
  group('$name: Attestierung mit Probe-Daten', () {
    if (verifiesQuoteSignature) {
      test('Quote: manipulierte Signatur → Quote rot, Sitzung fehlt', () async {
        final doc = copyJson(teeJson('gateway_attestation'));
        final ev = _evidence(doc);
        final quote = ev['quote']! as String;
        final at = quote.length - 80;
        ev['quote'] =
            '${quote.substring(0, at)}${quote[at] == '0' ? '1' : '0'}'
            '${quote.substring(at + 1)}';
        final result = await probeVerifier(
          attestationServer(doc),
          create(),
        ).attest();
        expect(result.status, AttestationStatus.red);
        expect(
          stagesWith(result.stages, StageOutcome.fail),
          contains(AttestationStage.quote),
        );
        expect(result.session, isNull);
      });
    }

    test('grüner Pfad: alle Prüfstufen bestehen', () async {
      final result = await probeVerifier(
        attestationServer(),
        create(),
      ).attest();
      expect(result.status, AttestationStatus.green);
      expect(stagesWith(result.stages, StageOutcome.fail), isEmpty);
      expect(
        stagesWith(result.stages, StageOutcome.pass),
        containsAll([
          AttestationStage.quote,
          AttestationStage.tcb,
          AttestationStage.nonceBinding,
          AttestationStage.keysetDigest,
          AttestationStage.freshness,
          AttestationStage.eventLog,
          AttestationStage.composeHash,
        ]),
      );
      final session = result.session!;
      expect(
        session.keysetDigest,
        teeJson('gateway_attestation')['workload_keyset_digest'],
      );
      expect(session.receiptKeys, contains('dstack-kms-receipt-ed25519-v1'));
      expect(session.repoCommit, '24a31ff1b33cb45cd2ad0ddac02749eb4ea424e2');
    });

    test('Nonce: andere Nonce erwartet → nur die Nonce-Bindung rot', () async {
      final result = await probeVerifier(
        attestationServer(),
        create(),
        nonce: Uint8List.fromList(List.filled(32, 0xcd)),
      ).attest();
      expect(result.status, AttestationStatus.red);
      expectRedStages(result.stages, {AttestationStage.nonceBinding});
      expect(result.session, isNull);
    });

    test('Keyset: manipulierter Schlüssel → nur der Keyset-Digest rot', () async {
      final doc = copyJson(teeJson('gateway_attestation'));
      final keys =
          (_attestation(doc)['workload_keyset']!
                  as Map<String, Object?>)['receipt_signing_keys']!
              as List<Object?>;
      (keys.first! as Map<String, Object?>)['public_key'] =
          '0${'110f3824daeeef29dbeba9677a5794ffed257b1082d9fd4599b3c0819953aa0a'.substring(1)}';
      final result = await probeVerifier(
        attestationServer(doc),
        create(),
      ).attest();
      expect(result.status, AttestationStatus.red);
      expectRedStages(result.stages, {AttestationStage.keysetDigest});
    });

    test(
      'Keyset-Digest im Dokument ersetzt → Digest und Nonce-Bindung rot',
      () async {
        final doc = copyJson(teeJson('gateway_attestation'));
        doc['workload_keyset_digest'] = 'sha256:${'00' * 32}';
        final result = await probeVerifier(
          attestationServer(doc),
          create(),
        ).attest();
        expectRedStages(result.stages, {
          AttestationStage.keysetDigest,
          AttestationStage.nonceBinding,
        });
      },
    );

    test('abgelaufenes not_after → nur die Frische rot', () async {
      final notAfter =
          (_attestation(teeJson('gateway_attestation'))['workload_keyset']!
                  as Map<String, Object?>)['not_after']!
              as int;
      final result = await probeVerifier(
        attestationServer(),
        create(),
        now: DateTime.fromMillisecondsSinceEpoch(
          (notAfter + 1) * 1000,
          isUtc: true,
        ),
      ).attest();
      expect(result.status, AttestationStatus.red);
      expectRedStages(result.stages, {AttestationStage.freshness});
    });

    test('app_compose verändert → nur der Compose-Hash rot', () async {
      final doc = copyJson(teeJson('gateway_attestation'));
      final ev = _evidence(doc);
      ev['app_compose'] = '${ev['app_compose']} ';
      final result = await probeVerifier(
        attestationServer(doc),
        create(),
      ).attest();
      expectRedStages(result.stages, {AttestationStage.composeHash});
    });

    test('Event-Log verändert → nur das Event-Log rot', () async {
      final doc = copyJson(teeJson('gateway_attestation'));
      final ev = _evidence(doc);
      final log = (ev['event_log']! as String).replaceFirst(
        '"event":"system-ready"',
        '"event":"system-readx"',
      );
      expect(log, isNot(ev['event_log']));
      ev['event_log'] = log;
      final result = await probeVerifier(
        attestationServer(doc),
        create(),
      ).attest();
      expectRedStages(result.stages, {AttestationStage.eventLog});
    });
  });

  group('$name: Quittung mit Probe-Daten', () {
    Future<(PhalaVerifier, AttestedSession)> session({
      bool enforced = false,
    }) async {
      final server = TeeServer({
        'aci/attestation': jsonBody(teeJson('gateway_attestation')),
        'aci/receipts/': jsonBody(receiptJson),
      });
      final v = probeVerifier(
        server,
        create(),
        expectUpstreamEnforced: enforced,
      );
      return (v, (await v.attest()).session!);
    }

    final bytes = Uint8List.fromList([1, 2, 3]);

    test(
      'echte Signatur und Bindung bestehen, fremde Bytes sind rot',
      () async {
        final (v, s) = await session();
        final r = await v.verifyReceipt(
          ReceiptRef(id: 'rcpt-6120', session: s),
          bytes,
          bytes,
        );
        // Request and response bytes of the probe are not stored: only their
        // hashes are checked, which must not match arbitrary bytes.
        expectRedStages(r.stages, {
          AttestationStage.requestHash,
          AttestationStage.responseHash,
        });
        expect(
          stagesWith(r.stages, StageOutcome.pass),
          containsAll([
            AttestationStage.receiptSignature,
            AttestationStage.receiptBinding,
            AttestationStage.upstream,
            AttestationStage.receiptEvents,
          ]),
        );
        expect(r.status, AttestationStatus.red);
      },
    );

    test('Quittungssignatur: verändertes Feld → Signatur rot', () async {
      final tampered = copyJson(receiptJson)..['served_at'] = 1;
      final server = TeeServer({
        'aci/attestation': jsonBody(teeJson('gateway_attestation')),
        'aci/receipts/': jsonBody(tampered),
      });
      final v = probeVerifier(server, create(), expectUpstreamEnforced: false);
      final s = (await v.attest()).session!;
      final r = await v.verifyReceipt(
        ReceiptRef(id: 'x', session: s),
        bytes,
        bytes,
      );
      expect(
        stagesWith(r.stages, StageOutcome.fail),
        contains(AttestationStage.receiptSignature),
      );
    });

    test('Quittungssignatur: gekipptes Bit → Signatur rot', () async {
      final tampered = copyJson(receiptJson);
      final sig = tampered['signature']! as String;
      tampered['signature'] =
          '${sig.substring(0, 5)}${sig[5] == '0' ? '1' : '0'}${sig.substring(6)}';
      final server = TeeServer({
        'aci/attestation': jsonBody(teeJson('gateway_attestation')),
        'aci/receipts/': jsonBody(tampered),
      });
      final v = probeVerifier(server, create(), expectUpstreamEnforced: false);
      final s = (await v.attest()).session!;
      final r = await v.verifyReceipt(
        ReceiptRef(id: 'x', session: s),
        bytes,
        bytes,
      );
      expect(
        stagesWith(r.stages, StageOutcome.fail),
        contains(AttestationStage.receiptSignature),
      );
    });
  });
}

/// The receipt of the probe.
Map<String, Object?> get receiptJson => teeJson('receipt');
