import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'app_settings.dart';
import 'providers.dart';

/// Result of one check stage as the restriction logic needs it.
typedef StageView = ({String stage, String result, String? detail});

/// Stage ids that are only logged (`info`): what this provider does not
/// deliver (no endorsement, no commit list, GPU not checked, …). Warnings
/// (`warn`), failures and unavailable stages are never restrictions: they
/// stay visible in the Prüfprotokoll and are not covered by an acceptance.
Set<String> restrictionStages(Iterable<StageView> stages) => {
  for (final s in stages)
    // The GPU line is the user's own setting (check off), not a property of
    // the provider.
    if (s.result == 'info' && s.stage != 'gpu') s.stage,
};

/// The restrictions of [profileId] the user accepted.
Future<Set<String>> loadAcceptedRestrictions(
  SettingsRepository settings,
  String profileId,
) async {
  try {
    final json = await settings.get(AppSettings.teeAccepted(profileId));
    final list = json?['stages'];
    return {if (list is List) ...list.whereType<String>()};
  } on FormatException {
    return {}; // A damaged value counts as nothing accepted.
  }
}

/// Stores [stages] as the accepted restrictions of [profileId].
Future<void> acceptRestrictions(
  SettingsRepository settings,
  String profileId,
  Set<String> stages,
) => settings.set(AppSettings.teeAccepted(profileId), {
  'stages': (stages.toList()..sort()),
});

/// Restrictions of the check behind [logId] that the user has not accepted
/// yet (empty: the answer is simply green). A new restriction (a stage that
/// was fine at setup and is only logged now) shows up here and makes the
/// chat point to the setup note again.
final openRestrictionsProvider = FutureProvider.autoDispose
    .family<Set<String>, String>((ref, logId) async {
      if (logId.isEmpty) return {};
      final storage = ref.watch(storageProvider);
      final record = await storage.attestations.byLogId(logId);
      if (record == null) return {};
      final now = restrictionStages([
        for (final s in record.stages)
          (stage: s.stage, result: s.result, detail: s.detail),
      ]);
      if (now.isEmpty) return {};
      final accepted = await loadAcceptedRestrictions(
        storage.settings,
        record.profileId,
      );
      return now.difference(accepted);
    });
