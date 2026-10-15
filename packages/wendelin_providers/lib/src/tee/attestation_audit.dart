import 'dart:math';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/http_settings.dart';
import 'attestation_log.dart';
import 'attestation_types.dart';

/// Writes the audit-log entries and the diagnostic lines of an
/// `AttestedProvider`. Diagnostics (`Wendelin/attest:`) name only the kind,
/// the stage and its outcome, never content.
final class AttestationAudit {
  /// Creates the audit writer.
  AttestationAudit(this.profileId, this.sink, this.settings);

  /// Provider profile id.
  final String profileId;

  /// Receives the entries (persisted by WP52).
  final AttestationLogSink? sink;

  /// Clock and diagnostic log.
  final HttpSettings settings;

  static final Random _random = Random.secure();

  int _counter = 0;

  /// Id of the entry written last.
  String lastLogId = '';

  /// Writes a diagnostic [line].
  void log(String line) => settings.log?.call(line);

  /// Writes an entry and the diagnostics for its stages; returns its id.
  String record(
    AttestationLogKind kind,
    AttestationStatus status,
    List<StageResult> stages, {
    String? model,
    String? receiptId,
    AttestedSession? session,
    List<String> notes = const [],
  }) {
    final now = settings.clock.now();
    // The random part keeps ids of different provider instances apart (the
    // store replaces entries with the same id).
    final nonce = ((_random.nextInt(1 << 32) << 32) | _random.nextInt(1 << 32))
        .toRadixString(16)
        .padLeft(16, '0');
    final id = 'att-${now.microsecondsSinceEpoch}-${_counter++}-$nonce';
    lastLogId = id;
    for (final s in stages) {
      final code = s.code == null ? '' : ' code=${s.code}';
      log('Wendelin/attest: ${kind.name} ${s.stage.id}=${s.outcome.name}$code');
    }
    log('Wendelin/attest: ${kind.name} ${status.name}');
    sink?.record(
      AttestationLogEntry(
        logId: id,
        time: now,
        kind: kind,
        profileId: profileId,
        status: status,
        stages: stages,
        model: model,
        receiptId: receiptId,
        repoCommit: session?.repoCommit,
        composeHash: session?.composeHash,
        keysetDigest: session?.keysetDigest,
        notes: notes,
      ),
    );
    return id;
  }
}
