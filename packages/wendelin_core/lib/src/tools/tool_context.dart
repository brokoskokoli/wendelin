import '../provider/cancel_token.dart';
import '../util/clock.dart';

/// Environment passed to `Tool.execute`.
final class ToolContext {
  /// Creates a tool context.
  ToolContext({
    required this.sessionId,
    required this.clock,
    required this.locale,
    required this.timeZone,
    CancelToken? cancel,
  }) : cancel = cancel ?? CancelToken();

  /// Current conversation session.
  final String sessionId;

  /// Time source (never call `DateTime.now()` in tools).
  final Clock clock;

  /// Device locale as BCP 47 tag, e.g. `de-DE`.
  final String locale;

  /// Device time zone as IANA name, e.g. `Europe/Berlin`.
  final String timeZone;

  /// Cancelled when the user aborts the run; long tools should check it.
  final CancelToken cancel;
}
