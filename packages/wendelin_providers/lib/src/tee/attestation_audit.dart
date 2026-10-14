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
    final id = 'att-${now.microsecondsSinceEpoch}-${_counter++}';
    lastLogId = id;
    for (final s in stages) {
      log('Wendelin/attest: ${kind.name} ${s.stage.id}=${s.outcome.name}');
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
