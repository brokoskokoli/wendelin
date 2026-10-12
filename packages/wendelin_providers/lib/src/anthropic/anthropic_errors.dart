import 'package:wendelin_core/wendelin_core.dart';

import '../common/http_errors.dart';
import '../common/json_util.dart';

const _label = 'Anthropic';

/// Maps an Anthropic `stop_reason`.
StopReason mapAnthropicStopReason(String reason) => switch (reason) {
  'end_turn' => StopReason.endTurn,
  'tool_use' => StopReason.toolUse,
  'max_tokens' || 'model_context_window_exceeded' => StopReason.maxTokens,
  'stop_sequence' => StopReason.stopSequence,
  'pause_turn' => StopReason.pauseTurn,
  'refusal' => StopReason.refusal,
  _ => StopReason.other,
};

/// HTTP status equivalent of an Anthropic error `type`.
int _statusForType(String? type) => switch (type) {
  'invalid_request_error' => 400,
  'authentication_error' => 401,
  'billing_error' => 402,
  'permission_error' => 403,
  'not_found_error' => 404,
  'request_too_large' => 413,
  'rate_limit_error' => 429,
  'timeout_error' => 504,
  'overloaded_error' => 529,
  _ => 500, // api_error and unknown types
};

/// Maps an in-stream `error` event (`{"type": "...", "message": "..."}`).
ProviderException anthropicStreamError(Map<String, Object?>? error) {
  final type = asString(error?['type']);
  final message = asString(error?['message']) ?? type ?? 'unbekannter Fehler';
  return exceptionForStatus(
    _statusForType(type),
    label: _label,
    detail: message,
  );
}

/// Maps a non-2xx HTTP response of the Anthropic API.
ProviderException anthropicHttpError(
  int status,
  String body,
  Duration? retryAfter,
) => exceptionForStatus(
  status,
  label: _label,
  detail: errorDetail(body),
  retryAfter: retryAfter,
);
