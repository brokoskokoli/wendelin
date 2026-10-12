import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../util/json_read.dart';

/// One piece of content inside a `Message`.
///
/// Serialisation via [toJson]/[ContentBlock.fromJson] is the storage format
/// (stable, versioned by the `type` discriminator). Provider wire formats are
/// produced by the adapters, never from this JSON.
@immutable
sealed class ContentBlock {
  const ContentBlock();

  /// Decodes a block written by [toJson]. Throws [FormatException] for
  /// unknown types or missing fields.
  factory ContentBlock.fromJson(Map<String, Object?> json) {
    final type = readField<String>(json, 'type', 'ContentBlock');
    return switch (type) {
      TextBlock.jsonType => TextBlock(readField(json, 'text', 'TextBlock')),
      ImageBlock.jsonType => ImageBlock.base64(
        mediaType: readField(json, 'mediaType', 'ImageBlock'),
        data: readField(json, 'data', 'ImageBlock'),
      ),
      ToolCallBlock.jsonType => ToolCallBlock(
        id: readField(json, 'id', 'ToolCallBlock'),
        name: readField(json, 'name', 'ToolCallBlock'),
        argumentsJson: readField(json, 'argumentsJson', 'ToolCallBlock'),
      ),
      ToolResultBlock.jsonType => ToolResultBlock(
        callId: readField(json, 'callId', 'ToolResultBlock'),
        content: [
          for (final c in readMapList(json, 'content', 'ToolResultBlock'))
            ContentBlock.fromJson(c),
        ],
        isError: readField(json, 'isError', 'ToolResultBlock'),
      ),
      ThinkingBlock.jsonType => ThinkingBlock(
        readField(json, 'text', 'ThinkingBlock'),
        signature: readOptional<String>(json, 'signature', 'ThinkingBlock'),
        redactedData: readOptional<String>(
          json,
          'redactedData',
          'ThinkingBlock',
        ),
      ),
      ProviderBlock.jsonType => ProviderBlock(
        provider: readField(json, 'provider', 'ProviderBlock'),
        rawJson: readField(json, 'rawJson', 'ProviderBlock'),
        summary: readOptional<String>(json, 'summary', 'ProviderBlock'),
      ),
      _ => throw FormatException('ContentBlock: unbekannter Typ "$type"'),
    };
  }

  /// Encodes this block as a JSON-compatible map.
  Map<String, Object?> toJson();
}

/// Plain text.
final class TextBlock extends ContentBlock {
  /// Creates a text block.
  const TextBlock(this.text);

  /// JSON discriminator.
  static const jsonType = 'text';

  /// The text.
  final String text;

  @override
  Map<String, Object?> toJson() => {'type': jsonType, 'text': text};

  @override
  bool operator ==(Object other) => other is TextBlock && other.text == text;

  @override
  int get hashCode => Object.hash(jsonType, text);

  @override
  String toString() => 'TextBlock($text)';
}

