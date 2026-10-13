import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/http_transport.dart';
import '../common/json_util.dart';
import 'anthropic_errors.dart';

const _label = 'Anthropic';

/// Decodes the SSE stream of the Anthropic Messages API.
///
/// Maps `message_start`, `content_block_start/delta/stop` (text, tool_use
/// with `input_json_delta`, thinking with `signature_delta`,
/// redacted_thinking), `message_delta` (stop
/// reason, cumulative usage → increments), `message_stop`, `ping` and
/// `error`. Block types the internal format does not model (server-side
/// web search: `server_tool_use`, `web_search_tool_result`, …) become
/// `ProviderBlockComplete` with the verbatim block – never text. Unknown
/// event types are ignored.
final class AnthropicStreamDecoder implements StreamDecoder {
  final Map<int, _Block> _blocks = {};
  var _toolOrdinal = 0;
  var _usage = Usage.zero;
  StopReason? _stopReason;
  var _started = false;

  @override
  List<ChatEvent> onEvent(SseEvent event) {
    final json = decodeObject(event.data, _label);
    final type = asString(json['type']) ?? event.event;
    return switch (type) {
      'message_start' => _messageStart(json),
      'content_block_start' => _blockStart(json),
      'content_block_delta' => _blockDelta(json),
      'content_block_stop' => _blockStop(json),
      'message_delta' => _messageDelta(json),
      'message_stop' => _messageStop(),
      'error' => throw anthropicStreamError(asMap(json['error'])),
      _ => const [],
    };
  }

  @override
  List<ChatEvent> onEnd() => throw const NetworkException(
    '$_label: Stream vorzeitig beendet (kein message_stop)',
  );

  List<ChatEvent> _messageStart(Map<String, Object?> json) {
    _started = true;
    final usage = asMap(asMap(json['message'])?['usage']);
    return _usageIncrement(usage);
  }

  List<ChatEvent> _blockStart(Map<String, Object?> json) {
    final index = _index(json);
    final block = asMap(json['content_block']);
    if (block == null) {
      throw const MalformedResponseException('$_label: content_block fehlt');
    }
    switch (asString(block['type'])) {
      case 'text':
        final text = asString(block['text']) ?? '';
        _blocks[index] = _TextBlock();
        return [if (text.isNotEmpty) TextDelta(text)];
      case 'tool_use':
        final id = asString(block['id']);
        final name = asString(block['name']);
        if (id == null || name == null) {
          throw const MalformedResponseException(
            '$_label: tool_use ohne id/name',
          );
        }
        final call = _ToolBlock(_toolOrdinal++, id, name);
        _blocks[index] = call;
        return [ToolCallDelta(index: call.ordinal, id: id, name: name)];
      case 'thinking':
        _blocks[index] = _ThinkingBlock()
          ..signature.write(asString(block['signature']) ?? '')
          ..text.write(asString(block['thinking']) ?? '');
        final text = asString(block['thinking']) ?? '';
        return [if (text.isNotEmpty) ThinkingDelta(text)];
      case 'redacted_thinking':
        _blocks[index] = _RedactedBlock(asString(block['data']) ?? '');
        return const [];
      default:
        // server_tool_use, web_search_tool_result, mcp_tool_use, … – kept
        // verbatim and sent back unchanged (pause_turn), never spoken.
        _blocks[index] = _RawBlock(block);
        return const [];
    }
  }

  List<ChatEvent> _blockDelta(Map<String, Object?> json) {
    final block = _blocks[_index(json)];
    final delta = asMap(json['delta']) ?? const {};
    final type = asString(delta['type']);
    switch ((block, type)) {
      case (_TextBlock(), 'text_delta'):
        final text = asString(delta['text']) ?? '';
        return [if (text.isNotEmpty) TextDelta(text)];
      case (final _ToolBlock b, 'input_json_delta'):
        final fragment = asString(delta['partial_json']) ?? '';
        if (fragment.isEmpty) return const [];
        b.arguments.write(fragment);
        return [ToolCallDelta(index: b.ordinal, argumentsFragment: fragment)];
      case (final _RawBlock b, 'input_json_delta'):
        b.input.write(asString(delta['partial_json']) ?? '');
        return const [];
      case (final _ThinkingBlock b, 'thinking_delta'):
        final text = asString(delta['thinking']) ?? '';
        b.text.write(text);
        return [if (text.isNotEmpty) ThinkingDelta(text)];
      case (final _ThinkingBlock b, 'signature_delta'):
        b.signature.write(asString(delta['signature']) ?? '');
        return const [];
      case (null, _):
        throw const MalformedResponseException(
          '$_label: Delta für unbekannten Block',
        );
      default:
        return const []; // e.g. citations_delta
    }
  }

