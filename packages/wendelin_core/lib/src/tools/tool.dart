import 'dart:async';

import '../messages/content_block.dart';
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

/// Marker for tools whose successful result does not count as foreign
/// content (ADR 0023): data the user or the app produced itself, or from a
/// source the maintainer classified as safe (notes, lists, calendar,
/// contacts, home automation, weather, location, alarms, memory, media).
/// Fail-closed (WP41, WP157): every other result – tools without this
/// marker, unknown tools and every error text – counts as foreign, i.e.
/// possibly written by third parties. Once the conversation contains such a
/// result, invisible channels like the `<spoken>` block are switched off and
/// tools with a network target ([NoNetworkTarget]) ask first.
abstract interface class TrustedContentSource {}

/// Tools whose trust depends on a setting of the user (HTTP tool, MCP
/// server: the tick „Kann unsichere Inhalte enthalten“, default on).
/// [mayContainUntrustedContent] `false` makes a successful result count like
/// one of a [TrustedContentSource]; errors never do.
abstract interface class ContentTrustAware {
  /// Whether the results may contain third-party text (default: yes).
  bool get mayContainUntrustedContent;
}

/// Tools whose trust depends on the content of one result (meta tool
/// `tools__search`: its result only repeats descriptions of other tools).
/// Takes precedence over the other markers; errors never count as trusted.
abstract interface class ResultTrustAware {
  /// Whether the successful result [content] is free of third-party text.
  /// Fail-closed: anything unreadable or unknown answers `false`.
  bool isResultTrusted(List<ContentBlock> content);
}

/// Marker for tools that **never** carry call arguments to a free network
/// target: they act on the device, on a fixed service of the app or on the
/// user's own accounts. Fail-closed (WP157, ADR 0023): a tool without this
/// marker counts as having a network target (HTTP tools, MCP, web search
/// and fetch, and anything new), so after foreign content the call is
/// confirmed first. Every built-in tool has to carry it or sit on the
/// explicit network list (checked over the whole catalog).
abstract interface class NoNetworkTarget {}

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

/// Optional capability of a [Tool]: tells what the audit log may keep of a
/// call. Tools whose arguments hold private text (message bodies) return a
/// reduced JSON (e.g. only the recipient) instead of the raw arguments.
/// Runtimes call it through [ToolAuditArguments.auditArguments].
abstract interface class AuditArgumentsRedactor {
  /// The JSON object stored in the audit log instead of the raw arguments.
  /// Must not contain private texts.
  Future<String> redactedArguments(Map<String, Object?> args, ToolContext ctx);
}

/// Audit text of any [Tool].
extension ToolAuditArguments on Tool {
  /// The arguments for the audit log: [raw] unless the tool implements
  /// [AuditArgumentsRedactor]. If redacting fails, only `{}` is stored
  /// (never the raw arguments of such a tool).
  Future<String> auditArguments(
    String raw,
    Map<String, Object?>? args,
    ToolContext ctx,
  ) async {
    final self = this;
    if (self is! AuditArgumentsRedactor) return raw;
    final redactor = self as AuditArgumentsRedactor;
    try {
      return await redactor.redactedArguments(args ?? const {}, ctx);
    } on Object {
      return '{}';
    }
  }
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