/// An image, held as raw [bytes]. Use [ImageBlock.base64] to create one from
/// base64 data; [base64Data] returns the encoded form.
final class ImageBlock extends ContentBlock {
  /// Creates an image block from raw bytes.
  ImageBlock({required this.mediaType, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  /// Creates an image block from base64-encoded data.
  factory ImageBlock.base64({
    required String mediaType,
    required String data,
  }) => ImageBlock(mediaType: mediaType, bytes: base64Decode(data));

  /// JSON discriminator.
  static const jsonType = 'image';

  /// MIME type, e.g. `image/png`.
  final String mediaType;

  /// Raw image bytes (unmodifiable).
  final Uint8List bytes;

  /// The image bytes base64-encoded.
  String get base64Data => base64Encode(bytes);

  @override
  Map<String, Object?> toJson() => {
    'type': jsonType,
    'mediaType': mediaType,
    'data': base64Data,
  };

  @override
  bool operator ==(Object other) =>
      other is ImageBlock &&
      other.mediaType == mediaType &&
      const ListEquality<int>().equals(other.bytes, bytes);

  @override
  int get hashCode =>
      Object.hash(jsonType, mediaType, const ListEquality<int>().hash(bytes));

  @override
  String toString() => 'ImageBlock($mediaType, ${bytes.length} bytes)';
}

/// A tool call requested by the model.
///
/// [argumentsJson] is kept as the raw string the model produced, because it
/// may be invalid JSON; validation happens in the tool runtime.
final class ToolCallBlock extends ContentBlock {
  /// Creates a tool call block.
  const ToolCallBlock({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  /// JSON discriminator.
  static const jsonType = 'toolCall';

  /// Provider-assigned call id; tool results refer to it.
  final String id;

  /// Tool name (`integration__action`).
  final String name;

  /// Arguments as produced by the model (should be a JSON object).
  final String argumentsJson;

  /// Decodes [argumentsJson] into a map, or returns `null` if it is not a
  /// valid JSON object.
  Map<String, Object?>? tryDecodeArguments() {
    try {
      final decoded = jsonDecode(argumentsJson);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'type': jsonType,
    'id': id,
    'name': name,
    'argumentsJson': argumentsJson,
  };

  @override
  bool operator ==(Object other) =>
      other is ToolCallBlock &&
      other.id == id &&
      other.name == name &&
      other.argumentsJson == argumentsJson;

  @override
  int get hashCode => Object.hash(jsonType, id, name, argumentsJson);

  @override
  String toString() => 'ToolCallBlock($id, $name, $argumentsJson)';
}

/// The result of a tool call, sent back to the model.
final class ToolResultBlock extends ContentBlock {
  /// Creates a tool result block.
  ToolResultBlock({
    required this.callId,
    required List<ContentBlock> content,
    this.isError = false,
  }) : content = List.unmodifiable(content);

  /// JSON discriminator.
  static const jsonType = 'toolResult';

  /// Id of the [ToolCallBlock] this result answers.
  final String callId;

  /// Result content (usually text, possibly images).
  final List<ContentBlock> content;

  /// Whether the tool failed; the content then holds a readable message.
  final bool isError;

  @override
  Map<String, Object?> toJson() => {
    'type': jsonType,
    'callId': callId,
    'content': [for (final c in content) c.toJson()],
    'isError': isError,
  };

  @override
  bool operator ==(Object other) =>
      other is ToolResultBlock &&
      other.callId == callId &&
      other.isError == isError &&
      const ListEquality<ContentBlock>().equals(other.content, content);

  @override
  int get hashCode => Object.hash(
    jsonType,
    callId,
    isError,
    const ListEquality<ContentBlock>().hash(content),
  );

  @override
  String toString() => 'ToolResultBlock($callId, isError: $isError, $content)';
}

/// Model reasoning. Only shown in the UI and passed back to the same
/// provider; never interpreted by the app.
///
/// Adapters must be able to send a block back **unchanged**: Anthropic
/// rejects modified thinking blocks and checks [signature]. Redacted thinking
/// (encrypted by the provider) has an empty [text] and the opaque payload in
/// [redactedData].
final class ThinkingBlock extends ContentBlock {
  /// Creates a thinking block.
  const ThinkingBlock(this.text, {this.signature, this.redactedData});

  /// A redacted (encrypted) reasoning block with the opaque [data].
  const ThinkingBlock.redacted(String data) : this('', redactedData: data);

  /// JSON discriminator.
  static const jsonType = 'thinking';

  /// The reasoning text (empty for redacted thinking).
  final String text;

  /// Opaque provider signature, if any.
  final String? signature;

  /// Opaque, provider-encrypted reasoning, if the block is redacted.
  final String? redactedData;

  /// Whether this is a redacted block.
  bool get isRedacted => redactedData != null;

  @override
  Map<String, Object?> toJson() => {
    'type': jsonType,
    'text': text,
    if (signature != null) 'signature': signature,
    if (redactedData != null) 'redactedData': redactedData,
  };

  @override
  bool operator ==(Object other) =>
      other is ThinkingBlock &&
      other.text == text &&
      other.signature == signature &&
      other.redactedData == redactedData;

  @override
  int get hashCode => Object.hash(jsonType, text, signature, redactedData);

  @override
  String toString() =>
      isRedacted ? 'ThinkingBlock(redacted)' : 'ThinkingBlock($text)';
}

/// A provider-specific block that the internal format does not model, e.g.
/// Anthropic's `server_tool_use` / `web_search_tool_result`.
///
/// The adapter that produced it stores the wire block verbatim in [rawJson]
/// and sends it back **unchanged** when the history goes to the same
/// [provider] again (required to resume `pause_turn`). Other providers never
/// see it: the agent drops provider blocks of a different provider, like
/// foreign thinking blocks. The content is untrusted data – it is never
/// spoken and never treated as the assistant's own words; [summary] is an
/// optional short display text (e.g. "Websuche: Wetter Nizza").
final class ProviderBlock extends ContentBlock {
  /// Creates a provider block.
  const ProviderBlock({
    required this.provider,
    required this.rawJson,
    this.summary,
  });

  /// JSON discriminator.
  static const jsonType = 'provider';

  /// Provider family that produced the block (`ProviderType.name`).
  final String provider;

  /// The block exactly as received on the wire (JSON text).
  final String rawJson;

  /// Optional display-only summary.
  final String? summary;

  @override
  Map<String, Object?> toJson() => {
    'type': jsonType,
    'provider': provider,
    'rawJson': rawJson,
    if (summary != null) 'summary': summary,
  };

  @override
  bool operator ==(Object other) =>
      other is ProviderBlock &&
      other.provider == provider &&
      other.rawJson == rawJson &&
      other.summary == summary;

  @override
  int get hashCode => Object.hash(jsonType, provider, rawJson, summary);

  @override
  String toString() => 'ProviderBlock($provider, ${summary ?? '…'})';
}
