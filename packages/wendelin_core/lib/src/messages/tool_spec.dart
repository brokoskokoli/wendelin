import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Description of a tool as sent to the model.
@immutable
final class ToolSpec {
  /// Creates a tool spec.
  const ToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  /// Tool name (`integration__action`, see `isValidToolName`).
  final String name;

  /// Short, precise description for the model.
  final String description;

  /// JSON Schema of the arguments object.
  final Map<String, Object?> inputSchema;

  @override
  bool operator ==(Object other) =>
      other is ToolSpec &&
      other.name == name &&
      other.description == description &&
      const DeepCollectionEquality().equals(other.inputSchema, inputSchema);

  @override
  int get hashCode => Object.hash(
    name,
    description,
    const DeepCollectionEquality().hash(inputSchema),
  );

  @override
  String toString() => 'ToolSpec($name)';
}
