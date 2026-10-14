import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'providers.dart';

/// Newest entries of the TEE verification log (Prüfprotokoll), newest first.
final attestationRecordsProvider =
    FutureProvider.autoDispose<List<AttestationRecord>>(
      (ref) => ref.watch(storageProvider).attestations.latest(limit: 200),
    );

/// One entry of the verification log by its id (`AttestationStatusChanged.logId`).
final attestationRecordProvider = FutureProvider.autoDispose
    .family<AttestationRecord?, String>(
      (ref, logId) => ref.watch(storageProvider).attestations.byLogId(logId),
    );
