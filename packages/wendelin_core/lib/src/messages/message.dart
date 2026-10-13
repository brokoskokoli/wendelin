import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../provider/privacy_level.dart';
import '../util/json_read.dart';
import 'content_block.dart';
import 'role.dart';

/// One turn of a conversation in the internal format.
@immutable
final class Message {
  /// Creates a message; [content] is copied into an unmodifiable list.
  Message(this.role, List<ContentBlock> content, {this.privacyFloor})
    : content = List.unmodifiable(content);

  /// A user message with [text] and optional [images] (images first, as
  /// vision models expect).
  factory Message.user(String text, {List<ImageBlock> images = const []}) =>
      Message(Role.user, [...images, TextBlock(text)]);

  /// An inline system message (prefer `ChatRequest.systemPrompt`).
  factory Message.system(String text) =>
      Message(Role.system, [TextBlock(text)]);

  /// An assistant message consisting of plain text.
  factory Message.assistantText(String text) =>
      Message(Role.assistant, [TextBlock(text)]);

  /// An assistant message with arbitrary blocks (text, tool calls, thinking).
  factory Message.assistant(List<ContentBlock> content) =>
      Message(Role.assistant, content);

  /// A tool message carrying [results] for earlier tool calls.
  factory Message.toolResults(List<ToolResultBlock> results) =>
      Message(Role.tool, results);

  /// Decodes a message written by [toJson]; throws [FormatException].
  factory Message.fromJson(Map<String, Object?> json) => Message(
    readEnum(json, 'role', Role.values, 'Message'),
    [
      for (final c in readMapList(json, 'content', 'Message'))
        ContentBlock.fromJson(c),
    ],
    privacyFloor: json['privacyFloor'] == null
        ? null
        : readEnum(json, 'privacyFloor', PrivacyLevel.values, 'Message'),
  );

  /// Author of the message.
  final Role role;

  /// Content blocks in order (unmodifiable).
  final List<ContentBlock> content;

  /// Set on messages of a privately routed turn: targets below this level
  /// must not see the message in later turns (the agent hides it). Not sent
  /// to any provider.
  final PrivacyLevel? privacyFloor;

  /// This message with [floor] as [privacyFloor].
  Message withPrivacyFloor(PrivacyLevel? floor) =>
      Message(role, content, privacyFloor: floor);

  /// Concatenation of all [TextBlock]s (without separator).
  String get text => content.whereType<TextBlock>().map((b) => b.text).join();

  /// All tool calls in this message, in order.
  List<ToolCallBlock> get toolCalls =>
      content.whereType<ToolCallBlock>().toList(growable: false);

  /// Encodes this message as a JSON-compatible map (storage format).
  Map<String, Object?> toJson() => {
    'role': role.name,
    'content': [for (final c in content) c.toJson()],
    if (privacyFloor case final floor?) 'privacyFloor': floor.name,
  };

  @override
  bool operator ==(Object other) =>
      other is Message &&
      other.role == role &&
      other.privacyFloor == privacyFloor &&
      const ListEquality<ContentBlock>().equals(other.content, content);

  @override
  int get hashCode => Object.hash(
    role,
    privacyFloor,
    const ListEquality<ContentBlock>().hash(content),
  );

  @override
  String toString() => privacyFloor == null
      ? 'Message(${role.name}, $content)'
      : 'Message(${role.name}, $content, floor: ${privacyFloor!.name})';
}
