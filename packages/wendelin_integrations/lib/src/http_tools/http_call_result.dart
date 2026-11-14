import 'package:meta/meta.dart';

/// The request as it was (or would be) sent, without secrets: secret
/// header values are [redactedSecret]. For the editor preview and logs.
@immutable
final class SentRequest {
  /// Creates the description.
  SentRequest({
    required this.method,
    required this.url,
    required Map<String, String> headers,
    this.body,
  }) : headers = Map.unmodifiable(headers);

  /// Longest body kept in [body].
  static const maxBodyChars = 2000;

  /// HTTP method.
  final String method;

  /// URL of the first request (no secrets: secrets only go into headers).
  final Uri url;

  /// Headers; secret values replaced by [redactedSecret].
  final Map<String, String> headers;

  /// Body text (shortened to [maxBodyChars]), if any.
  final String? body;

  /// JSON for the editor preview.
  Map<String, Object?> toJson() => {
    'method': method,
    'url': url.toString(),
    'headers': headers,
    if (body != null) 'body': body,
  };

  @override
  String toString() => 'SentRequest($method $url)';
}

/// Outcome of [HttpToolRunner.call]. Never contains secrets.
@immutable
final class HttpCallResult {
  /// Creates a result.
  const HttpCallResult({
    required this.duration,
    this.request,
    this.finalUrl,
    this.status,
    this.reason,
    this.contentType,
    this.text = '',
    this.truncated = false,
    this.error,
    this.retryable = false,
  });

  /// What was sent (`null` if the call failed before a request was built).
  final SentRequest? request;

  /// URL of the last request (after same-origin redirects).
  final Uri? finalUrl;

  /// HTTP status, if a response arrived.
  final int? status;

  /// Reason phrase of [status], if any.
  final String? reason;

  /// MIME type of the response without parameters.
  final String? contentType;

  /// Response text (after `responsePath`), secrets scrubbed.
  final String text;

  /// Whether the body exceeded the size limit and was cut.
  final bool truncated;

  /// Time from start to finish.
  final Duration duration;

  /// German, model-safe description of a failure without usable answer.
  final String? error;

  /// The failure is transient (timeout, connection): repeating may help.
  final bool retryable;

  /// Whether the call failed ([error] or HTTP status ≥ 400).
  bool get isError => error != null || (status ?? 0) >= 400;

  @override
  String toString() =>
      'HttpCallResult(status: $status, error: $error, '
      'truncated: $truncated)';
}
