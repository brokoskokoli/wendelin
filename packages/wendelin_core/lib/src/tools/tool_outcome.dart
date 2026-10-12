import 'package:meta/meta.dart';

import '../messages/content_block.dart';

/// Reverts the effect of a `write` tool (e.g. deletes the created event).
@immutable
final class UndoAction {
  /// Creates an undo action with a UI [label] such as „Termin entfernen“.
  const UndoAction({required this.label, required this.run});

  /// Text for the undo button.
  final String label;

  /// Performs the undo.
  final Future<void> Function() run;

  /// Runs the undo; same as calling [run].
  Future<void> call() => run();
}

/// What a tool returns: content for the model plus UI extras.
///
/// Richer than a bare `ToolResultBlock`: [summary] feeds the tool card and
/// [undo] the undo button; only [content] and [isError] reach the model.
@immutable
final class ToolOutcome {
  /// Creates an outcome; [content] is copied unmodifiable.
  ToolOutcome({
    required List<ContentBlock> content,
    this.isError = false,
    this.undo,
    this.summary,
  }) : content = List.unmodifiable(content);

  /// Successful outcome with a single text block.
  factory ToolOutcome.text(String text, {String? summary, UndoAction? undo}) =>
      ToolOutcome(content: [TextBlock(text)], summary: summary, undo: undo);

  /// Failed outcome with a readable [message] for the model (no stack
  /// traces).
  factory ToolOutcome.error(String message, {String? summary}) => ToolOutcome(
    content: [TextBlock(message)],
    isError: true,
    summary: summary,
  );

  /// Content for the model.
  final List<ContentBlock> content;

  /// Whether the tool failed.
  final bool isError;

  /// Optional undo for `write` tools.
  final UndoAction? undo;

  /// Short UI text, e.g. „Termin angelegt: Tauchen, Di 10:00“.
  final String? summary;

  /// Concatenated text of all [TextBlock]s in [content].
  String get text => content.whereType<TextBlock>().map((b) => b.text).join();

  /// The block sent back to the model for the call [callId].
  ToolResultBlock toResultBlock(String callId) =>
      ToolResultBlock(callId: callId, content: content, isError: isError);

  @override
  String toString() =>
      'ToolOutcome(isError: $isError, summary: $summary, $content)';
}
