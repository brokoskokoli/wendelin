import 'dart:async';

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

/// Marker for tools whose successful result only contains data the user or
/// the app produced itself (a confirmation of what was just set or saved).
/// Fail-closed (WP41): every other result – tools without this marker,
/// unknown tools and every error text – counts as untrusted, i.e. possibly
/// written by third parties. Once the conversation contains such a result,
/// invisible channels like the `<spoken>` block are switched off, because
/// the user cannot check what would be spoken.
abstract interface class TrustedContentSource {}

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
  /// „Termin ‚Tauchen‘ Do 10:00–11:00 löschen“. Synchronous fallback; tools
  /// that need to look something up implement [ConfirmationPreparer].
  String describeForConfirmation(Map<String, Object?> args);
}

/// Optional capability of a [Tool]: builds the confirmation text
/// asynchronously with the [ToolContext], e.g. to look up the title and time
/// of the event that will be deleted. Runtimes call it through
/// [ToolConfirmation.confirmationText], which falls back to
/// [Tool.describeForConfirmation].
abstract interface class ConfirmationPreparer {
  /// German one-liner for the confirmation card. Must not change anything.
  Future<String> prepareConfirmation(
    Map<String, Object?> args,
    ToolContext ctx,
  );
}

/// Confirmation text of any [Tool].
extension ToolConfirmation on Tool {
  /// Longest time [confirmationText] waits for the preparer.
  static const defaultTimeout = Duration(seconds: 5);

  /// The text for the confirmation card: [ConfirmationPreparer.
  /// prepareConfirmation] if the tool implements it, else
  /// [Tool.describeForConfirmation]. If preparing fails, takes longer than
  /// [timeout] or the run is cancelled, the synchronous text is used – the
  /// user is asked either way.
  Future<String> confirmationText(
    Map<String, Object?> args,
    ToolContext ctx, {
    Duration timeout = defaultTimeout,
  }) async {
    final self = this;
    if (self is! ConfirmationPreparer) return describeForConfirmation(args);
    final preparer = self as ConfirmationPreparer;
    try {
      final text = await Future.any([
        preparer.prepareConfirmation(args, ctx).timeout(timeout),
        ctx.cancel.whenCancelled.then<String>(
          (_) => throw TimeoutException('abgebrochen'),
        ),
      ]);
      if (text.trim().isNotEmpty) return text;
    } on Object {
      // Fallback below: a failed lookup must not block the question.
    }
    return describeForConfirmation(args);
  }
}

/// Conversion of a [Tool] to the spec sent to the model.
extension ToolToSpec on Tool {
  /// The [ToolSpec] describing this tool.
  ToolSpec get spec =>
      ToolSpec(name: name, description: description, inputSchema: inputSchema);
}
