import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/testing.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'provider_harness.dart';
import 'tee_support.dart';

const _pending =
    'Sicherheits-Update beim Betreiber ausstehend (Upstream-TCB OutOfDate)';

Future<ReceiptResult> _verify(
  Map<String, Object?> session, {
  int sessionStatus = 200,
}) async {
  final receipt = syntheticReceipt(_empty, _empty);
  final server = TeeServer({
    'aci/attestation': jsonBody(teeJson('gateway_attestation')),
    'aci/receipts/': jsonBody(receipt),
    'aci/sessions/': jsonBody(session, status: sessionStatus),
  });
  final v = probeVerifier(server, FakeAttestationCrypto(ed25519Result: true));
  final s = (await v.attest()).session!;
  return v.verifyReceipt(ReceiptRef(id: 'rcpt-1', session: s), _empty, _empty);
}

final _empty = Uint8List(0);

void main() {
  group('Upstream-TCB (receipt.upstream.tcb)', () {
    test('Fixture-Session OutOfDate: rot mit eigenem Grund-Code', () async {
      final r = await _verify(outOfDateSession());
      expect(r.status, AttestationStatus.red);
      final stage = r.firstProblem!;
      expect(stage.stage, AttestationStage.upstreamTcb);
      expect(stage.code, StageResult.upstreamTcbOutOfDate);
      expect(stage.detail, _pending);
      // Only this stage is red: no forgery, signature and hashes are fine.
      expect(stagesWith(r.stages, StageOutcome.fail), [
        AttestationStage.upstreamTcb,
      ]);
    });

    test('manipulierte UpToDate-Variante: grün', () async {
      final r = await _verify(upToDateSession());
      expect(r.status, AttestationStatus.green);
      expect(
        r.stages.singleWhere((s) => s.stage == AttestationStage.upstreamTcb),
        isA<StageResult>().having(
          (s) => s.outcome,
          'outcome',
          StageOutcome.pass,
        ),
      );
    });

    test('nur tcb_up_to_date refuted (Status UpToDate) ist rot', () async {
      final s = upToDateSession();
      ((s['claims']! as Map)['tcb_up_to_date']! as Map)['status'] = 'refuted';
      expect((await _verify(s)).status, AttestationStatus.red);
    });

    test('Revoked: rot mit eigenem Code', () async {
      final s = upToDateSession();
      (((s['claims']! as Map)['extra']!) as Map)['tcb_status'] = 'Revoked';
      final r = await _verify(s);
      expect(r.firstProblem?.code, StageResult.upstreamTcbRevoked);
    });

    test('Hardening-Hinweis: grün mit Notiz', () async {
      final s = upToDateSession();
      (((s['claims']! as Map)['extra']!) as Map)['tcb_status'] =
          'SWHardeningNeeded';
      final r = await _verify(s);
      expect(r.status, AttestationStatus.green);
      expect(stagesWith(r.stages, StageOutcome.warn), [
        AttestationStage.upstreamTcb,
      ]);
    });

    test('Session nicht ladbar: gelb (unavailable)', () async {
      final r = await _verify(upToDateSession(), sessionStatus: 500);
      expect(r.status, AttestationStatus.yellow);
      expect(r.firstProblem?.stage, AttestationStage.upstreamTcb);
      expect(r.firstProblem?.outcome, StageOutcome.unavailable);
    });

    test('Session ohne claims: rot (unlesbar)', () async {
      final r = await _verify({'api_version': 'aci/1'});
      expect(r.status, AttestationStatus.red);
    });

    group('im AttestedProvider', () {
      test(
        'OutOfDate: rot, Sperre, Grund-Code im Bericht und im Protokoll',
        () async {
          final h = TeeHarness()..sessionDoc = outOfDateSession();
          await h.chat();
          final report = await h.provider.pendingReport();
          expect(report?.status, AttestationStatus.red);
          expect(report?.reasonCode, StageResult.upstreamTcbOutOfDate);
          expect(report?.detail, _pending);
          expect(h.provider.locked, isTrue);
          final logged = h.log.entries.last.stages.singleWhere(
            (s) => s.stage == AttestationStage.upstreamTcb,
          );
          expect(logged.toJson()['code'], 'upstream_tcb_out_of_date');
        },
      );

      test('Netzfehler bei der Session: wiederholt, dann grün', () async {
        final h = TeeHarness()..sessionFailures = 2;
        await h.chat();
        final report = await h.provider.pendingReport();
        expect(report?.status, AttestationStatus.green);
        expect(h.server.count('aci/sessions'), 3);
      });

      test('Netzfehler bei der Session: nach 3 Versuchen rot', () async {
        final h = TeeHarness()..sessionFailures = 10;
        final reports = <AttestationReport>[];
        h.provider.reports.listen(reports.add);
        await h.chat();
        final report = await h.provider.pendingReport();
        expect(report?.status, AttestationStatus.red);
        expect(h.server.count('aci/sessions'), 3);
        expect(
          reports.where((r) => r.status == AttestationStatus.yellow),
          hasLength(2),
        );
      });
    });
  });
}
