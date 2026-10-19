import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/speaker_providers.dart';
import '../../../di/voice_providers.dart';
import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../model_download_row.dart';
import '../settings_page.dart';
import 'speaker_enroll_screen.dart';

/// Einstellungen → Sprache → Sprechererkennung (WP92a): switch (off by
/// default, with the note that a voice is no secure login), model download,
/// the enrolled people and enrolling a new one.
class SpeakerScreen extends ConsumerWidget {
  /// Creates the screen.
  const SpeakerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final enabled = ref.watch(speakerRecognitionEnabledProvider);
    final people = ref.watch(speakerProfilesProvider).value ?? const [];
    final installed =
        ref
            .watch(modelStatesProvider)[SpeechModelCatalog.speakerCamPlus.id]
            ?.phase ==
        ModelPhase.installed;
    return SettingsPage(
      title: l.speakerTitle,
      intro: l.speakerIntro,
      children: [
        SettingsSection(
          title: l.speakerSwitch,
          children: [
            SettingsRow(
              title: l.speakerSwitch,
              detail: l.speakerSwitchHint,
              trailing: WSwitch(
                value: enabled,
                semanticLabel: l.speakerSwitchLabel,
                onChanged: (v) => unawaited(
                  ref
                      .read(voiceSettingsProvider.notifier)
                      .change((s) => s.copyWith(speakerRecognition: v)),
                ),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: l.speakerModelSection,
          children: [
            ModelDownloadRow(model: SpeechModelCatalog.speakerCamPlus),
          ],
        ),
        SettingsSection(
          title: l.speakerPeople,
          children: [
            if (people.isEmpty)
              SettingsRow(title: l.speakerNobody)
            else
              for (final p in people)
                SettingsRow(
                  title: p.name,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l.speakerDeleteSemantic(p.name),
                    onPressed: () => unawaited(_delete(context, ref, p)),
                  ),
                ),
            SettingsRow(
              title: l.speakerAdd,
              detail: installed ? l.speakerAddDetail : l.speakerAddNeedsModel,
              onTap: installed ? () => unawaited(_add(context)) : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SpeakerProfile p,
  ) async {
    final l = context.l10n;
    final ok = await confirm(
      context,
      title: l.speakerDeleteTitle,
      message: l.speakerDeleteBody(p.name),
      yes: l.speakerDeleteConfirm,
    );
    if (ok) await ref.read(speakerProfilesProvider.notifier).remove(p.id);
  }

  Future<void> _add(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || !context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SpeakerEnrollScreen(name: name)),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: WColors.surface,
    title: Text(context.l10n.speakerAdd, style: WText.label),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(hintText: context.l10n.speakerNameLabel),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_controller.text.trim()),
        child: Text(context.l10n.speakerNext),
      ),
    ],
  );
}
