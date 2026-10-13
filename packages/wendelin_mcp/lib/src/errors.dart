import 'package:meta/meta.dart';

/// What went wrong in an MCP exchange.
enum McpErrorKind {
  /// Connection failed (DNS, refused, reset, TLS).
  network,

  /// The server wants (other) credentials: 401/403, missing secret, expired
  /// token that cannot be renewed, failed OAuth step.
  authRequired,

  /// The server broke the protocol (no JSON-RPC, wrong content type,
  /// missing fields, unsupported protocol version).
  protocol,

  /// The server answered with a JSON-RPC error or an HTTP error status.
  server,

  /// Connect or response time limit exceeded.
  timeout,

  /// Cancelled by the caller (`CancelToken`).
  cancelled,

  /// The response exceeded the size limit.
  tooLarge,

  /// The target was refused by the network rules (scheme, credentials in
  /// the URL, redirect to another origin).
  rejected,

  /// The server no longer knows the session (HTTP 404 with a session id);
  /// the client re-initializes once by itself.
  sessionExpired,
}

/// Error of the MCP client. [message] is German, meant for logs and the UI,
/// and never contains secrets (tokens, header values).
@immutable
final class McpException implements Exception {
  /// Creates the exception.
  const McpException(
    this.kind,
    this.message, {
    this.statusCode,
    this.rpcCode,
    this.challenge,
  });

  /// Category of the failure.
  final McpErrorKind kind;

  /// Secret-free description.
  final String message;

  /// HTTP status, if the failure came from one.
  final int? statusCode;

  /// JSON-RPC error code, for [McpErrorKind.server] errors from the server.
  final int? rpcCode;

  /// The `WWW-Authenticate` header of a 401/403 (input for OAuth
  /// discovery; contains no secrets).
  final String? challenge;

  /// Whether trying again later may help.
  bool get retryable => switch (kind) {
    McpErrorKind.network ||
    McpErrorKind.timeout ||
    McpErrorKind.sessionExpired => true,
    McpErrorKind.server => statusCode != null && statusCode! >= 500,
    _ => false,
  };

  /// Copy with [message] replaced (used for redaction).
  McpException withMessage(String message) => McpException(
    kind,
    message,
    statusCode: statusCode,
    rpcCode: rpcCode,
    challenge: challenge,
  );

  @override
  bool operator ==(Object other) =>
      other is McpException &&
      other.kind == kind &&
      other.message == message &&
      other.statusCode == statusCode &&
      other.rpcCode == rpcCode;

  @override
  int get hashCode => Object.hash(kind, message, statusCode, rpcCode);

  @override
  String toString() => 'McpException(${kind.name}): $message';
}
