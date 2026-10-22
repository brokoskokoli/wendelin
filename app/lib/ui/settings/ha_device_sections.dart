import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Devices that Home Assistant no longer lists (WP135 A), with a button to
/// remove each from the approved ones.
class HaGoneSection extends StatelessWidget {
  /// Creates the section.
  const HaGoneSection({required this.gone, required this.onRemove, super.key});

  /// The approved devices that are missing in Home Assistant.
  final List<HaEntity> gone;

  /// Called when the user removes [HaEntity] from the approved ones.
  final void Function(HaEntity entity) onRemove;

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: context.l10n.haGone,
    children: [
      for (final e in gone)
        SettingsRow(
          title: e.name,
          detail: e.entityId,
          trailing: TextButton(
            key: ValueKey('haRemove_${e.entityId}'),
            onPressed: () => onRemove(e),
            child: Text(context.l10n.haRemoveGone),
          ),
        ),
    ],
  );
}

/// The devices of one room with the switch "to the model" and, for switches,
/// "always confirm".
class HaAreaSection extends StatelessWidget {
  /// Creates the section.
  const HaAreaSection({
    required this.title,
    required this.entities,
    required this.approved,
    required this.alwaysConfirm,
    required this.onToggle,
    required this.onToggleConfirm,
    super.key,
  });

  /// Room name.
  final String title;

  /// Devices in the room.
  final List<HaEntity> entities;

  /// Ids of the approved devices.
  final Set<String> approved;

  /// Ids of the devices with "always confirm".
  final Set<String> alwaysConfirm;

  /// Approves or revokes a device.
  final void Function(HaEntity entity, bool on) onToggle;

  /// Sets "always confirm" of a device.
  final void Function(HaEntity entity, bool on) onToggleConfirm;

  static bool _secure(HaEntity e) =>
      haRiskForDomain(e.domain) == RiskLevel.external;

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: title,
    children: [
      for (final e in entities) ...[
        SettingsRow(
          title: e.name,
          detail: _secure(e)
              ? context.l10n.haEntityAlwaysAsks(e.entityId)
              : e.entityId,
          trailing: WSwitch(
            key: ValueKey('haEntity_${e.entityId}'),
            value: approved.contains(e.entityId),
            semanticLabel: e.name,
            onChanged: (on) => onToggle(e, on),
          ),
        ),
        if (e.domain == 'switch' && approved.contains(e.entityId))
          SettingsRow(
            title: context.l10n.haAlwaysConfirm,
            detail: context.l10n.haAlwaysConfirmHelp,
            trailing: WSwitch(
              key: ValueKey('haConfirm_${e.entityId}'),
              value: alwaysConfirm.contains(e.entityId),
              semanticLabel: context.l10n.haAlwaysConfirmSemantics(
                e.name,
                context.l10n.haAlwaysConfirm,
              ),
              onChanged: (on) => onToggleConfirm(e, on),
            ),
          ),
      ],
    ],
  );
}
