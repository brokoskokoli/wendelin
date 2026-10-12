import 'package:wendelin_core/wendelin_core.dart';

import 'anthropic_options.dart';

/// Models that support the dynamic-filtering web search tool version.
const _dynamicWebSearchModels = [
  'claude-opus-5-5',
  'claude-opus-5',
  'claude-opus-4-8',
  'claude-opus-4-7',
  'claude-opus-4-6',
  'claude-sonnet-5-5',
  'claude-sonnet-5',
  'claude-sonnet-4-6',
];

const _ephemeral = {'type': 'ephemeral'};

/// Builds the JSON body of `POST /v1/messages` (streaming) for [req].
///
/// - System prompt (and inline `Role.system` messages) as `system` blocks,
///   the first block with `cache_control`.
/// - Tools with `cache_control` on the last one; optional server-side web
///   search first.
/// - `Role.tool` messages become `user` messages with `tool_result` blocks;
///   consecutive messages of the same wire role are merged.
/// - Thinking blocks are sent back unchanged; blocks without a signature
///   (from other providers) are dropped, as Anthropic rejects them.
/// - Assistant turns without thinking (e.g. after an escalation from another
///   provider) are sent as they are, also with thinking enabled: adaptive
///   thinking has no "must start with thinking" rule, and for manual
///   thinking the API disables thinking for such a request instead of
///   failing (docs: "Thinking with tool use", mid-turn conflicts).
Map<String, Object?> buildAnthropicBody(
  ChatRequest req,
  AnthropicOptions options,
) {
  final system = <Map<String, Object?>>[
    if (req.systemPrompt != null && req.systemPrompt!.isNotEmpty)
      {'type': 'text', 'text': req.systemPrompt},
    for (final m in req.messages)
      if (m.role == Role.system && m.text.isNotEmpty)
        {'type': 'text', 'text': m.text},
  ];
  if (system.isNotEmpty) {
    system[0] = {...system[0], 'cache_control': _ephemeral};
  }

  final tools = <Map<String, Object?>>[
    if (options.enableServerWebSearch)
      {
        'type': options.webSearchToolType ?? _webSearchType(req.model),
        'name': 'web_search',
        'max_uses': options.webSearchMaxUses,
      },
    for (final t in req.tools)
      {
        'name': t.name,
        'description': t.description,
        'input_schema': t.inputSchema,
      },
  ];
  if (tools.isNotEmpty) {
    tools[tools.length - 1] = {...tools.last, 'cache_control': _ephemeral};
  }

  return {
    'model': req.model,
    'max_tokens': req.maxTokens,
    if (system.isNotEmpty) 'system': system,
    'messages': _messages(req.messages),
    if (tools.isNotEmpty) 'tools': tools,
    if (tools.isNotEmpty) ...?_toolChoice(req.toolChoice),
    if (req.temperature != null) 'temperature': req.temperature,
    ...?_thinking(options),
    if (options.reasoningEffort != null)
      'output_config': {'effort': options.reasoningEffort},
    if (options.cacheConversation) 'cache_control': _ephemeral,
    'stream': true,
  };
}

String _webSearchType(String model) =>
    _dynamicWebSearchModels.any((m) => model == m || model.startsWith('$m-'))
    ? 'web_search_20260209'
    : 'web_search_20250305';

Map<String, Object?>? _toolChoice(ToolChoice choice) => switch (choice) {
  ToolChoiceAuto() => null,
  ToolChoiceNone() => {
    'tool_choice': {'type': 'none'},
  },
  ToolChoiceRequired() => {
    'tool_choice': {'type': 'any'},
  },
  ToolChoiceTool(:final name) => {
    'tool_choice': {'type': 'tool', 'name': name},
  },
};

Map<String, Object?>? _thinking(AnthropicOptions o) {
  if (o.thinking == 'disabled') {
    return {
      'thinking': {'type': 'disabled'},
    };
  }
  if (o.thinking == 'adaptive') {
    return {
      'thinking': {
        'type': 'adaptive',
        if (o.thinkingDisplay != null) 'display': o.thinkingDisplay,
      },
    };
  }
  final budget = o.thinkingBudget;
  if (budget != null && budget > 0) {
    return {
      'thinking': {'type': 'enabled', 'budget_tokens': budget},
    };
  }
  return null;
}

List<Map<String, Object?>> _messages(List<Message> messages) {
  final result = <Map<String, Object?>>[];
  for (final m in messages) {
    final role = switch (m.role) {
      Role.system => null,
      Role.user || Role.tool => 'user',
      Role.assistant => 'assistant',
    };
    if (role == null) continue;
    final blocks = [
      for (final b in m.content)
        ...?_block(b, inAssistant: role == 'assistant'),
    ];
    if (blocks.isEmpty) continue;
    if (result.isNotEmpty && result.last['role'] == role) {
      final previous = result.last['content']! as List<Map<String, Object?>>;
      result[result.length - 1] = {
        'role': role,
        'content': [...previous, ...blocks],
      };
    } else {
      result.add({'role': role, 'content': blocks});
    }
  }
  return result;
}

List<Map<String, Object?>>? _block(
  ContentBlock b, {
  required bool inAssistant,
}) => switch (b) {
  TextBlock(:final text) =>
    text.isEmpty
        ? null
        : [
            {'type': 'text', 'text': text},
          ],
  ImageBlock() => [_image(b)],
  ToolCallBlock(:final id, :final name) => [
    {
      'type': 'tool_use',
      'id': id,
      'name': name,
      'input': b.tryDecodeArguments() ?? const <String, Object?>{},
    },
  ],
  ToolResultBlock(:final callId, :final isError) => [
    {
      'type': 'tool_result',
      'tool_use_id': callId,
      ...?_resultContent(b),
      if (isError) 'is_error': true,
    },
  ],
  ThinkingBlock(:final redactedData) when redactedData != null =>
    inAssistant
        ? [
            {'type': 'redacted_thinking', 'data': redactedData},
          ]
        : null,
  ThinkingBlock(:final text, :final signature) =>
    inAssistant && signature != null
        ? [
            {'type': 'thinking', 'thinking': text, 'signature': signature},
          ]
        : null,
};

Map<String, Object?>? _resultContent(ToolResultBlock b) {
  final content = [
    for (final c in b.content)
      if (c is TextBlock && c.text.isNotEmpty)
        {'type': 'text', 'text': c.text}
      else if (c is ImageBlock)
        _image(c),
  ];
  return content.isEmpty ? null : {'content': content};
}

Map<String, Object?> _image(ImageBlock b) => {
  'type': 'image',
  'source': {'type': 'base64', 'media_type': b.mediaType, 'data': b.base64Data},
};
