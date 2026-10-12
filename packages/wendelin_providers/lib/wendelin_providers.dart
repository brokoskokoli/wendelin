/// LLM provider adapters for Wendelin: Anthropic Messages API and
/// OpenAI-compatible Chat Completions, SSE parsing, provider templates,
/// model catalog with prices and cost calculation.
///
/// Provider wire formats stay inside `src/anthropic/` and `src/openai/`;
/// everything exported here speaks the `wendelin_core` types.
library;

export 'src/anthropic/anthropic_adapter.dart' show AnthropicMessagesAdapter;
export 'src/anthropic/anthropic_options.dart';
export 'src/catalog/cost_calculator.dart';
export 'src/catalog/model_catalog.dart';
export 'src/catalog/provider_template.dart';
export 'src/common/credentials.dart';
export 'src/common/http_settings.dart' show HttpSettings, ProviderLog;
export 'src/openai/openai_adapter.dart' show OpenAiChatAdapter;
export 'src/openai/openai_options.dart';
export 'src/provider_factory.dart';
export 'src/sse/sse_parser.dart';
