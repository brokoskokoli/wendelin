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
