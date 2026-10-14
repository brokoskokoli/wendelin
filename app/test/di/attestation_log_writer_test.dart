import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/attestation_log_writer.dart';
import 'package:wendelin/di/audit_recorder.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

AttestationLogEntry _entry() => AttestationLogEntry(
  logId: 'log-1',
  time: DateTime.utc(2026, 10, 14, 9),
  kind: AttestationLogKind.receipt,
  profileId: 'near',
  model: 'm',
  status: AttestationStatus.red,
  receiptId: 'rc-1',
  repoCommit: 'abc',
  composeHash: 'sha256:c',
  keysetDigest: 'sha256:k',
  stages: const [
    StageResult.pass(AttestationStage.quote),
    StageResult.fail(
      AttestationStage.upstreamTcb,
      'TCB veraltet',
      code: StageResult.upstreamTcbOutOfDate,
    ),
    StageResult.fail(AttestationStage.gpu, 'GPU-Prüfung fehlgeschlagen'),
  ],
);

void main() {
  test(
    'Sink schreibt Stufen, TCB und Grundcode; attach ordnet den Schritt zu',
    () async {
      final storage = openInMemoryStorage();
      addTearDown(storage.close);
      final writer = AttestationLogWriter(storage.attestations);
      final recorder = AuditRecorder(
        storage.audit,
        clock: const SystemClock(),
        attestation: writer,
      );
      writer.record(_entry());
      recorder.agentEvent(
        'sess',
        const AttestationStatusChanged(
          stepId: 'step-1',
          status: AttestationStatus.red,
          logId: 'log-1',
        ),
      );
      await writer.flush();

      final r = (await storage.attestations.forStep('step-1')).single;
      expect(r.sessionId, 'sess');
      expect(r.status, AttestationStatus.red);
      expect(r.reasonCode, 'upstream_tcb_out_of_date');
      expect(r.tcbStatus, 'fail');
      expect(
        [for (final s in r.stages) s.stage],
        ['quote', 'receipt.upstream.tcb', 'gpu'],
      );
      expect(r.receiptId, 'rc-1');
      expect(r.workloadKeysetDigest, 'sha256:k');
      // Nicht im allgemeinen Audit-Log.
      expect(await storage.audit.query(), isEmpty);
    },
  );

  test('Grundcode: der erste Stufen-Code gewinnt (Ursache vor Folgen)', () {
    final e = AttestationLogEntry(
      logId: 'l',
      time: DateTime.utc(2026),
      kind: AttestationLogKind.receipt,
      profileId: 'near',
      status: AttestationStatus.red,
      stages: const [
        StageResult.fail(AttestationStage.quote, 'a', code: 'first_code'),
        StageResult.fail(AttestationStage.gpu, 'b', code: 'last_code'),
      ],
    );
    expect(AttestationLogWriter.toRecord(e).reasonCode, 'first_code');
  });

  test('langer Servertext im detail wird auf 200 Zeichen gekürzt', () {
    final long = 'x' * 500;
    final e = AttestationLogEntry(
      logId: 'l',
      time: DateTime.utc(2026),
      kind: AttestationLogKind.receipt,
      profileId: 'near',
      status: AttestationStatus.red,
      stages: [StageResult.fail(AttestationStage.quote, long)],
    );
    final d = AttestationLogWriter.toRecord(e).stages.single.detail!;
    expect(d, '${'x' * 200}…');
  });

  test('Schreibfehler gehen an onError', () async {
    final errors = <Object>[];
    final writer = AttestationLogWriter(
      _Failing(),
      onError: (e, _) => errors.add(e),
    );
    writer.record(_entry());
    await writer.flush();
    expect(errors, hasLength(1));
  });
}

final class _Failing implements AttestationLogRepository {
  @override
  Future<void> add(AttestationRecord record) =>
      Future.error(StateError('Datenbank weg'));

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
