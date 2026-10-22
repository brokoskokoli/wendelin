import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/voice_providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../onboarding/voice_download_step.dart';
import 'settings_page.dart';

/// One downloadable speech model: name, size and state, a progress bar
/// while loading and the matching action (Laden, Abbrechen, Fortsetzen,
/// Löschen). With [onSelect] an installed model can be chosen; [selected]
/// shows the check mark.
class ModelDownloadRow extends ConsumerWidget {
  /// Creates the row for [model].
  const ModelDownloadRow({
    super.key,
    required this.model,
    this.selected = false,
    this.onSelect,
    this.deletable = true,
    this.onDeleted,
    this.extra,
    this.recommended = false,
  });

  /// Small action next to the check mark of the chosen model (WP74: the
  /// play button of „Probe hören“).
  final Widget? extra;

  /// Adds „(empfohlen)“ to the title (WP129: Parakeet checks the wake word).
  final bool recommended;

  /// Catalog entry.
  final SpeechModel model;

  /// Whether this model is the chosen one.
  final bool selected;

  /// Chooses the model (only offered once it is installed).
  final VoidCallback? onSelect;

  /// Called after the model was deleted.
  final VoidCallback? onDeleted;

  /// Whether „Löschen“ is offered for an installed model.
  final bool deletable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      modelStatesProvider.select(
        (s) => s[model.id] ?? const ModelState(ModelPhase.unknown),
      ),
    );
    final notifier = ref.read(modelStatesProvider.notifier);
    final installed = state.phase == ModelPhase.installed;
    final size = sizeLabel(context.l10n, model.sizeBytes);
    final detail = switch (state.phase) {
      ModelPhase.downloading => context.l10n.voiceDownloadLoadingPercentOf(
        '${(state.progress * 100).floor()}',
        size,
      ),
      ModelPhase.unpacking => context.l10n.voiceDownloadUnpacking,
      ModelPhase.installed => context.l10n.modelRowLoaded(size),
      ModelPhase.partial => context.l10n.modelRowStarted(size),
      ModelPhase.absent ||
      ModelPhase.unknown => context.l10n.modelRowNotLoaded(size),
    };
    final action = switch (state.phase) {
      ModelPhase.downloading => (
        context.l10n.cancel,
        () => notifier.cancel(model.id),
      ),
      ModelPhase.unpacking || ModelPhase.unknown => null,
      ModelPhase.installed =>
        deletable
            ? (context.l10n.delete, () => unawaited(_delete(context, ref)))
            : null,
      ModelPhase.partial => (
        context.l10n.modelRowResume,
        () => unawaited(notifier.download(model.id)),
      ),
      ModelPhase.absent => (
        state.error == null
            ? context.l10n.voiceDownloadLoad
            : context.l10n.voiceDownloadLoadAgain,
        () => unawaited(notifier.download(model.id)),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          title: recommended
              ? '${model.displayName} ${context.l10n.modelRowRecommended}'
              : model.displayName,
          detail: [
            detail,
            if (model.ramBytes case final ram?)
              context.l10n.modelRowRam(sizeLabel(context.l10n, ram)),
            ?model.hint,
          ].join('\n'),
          onTap: installed ? onSelect : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: WSpace.s,
            children: [
              if (selected && installed)
                CheckStatusIcon(
                  CheckStatus.ok,
                  semanticLabel: context.l10n.selected,
                ),
              if (selected && installed && extra != null) extra!,
              if (action != null)
                _SmallButton(label: action.$1, onPressed: action.$2),
            ],
          ),
        ),
        if (state.busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(WSpace.l, 0, WSpace.l, WSpace.m),
            child: LinearProgressIndicator(
              value: state.phase == ModelPhase.unpacking
                  ? null
                  : state.progress,
              color: WColors.accent,
              backgroundColor: WColors.surfaceRaised,
              semanticsLabel: context.l10n.modelRowProgressOf(
                model.displayName,
              ),
            ),
          ),
        if (state.error case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(WSpace.l, 0, WSpace.l, WSpace.m),
            child: Row(
              spacing: WSpace.s,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckStatusIcon(
                  CheckStatus.failed,
                  semanticLabel: context.l10n.error,
                ),
                Expanded(child: Text(error, style: WText.detail)),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: context.l10n.modelRowDeleteTitle(model.displayName),
      message: context.l10n.modelRowDeleteBody,
      yes: context.l10n.delete,
    );
    if (!ok) return;
    await ref.read(modelStatesProvider.notifier).delete(model.id);
    onDeleted?.call();
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: WColors.text,
      side: const BorderSide(color: WColors.line, width: WSize.border),
      textStyle: WText.buttonSmall,
      minimumSize: const Size(WSize.touchMin, WSize.buttonHeightSmall),
      padding: const EdgeInsets.symmetric(horizontal: WSpace.m14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WRadius.tile),
      ),
    ),
    child: Text(label),
  );
}
