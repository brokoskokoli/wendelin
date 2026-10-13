import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/voice_providers.dart';
import '../../platform/device_memory.dart';
import '../../platform/voice/model_installer.dart';
import '../design/design.dart';
import '../settings/settings_page.dart';

/// [bytes] for the user: below 10 MB with one decimal („0,6 MB“), above
/// rounded like [megabytes].
String sizeLabel(int bytes) => bytes >= 10000000
    ? megabytes(bytes)
    : '${(bytes / 1000000).toStringAsFixed(1).replaceAll('.', ',')} MB';

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
  String get status => ready
      ? 'Bereit'
      : 'Noch nötig: ${[for (final m in missing) '${shortModelName(m)} '
              '(${sizeLabel(m.sizeBytes)})'].join(' und ')}';

  /// Label of the load button.
  String get loadLabel => busy
      ? 'Lädt …'
      : error != null
      ? 'Erneut laden'
      : resumable
      ? 'Weiterladen'
      : 'Laden';
}

/// Onboarding step „Spracherkennung laden“ (concept: Onboarding): the
/// user picks the Whisper model, one „Laden“ fetches it together with
/// Silero VAD, which belongs to it. „Noch nötig: …“ or „Bereit“ says what
/// is missing; „Weiter“ appears once the combination is installed. The
/// step can be skipped; a running download continues in the background,
/// further models come from Einstellungen → Sprache.
class VoiceDownloadStep extends ConsumerStatefulWidget {
  /// Creates the step; [onNext] goes to the next step.
  const VoiceDownloadStep({super.key, required this.onNext});

  /// Next onboarding step.
  final VoidCallback onNext;

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
        title: plan.status,
        detail: plan.ready
            ? null
            : plan.busy
            ? 'Lädt … ${(plan.progress * 100).floor()} %'
            : plan.error,
      ),
      if (plan.busy)
        LinearProgressIndicator(
          value: plan.progress,
          color: WColors.accent,
          backgroundColor: WColors.surfaceRaised,
          semanticsLabel: 'Fortschritt Spracherkennung',
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
      title: 'Spracherkennung laden',
      intro:
          'Wendelin erkennt Sprache auf dem Gerät, ohne Internet und ohne '
          'Google. Wähle das Modell und lade es einmal, am besten im WLAN.',
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
          '${vad.displayName} gehört dazu (${sizeLabel(vad.sizeBytes)}) und '
          'wird mitgeladen. „small“ erkennt Deutsch, Französisch und Namen '
          'deutlich besser und ist empfohlen. „base“ ist schnell und für '
          'schwache Geräte gedacht. Weitere Modelle: Einstellungen → Sprache.',
          style: WText.caption,
        ),
        if (lowMemory && whisper.id == SpeechModelCatalog.whisperBase.id)
          Text(
            lowMemoryReason(ref.watch(deviceMemoryProvider).value!),
            style: WText.caption,
          ),
        _status(plan),
        if (plan.ready)
          PrimaryButton('Weiter', onPressed: widget.onNext)
        else ...[
          PrimaryButton(
            plan.loadLabel,
            onPressed: plan.canLoad ? () => _load(plan) : null,
          ),
          WideButton(
            plan.busy ? 'Im Hintergrund weiterladen' : 'Später',
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
    final size = sizeLabel(model.sizeBytes);
    return Semantics(
      selected: selected,
      button: true,
      child: SettingsRow(
        title: model.displayName,
        detail: switch (state.phase) {
          ModelPhase.downloading =>
            'Lädt … ${(state.progress * 100).floor()} % von $size',
          ModelPhase.unpacking => 'Wird entpackt …',
          ModelPhase.installed => '$size · geladen',
          ModelPhase.partial => '$size · angefangen',
          ModelPhase.absent || ModelPhase.unknown => size,
        },
        onTap: onSelect,
        trailing: selected
            ? const CheckStatusIcon(CheckStatus.ok, semanticLabel: 'gewählt')
            : null,
      ),
    );
  }
}

/// Why the onboarding suggests base on a device with [totalBytes] RAM.
String lowMemoryReason(int totalBytes) {
  final gb = (totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
  return 'Vorausgewählt ist „base“, weil das Gerät wenig Arbeitsspeicher '
      'hat (${gb.replaceAll('.', ',')} GB). „small“ braucht beim Erkennen '
      'deutlich mehr Speicher.';
}
