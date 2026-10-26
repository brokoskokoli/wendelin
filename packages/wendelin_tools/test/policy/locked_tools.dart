import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// A [FakeTool] that also declares a standard level ([DefaultLevelTool]).
final class LevelFake implements Tool, DefaultLevelTool {
  /// Creates the tool with [defaultLevel].
  LevelFake(this.inner, this.defaultLevel);

  /// The wrapped fake (calls, handler).
  final FakeTool inner;

  @override
  final SecurityLevel defaultLevel;

  @override
  String get name => inner.name;
  @override
  String get description => inner.description;
  @override
  Map<String, Object?> get inputSchema => inner.inputSchema;
  @override
  RiskLevel get risk => inner.risk;
  @override
  Future<ToolOutcome> execute(Map<String, Object?> args, ToolContext ctx) =>
      inner.execute(args, ctx);
  @override
  String describeForConfirmation(Map<String, Object?> args) =>
      inner.describeForConfirmation(args);
}

/// A [FakeTool] that decides per device itself ([LevelPerDeviceTool]).
final class PerDeviceFake implements Tool, LevelPerDeviceTool {
  /// Creates the tool.
  PerDeviceFake(this.inner);

  /// The wrapped fake (calls, handler).
  final FakeTool inner;

  @override
  String get name => inner.name;
  @override
  String get description => inner.description;
  @override
  Map<String, Object?> get inputSchema => inner.inputSchema;
  @override
  RiskLevel get risk => inner.risk;
  @override
  Future<ToolOutcome> execute(Map<String, Object?> args, ToolContext ctx) =>
      inner.execute(args, ctx);
  @override
  String describeForConfirmation(Map<String, Object?> args) =>
      inner.describeForConfirmation(args);
}
