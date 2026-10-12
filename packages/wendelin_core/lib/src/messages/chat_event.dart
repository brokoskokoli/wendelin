import 'package:meta/meta.dart';

import '../provider/provider_exception.dart';
import 'content_block.dart';
import 'stop_reason.dart';
import 'usage.dart';

/// One event of a streaming model response (`LlmProvider.chat`).
///
/// Stream contract (checked by `llmProviderContract`):
/// - The stream ends with exactly one *terminal* event: [Done] on success or
///   [ErrorEvent] on failure (incl. cancellation). Nothing follows it and the
///   stream then closes. Providers never emit stream errors.
/// - Tool calls are numbered 0, 1, … in order of appearance. The *k*-th
///   [ToolCallComplete] belongs to the [ToolCallDelta]s with `index == k`;
///   those deltas come before it.
/// - If the stream ends with [Done], every tool call that has deltas also
///   has its [ToolCallComplete]. If it ends with [ErrorEvent] (including
///   cancellation), calls may be left incomplete; consumers must discard
///   incomplete calls and never execute them.
/// - [ThinkingDelta]s of a reasoning block are followed by one
///   [ThinkingComplete] carrying the full block (with signature or redacted
///   data) that must be sent back unchanged.
/// - Provider-specific blocks the internal format does not model arrive as
///   [ProviderBlockComplete] at their position in the answer.
/// - [UsageEvent]s come before [Done].
@immutable
sealed class ChatEvent {
  const ChatEvent();

  /// Whether this event ends the stream ([Done] or [ErrorEvent]).
  bool get isTerminal => false;
}

/// A piece of answer text.
final class TextDelta extends ChatEvent {
  /// Creates a text delta.
  const TextDelta(this.text);

  /// The text fragment.
  final String text;

  @override
  bool operator ==(Object other) => other is TextDelta && other.text == text;

  @override
  int get hashCode => Object.hash(TextDelta, text);

  @override
  String toString() => 'TextDelta($text)';
}

/// A piece of model reasoning (display only).
final class ThinkingDelta extends ChatEvent {
  /// Creates a thinking delta.
  const ThinkingDelta(this.text);

  /// The reasoning fragment.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ThinkingDelta && other.text == text;

  @override
  int get hashCode => Object.hash(ThinkingDelta, text);

  @override
  String toString() => 'ThinkingDelta($text)';
}

/// A finished reasoning block, emitted after its [ThinkingDelta]s (or alone
/// for redacted thinking).
///
/// Providers such as Anthropic require signed or redacted thinking blocks to
/// be sent back **unchanged** in the next request; the agent stores [block]
/// in the assistant message.
final class ThinkingComplete extends ChatEvent {
  /// Creates the event.
  const ThinkingComplete(this.block);

  /// The complete block.
  final ThinkingBlock block;

  @override
  bool operator ==(Object other) =>
      other is ThinkingComplete && other.block == block;

  @override
  int get hashCode => Object.hash(ThinkingComplete, block);

  @override
  String toString() => 'ThinkingComplete($block)';
}

/// A finished provider-specific block (see [ProviderBlock]), emitted at its
/// position in the answer. The agent keeps it in the assistant message so
/// the same provider gets it back unchanged; it is not text for UI or TTS.
final class ProviderBlockComplete extends ChatEvent {
  /// Creates the event.
  const ProviderBlockComplete(this.block);

  /// The block.
  final ProviderBlock block;

  @override
  bool operator ==(Object other) =>
      other is ProviderBlockComplete && other.block == block;

  @override
  int get hashCode => Object.hash(ProviderBlockComplete, block);

  @override
  String toString() => 'ProviderBlockComplete($block)';
}

/// A fragment of a tool call while it is being generated.
///
/// [index] is the 0-based position of the tool call among the tool calls of
/// this response (not the provider's content-block index). [id] and [name]
/// are usually only set on the first delta of a call.
final class ToolCallDelta extends ChatEvent {
  /// Creates a tool call delta.
  const ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsFragment = '',
  });

  /// 0-based ordinal of the tool call in this response.
  final int index;

  /// Call id, if known in this fragment.
  final String? id;

  /// Tool name, if known in this fragment.
  final String? name;

  /// Next fragment of the raw arguments JSON.
  final String argumentsFragment;

  @override
  bool operator ==(Object other) =>
      other is ToolCallDelta &&
      other.index == index &&
      other.id == id &&
      other.name == name &&
      other.argumentsFragment == argumentsFragment;

  @override
  int get hashCode =>
      Object.hash(ToolCallDelta, index, id, name, argumentsFragment);

  @override
  String toString() => 'ToolCallDelta($index, $id, $name, $argumentsFragment)';
}

/// A fully assembled tool call.
final class ToolCallComplete extends ChatEvent {
  /// Creates the event.
  const ToolCallComplete(this.call);

  /// The complete call.
  final ToolCallBlock call;

  @override
  bool operator ==(Object other) =>
      other is ToolCallComplete && other.call == call;

  @override
  int get hashCode => Object.hash(ToolCallComplete, call);

  @override
  String toString() => 'ToolCallComplete($call)';
}

/// Token usage reported by the provider.
///
/// May occur more than once per response; each event carries an
/// **increment**, consumers sum all of them. Adapters whose API reports
/// cumulative totals (e.g. Anthropic `message_delta`) must convert them into
/// increments.
final class UsageEvent extends ChatEvent {
  /// Creates the event.
  const UsageEvent(this.usage);

  /// Reported usage.
  final Usage usage;

  @override
  bool operator ==(Object other) => other is UsageEvent && other.usage == usage;

  @override
  int get hashCode => Object.hash(UsageEvent, usage);

  @override
  String toString() => 'UsageEvent($usage)';
}

/// Successful end of the response (terminal).
final class Done extends ChatEvent {
  /// Creates the event.
  const Done(this.stopReason);

  /// Why the model stopped.
  final StopReason stopReason;

  @override
  bool get isTerminal => true;

  @override
  bool operator ==(Object other) =>
      other is Done && other.stopReason == stopReason;

  @override
  int get hashCode => Object.hash(Done, stopReason);

  @override
  String toString() => 'Done(${stopReason.name})';
}

/// Failed end of the response (terminal), including cancellation
/// ([CancelledException]).
final class ErrorEvent extends ChatEvent {
  /// Creates the event.
  const ErrorEvent(this.error);

  /// What went wrong.
  final ProviderException error;

  @override
  bool get isTerminal => true;

  @override
  bool operator ==(Object other) => other is ErrorEvent && other.error == error;

  @override
  int get hashCode => Object.hash(ErrorEvent, error);

  @override
  String toString() => 'ErrorEvent($error)';
}
