import 'package:meta/meta.dart';

/// How the model may use tools in a request.
@immutable
sealed class ToolChoice {
  const ToolChoice();

  /// The model decides (default).
  static const ToolChoice auto = ToolChoiceAuto();

  /// The model must not call tools.
  static const ToolChoice none = ToolChoiceNone();

  /// The model must call at least one tool.
  static const ToolChoice required = ToolChoiceRequired();

  /// The model must call the tool [name].
  const factory ToolChoice.tool(String name) = ToolChoiceTool;
}

/// See [ToolChoice.auto].
final class ToolChoiceAuto extends ToolChoice {
  /// Use [ToolChoice.auto].
  const ToolChoiceAuto();

  @override
  bool operator ==(Object other) => other is ToolChoiceAuto;

  @override
  int get hashCode => (ToolChoiceAuto).hashCode;

  @override
  String toString() => 'ToolChoice.auto';
}

/// See [ToolChoice.none].
final class ToolChoiceNone extends ToolChoice {
  /// Use [ToolChoice.none].
  const ToolChoiceNone();

  @override
  bool operator ==(Object other) => other is ToolChoiceNone;

  @override
  int get hashCode => (ToolChoiceNone).hashCode;

  @override
  String toString() => 'ToolChoice.none';
}

/// See [ToolChoice.required].
final class ToolChoiceRequired extends ToolChoice {
  /// Use [ToolChoice.required].
  const ToolChoiceRequired();

  @override
  bool operator ==(Object other) => other is ToolChoiceRequired;

  @override
  int get hashCode => (ToolChoiceRequired).hashCode;

  @override
  String toString() => 'ToolChoice.required';
}

/// Forces a specific tool, see [ToolChoice.tool].
final class ToolChoiceTool extends ToolChoice {
  /// Forces the tool [name].
  const ToolChoiceTool(this.name);

  /// Name of the forced tool.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ToolChoiceTool && other.name == name;

  @override
  int get hashCode => Object.hash(ToolChoiceTool, name);

  @override
  String toString() => 'ToolChoice.tool($name)';
}
