import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../../../di/provider_setup.dart';
import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../provider_setup_screen.dart' show ConnectionStatus;
import '../settings_page.dart';

/// [models] with the recommended ones first (in the order of [recs]), the
/// rest in its original order. Free choice stays: nothing is dropped.
List<ModelInfo> orderModels(
  List<ModelInfo> models,
  List<ModelRecommendation> recs,
) {
  final out = <ModelInfo>[];
  for (final r in recs) {
    out.addAll(models.where((m) => m.id == r.modelId));
  }
  final rec = {for (final r in recs) r.modelId};
  return [...out, ...models.where((m) => !rec.contains(m.id))];
}

/// The model to preselect after loading [models]: [current] if listed, else
/// the first listed recommendation, else the first model; `null` if empty.
String? preselectModel(
  String current,
  List<ModelInfo> models,
  List<ModelRecommendation> recs,
) {
  final ids = {for (final m in models) m.id};
  if (ids.isEmpty || ids.contains(current)) return null;
  for (final r in recs) {
    if (ids.contains(r.modelId)) return r.modelId;
  }
  return models.first.id;
}

String _reason(AppLocalizations l, ModelRecommendation r) {
  final p50 = NumberFormat('0.0', l.localeName).format(r.p50Seconds);
  final text = l.providerModelRecommendedReason(
    '${r.hits}',
    '${r.runs}',
    p50,
    r.measured,
  );
  return r.weakerThanTee ? '$text ${l.providerModelRecommendedWeaker}' : text;
}

/// Step 3: the models of the provider and a probe of the chosen one.
List<Widget> modelStep({
  required AppLocalizations l,
  required SetupTestResult? connection,
  required List<ModelInfo> models,
  required List<ModelRecommendation> recommendations,
  required TextEditingController model,
  required Set<String> noGpuEvidence,
  required Widget? failure,
  required bool busy,
  required VoidCallback onChanged,
  required void Function(String id) onPick,
  required VoidCallback onProbe,
}) => [
  if (connection case final c?) ConnectionStatus(c),
  if (models.isNotEmpty)
    SettingsSection(
      title: l.providerSetupProviderSetupModels,
      children: [
        for (final m in orderModels(models, recommendations).take(50))
          _modelRow(l, m, recommendations, noGpuEvidence, model, onPick),
      ],
    ),
  TextField(
    controller: model,
    style: WText.body,
    onChanged: (_) => onChanged(),
    decoration: InputDecoration(labelText: l.providerSetupProviderSetupModelId),
  ),
  ?failure,
  PrimaryButton(
    busy ? l.bringChecking : l.providerSetupProviderSetupProbeModel,
    onPressed: busy || model.text.trim().isEmpty ? null : onProbe,
  ),
];

Widget _modelRow(
  AppLocalizations l,
  ModelInfo m,
  List<ModelRecommendation> recs,
  Set<String> noGpuEvidence,
  TextEditingController model,
  void Function(String id) onPick,
) {
  final rec = recs.where((r) => r.modelId == m.id).firstOrNull;
  final details = [
    ?(rec == null ? null : _reason(l, rec)),
    ?(noGpuEvidence.contains(m.id) ? l.gpuNoEvidenceHint : null),
  ];
  return SettingsRow(
    key: rec == null ? null : ValueKey('recommended-${m.id}'),
    title: m.displayName,
    mono: true,
    detail: details.isEmpty ? null : details.join('\n'),
    onTap: () => onPick(m.id),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: WSpace.s,
      children: [
        if (rec != null) MetaChip(l.providerModelRecommendedBadge),
        if (model.text == m.id)
          CheckStatusIcon(CheckStatus.ok, semanticLabel: l.selected),
      ],
    ),
  );
}
