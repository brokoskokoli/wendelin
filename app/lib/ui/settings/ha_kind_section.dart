import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/home_assistant.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'security_level_picker.dart';
import 'settings_page.dart';

/// „Stufe je Geräteart“ (WP160): one level picker per kind of Home
/// Assistant device (lights, media, scenes, switches, climate, blinds) for
/// all devices of the kind without a level of their own.
class HaKindLevelSection extends ConsumerWidget {
  /// Creates the section.
  const HaKindLevelSection({super.key});

  static String _name(AppLocalizations t, HaKind k) => switch (k) {
    HaKind.light => t.levelKindLight,
    HaKind.media => t.levelKindMedia,
    HaKind.scene => t.levelKindScene,
    HaKind.switchKind => t.levelKindSwitch,
    HaKind.climate => t.levelKindClimate,
    HaKind.cover => t.levelKindCover,
  };

  /// Default level of a kind without a choice (scenes depend on their
  /// members, blinds are D unless the old „ohne Rückfrage“ holds).
  static SecurityLevel _default(HaKind k) => haDefaultLevel(
    HaEntity(entityId: '${k.domain}.x', name: k.key),
    scene: HaSceneKind.safe,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final loaded = ref.watch(haKindLevelsProvider);
    // No choice before the stored levels are read: a choice on an empty base
    // would overwrite the stored kinds. An error counts as unreadable = D.
    if (loaded.isLoading && !loaded.hasValue && !loaded.hasError) {
      return SettingsSection(
        key: const ValueKey('haKindSection'),
        title: t.levelKindTitle,
        children: [SettingsRow(title: t.levelKindLoading)],
      );
    }
    final kinds = loaded.value ?? const HaKindLevels.broken();
    Future<void> set(HaKind k, SecurityLevel? l) async {
      // Fresh from the store: never write over a stale copy.
      final store = ref.read(haStoreProvider);
      await store.saveKindLevels((await store.kindLevels()).withLevel(k, l));
      ref.invalidate(haKindLevelsProvider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.s,
      children: [
        SettingsSection(
          key: const ValueKey('haKindSection'),
          title: t.levelKindTitle,
          children: [
            for (final k in HaKind.values) ...[
              SettingsRow(title: _name(t, k)),
              _picker(context, k, kinds, set),
            ],
          ],
        ),
        InfoBox(t.levelKindIntro),
      ],
    );
  }

  Widget _picker(
    BuildContext context,
    HaKind k,
    HaKindLevels kinds,
    Future<void> Function(HaKind, SecurityLevel?) set,
  ) {
    final t = context.l10n;
    final chosen = kinds.levelOf(k);
    final base = _default(k);
    final varies = k == HaKind.scene || k == HaKind.cover;
    return SecurityLevelPicker(
      idKey: 'kind_${k.key}',
      name: _name(t, k),
      level: chosen ?? base,
      isDefault: chosen == null,
      // The default of scenes and blinds is not one level: do not claim it.
      summary: chosen == null && varies
          ? (k == HaKind.scene ? t.levelSummaryScene : t.levelKindSummaryCover)
          : null,
      warnLevels: k == HaKind.cover || k == HaKind.switchKind
          ? const {SecurityLevel.a, SecurityLevel.b}
          : const {},
      warnMessage: k == HaKind.cover
          ? t.levelWarnKindCover
          : t.levelWarnKindSwitch,
      onChanged: (l) => unawaited(set(k, l)),
    );
  }
}
