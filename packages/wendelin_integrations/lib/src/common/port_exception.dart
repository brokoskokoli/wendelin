/// Category of a [PortException].
enum PortErrorKind {
  /// The OS permission is missing (calendar access, clipboard in background).
  permissionDenied,

  /// The addressed item (event, calendar, memory entry, alarm) does not
  /// exist.
  notFound,

  /// The target is read-only (e.g. a subscribed calendar).
  readOnly,

  /// The device or platform does not support the operation.
  unsupported,

  /// The input was refused on purpose (e.g. sensitive memory content).
  rejected,

  /// A remote service is unreachable, rate limited or misconfigured.
  unavailable,

  /// Any other failure.
  failed,
}

/// Expected failure of a port (device or backend access).
///
/// Tools turn it into an error outcome with [message] for the model, so the
/// message must be German, short and free of secrets and stack traces.
final class PortException implements Exception {
  /// Creates a port exception.
  const PortException(this.kind, this.message);

  /// What went wrong.
  final PortErrorKind kind;

  /// German, model-safe description.
  final String message;

  @override
  String toString() => 'PortException(${kind.name}): $message';
}
