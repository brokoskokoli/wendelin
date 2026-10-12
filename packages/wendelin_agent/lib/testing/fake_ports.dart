import 'package:wendelin_core/wendelin_core.dart';

import '../wendelin_agent.dart';

/// [MemoryRetriever] returning a fixed list (ignores the query).
final class FixedMemoryRetriever implements MemoryRetriever {
  /// Creates a retriever over [items].
  FixedMemoryRetriever(List<MemoryItem> items)
    : items = List.unmodifiable(items);

  /// The entries.
  final List<MemoryItem> items;

  /// Queries received.
  final List<String> queries = [];

  @override
  Future<List<MemoryItem>> relevant(String query, {required int limit}) async {
    queries.add(query);
    return items.take(limit).toList();
  }
}

/// [HistoryProvider] and [ConversationRecorder] over an in-memory list.
///
/// [recentMessages] returns the messages of the last `turns` turns, a turn
/// starting with a user message that carries text.
final class InMemoryConversation
    implements HistoryProvider, ConversationRecorder {
  /// Creates a conversation with [initial] messages.
  InMemoryConversation([List<Message> initial = const []])
    : messages = List.of(initial);

  /// All messages, oldest first.
  final List<Message> messages;

  @override
  Future<void> record(Message message) async => messages.add(message);

  @override
  Future<List<Message>> recentMessages({required int turns}) async {
    if (turns <= 0) return const [];
    var seen = 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == Role.user && ++seen == turns) {
        return messages.sublist(i);
      }
    }
    return List.of(messages);
  }
}

/// [BudgetGuard] with a settable [status]; records the checked profiles.
final class FixedBudgetGuard implements BudgetGuard {
  /// Creates a guard answering [status].
  FixedBudgetGuard([this.status = BudgetStatus.ok]);

  /// Answer of [check].
  BudgetStatus status;

  /// Profiles checked, in order.
  final List<String> checked = [];

  @override
  Future<BudgetStatus> check(String profileId) async {
    checked.add(profileId);
    return status;
  }
}

/// [CostEstimator] with flat prices per million tokens (micro-USD).
final class FlatCostEstimator implements CostEstimator {
  /// Creates an estimator; prices are micro-USD per million tokens.
  const FlatCostEstimator({
    this.inputPerMillion = 1000000,
    this.outputPerMillion = 5000000,
  });

  /// Price of one million input tokens (all input kinds).
  final int inputPerMillion;

  /// Price of one million output tokens.
  final int outputPerMillion;

  @override
  int? estimateMicros({
    required String profileId,
    required String modelId,
    required Usage usage,
  }) =>
      ((usage.inputTokens + usage.cachedInputTokens + usage.cacheWriteTokens) *
              inputPerMillion +
          usage.outputTokens * outputPerMillion) ~/
      1000000;
}
