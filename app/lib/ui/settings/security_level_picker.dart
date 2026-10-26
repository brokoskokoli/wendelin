import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Texts of the level [l] (WP154).
String levelHelp(AppLocalizations t, SecurityLevel l) => switch (l) {
  SecurityLevel.a => t.levelHelpA,
  SecurityLevel.b => t.levelHelpB,
  SecurityLevel.c => t.levelHelpC,
  SecurityLevel.d => t.levelHelpD,
};

/// Collapsed „Details“ row of a device or tool: shows the level as a short
/// text, unfolds to the choice A–D with one explanation line each
/// (smaller and indented against the normal rows). Used for Home Assistant
/// devices and for tools.
///
/// [level] is the level that counts, [isDefault] whether it is the default.
/// [onChanged] gets the chosen level, `null` = restore the default. Picking
/// a level of [warnLevels] first asks once with [warnMessage].
class SecurityLevelPicker extends StatefulWidget {
  /// Creates the picker.
  const SecurityLevelPicker({
    required this.idKey,
    required this.name,
    required this.level,
    required this.isDefault,
    required this.onChanged,
    this.warnLevels = const {},
    this.warnMessage = '',
    this.summary,
    super.key,
  });

  /// Suffix of the widget keys (`levelDetails_<idKey>`, `level_<idKey>_a`).
  final String idKey;

  /// Name of the device or tool (screen reader).
  final String name;

  /// The level that counts.
  final SecurityLevel level;

  /// Whether [level] is the default.
  final bool isDefault;

  /// Called with the new level, `null` for „Standard wiederherstellen“.
  final void Function(SecurityLevel? level) onChanged;

  /// Levels that need the hint before they are set.
  final Set<SecurityLevel> warnLevels;

  /// Text of the hint.
  final String warnMessage;

  /// Replaces „Stufe X · Standard“ in the header and leaves the choice
  /// unmarked (a scene's level depends on its members at every call).
  final String? summary;

  @override
  State<SecurityLevelPicker> createState() => _SecurityLevelPickerState();
}

class _SecurityLevelPickerState extends State<SecurityLevelPicker> {
  bool _open = false;

  Future<void> _pick(SecurityLevel l) async {
    if (widget.summary == null && l == widget.level) return;
    if (widget.warnLevels.contains(l)) {
      final ok = await confirm(
        context,
        title: context.l10n.levelWarnTitle,
        message: widget.warnMessage,
        yes: context.l10n.levelWarnConfirm,
      );
      if (!ok) return;
    }
    widget.onChanged(l);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: WSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          if (_open) ...[
            for (final l in SecurityLevel.values) _option(context, l),
            if (!widget.isDefault)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('levelRestore_${widget.idKey}'),
                  onPressed: () => widget.onChanged(null),
                  child: Text(context.l10n.levelRestore, style: WText.caption),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final t = context.l10n;
    final state = widget.isDefault ? t.levelStateDefault : t.levelStateChanged;
    return Semantics(
      button: true,
      expanded: _open,
      label: '${widget.name}: ${t.levelDetails}',
      child: InkWell(
        key: ValueKey('levelDetails_${widget.idKey}'),
        onTap: () => setState(() => _open = !_open),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: WSize.touchMin),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WSpace.l,
              vertical: WSpace.s,
            ),
            child: Row(
              spacing: WSpace.s,
              children: [
                Icon(
                  _open ? Icons.expand_less : Icons.chevron_right,
                  size: WSize.iconDetail,
                  color: WColors.textMuted,
                ),
                Expanded(
                  child: Text(
                    '${t.levelDetails} · '
                    '${widget.summary ?? t.levelSummary(widget.level.name.toUpperCase(), state)}',
                    style: WText.caption,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(BuildContext context, SecurityLevel l) {
    final t = context.l10n;
    final on = widget.summary == null && l == widget.level;
    return Semantics(
      button: true,
      selected: on,
      label: t.levelSemantics(widget.name, l.name.toUpperCase()),
      child: InkWell(
        key: ValueKey('level_${widget.idKey}_${l.name}'),
        onTap: () => _pick(l),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: WSize.touchMin),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WSpace.l,
              vertical: WSpace.xs,
            ),
            child: Row(
              spacing: WSpace.s,
              children: [
                Icon(
                  on
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: WSize.iconDetail,
                  color: on ? WColors.accent : WColors.textMuted,
                ),
                Expanded(
                  child: Text(
                    '${l.name.toUpperCase()} · ${levelHelp(t, l)}',
                    style: WText.caption,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
