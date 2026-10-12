import 'package:wendelin_core/testing.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';

/// Fixture answer of an OpenAI-compatible server for each contract
/// scenario.
FakeResponse openAiResponseFor(
  ContractScenario scenario, {
  int chunkSize = 7,
}) => switch (scenario) {
  ContractScenario.text => FakeResponse.sse(
    fixture('openai/text.sse'),
    chunkSize: chunkSize,
  ),
  ContractScenario.toolCall => FakeResponse.sse(
    fixture('openai/tool_call.sse'),
    chunkSize: chunkSize,
  ),
  ContractScenario.parallelToolCalls => FakeResponse.sse(
    fixture('openai/parallel_tool_calls.sse'),
    chunkSize: chunkSize,
  ),
  ContractScenario.serverError => FakeResponse.json(
    500,
    fixture('openai/500.json'),
  ),
  ContractScenario.authError => FakeResponse.json(
    401,
    fixture('openai/401.json'),
  ),
  ContractScenario.rateLimited => FakeResponse.json(
    429,
    fixture('openai/429.json'),
    headers: {'retry-after-ms': '1500'},
  ),
  ContractScenario.errorDuringToolCall => FakeResponse.sse(
    fixture('openai/error_during_tool_call.sse'),
    chunkSize: chunkSize,
  ),
  ContractScenario.hang => const FakeResponse.hang(
    'data: {"choices":[{"index":0,"delta":{"content":"Ich denke"}}]}\n\n',
  ),
};

void main() {
  for (final chunkSize in [1, 7, 4096]) {
    llmProviderContract(
      (scenario) => OpenAiChatAdapter(
        baseUrl: Uri.parse('https://api.openai.com/v1'),
        credentials: Credentials.apiKey(
          'test-key-contract',
          style: ApiKeyStyle.bearer,
        ),
        defaultModel: 'contract-model',
        client: FakeServer([openAiResponseFor(scenario, chunkSize: chunkSize)])
            .client,
      ),
      name: 'OpenAiChatAdapter (Chunks à $chunkSize Byte)',
    );
  }
}
