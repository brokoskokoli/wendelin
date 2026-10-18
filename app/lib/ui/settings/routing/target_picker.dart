import 'package:flutter/material.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../../l10n/l10n.dart';
import '../../design/design.dart';

/// Profile and model of a routing target: a dropdown of the profiles (with
/// their privacy glyph) and the model id (prefilled with the profile's
/// default model).
class TargetPicker extends StatefulWidget {
  /// Creates the picker.
  const TargetPicker({
    super.key,
    required this.profiles,
    required this.value,
    required this.onChanged,
  });

  /// Profiles to choose from.
  final List<ProviderProfile> profiles;

  /// Current target (its profile may be gone).
  final RouteTarget value;

  /// New target.
  final ValueChanged<RouteTarget> onChanged;

  @override
  State<TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<TargetPicker> {
  late final _model = TextEditingController(text: widget.value.modelId);

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final known = widget.profiles.any((p) => p.id == widget.value.profileId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.m,
      children: [
        DropdownButtonFormField<String>(
          initialValue: known ? widget.value.profileId : null,
          isExpanded: true,
          dropdownColor: WColors.surfaceRaised,
          decoration: InputDecoration(
            labelText: context.l10n.targetPickerProfile,
            errorText: known
                ? null
                : context.l10n.targetPickerProfileGone(widget.value.profileId),
          ),
          items: [
            for (final p in widget.profiles)
              DropdownMenuItem(
                value: p.id,
                child: Row(
                  spacing: WSpace.s,
                  children: [
                    Glyph(
                      GlyphShape.forPrivacy(p.privacy),
                      color: WColors.textMuted,
                    ),
                    Flexible(
                      child: Text(
                        '${p.name} · ${p.privacy.labelOf(context.l10n)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (id) {
            final p = widget.profiles.where((p) => p.id == id).firstOrNull;
            if (p == null) return;
            _model.text = p.defaultModel;
            widget.onChanged(
              RouteTarget(profileId: p.id, modelId: p.defaultModel),
            );
          },
        ),
        TextField(
          controller: _model,
          style: WText.mono.copyWith(color: WColors.text),
          decoration: InputDecoration(labelText: context.l10n.attLogModel),
          onChanged: (m) => widget.onChanged(
            RouteTarget(profileId: widget.value.profileId, modelId: m.trim()),
          ),
        ),
      ],
    );
  }
}

/// Asks for a target (profile + model); `null` if cancelled.
Future<RouteTarget?> pickTarget(
  BuildContext context, {
  required String title,
  required List<ProviderProfile> profiles,
  required RouteTarget initial,
}) => showDialog<RouteTarget>(
  context: context,
  builder: (context) {
    var target = initial;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: WColors.surface,
        title: Text(title, style: WText.label),
        content: TargetPicker(
          profiles: profiles,
          value: target,
          onChanged: (t) => setState(() => target = t),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed:
                target.modelId.isEmpty ||
                    !profiles.any((p) => p.id == target.profileId)
                ? null
                : () => Navigator.of(context).pop(target),
            child: Text(context.l10n.targetPickerApply),
          ),
        ],
      ),
    );
  },
);
