import 'package:flutter/material.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

import '../../../di/routing.dart';
import '../../design/design.dart';
import 'routing_texts.dart';

/// What an import of [imported] would do to [current].
final class ImportPreview {
  /// Creates the preview.
  ImportPreview({required this.current, required this.imported});

  /// The rules and profiles now.
  final RoutingState current;

  /// The rules from the file.
  final RuleSet imported;

  /// Whether the imported default target's profile exists here.
  bool get defaultKnown =>
      current.profile(imported.defaultTarget.profileId) != null;

  /// The rule set that replaces the current one: the imported one; if its
  /// default profile does not exist here, the current default stays.
  RuleSet get result => defaultKnown
      ? imported
      : imported.copyWith(defaultTarget: current.rules!.defaultTarget);

  /// Warnings about [result] with the profiles of this device.
  List<RuleSetIssue> get issues =>
      validateRuleSet(result, current.routingProfiles);
}

/// Shows [preview]; `true` if the user confirms the replacement.
Future<bool> showImportPreview(
  BuildContext context,
  ImportPreview preview,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _ImportDialog(preview),
    ) ??
    false;

class _ImportDialog extends StatelessWidget {
  const _ImportDialog(this.preview);

  final ImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final result = preview.result;
    final current = preview.current;
    final issues = preview.issues;
    final before = current.rules!.rules.length;
    return AlertDialog(
      backgroundColor: WColors.surface,
      title: Text('Regeln importieren?', style: WText.label),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WSpace.m,
          children: [
            Text(
              '${result.rules.length} Regeln ersetzen die bisherigen '
              '$before. Erst mit „Ersetzen“ wird etwas geändert.',
              style: WText.intro,
            ),
            for (final (i, r) in result.rules.indexed)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WSpace.xxs,
                children: [
                  Text('${i + 1}. ${r.name}', style: WText.label),
                  Text(
                    '${describeCondition(r.condition)} → '
                    '${fullTargetLabel(current, r.target)}',
                    style: WText.mono,
                  ),
                ],
              ),
            Text(
              'Standard: ${fullTargetLabel(current, result.defaultTarget)}',
              style: WText.detail,
            ),
            if (!preview.defaultKnown)
              Text(
                'Das Standardprofil „${preview.imported.defaultTarget.profileId}“ '
                'gibt es hier nicht; der bisherige Standard bleibt.',
                style: WText.detail.copyWith(color: WColors.warn),
              ),
            Text(
              'Eskalationsketten für ${result.chains.length} Profil'
              '${result.chains.length == 1 ? '' : 'e'}.',
              style: WText.detail,
            ),
            for (final i in issues)
              Text(
                i.message,
                style: WText.detail.copyWith(color: WColors.warn),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Ersetzen'),
        ),
      ],
    );
  }
}
