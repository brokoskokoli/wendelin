import 'package:wendelin_core/wendelin_core.dart';

/// 1×1 PNG used in request snapshots.
const pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Tool used in the sample conversation.
const calendarTool = ToolSpec(
  name: 'calendar__create',
  description: 'Legt einen Termin an.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
      'start': {'type': 'string'},
    },
    'required': ['title', 'start'],
  },
);

/// Example conversation: system prompt, user text with image, assistant
/// with thinking, text and a tool call, tool result, follow-up user text.
ChatRequest sampleRequest({ToolChoice toolChoice = ToolChoice.auto}) =>
    ChatRequest(
      systemPrompt: 'Du bist Wendelin. Heute ist Dienstag.',
      model: 'test-model',
      maxTokens: 1024,
      temperature: 0.2,
      toolChoice: toolChoice,
      tools: const [calendarTool],
      messages: [
        Message.user(
          'Trag das Tauchen von diesem Flyer ein.',
          images: [ImageBlock.base64(mediaType: 'image/png', data: pngBase64)],
        ),
        Message.assistant([
          const ThinkingBlock('Flyer lesen.', signature: 'sig-abc'),
          const ThinkingBlock.redacted('opaque-data'),
          const ThinkingBlock('ohne Signatur'),
          const TextBlock('Ich trage es ein.'),
          const ToolCallBlock(
            id: 'call_1',
            name: 'calendar__create',
            argumentsJson: '{"title":"Tauchen","start":"2026-10-14T10:00"}',
          ),
        ]),
        Message.toolResults([
          ToolResultBlock(
            callId: 'call_1',
            content: const [TextBlock('Termin angelegt')],
          ),
        ]),
        Message.user('Danke!'),
      ],
    );
