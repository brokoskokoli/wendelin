/// LLM provider adapters for Wendelin: Anthropic Messages API and
/// OpenAI-compatible Chat Completions, SSE parsing, provider templates,
/// model catalog with prices and cost calculation.
///
/// Provider wire formats stay inside `src/anthropic/` and `src/openai/`;
/// everything exported here speaks the `wendelin_core` types.
library;

// SSE-Parser liegt seit WP22 in wendelin_core und wird hier weiter exportiert.
export 'package:wendelin_core/wendelin_core.dart' show SseEvent, SseParser;

export 'src/anthropic/anthropic_adapter.dart' show AnthropicMessagesAdapter;
export 'src/anthropic/anthropic_options.dart';
export 'src/catalog/cost_calculator.dart';
export 'src/catalog/model_catalog.dart';
export 'src/catalog/provider_template.dart';
export 'src/common/chat_wire.dart' show ChatWire, ChatWireCodec, SealedBody;
export 'src/common/credentials.dart';
export 'src/common/exchange_tap.dart' show ExchangeObserver, ExchangeRecord;
export 'src/common/http_settings.dart' show HttpSettings, ProviderLog;
export 'src/openai/openai_adapter.dart' show OpenAiChatAdapter;
export 'src/openai/openai_options.dart';
export 'src/provider_factory.dart';
export 'src/tee/attestation_crypto.dart';
export 'src/tee/attestation_log.dart';
export 'src/tee/attestation_pin_store.dart';
export 'src/tee/attestation_policy.dart';
export 'src/tee/attestation_types.dart';
export 'src/tee/attested_provider.dart' show AttestedProvider;
export 'src/tee/e2ee_v2.dart' show E2eeProtocolV2, E2eeV2Wire, PhalaE2eeChannel;
export 'src/tee/gpu_attestation.dart';
export 'src/tee/phala_verifier.dart' show PhalaVerifier;
export 'src/tee/tls_pin_gate.dart' show TlsPinGate;
export 'src/tee/tls_pinned_client.dart' show PinnedHttpClient, TlsConnect;
