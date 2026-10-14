import 'package:meta/meta.dart';

/// Base of all errors a provider reports.
///
/// Adapters map HTTP and stream errors onto these subclasses. [message] is
/// meant for logs and the UI and must **never** contain secrets (API keys,
/// auth headers).
@immutable
sealed class ProviderException implements Exception {
  const ProviderException(this.message);

  /// Human-readable, secret-free description.
  final String message;

  /// Whether retrying (or escalating to another provider) may help.
  bool get retryable;

  @override
  bool operator ==(Object other) =>
      other is ProviderException &&
      other.runtimeType == runtimeType &&
      other.message == message;

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Credentials missing, invalid or not permitted (HTTP 401/403).
final class AuthException extends ProviderException {
  /// Creates the exception.
  const AuthException(super.message);

  @override
  bool get retryable => false;
}

/// Rate limit hit (HTTP 429).
final class RateLimitException extends ProviderException {
  /// Creates the exception; [retryAfter] from the `retry-after` header.
  const RateLimitException(super.message, {this.retryAfter});

  /// How long the provider asks to wait, if known.
  final Duration? retryAfter;

  @override
  bool get retryable => true;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is RateLimitException &&
      other.retryAfter == retryAfter;

  @override
  int get hashCode => Object.hash(super.hashCode, retryAfter);
}

/// Request or stream timed out (HTTP 408/504 or client timeout).
final class ProviderTimeoutException extends ProviderException {
  /// Creates the exception.
  const ProviderTimeoutException(super.message);

  @override
  bool get retryable => true;
}

/// Connection failed (DNS, TLS, socket closed, offline).
final class NetworkException extends ProviderException {
  /// Creates the exception.
  const NetworkException(super.message);

  @override
  bool get retryable => true;
}

/// The provider answered with an unexpected HTTP status (typically 5xx or
/// 529 "overloaded"), or reported a server error inside the stream.
final class ServerException extends ProviderException {
  /// Creates the exception.
  const ServerException(super.message, {required this.statusCode});

  /// HTTP status code (for in-stream errors the adapter's best mapping).
  final int statusCode;

  /// Server-side failures (>= 500) are retryable, others not.
  @override
  bool get retryable => statusCode >= 500;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is ServerException &&
      other.statusCode == statusCode;

  @override
  int get hashCode => Object.hash(super.hashCode, statusCode);
}

/// The request was rejected as invalid (HTTP 400, unknown model, …).
final class InvalidRequestException extends ProviderException {
  /// Creates the exception.
  const InvalidRequestException(super.message);

  @override
  bool get retryable => false;
}

/// The call was cancelled via `CancelToken`.
final class CancelledException extends ProviderException {
  /// Creates the exception.
  const CancelledException([super.message = 'Abgebrochen']);

  @override
  bool get retryable => false;
}

/// The provider sent something that could not be parsed.
final class MalformedResponseException extends ProviderException {
  /// Creates the exception.
  const MalformedResponseException(super.message);

  @override
  bool get retryable => false;
}

/// A TEE provider could not be attested or its receipt was invalid (WP46).
///
/// Nothing was sent to the provider when this is raised before a request;
/// [stage] names the failed check (`quote`, `receipt.signature`, `gpu`, …).
/// Retryable only when the check could not be completed (network), not when
/// it failed. Never a reason to hand the request to another provider.
final class AttestationFailedException extends ProviderException {
  /// Creates the exception.
  const AttestationFailedException(
    super.message, {
    required this.stage,
    this.unavailable = false,
  });

  /// Stable name of the failed check stage (secret-free).
  final String stage;

  /// The check could not be completed (e.g. network), as opposed to failed.
  final bool unavailable;

  @override
  bool get retryable => unavailable;
}
