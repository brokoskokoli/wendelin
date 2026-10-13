import '../provider/cancel_token.dart';
import '../provider/privacy_level.dart';
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
    this.privacyLevel,
    this.privacyFloor,
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

  /// Privacy level of the model the calls come from, if known. Invokers
  /// that serve several levels look tools up in the catalog of this level
  /// (a standard target never reaches a sensitive tool, also not through
  /// `tools__search`). `null` = the invoker's default catalog.
  final PrivacyLevel? privacyLevel;

  /// Privacy floor of the run the calls come from (a private or tainted
  /// run), if any. Tools that persist content for later turns (e.g.
  /// `memory__save`) store it with this floor so weaker targets never see
  /// it.
  final PrivacyLevel? privacyFloor;
}