  List<ChatEvent> _blockStop(Map<String, Object?> json) {
    final block = _blocks.remove(_index(json));
    switch (block) {
      case final _ToolBlock b:
        return [
          ToolCallComplete(
            ToolCallBlock(
              id: b.id,
              name: b.name,
              argumentsJson: b.arguments.isEmpty
                  ? '{}'
                  : b.arguments.toString(),
            ),
          ),
        ];
      case final _ThinkingBlock b:
        final signature = b.signature.toString();
        return [
          ThinkingComplete(
            ThinkingBlock(
              b.text.toString(),
              signature: signature.isEmpty ? null : signature,
            ),
          ),
        ];
      case _RedactedBlock(:final data):
        return [ThinkingComplete(ThinkingBlock.redacted(data))];
      case final _RawBlock b:
        return [ProviderBlockComplete(b.complete())];
      case null:
        throw const MalformedResponseException(
          '$_label: content_block_stop für unbekannten Block',
        );
      default:
        return const [];
    }
  }

  List<ChatEvent> _messageDelta(Map<String, Object?> json) {
    final reason = asString(asMap(json['delta'])?['stop_reason']);
    if (reason != null) _stopReason = mapAnthropicStopReason(reason);
    return _usageIncrement(asMap(json['usage']));
  }

  List<ChatEvent> _messageStop() {
    if (!_started) {
      throw const MalformedResponseException(
        '$_label: message_stop ohne message_start',
      );
    }
    if (_blocks.values.any((b) => b is! _TextBlock && b is! _RedactedBlock)) {
      throw const MalformedResponseException(
        '$_label: Nachricht endet mit offenem Block',
      );
    }
    return [Done(_stopReason ?? StopReason.other)];
  }

  /// Anthropic reports cumulative counts; emit only the growth.
  List<ChatEvent> _usageIncrement(Map<String, Object?>? usage) {
    if (usage == null) return const [];
    int read(String key, int previous) => asInt(usage[key]) ?? previous;
    final total = Usage(
      inputTokens: read('input_tokens', _usage.inputTokens),
      outputTokens: read('output_tokens', _usage.outputTokens),
      cachedInputTokens: read(
        'cache_read_input_tokens',
        _usage.cachedInputTokens,
      ),
      cacheWriteTokens: read(
        'cache_creation_input_tokens',
        _usage.cacheWriteTokens,
      ),
    );
    int grow(int now, int before) => now > before ? now - before : 0;
    final increment = Usage(
      inputTokens: grow(total.inputTokens, _usage.inputTokens),
      outputTokens: grow(total.outputTokens, _usage.outputTokens),
      cachedInputTokens: grow(
        total.cachedInputTokens,
        _usage.cachedInputTokens,
      ),
      cacheWriteTokens: grow(total.cacheWriteTokens, _usage.cacheWriteTokens),
    );
    _usage = Usage(
      inputTokens: _max(total.inputTokens, _usage.inputTokens),
      outputTokens: _max(total.outputTokens, _usage.outputTokens),
      cachedInputTokens: _max(
        total.cachedInputTokens,
        _usage.cachedInputTokens,
      ),
      cacheWriteTokens: _max(total.cacheWriteTokens, _usage.cacheWriteTokens),
    );
    return increment == Usage.zero ? const [] : [UsageEvent(increment)];
  }

  static int _max(int a, int b) => a > b ? a : b;

  static int _index(Map<String, Object?> json) {
    final index = asInt(json['index']);
    if (index == null) {
      throw const MalformedResponseException('$_label: index fehlt');
    }
    return index;
  }
}

sealed class _Block {}

final class _TextBlock extends _Block {}

final class _ToolBlock extends _Block {
  _ToolBlock(this.ordinal, this.id, this.name);
  final int ordinal;
  final String id;
  final String name;
  final StringBuffer arguments = StringBuffer();
}

final class _ThinkingBlock extends _Block {
  final StringBuffer text = StringBuffer();
  final StringBuffer signature = StringBuffer();
}

final class _RedactedBlock extends _Block {
  _RedactedBlock(this.data);
  final String data;
}

/// A block the internal format does not model, stored verbatim. Input
/// fragments (`input_json_delta`, e.g. the query of `server_tool_use`) are
/// merged into `input`, as the API expects the complete block back.
final class _RawBlock extends _Block {
  _RawBlock(this.start);
  final Map<String, Object?> start;
  final StringBuffer input = StringBuffer();

  ProviderBlock complete() {
    final block = Map<String, Object?>.of(start);
    if (input.isNotEmpty) {
      try {
        block['input'] = jsonDecode(input.toString());
      } on FormatException {
        throw const MalformedResponseException(
          '$_label: ungültige Eingabe in Server-Tool-Block',
        );
      }
    }
    return ProviderBlock(
      provider: ProviderType.anthropic.name,
      rawJson: jsonEncode(block),
      summary: _summary(block),
    );
  }

  static String? _summary(Map<String, Object?> block) {
    switch (asString(block['type'])) {
      case 'server_tool_use':
        final query = asString(asMap(block['input'])?['query']);
        if (asString(block['name']) == 'web_search' && query != null) {
          return 'Websuche: $query';
        }
        return asString(block['name']);
      case 'web_search_tool_result':
        final content = block['content'];
        if (content is List<Object?>) return 'Quellen: ${content.length}';
        final code = asString(asMap(content)?['error_code']) ?? 'unbekannt';
        return 'Websuche fehlgeschlagen: $code';
      default:
        return asString(block['type']);
    }
  }
}
