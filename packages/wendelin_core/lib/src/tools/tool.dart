import '../messages/tool_spec.dart';
import 'tool_context.dart';
import 'tool_outcome.dart';

/// Risk level of a tool; decides whether the user must confirm.
enum RiskLevel {
  /// Reads data; runs without asking.
  read,

  /// Changes local data; runs without asking, offers undo for 10 s.
  write,

  /// Has effects outside the app (SMS, delete, …); always confirmed.
  external,
}

/// Mobile platform an integration supports.
enum AppPlatform {
  /// Android.
  android,

  /// iOS.
  ios,
}

final _toolNamePattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

/// A single action the model can call.
abstract interface class Tool {
  /// Whether [name] is a valid tool name: 1–64 characters out of letters,
  /// digits, `_` and `-` (no dots or spaces; some APIs reject them). By
  /// convention names follow `integration__action`.
  static bool isValidToolName(String name) => _toolNamePattern.hasMatch(name);

  /// Unique name, `integration__action` (see [Tool.isValidToolName]).
  String get name;

  /// Short, precise description for the model.
  String get description;

  /// JSON Schema of the arguments object.
  Map<String, Object?> get inputSchema;

  /// Risk level (default policy: see [RiskLevel]).
  RiskLevel get risk;

  /// Runs the tool with already validated [args].
  ///
  /// Expected failures should be returned as `ToolOutcome.error`; thrown
  /// exceptions are turned into error outcomes by the tool runtime.
  Future<ToolOutcome> execute(Map<String, Object?> args, ToolContext ctx);

  /// German one-liner for the confirmation card, e.g.
  /// „Termin ‚Tauchen‘ Do 10:00–11:00 löschen“.
  String describeForConfirmation(Map<String, Object?> args);
}

/// Conversion of a [Tool] to the spec sent to the model.
extension ToolToSpec on Tool {
  /// The [ToolSpec] describing this tool.
  ToolSpec get spec =>
      ToolSpec(name: name, description: description, inputSchema: inputSchema);
}
