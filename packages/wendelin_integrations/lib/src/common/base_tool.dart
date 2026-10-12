import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import 'port_exception.dart';
import 'tool_args.dart';

/// Common base of the built-in tools.
///
/// [execute] turns [InvalidArgumentsException] and [PortException] into
/// error outcomes; other exceptions propagate to the tool runtime, which
/// reports them as errors as well. [describeForConfirmation] never throws.
abstract base class IntegrationTool implements Tool {
  /// Const base constructor.
  const IntegrationTool();

  /// The tool logic with typed [args].
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx);

  /// German confirmation text for valid [args].
  String describe(ToolArgs args);

  /// Confirmation text when [args] cannot be read.
  String get fallbackDescription;

  @override
  Future<ToolOutcome> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    try {
      return await run(ToolArgs(args), ctx);
    } on InvalidArgumentsException catch (e) {
      return ToolOutcome.error(
        'Ungültige Argumente: ${e.message}',
        summary: 'Ungültige Angaben',
      );
    } on PortException catch (e) {
      return ToolOutcome.error(e.message, summary: e.message);
    }
  }

  @override
  String describeForConfirmation(Map<String, Object?> args) {
    try {
      return describe(ToolArgs(args));
    } on InvalidArgumentsException {
      return fallbackDescription;
    }
  }
}

/// A successful outcome whose content is [data] as compact JSON.
ToolOutcome jsonOutcome(Object? data, {String? summary, UndoAction? undo}) =>
    ToolOutcome.text(jsonEncode(data), summary: summary, undo: undo);

/// Shortens [text] to at most [maxChars] characters and marks the cut.
({String text, bool truncated}) truncateText(String text, int maxChars) {
  if (text.length <= maxChars) return (text: text, truncated: false);
  return (
    text:
        '${text.substring(0, maxChars)}\n[… gekürzt, '
        '${text.length - maxChars} Zeichen ausgelassen]',
    truncated: true,
  );
}

/// Shortens [text] for a one-line UI summary.
String ellipsize(String text, int maxChars) {
  final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return single.length <= maxChars
      ? single
      : '${single.substring(0, maxChars - 1)}…';
}
