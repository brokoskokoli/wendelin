import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// [HistoryProvider] and [ConversationRecorder] of one session in the local
/// database.
final class StorageConversation
    implements HistoryProvider, ConversationRecorder {
  /// Creates the adapter for [sessionId].
  StorageConversation(this.repository, this.sessionId);

  /// Sessions and messages.
  final ConversationRepository repository;

  /// The session.
  final String sessionId;

  @override
  Future<List<Message>> recentMessages({required int turns}) async => [
    for (final m in await repository.lastTurns(sessionId, turns)) m.message,
  ];

  @override
  Future<void> record(Message message) async {
    await repository.append(sessionId, message);
  }
}

/// [MemoryRetriever] on the memory repository (FTS5 search).
final class StorageMemoryRetriever implements MemoryRetriever {
  /// Creates the retriever.
  StorageMemoryRetriever(this.repository);

  /// Long-term memory.
  final MemoryRepository repository;

  @override
  Future<List<MemoryItem>> relevant(String query, {required int limit}) async {
    final hits = await repository.search(query, limit: limit);
    return [
      for (final e in hits)
        MemoryItem(
          id: e.id,
          text: e.text,
          category: e.category.name,
          privacyFloor: e.privacyFloor,
        ),
    ];
  }
}
