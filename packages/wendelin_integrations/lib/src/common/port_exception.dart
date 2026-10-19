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

/// Result of a failed `reconnect()` („Erneut versuchen“): the app words it
/// per [kind] and [service] in the user's language. [message] is the German
/// text for the model and logs; the UI does not show it.
final class ReconnectFailure {
  /// Creates the failure of [service] (integration id).
  const ReconnectFailure(this.service, this.kind, this.message);

  /// Failure of [service] taken from [e].
  ReconnectFailure.of(String service, PortException e)
    : this(service, e.kind, e.message);

  /// Integration id (`spotify`, `bring`, `todoist`, `gtasks`, `ha`).
  final String service;

  /// What went wrong.
  final PortErrorKind kind;

  /// German, model-safe description (not for the UI).
  final String message;

  @override
  String toString() => 'ReconnectFailure($service, ${kind.name})';
}
