import 'package:wendelin_core/wendelin_core.dart';

import '../protocol.dart';

/// Risk level of an MCP tool.
///
/// Default from the annotations: `destructiveHint: true` → `external`,
/// otherwise `readOnlyHint: true` → `read`, otherwise `write`. The
/// annotations are claims of the server and not trustworthy, so a
/// contradiction (read-only *and* destructive) resolves to the stricter
/// level. [confirmAll] makes every tool `external`. A user [override] only
/// raises the level, never lowers it (K8 b).
RiskLevel mcpRisk(
  McpToolAnnotations annotations, {
  bool confirmAll = false,
  RiskLevel? override,
}) {
  final base = confirmAll || annotations.destructiveHint == true
      ? RiskLevel.external
      : annotations.readOnlyHint == true
      ? RiskLevel.read
      : RiskLevel.write;
  if (override == null || override.index <= base.index) return base;
  return override;
}
