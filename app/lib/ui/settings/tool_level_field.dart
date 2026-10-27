import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart' show RiskPolicy;

import '../../l10n/l10n.dart';
import 'security_level_picker.dart';

/// Levels of a tool with [risk] that need the hint before they are set
/// (WP154): outside effect warns at A to C, a [sensitive] tool (personal
/// content) at A and B, all others never.
Set<SecurityLevel> warnLevelsFor(RiskLevel risk, {bool sensitive = false}) {
  if (risk == RiskLevel.external) {
    return const {SecurityLevel.a, SecurityLevel.b, SecurityLevel.c};
  }
  if (sensitive) return const {SecurityLevel.a, SecurityLevel.b};
  return const {};
}

/// The security level picker (A–D) of a user-defined tool (MCP, HTTP;
/// WP160). Same storage and default as the built-in tools: the default is
/// the one of [risk] (`RiskPolicy.defaultLevelFor`), [stored] is the text in
/// `ToolPrefs.levels` (`null` = default, anything but `a`..`d` = D).
///
/// A chosen level is written as chosen, also when it equals today's default
/// (the picker itself ignores a tap on the level that already counts): the
/// default of these tools moves with their risk (switch „ohne Nachfrage“,
/// annotations), a level the user chose must not loosen with it.
class ToolLevelField extends StatelessWidget {
  /// Creates the field.
  const ToolLevelField({
    required this.toolName,
    required this.risk,
    required this.stored,
    required this.onChanged,
    this.sensitive = false,
    super.key,
  });

  /// Registry name of the tool (`<server>__<tool>`, `http__<name>`).
  final String toolName;

  /// The risk the tool runs with; its default level follows it.
  final RiskLevel risk;

  /// Whether the tool reads or changes personal content.
  final bool sensitive;

  /// The stored level text, see `ToolPrefs.levelOf`.
  final String? stored;

  /// Called with the chosen level, `null` = default again.
  final void Function(SecurityLevel? level) onChanged;

  @override
  Widget build(BuildContext context) => SecurityLevelPicker(
    idKey: toolName,
    name: toolName,
    level: SecurityLevel.effective(stored, RiskPolicy.defaultLevelFor(risk)),
    isDefault: stored == null,
    warnLevels: warnLevelsFor(risk, sensitive: sensitive),
    warnMessage: risk == RiskLevel.external
        ? context.l10n.levelWarnToolMessage
        : context.l10n.levelWarnPersonalMessage,
    onChanged: onChanged,
  );
}
