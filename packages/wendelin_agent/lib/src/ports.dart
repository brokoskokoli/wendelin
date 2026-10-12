import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// One memory entry handed to the system prompt.
@immutable
final class MemoryItem {
  /// Creates an entry.
  const MemoryItem({required this.id, required this.text, this.category});

  /// Stable id.
  final String id;

  /// The remembered fact.
  final String text;

  /// Optional category (person, vorliebe, fakt, projekt).
  final String? category;

  @override
  String toString() => 'MemoryItem($id, $text)';
}

/// Finds the memory entries most relevant to a request (implemented by the
/// memory integration on top of storage).
abstract interface class MemoryRetriever {
  /// Returns at most [limit] entries relevant to [query], best first.
  Future<List<MemoryItem>> relevant(String query, {required int limit});
}

/// Supplies the recent conversation of the current session.
abstract interface class HistoryProvider {
  /// The messages of the last [turns] turns (a turn starts with a user
  /// message), oldest first. Every tool call must have its tool result.
  Future<List<Message>> recentMessages({required int turns});
}

/// Persists the messages of a run (implemented in the app via storage).
///
/// The runner calls [record] for every message that becomes part of the
/// conversation, in order: the user message, each assistant message and each
/// tool-result message. Answers that were replaced by an escalation are not
/// recorded.
abstract interface class ConversationRecorder {
  /// Stores [message].
  Future<void> record(Message message);
}

/// Estimates the cost of one model call.
abstract interface class CostEstimator {
  /// Cost of [usage] on [modelId] of [profileId] in micro-USD, or `null` if
  /// prices are unknown.
  int? estimateMicros({
    required String profileId,
    required String modelId,
    required Usage usage,
  });
}

/// Result of a [BudgetGuard] check.
enum BudgetStatus {
  /// Within budget.
  ok,

  /// Warning threshold reached; the call still happens.
  warn,

  /// Budget exhausted; the call is refused.
  block,
}

/// Answer of [BudgetGuard.check].
@immutable
final class BudgetCheck {
  /// Creates a result.
  const BudgetCheck(this.status, {this.spentMicros = 0, this.budgetMicros = 0});

  /// Within budget (amounts not needed).
  static const ok = BudgetCheck(BudgetStatus.ok);

  /// The state.
  final BudgetStatus status;

  /// Spent this month in micro-USD.
  final int spentMicros;

  /// Monthly budget in micro-USD.
  final int budgetMicros;
}

/// Checks the monthly budget of a provider profile before each model call.
abstract interface class BudgetGuard {
  /// Current budget state of [profileId].
  Future<BudgetCheck> check(String profileId);
}

/// Device information for the system prompt and the tool context.
@immutable
final class DeviceInfo {
  /// Creates the info.
  const DeviceInfo({required this.locale, required this.timeZone});

  /// Device locale as BCP 47 tag, e.g. `de-DE`.
  final String locale;

  /// Device time zone as IANA name, e.g. `Europe/Berlin`.
  final String timeZone;
}
