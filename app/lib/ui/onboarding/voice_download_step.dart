import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/voice_providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/device_memory.dart';
import '../design/design.dart';
import '../settings/settings_page.dart';

/// [bytes] for the user: below 10 MB with one decimal („0,6 MB“), above
/// rounded like [megabytes].
String sizeLabel(AppLocalizations l, int bytes) => bytes >= 10000000
    ? l.voiceDownloadSizeMb('${(bytes / 1000000).round()}')
    : l.voiceDownloadSizeMb(decimal1(l, bytes / 1000000));

/// Name of [model] without the note after the dash or in brackets
/// („Whisper small“).
String shortModelName(SpeechModel model) =>
    model.displayName.split(' – ').first.split(' (').first;

/// What the onboarding download still needs for the chosen combination
/// (Whisper model plus Silero VAD), derived from the download states.
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

  /// Label of the load button.
  String loadLabel(AppLocalizations l) => busy
      ? l.voiceDownloadLoading
      : error != null
      ? l.voiceDownloadLoadAgain
      : resumable
      ? l.voiceDownloadContinueLoading
      : l.voiceDownloadLoad;
}

/// Onboarding step „Spracherkennung laden“ (concept: Onboarding): the
/// user picks the Whisper model, one „Laden“ fetches it together with
/// Silero VAD, which belongs to it. „Noch nötig: …“ or „Bereit“ says what
/// is missing; „Weiter“ appears once the combination is installed. The
/// step can be skipped; a running download continues in the background,
/// further models come from Einstellungen → Sprache.
class VoiceDownloadStep extends ConsumerStatefulWidget {
  /// Creates the step; [onNext] goes to the next step.
  const VoiceDownloadStep({
    super.key,
    required this.onNext,
    this.skippable = true,
  });

  /// Next onboarding step.
  final VoidCallback onNext;

  /// Offers „Später“ / „Im Hintergrund weiter“ (off in the setup wizard,
  /// where the page is required).
  final bool skippable;

  @override
  ConsumerState<VoiceDownloadStep> createState() => _VoiceDownloadState();
}

class _VoiceDownloadState extends ConsumerState<VoiceDownloadStep> {
  @override
  void initState() {
    super.initState();
    // A download interrupted by closing the app continues here.
    unawaited(
      Future(() => ref.read(modelStatesProvider.notifier).resumePartial()),
    );
  }

  void _load(DownloadPlan plan) {
    final n = ref.read(modelStatesProvider.notifier);
    for (final m in plan.missing) {
      unawaited(n.download(m.id));
    }
  }

  Widget _status(DownloadPlan plan) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: WSpace.s,
    children: [
      StatusCard(
        key: const ValueKey('downloadStatus'),
        status: plan.ready
            ? CheckStatus.ok
            : plan.error != null && !plan.busy
            ? CheckStatus.failed
            : CheckStatus.pending,
        title: plan.status(context.l10n),
        detail: plan.ready
            ? null
            : plan.busy
            ? context.l10n.voiceDownloadLoadingPercent(
                '${(plan.progress * 100).floor()}',
              )
            : plan.error,
      ),
      if (plan.busy)
        LinearProgressIndicator(
          value: plan.progress,
          color: WColors.accent,
          backgroundColor: WColors.surfaceRaised,
          semanticsLabel: context.l10n.voiceDownloadProgressLabel,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(voiceSettingsProvider).value ?? const VoiceSettings();
    final catalog = ref.watch(speechModelCatalogProvider);
    final states = ref.watch(modelStatesProvider);
    final whisper =
        catalog.byId(settings.sttModel) ?? SpeechModelCatalog.whisperSmall;
    final lowMemory = isLowMemory(ref.watch(deviceMemoryProvider).value);
    const vad = SpeechModelCatalog.sileroVad;
    final plan = DownloadPlan.of([whisper, vad], states);

    return SettingsPage(
      title: context.l10n.voiceDownloadTitle,
      intro: context.l10n.voiceDownloadIntro,
      children: [
        SectionCard(
          children: [
            for (final m in catalog.ofKind(SpeechModelKind.stt))
              _ModelChoice(
                model: m,
                state: states[m.id] ?? const ModelState(ModelPhase.unknown),
                selected: m.id == whisper.id,
                onSelect: plan.busy
                    ? null
                    : () => unawaited(
                        ref
                            .read(voiceSettingsProvider.notifier)
                            .change((s) => s.copyWith(sttModel: m.id)),
                      ),
              ),
          ],
        ),
        Text(
          context.l10n.voiceDownloadBundled(
            vad.displayName,
            sizeLabel(context.l10n, vad.sizeBytes),
          ),
          style: WText.caption,
        ),
        if (lowMemory && whisper.id == SpeechModelCatalog.whisperBase.id)
          Text(
            lowMemoryReason(
              context.l10n,
              ref.watch(deviceMemoryProvider).value!,
            ),
            style: WText.caption,
          ),
        _status(plan),
        if (plan.ready)
          PrimaryButton(context.l10n.next, onPressed: widget.onNext)
        else ...[
          PrimaryButton(
            plan.loadLabel(context.l10n),
            onPressed: plan.canLoad ? () => _load(plan) : null,
          ),
          if (widget.skippable)
            WideButton(
              plan.busy
                  ? context.l10n.voiceDownloadContinueInBackground
                  : context.l10n.later,
              onPressed: widget.onNext,
            ),
        ],
      ],
    );
  }
}

/// A Whisper model to choose: name, size and state, check mark when
/// chosen. No button of its own: „Laden“ below loads the choice.
class _ModelChoice extends StatelessWidget {
  const _ModelChoice({
    required this.model,
    required this.state,
    required this.selected,
    required this.onSelect,
  });

  final SpeechModel model;
  final ModelState state;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final size = sizeLabel(context.l10n, model.sizeBytes);
    return Semantics(
      selected: selected,
      button: true,
      child: SettingsRow(
        title: model.displayName,
        detail: switch (state.phase) {
          ModelPhase.downloading => context.l10n.voiceDownloadLoadingPercentOf(
            '${(state.progress * 100).floor()}',
            size,
          ),
          ModelPhase.unpacking => context.l10n.voiceDownloadUnpacking,
          ModelPhase.installed => context.l10n.voiceDownloadSizeLoaded(size),
          ModelPhase.partial => context.l10n.voiceDownloadSizePartial(size),
          ModelPhase.absent || ModelPhase.unknown => size,
        },
        onTap: onSelect,
        trailing: selected
            ? CheckStatusIcon(
                CheckStatus.ok,
                semanticLabel: context.l10n.selected,
              )
            : null,
      ),
    );
  }
}

/// Why the onboarding suggests base on a device with [totalBytes] RAM.
String lowMemoryReason(AppLocalizations l, int totalBytes) {
  final gb = decimal1(l, totalBytes / (1024 * 1024 * 1024));
  return l.voiceDownloadPreselectedBase(gb);
}
