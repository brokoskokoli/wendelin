import 'package:wendelin_core/wendelin_core.dart';

import '../protocol.dart';

/// Base risk level from the annotations, following the MCP defaults
/// (2025-11-25: a missing `destructiveHint` counts as `true`):
/// `readOnlyHint: true` → `read`; otherwise only an explicit
/// `destructiveHint: false` → `write`; everything else (also no
/// annotations at all) → `external`. [confirmAll] makes it `external`.
RiskLevel mcpBaseRisk(
  McpToolAnnotations annotations, {
  bool confirmAll = false,
}) {
  if (confirmAll) return RiskLevel.external;
  if (annotations.readOnlyHint == true) return RiskLevel.read;
  if (annotations.destructiveHint == false) return RiskLevel.write;
  return RiskLevel.external;
}

/// Effective risk level of an MCP tool.
///
/// MCP tools have no undo, so a tool with base level `write` is still
/// confirmed (`external`) unless the user allowed it to run on its own
/// ([autoRun]); [autoRun] only acts on base `write` and never under
/// [confirmAll]. A user [override] only raises the result, never lowers it
/// (K8 b).
RiskLevel mcpRisk(
  McpToolAnnotations annotations, {
  bool confirmAll = false,
  bool autoRun = false,
  RiskLevel? override,
}) {
  final base = mcpBaseRisk(annotations, confirmAll: confirmAll);
  final effective = base == RiskLevel.write && !autoRun
      ? RiskLevel.external
      : base;
  if (override == null || override.index <= effective.index) return effective;
  return override;
}
