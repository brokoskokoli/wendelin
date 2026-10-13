import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/voice_providers.dart';
import '../../platform/voice/model_installer.dart';
import '../design/design.dart';
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
  });

  /// Catalog entry.
  final SpeechModel model;

  /// Whether this model is the chosen one.
  final bool selected;

  /// Chooses the model (only offered once it is installed).
  final VoidCallback? onSelect;

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
    final size = megabytes(model.sizeBytes);
    final detail = switch (state.phase) {
      ModelPhase.downloading =>
        'Lädt … ${(state.progress * 100).floor()} % von $size',
      ModelPhase.unpacking => 'Wird entpackt …',
      ModelPhase.installed => '$size · geladen',
      ModelPhase.partial => '$size · angefangen',
      ModelPhase.absent || ModelPhase.unknown => '$size · nicht geladen',
    };
    final action = switch (state.phase) {
      ModelPhase.downloading => ('Abbrechen', () => notifier.cancel(model.id)),
      ModelPhase.unpacking || ModelPhase.unknown => null,
      ModelPhase.installed =>
        deletable ? ('Löschen', () => unawaited(_delete(context, ref))) : null,
      ModelPhase.partial => (
        'Fortsetzen',
        () => unawaited(notifier.download(model.id)),
      ),
      ModelPhase.absent => (
        state.error == null ? 'Laden' : 'Erneut laden',
        () => unawaited(notifier.download(model.id)),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          title: model.displayName,
          detail: detail,
          onTap: installed ? onSelect : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: WSpace.s,
            children: [
              if (selected && installed)
                const CheckStatusIcon(CheckStatus.ok, semanticLabel: 'gewählt'),
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
              semanticsLabel: 'Fortschritt ${model.displayName}',
            ),
          ),
        if (state.error case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(WSpace.l, 0, WSpace.l, WSpace.m),
            child: Row(
              spacing: WSpace.s,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CheckStatusIcon(
                  CheckStatus.failed,
                  semanticLabel: 'Fehler',
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
      title: '${model.displayName} löschen?',
      message:
          'Das Modell wird vom Gerät entfernt und muss vor der nächsten '
          'Nutzung neu geladen werden.',
      yes: 'Löschen',
    );
    if (ok) await ref.read(modelStatesProvider.notifier).delete(model.id);
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
