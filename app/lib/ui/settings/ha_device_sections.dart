import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'security_level_picker.dart';
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

/// The devices of one room with the switch "to the model" and, for
/// devices that can be controlled, the collapsed „Details“ row with the
/// security level (WP154).
class HaAreaSection extends StatelessWidget {
  /// Creates the section.
  const HaAreaSection({
    required this.title,
    required this.entities,
    required this.approved,
    required this.choiceOf,
    required this.onToggle,
    required this.onLevel,
    super.key,
  });

  /// Room name.
  final String title;

  /// Devices in the room.
  final List<HaEntity> entities;

  /// Ids of the approved devices.
  final Set<String> approved;

  /// The device with the user's choice (level, legacy flags) applied.
  final HaEntity Function(HaEntity entity) choiceOf;

  /// Approves or revokes a device.
  final void Function(HaEntity entity, bool on) onToggle;

  /// Sets the level of a device, `null` = default.
  final void Function(HaEntity entity, SecurityLevel? level) onLevel;

  /// Domains whose A/B level gets the hint (lock, alarm, gate, door).
  static bool dangerous(HaEntity e) =>
      e.domain == 'lock' ||
      e.domain == 'alarm_control_panel' ||
      e.domain == 'cover';

  /// The default level shown for [e] (without the legacy flags). Scenes are
  /// checked at every call; B is their usual default.
  static SecurityLevel defaultOf(HaEntity e) => haDefaultLevel(
    HaEntity(entityId: e.entityId, name: e.name, deviceClass: e.deviceClass),
    liveClass: e.deviceClass,
    scene: HaSceneKind.safe,
  );

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: title,
    children: [
      for (final e in entities) ...[
        SettingsRow(
          title: e.name,
          detail: e.entityId,
          trailing: WSwitch(
            key: ValueKey('haEntity_${e.entityId}'),
            value: approved.contains(e.entityId),
            semanticLabel: e.name,
            onChanged: (on) => onToggle(e, on),
          ),
        ),
        if (haRiskForDomain(e.domain) != null && approved.contains(e.entityId))
          _picker(context, e),
      ],
    ],
  );

  Widget _picker(BuildContext context, HaEntity e) {
    final chosen = choiceOf(e);
    final level = haEffectiveLevel(
      chosen,
      liveClass: e.deviceClass,
      scene: HaSceneKind.safe,
    );
    final isDefault =
        chosen.level == null &&
        !chosen.alwaysConfirm &&
        !chosen.noConfirm &&
        level == defaultOf(e);
    return SecurityLevelPicker(
      idKey: e.entityId,
      name: e.name,
      level: level,
      isDefault: isDefault,
      warnLevels: dangerous(e)
          ? const {SecurityLevel.a, SecurityLevel.b}
          : const {},
      warnMessage: context.l10n.levelWarnDeviceMessage,
      onChanged: (l) => onLevel(e, l),
    );
  }
}
