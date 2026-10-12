import '../messages/chat_event.dart';
import '../messages/chat_request.dart';
import 'cancel_token.dart';
import 'model_info.dart';
import 'provider_type.dart';

/// A language model backend behind one API family.
///
/// Implementations: the adapters in `wendelin_providers` and
/// `FakeLlmProvider`. All must pass `llmProviderContract` from
/// `package:wendelin_core/testing.dart`.
abstract interface class LlmProvider {
  /// API family.
  ProviderType get type;

  /// Supported features.
  ProviderCapabilities get caps;

  /// Lists available models. Throws a [ProviderException] subclass on failure.
  Future<List<ModelInfo>> listModels();

  /// Streams the answer to [req]. See [ChatEvent] for the stream contract:
  /// failures (including cancellation through [cancel]) end the stream with
  /// an `ErrorEvent`, success with `Done`; the stream never emits errors.
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel});

  /// Checks connectivity, credentials and tool support for the setup dialog.
  /// Never throws; failures are reported as `HealthCheck(ok: false)`.
  Future<HealthCheck> test();
}
