import 'package:meta/meta.dart';

import '../messages/content_block.dart';
import 'fixed_confirmation.dart';

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
    this.fixed,
    this.endsRun = false,
  }) : content = List.unmodifiable(content);

  /// Successful outcome with a single text block.
  factory ToolOutcome.text(
    String text, {
    String? summary,
    UndoAction? undo,
    ConfirmationSentence? fixed,
  }) => ToolOutcome(
    content: [TextBlock(text)],
    summary: summary,
    undo: undo,
    fixed: fixed,
  );

  /// Failed outcome with a readable [message] for the model (no stack
  /// traces).
  factory ToolOutcome.error(
    String message, {
    String? summary,
    bool endsRun = false,
  }) => ToolOutcome(
    content: [TextBlock(message)],
    isError: true,
    summary: summary,
    endsRun: endsRun,
  );

  /// The user declined the confirmation; not an error, the model should
  /// accept the decision.
  factory ToolOutcome.declined() => ToolOutcome(
    content: const [TextBlock(declinedText)],
    summary: 'Abgelehnt',
  );

  /// The run was cancelled before the tool finished (error outcome).
  factory ToolOutcome.cancelled() => ToolOutcome(
    content: const [TextBlock(cancelledText)],
    isError: true,
    summary: 'Abgebrochen',
  );

  /// Model-facing text of [ToolOutcome.declined].
  static const declinedText = 'Nutzer hat abgelehnt';

  /// Model-facing text of [ToolOutcome.cancelled].
  static const cancelledText = 'Abgebrochen';

  /// Content for the model.
  final List<ContentBlock> content;

  /// Whether the tool failed.
  final bool isError;

  /// Optional undo for `write` tools.
  final UndoAction? undo;

  /// Short UI text, e.g. „Termin angelegt: Tauchen, Di 10:00“.
  final String? summary;

  /// The fixed confirmation sentence for this success (WP122), only set by
  /// tools that implement [FixedConfirmationTool]. `null` = the model words
  /// the answer. Never sent to the model.
  final ConfirmationSentence? fixed;

  /// The run ends with this round: the agent records the results and sends
  /// no further model request (WP163 B: a call held back until the unlock;
  /// the caller answers). Checked by the agent before the next request, so
  /// it does not depend on when a listener reacts.
  final bool endsRun;

  /// Concatenated text of all [TextBlock]s in [content].
  String get text => content.whereType<TextBlock>().map((b) => b.text).join();

  /// The block sent back to the model for the call [callId].
  ToolResultBlock toResultBlock(String callId) =>
      ToolResultBlock(callId: callId, content: content, isError: isError);

  @override
  String toString() =>
      'ToolOutcome(isError: $isError, summary: $summary, $content)';
}
