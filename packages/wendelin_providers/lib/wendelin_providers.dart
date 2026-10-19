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
export 'src/common/chat_wire.dart'
    show BytesChatWire, ChatWire, ChatWireCodec, SealedBody, SealedBytes;
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
export 'src/tee/near/near_crypto.dart';
export 'src/tee/near/near_e2ee.dart'
    show NearE2eeChannel, NearE2eeProtocol, NearE2eeWire;
export 'src/tee/near/near_verifier.dart' show NearVerifier;
export 'src/tee/nras_jwt.dart';
export 'src/tee/phala_verifier.dart' show PhalaVerifier;
export 'src/tee/session_channel.dart'
    show ReceiptFreeVerifier, ReceiptIdSource, SessionBoundChannel;
export 'src/tee/sigstore_crypto.dart';
export 'src/tee/snp_crypto.dart';
export 'src/tee/tinfoil/ehbp_crypto.dart';
export 'src/tee/tinfoil/kds_cache.dart';
export 'src/tee/tinfoil/release_floor.dart';
export 'src/tee/tinfoil/tinfoil_ehbp.dart';
export 'src/tee/tinfoil/tinfoil_policy.dart';
export 'src/tee/tinfoil/tinfoil_verifier.dart';
export 'src/tee/tls_pin_gate.dart' show TlsPinGate;
export 'src/tee/tls_pinned_client.dart' show PinnedHttpClient, TlsConnect;
