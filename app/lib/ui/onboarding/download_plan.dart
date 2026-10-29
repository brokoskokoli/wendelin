import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../l10n/l10n.dart';

/// [bytes] for the user: below 10 MB with one decimal („0,6 MB“), above
/// rounded like [megabytes].
String sizeLabel(AppLocalizations l, int bytes) => bytes >= 10000000
    ? l.voiceDownloadSizeMb('${(bytes / 1000000).round()}')
    : l.voiceDownloadSizeMb(decimal1(l, bytes / 1000000));

/// Name of [model] without the note after the dash or in brackets
/// („Whisper small“).
String shortModelName(SpeechModel model) =>
    model.displayName.split(' – ').first.split(' (').first;

/// What the setup wizard's speech page still needs for the chosen
/// combination (recognition model plus Silero VAD), derived from the
/// download states.
@immutable
final class DownloadPlan {
  /// Plan for [needed] with the download [states].
  factory DownloadPlan.of(
    List<SpeechModel> needed,
    Map<String, ModelState> states,
  ) {
    ModelState state(SpeechModel m) =>
        states[m.id] ?? const ModelState(ModelPhase.unknown);
    final missing = [
      for (final m in needed)
        if (state(m).phase != ModelPhase.installed) m,
    ];
    final total = needed.fold(0, (n, m) => n + m.sizeBytes);
    final loaded = needed.fold(
      0.0,
      (n, m) => switch (state(m).phase) {
        ModelPhase.installed => n + m.sizeBytes,
        ModelPhase.downloading => n + m.sizeBytes * state(m).progress,
        _ => n,
      },
    );
    return DownloadPlan._(
      missing: missing,
      busy: needed.any((m) => state(m).busy),
      checking: needed.any((m) => state(m).phase == ModelPhase.unknown),
      resumable: missing.any((m) => state(m).phase == ModelPhase.partial),
      progress: total == 0 ? 0 : loaded / total,
      error: needed.map((m) => state(m).error).nonNulls.firstOrNull,
    );
  }

  const DownloadPlan._({
    required this.missing,
    required this.busy,
    required this.checking,
    required this.resumable,
    required this.progress,
    required this.error,
  });

  /// Models of the combination that are not installed yet.
  final List<SpeechModel> missing;

  /// Whether a download or unpacking runs.
  final bool busy;

  /// Whether a state is still being checked (nothing to start yet).
  final bool checking;

  /// Whether a stopped download can continue.
  final bool resumable;

  /// Share of the combination on the device (0–1).
  final double progress;

  /// Message of the last failure, if any.
  final String? error;

  /// Whether the whole combination is installed: „Weiter“ is active.
  bool get ready => missing.isEmpty;

  /// Whether „Laden“ can start the missing downloads.
  bool get canLoad => !ready && !busy && !checking;

  /// „Bereit“ or „Noch nötig: …“ with the missing models and sizes.
  String status(AppLocalizations l) => ready
      ? l.voiceDownloadReady
      : l.voiceDownloadStillNeeded(
          [
            for (final m in missing)
              '${shortModelName(m)} '
                  '(${sizeLabel(l, m.sizeBytes)})',
          ].join(l.voiceDownloadAnd),
        );

  /// Label of the download button: „Herunterladen“, „Weiterladen“ for a
  /// stopped download, „Erneut versuchen“ after an error.
  String loadLabel(AppLocalizations l) => busy
      ? l.voiceDownloadLoading
      : error != null
      ? l.setupRetry
      : resumable
      ? l.voiceDownloadContinueLoading
      : l.setupSpeechDownload;
}
