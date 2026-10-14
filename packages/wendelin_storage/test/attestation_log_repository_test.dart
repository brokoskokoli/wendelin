import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/storage_fixture.dart';

AttestationRecord rec(
  String logId,
  DateTime at, {
  AttestationRecordKind kind = AttestationRecordKind.receipt,
  AttestationStatus status = AttestationStatus.green,
  String? sessionId,
  String? stepId,
}) => AttestationRecord(
  logId: logId,
  at: at,
  profileId: 'near',
  model: 'm1',
  kind: kind,
  sessionId: sessionId,
  stepId: stepId,
  receiptId: 'r-$logId',
  workloadKeysetDigest: 'sha256:abc',
  workloadId: 'w1',
  repoCommit: 'c0ffee',
  composeHash: 'sha256:def',
  status: status,
  stages: const [
    StageRecord('quote', 'pass'),
    StageRecord(
      'receipt.upstream.tcb',
      'fail',
      detail: 'TCB veraltet',
      code: 'upstream_tcb_out_of_date',
    ),
  ],
  tcbStatus: 'fail',
  reasonCode: 'upstream_tcb_out_of_date',
);

void main() {
  late WendelinStorage storage;
  late FixedClock clock;
  late AttestationLogRepository repo;

  setUp(() {
    final f = openTestStorage();
    storage = f.storage;
    clock = f.clock;
    repo = storage.attestations;
  });
  tearDown(() => storage.close());

  test('add/byLogId: Roundtrip aller Felder', () async {
    final r = rec('l1', t0, sessionId: 's1', stepId: 'st1');
    await repo.add(r);
    final back = (await repo.byLogId('l1'))!;
    expect(back, r);
    expect(back.id, isNotNull);
    expect(await repo.byLogId('nope'), isNull);
  });

  test('forSession/forStep filtern, älteste zuerst', () async {
    await repo.add(
      rec(
        'a',
        t0.add(const Duration(minutes: 2)),
        sessionId: 's1',
        stepId: 'x',
      ),
    );
    await repo.add(
      rec(
        'b',
        t0.add(const Duration(minutes: 1)),
        sessionId: 's1',
        stepId: 'y',
      ),
    );
    await repo.add(rec('c', t0, sessionId: 's2', stepId: 'x'));
    expect([for (final r in await repo.forSession('s1')) r.logId], ['b', 'a']);
    expect([for (final r in await repo.forStep('x')) r.logId], ['c', 'a']);
    expect(await repo.forSession('s9'), isEmpty);
  });

  test('latest: neueste zuerst, mit Limit', () async {
    for (var i = 0; i < 4; i++) {
      await repo.add(rec('l$i', t0.add(Duration(minutes: i))));
    }
    expect(
      [for (final r in await repo.latest(limit: 2)) r.logId],
      ['l3', 'l2'],
    );
  });

  test('attachStep setzt Sitzung und Schritt nachträglich', () async {
    await repo.add(rec('l1', t0));
    expect(await repo.attachStep('l1', 's1', 'st1'), isTrue);
    expect(await repo.attachStep('zz', 's1', 'st1'), isFalse);
    final r = (await repo.byLogId('l1'))!;
    expect((r.sessionId, r.stepId), ('s1', 'st1'));
    expect(await repo.forStep('st1'), hasLength(1));
  });

  test('gleiche logId ersetzt den Eintrag', () async {
    await repo.add(rec('l1', t0));
    await repo.add(rec('l1', t0, status: AttestationStatus.red));
    final all = await repo.latest();
    expect(all.single.status, AttestationStatus.red);
  });

  test('purgeOlderThan löscht nur Alte, Standard 30 Tage', () async {
    await repo.add(rec('old', t0.subtract(const Duration(days: 31))));
    await repo.add(rec('new', t0.subtract(const Duration(days: 29))));
    expect(await repo.purgeOlderThan(), 1);
    expect([for (final r in await repo.latest()) r.logId], ['new']);
    clock.advance(const Duration(days: 10));
    expect(await repo.purgeOlderThan(const Duration(days: 30)), 1);
    expect(await repo.latest(), isEmpty);
  });

  test('deleteAll leert das Protokoll', () async {
    await repo.add(rec('a', t0));
    await repo.add(rec('b', t0));
    await repo.deleteAll();
    expect(await repo.latest(), isEmpty);
  });

  test('exportJson entspricht dem Golden-JSON', () async {
    await repo.add(
      rec(
        'l2',
        DateTime.utc(2026, 10, 14, 10),
        sessionId: 's1',
        stepId: 'st2',
        status: AttestationStatus.red,
      ),
    );
    await repo.add(
      rec(
        'l1',
        DateTime.utc(2026, 10, 14, 9),
        kind: AttestationRecordKind.session,
      ),
    );
    final golden = File('test/golden/attestation_export.json');
    final actual = await repo.exportJson();
    expect(jsonDecode(actual), jsonDecode(golden.readAsStringSync()));
  });

  test(
    'Export enthält nur Kennungen, Hashes und Ergebnisse, keine Inhalte',
    () async {
      await repo.add(rec('l1', t0, sessionId: 's1', stepId: 'st1'));
      final json = jsonDecode(await repo.exportJson()) as Map<String, Object?>;
      expect(json['version'], attestationExportVersion);
      final entry = (json['entries']! as List).single as Map<String, Object?>;
      expect(entry.keys.toSet(), {
        'logId',
        'at',
        'profileId',
        'model',
        'kind',
        'sessionId',
        'stepId',
        'receiptId',
        'workloadKeysetDigest',
        'workloadId',
        'repoCommit',
        'composeHash',
        'status',
        'stages',
        'tcbStatus',
        'reasonCode',
      });
      final stage = ((entry['stages']! as List).first as Map).keys.toSet();
      expect(stage, {'stage', 'result'});
    },
  );
}
