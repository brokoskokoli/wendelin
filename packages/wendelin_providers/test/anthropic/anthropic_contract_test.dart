import 'package:wendelin_core/testing.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';

/// Fixture answer of the Anthropic API for each contract scenario.
FakeResponse anthropicResponseFor(
  ContractScenario scenario, {
  int chunkSize = 7,
}) => switch (scenario) {
  ContractScenario.text => FakeResponse.sse(
    fixture('anthropic/text.sse'),
    chunkSize: chunkSize,
  ),
  ContractScenario.toolCall => FakeResponse.sse(
    fixture('anthropic/tool_call.sse'),
    chunkSize: chunkSize,
  ),
  ContractScenario.parallelToolCalls => FakeResponse.sse(
    fixture('anthropic/parallel_tool_calls.sse'),
    chunkSize: chunkSize,
  ),
  ContractScenario.serverError => FakeResponse.json(
    529,
    fixture('anthropic/529.json'),
  ),
  ContractScenario.authError => FakeResponse.json(
    401,
    fixture('anthropic/401.json'),
  ),
  ContractScenario.rateLimited => FakeResponse.json(
    429,
    fixture('anthropic/429.json'),
    headers: {'retry-after': '20'},
  ),
  ContractScenario.errorDuringToolCall => FakeResponse.sse(
    fixture('anthropic/error_during_tool_call.sse'),
    chunkSize: chunkSize,
  ),
  ContractScenario.hang => const FakeResponse.hang(
    'event: message_start\n'
    'data: {"type":"message_start","message":{"id":"msg_h","usage":'
    '{"input_tokens":5,"output_tokens":1}}}\n\n'
    'event: content_block_start\n'
    'data: {"type":"content_block_start","index":0,'
    '"content_block":{"type":"text","text":""}}\n\n'
    'event: content_block_delta\n'
    'data: {"type":"content_block_delta","index":0,'
    '"delta":{"type":"text_delta","text":"Ich denke"}}\n\n',
  ),
};

void main() {
  for (final chunkSize in [1, 7, 4096]) {
    llmProviderContract(
      (scenario) => AnthropicMessagesAdapter(
        credentials: Credentials.apiKey(
          'test-key-contract',
          style: ApiKeyStyle.xApiKey,
        ),
        defaultModel: 'contract-model',
        client: FakeServer([
          anthropicResponseFor(scenario, chunkSize: chunkSize),
        ]).client,
      ),
      name: 'AnthropicMessagesAdapter (Chunks à $chunkSize Byte)',
    );
  }
}
