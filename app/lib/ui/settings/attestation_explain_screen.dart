import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../di/tee_restrictions.dart';
import '../attestation/attestation_texts.dart';
import '../attestation/stage_explanations.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// „Details“ (WP78): per check stage what is checked, the result of this
/// check and what it means for security. With a [profileId] the page also
/// offers to accept the provider's restrictions (stages that are only
/// logged), which the chat then no longer points out.
class AttestationExplainScreen extends ConsumerWidget {
  /// Creates the page.
  const AttestationExplainScreen({
    super.key,
    required this.stages,
    this.profileId,
  });

  /// Results of the check, one per stage.
  final List<StageView> stages;

  /// Profile whose restrictions can be accepted here; `null` where the
  /// acceptance happens elsewhere (setup: with „Speichern“).
  final String? profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = profileId;
    final accepted = id == null
        ? null
        : ref.watch(_acceptedProvider(id)).value ?? const <String>{};
    final restricted = {for (final s in restrictedStages(stages)) s.stage};
    final open = accepted == null
        ? <String>{}
        : restricted.difference(accepted);
    return SettingsPage(
      title: 'Details zur Prüfung',
      intro:
          'Was Wendelin prüft, was dabei herauskam und was das für deine '
          'Sicherheit heißt.',
      children: [
        if (open.isNotEmpty && id != null)
          StatusCard(
            key: const ValueKey('restrictionNotice'),
            status: CheckStatus.info,
            title: 'Einschränkungen dieses Anbieters',
            detail:
                '${open.map(stageLabel).join(', ')}: nur protokolliert. '
                'Wenn du das akzeptierst, zeigt der Chat dafür keinen '
                'Hinweis mehr.',
            actionBelow: true,
            action: TextButton(
              key: const ValueKey('acceptRestrictions'),
              onPressed: () => unawaited(_accept(ref, id, restricted)),
              child: const Text('Akzeptieren'),
            ),
          ),
        for (final s in stages) _StageBlock(s),
      ],
    );
  }

  Future<void> _accept(WidgetRef ref, String id, Set<String> all) async {
    final settings = ref.read(storageProvider).settings;
    final now = await loadAcceptedRestrictions(settings, id);
    await acceptRestrictions(settings, id, {...now, ...all});
    ref
      ..invalidate(_acceptedProvider(id))
      ..invalidate(openRestrictionsProvider);
  }
}

final _acceptedProvider = FutureProvider.autoDispose
    .family<Set<String>, String>(
      (ref, id) =>
          loadAcceptedRestrictions(ref.watch(storageProvider).settings, id),
    );

class _StageBlock extends StatelessWidget {
  const _StageBlock(this.s);

  final StageView s;

  @override
  Widget build(BuildContext context) {
    final e = stageExplanationFor(s.stage);
    return SectionCard(
      key: ValueKey('stage-${s.stage}'),
      children: [
        StageLineWithText(
          label: stageLabel(s.stage),
          result: stageResultLabel(s.result),
          status: stageResultStatus(s.result),
          paragraphs: [
            if (e != null) 'Geprüft wird: ${e.what}',
            if (s.detail != null) 'Ergebnis: ${s.detail}',
            'Bedeutung: ${stageMeaning(s.stage, s.result)}',
          ],
        ),
      ],
    );
  }
}

/// A stage line with several paragraphs of explanation.
class StageLineWithText extends StatelessWidget {
  /// Creates the block.
  const StageLineWithText({
    super.key,
    required this.label,
    required this.result,
    required this.status,
    required this.paragraphs,
  });

  /// Name of the stage.
  final String label;

  /// Result in words.
  final String result;

  /// Symbol.
  final CheckStatus status;

  /// Explanation paragraphs.
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: WSpace.l,
      vertical: WSpace.s,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WSpace.m,
      children: [
        CheckStatusIcon(status, size: WSize.statusIconSmall),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WSpace.xs,
            children: [
              Text('$label · $result', style: WText.body),
              for (final p in paragraphs) Text(p, style: WText.caption),
            ],
          ),
        ),
      ],
    ),
  );
}
