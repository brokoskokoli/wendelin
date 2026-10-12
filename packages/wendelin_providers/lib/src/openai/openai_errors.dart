import 'package:wendelin_core/wendelin_core.dart';

import '../common/http_errors.dart';
import '../common/json_util.dart';

/// Maps an OpenAI `finish_reason`. A plain `stop` with pending tool calls
/// (seen on some compatible servers) counts as tool use.
StopReason mapOpenAiFinishReason(String? reason, {required bool hasToolCalls}) {
  final mapped = switch (reason) {
    'stop' || null => StopReason.endTurn,
    'tool_calls' || 'function_call' => StopReason.toolUse,
    'length' => StopReason.maxTokens,
    'content_filter' => StopReason.refusal,
    _ => StopReason.other,
  };
  return hasToolCalls && mapped == StopReason.endTurn
      ? StopReason.toolUse
      : mapped;
}

/// Maps an error object (`{"message", "type", "code"}`) from a response body
/// or an in-stream `error` chunk. [status] is the HTTP status, if any.
ProviderException openAiError(
  Map<String, Object?>? error, {
  required String label,
  int? status,
  Duration? retryAfter,
}) {
  final message =
      asString(error?['message']) ??
      asString(error?['type']) ??
      'unbekannter Fehler';
  final type = asString(error?['type']) ?? '';
  final code = error?['code'];
  final codeText = code is String ? code : '';
  if (codeText == 'insufficient_quota') {
    return AuthException('$label: Kein Guthaben – $message');
  }
  final effective =
      status ??
      (code is int ? code : null) ??
      switch ('$type $codeText') {
        final s when s.contains('rate_limit') => 429,
        final s
            when s.contains('auth') ||
                s.contains('invalid_api_key') ||
                s.contains('permission') =>
          401,
        final s when s.contains('invalid_request') => 400,
        final s when s.contains('timeout') => 504,
        _ => 500,
      };
  return exceptionForStatus(
    effective,
    label: label,
    detail: message,
    retryAfter: retryAfter,
  );
}

/// Whether a 400 response complains about `stream_options`, i.e. the
/// server does not support `include_usage`.
bool rejectsStreamOptions(int status, String body) =>
    status == 400 &&
    (body.contains('stream_options') || body.contains('include_usage'));
