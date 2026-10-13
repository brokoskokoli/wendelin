import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/http_transport.dart';
import '../common/json_util.dart';
import 'openai_errors.dart';

/// Decodes the SSE stream of an OpenAI-compatible Chat Completions call.
///
/// Tool calls are assembled by their `index`; ids and names come with the
/// first fragment (missing ids are generated). `ToolCallComplete`s are
/// emitted at `finish_reason`, usage from the final chunk
/// (`include_usage`), `Done` at `[DONE]` or the end of the body.
/// `reasoning_content` / `reasoning` deltas become thinking events (or are
/// dropped if [emitReasoning] is false).
final class OpenAiStreamDecoder implements StreamDecoder {
  /// Creates a decoder; [label] names the provider in errors.
  OpenAiStreamDecoder({required this.label, this.emitReasoning = true});

  /// Provider name for error messages.
  final String label;

  /// Whether reasoning deltas are forwarded.
  final bool emitReasoning;

  final Map<int, _Call> _calls = {};
  final StringBuffer _thinking = StringBuffer();
  var _thinkingOpen = false;
  var _completed = false;
  String? _finishReason;
  var _finished = false;
  var _reported = Usage.zero;

  @override
  List<ChatEvent> onEvent(SseEvent event) {
    if (event.isDone) return _end();
    final json = decodeObject(event.data, label);
    final error = json['error'];
    if (error != null) {
      throw openAiError(asMap(error) ?? {'message': '$error'}, label: label);
    }
    final out = <ChatEvent>[];
    final choices = asList(json['choices']);
    final choice = choices.isEmpty ? null : asMap(choices.first);
    if (choice != null) {
      final delta = asMap(choice['delta']) ?? const {};
      final reasoning =
          asString(delta['reasoning_content']) ?? asString(delta['reasoning']);
      if (reasoning != null && reasoning.isNotEmpty && emitReasoning) {
        _thinkingOpen = true;
        _thinking.write(reasoning);
        out.add(ThinkingDelta(reasoning));
      }
      final content = asString(delta['content']);
      if (content != null && content.isNotEmpty) {
        out
          ..addAll(_closeThinking())
          ..add(TextDelta(content));
      }
      final toolCalls = asList(delta['tool_calls']);
      if (toolCalls.isNotEmpty) out.addAll(_closeThinking());
      for (final (position, raw) in toolCalls.indexed) {
        out.addAll(_toolDelta(asMap(raw) ?? const {}, position));
      }
      final finish = asString(choice['finish_reason']);
      if (finish != null) {
        _finishReason = finish;
        _finished = true;
        out
          ..addAll(_closeThinking())
          ..addAll(_completeCalls());
      }
    }
    final usage = asMap(json['usage']);
    if (usage != null) out.addAll(_usage(usage));
    return out;
  }

  @override
  List<ChatEvent> onEnd() {
    if (!_finished) {
      throw NetworkException('$label: Stream vorzeitig beendet');
    }
    return _end();
  }

  List<ChatEvent> _end() => [
    ..._closeThinking(),
    ..._completeCalls(),
    Done(mapOpenAiFinishReason(_finishReason, hasToolCalls: _calls.isNotEmpty)),
  ];

  List<ChatEvent> _toolDelta(Map<String, Object?> raw, int position) {
    if (_completed) {
      throw MalformedResponseException(
        '$label: Tool-Call-Fragment nach finish_reason',
      );
    }
    final key = asInt(raw['index']) ?? position;
    final function = asMap(raw['function']) ?? const {};
    final isNew = !_calls.containsKey(key);
    final call = _calls.putIfAbsent(key, () => _Call(_calls.length));
    final id = asString(raw['id']);
    final name = asString(function['name']);
    if (id != null && id.isNotEmpty && call.id == null) call.id = id;
    if (name != null && name.isNotEmpty && call.name.isEmpty) {
      call.name = name;
    }
    final args = function['arguments'];
    final fragment = switch (args) {
      final String s => s,
      final Map<String, Object?> m => jsonEncode(m),
      _ => '',
    };
    call.arguments.write(fragment);
    if (!isNew && fragment.isEmpty) return const [];
    return [
      ToolCallDelta(
        index: call.ordinal,
        id: isNew ? call.id : null,
        name: isNew && call.name.isNotEmpty ? call.name : null,
        argumentsFragment: fragment,
      ),
    ];
  }

  List<ChatEvent> _completeCalls() {
    if (_completed) return const [];
    _completed = true;
    final ordered = _calls.values.toList()
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return [
      for (final c in ordered)
        if (c.name.isEmpty)
          throw MalformedResponseException('$label: Tool-Call ohne Namen')
        else
          ToolCallComplete(
            ToolCallBlock(
              id: c.id ?? 'call_${c.ordinal}',
              name: c.name,
              argumentsJson: c.arguments.isEmpty
                  ? '{}'
                  : c.arguments.toString(),
            ),
          ),
    ];
  }

  List<ChatEvent> _closeThinking() {
    if (!_thinkingOpen) return const [];
    _thinkingOpen = false;
    final text = _thinking.toString();
    _thinking.clear();
    return [ThinkingComplete(ThinkingBlock(text))];
  }

  /// Usage is treated as cumulative (OpenAI sends it once at the end, vLLM
  /// with `continuous_usage_stats` in every chunk); only growth is emitted.
  List<ChatEvent> _usage(Map<String, Object?> usage) {
    final prompt = asInt(usage['prompt_tokens']) ?? 0;
    final completion = asInt(usage['completion_tokens']) ?? 0;
    final cached =
        asInt(asMap(usage['prompt_tokens_details'])?['cached_tokens']) ?? 0;
    final total = Usage(
      inputTokens: prompt - cached < 0 ? 0 : prompt - cached,
      outputTokens: completion,
      cachedInputTokens: cached,
    );
    int grow(int now, int before) => now > before ? now - before : 0;
    final increment = Usage(
      inputTokens: grow(total.inputTokens, _reported.inputTokens),
      outputTokens: grow(total.outputTokens, _reported.outputTokens),
      cachedInputTokens: grow(
        total.cachedInputTokens,
        _reported.cachedInputTokens,
      ),
    );
    _reported = _reported + increment;
    return increment == Usage.zero ? const [] : [UsageEvent(increment)];
  }
}

final class _Call {
  _Call(this.ordinal);
  final int ordinal;
  String? id;
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
