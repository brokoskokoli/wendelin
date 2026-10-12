import 'package:wendelin_core/wendelin_core.dart';

import 'openai_options.dart';

/// Builds the JSON body of `POST /chat/completions` (streaming) for [req].
///
/// - System prompt as first `system` message.
/// - User images as `image_url` data URLs.
/// - Assistant tool calls as `tool_calls`; thinking blocks are dropped (the
///   Chat Completions API does not take reasoning back).
/// - Each tool result becomes one `role: tool` message (text only; images
///   are replaced by a placeholder, errors prefixed with `Fehler: `).
Map<String, Object?> buildOpenAiBody(
  ChatRequest req,
  OpenAiOptions options, {
  required String maxTokensField,
  required bool includeUsage,
}) {
  final hasTools = req.tools.isNotEmpty;
  return {
    'model': req.model,
    'messages': [
      if (req.systemPrompt != null && req.systemPrompt!.isNotEmpty)
        {'role': 'system', 'content': req.systemPrompt},
      for (final m in req.messages) ..._message(m),
    ],
    if (hasTools)
      'tools': [
        for (final t in req.tools)
          {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.inputSchema,
            },
          },
      ],
    if (hasTools) ...?_toolChoice(req.toolChoice),
    maxTokensField: req.maxTokens,
    if (req.temperature != null) 'temperature': req.temperature,
    if (options.reasoningEffort != null)
      'reasoning_effort': options.reasoningEffort,
    if (options.disableReasoning) 'reasoning': {'enabled': false},
    ...options.extraBody,
    'stream': true,
    if (includeUsage) 'stream_options': {'include_usage': true},
  };
}

Map<String, Object?>? _toolChoice(ToolChoice choice) => switch (choice) {
  ToolChoiceAuto() => null,
  ToolChoiceNone() => {'tool_choice': 'none'},
  ToolChoiceRequired() => {'tool_choice': 'required'},
  ToolChoiceTool(:final name) => {
    'tool_choice': {
      'type': 'function',
      'function': {'name': name},
    },
  },
};

List<Map<String, Object?>> _message(Message m) {
  switch (m.role) {
    case Role.system:
      return [
        if (m.text.isNotEmpty) {'role': 'system', 'content': m.text},
      ];
    case Role.user:
      return [
        if (_userContent(m.content) case final content?)
          {'role': 'user', 'content': content},
      ];
    case Role.assistant:
      final text = m.text;
      final calls = m.toolCalls;
      if (text.isEmpty && calls.isEmpty) return const [];
      return [
        {
          'role': 'assistant',
          'content': text.isEmpty ? null : text,
          if (calls.isNotEmpty)
            'tool_calls': [
              for (final c in calls)
                {
                  'id': c.id,
                  'type': 'function',
                  'function': {'name': c.name, 'arguments': c.argumentsJson},
                },
            ],
        },
      ];
    case Role.tool:
      return [
        for (final r in m.content.whereType<ToolResultBlock>())
          {'role': 'tool', 'tool_call_id': r.callId, 'content': _resultText(r)},
      ];
  }
}

/// A plain string for text-only content, otherwise a parts list; `null`
/// if there is nothing to send.
Object? _userContent(List<ContentBlock> content) {
  final parts = [
    for (final b in content)
      if (b is TextBlock && b.text.isNotEmpty)
        {'type': 'text', 'text': b.text}
      else if (b is ImageBlock)
        {
          'type': 'image_url',
          'image_url': {'url': 'data:${b.mediaType};base64,${b.base64Data}'},
        },
  ];
  if (parts.isEmpty) return null;
  if (parts.every((p) => p['type'] == 'text')) {
    return parts.map((p) => p['text']).join('\n');
  }
  return parts;
}

String _resultText(ToolResultBlock r) {
  final text = [
    for (final c in r.content)
      if (c is TextBlock)
        c.text
      else if (c is ImageBlock)
        '[Bild: ${c.mediaType}]',
  ].join('\n');
  return r.isError ? 'Fehler: $text' : text;
}
