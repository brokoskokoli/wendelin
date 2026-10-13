import 'package:wendelin_core/wendelin_core.dart';

import '../model/audit_entry.dart';
import '../model/conversation.dart';
import '../model/memory_entry.dart';
import '../model/note_search_hit.dart';
import '../model/setting_key.dart';
import '../model/usage_record.dart';

/// Conversation sessions and their messages.
abstract interface class ConversationRepository {
  /// Default inactivity after which a session ends (concept: 5 min).
  static const defaultInactivity = Duration(minutes: 5);

  /// The most recently active session if its last activity is less than
  /// [inactivity] before [now]; otherwise a new session started at [now].
  Future<Session> currentOrNew(
    DateTime now, {
    Duration inactivity = defaultInactivity,
  });

  /// Starts a new session at [now] ("neues Thema").
  Future<Session> startNew(DateTime now, {String? title});

  /// The session with [id], or `null`.
  Future<Session?> session(String id);

  /// Sessions, most recently active first.
  Future<List<Session>> sessions({int? limit});

  /// Sets or clears the title of session [id].
  Future<void> setTitle(String id, String? title);

  /// Appends [message] to session [sessionId] at time [at] (default: now)
  /// and updates the session's last activity. Throws [ArgumentError] if the
  /// session does not exist.
  Future<StoredMessage> append(
    String sessionId,
    Message message, {
    DateTime? at,
    String? profileId,
    String? modelId,
  });

  /// All messages of session [sessionId] in order.
  Future<List<StoredMessage>> messages(String sessionId);

  /// The last [turns] turns of session [sessionId] in order. A turn starts
  /// with a [Role.user] message and contains everything up to the next one,
  /// so tool calls and their results are never split.
  Future<List<StoredMessage>> lastTurns(String sessionId, int turns);

  /// Deletes session [id] with its messages.
  Future<void> deleteSession(String id);

  /// Deletes sessions whose last activity is older than [maxAge]; returns
  /// the number of deleted sessions.
  Future<int> purgeOlderThan(Duration maxAge);
}

/// Long-term memory with full-text search.
///
/// [save] and [update] reject sensitive content (card numbers, IBANs,
/// passwords/PINs) with a `SensitiveContentException`.
abstract interface class MemoryRepository {
  /// Stores a new entry.
  Future<MemoryEntry> save(
    String text, {
    required MemoryCategory category,
    required String source,
  });

  /// Changes text and/or category of entry [id]; returns the updated entry
  /// or `null` if it does not exist.
  Future<MemoryEntry?> update(
    String id, {
    String? text,
    MemoryCategory? category,
  });

  /// Deletes entry [id]; returns whether it existed.
  Future<bool> forget(String id);

  /// The entry with [id], or `null`.
  Future<MemoryEntry?> get(String id);

  /// All entries (optionally of one [category]), newest first.
  Future<List<MemoryEntry>> list({MemoryCategory? category});

  /// Up to [limit] entries matching [query], most relevant first (FTS5
  /// bm25). Words are matched as prefixes and combined with OR; FTS syntax
  /// in [query] has no effect. Updates `lastUsedAt` of the returned entries.
  Future<List<MemoryEntry>> search(String query, {int limit = 5});

  /// All entries as Markdown, grouped by category.
  Future<String> exportMarkdown();
}

/// Audit log (concept: Logging). Entries are redacted before storing.
abstract interface class AuditLogRepository {
  /// Default retention (concept: 30 days).
  static const defaultRetention = Duration(days: 30);

  /// Stores [entry] with secret-looking payload fields replaced by `***`;
  /// returns the stored (redacted) entry with its id.
  Future<AuditEntry> record(AuditEntry entry);

  /// Entries matching [filter], newest first.
  Future<List<AuditEntry>> query([AuditFilter filter = const AuditFilter()]);

  /// Deletes entries older than [maxAge]; returns the number deleted.
  Future<int> purgeOlderThan([Duration maxAge = defaultRetention]);

  /// All entries as a JSON array, oldest first.
  Future<String> exportJson();

  /// Deletes all entries.
  Future<void> clear();
}

/// Provider profiles (stored without secrets) and the default profile.
abstract interface class ProviderProfileRepository {
  /// Inserts or replaces [profile]. Throws [ArgumentError] if a non-secret
  /// field (`extraHeaders`, `options`) has a key that looks like a secret;
  /// those belong in the `SecretStore`.
  Future<void> save(ProviderProfile profile);

  /// The profile with [id], or `null`.
  Future<ProviderProfile?> get(String id);

  /// All profiles in insertion order.
  Future<List<ProviderProfile>> list();

  /// Deletes profile [id] (and clears the default if it was the default);
  /// returns whether it existed.
  Future<bool> delete(String id);

  /// Makes profile [id] the default. Throws [ArgumentError] if unknown.
  Future<void> setDefault(String id);

  /// The default profile, or `null` if none is set.
  Future<ProviderProfile?> defaultProfile();
}

/// Token usage and cost.
abstract interface class UsageRepository {
  /// Stores a record (at [at], default: now).
  Future<UsageRecord> record({
    required String sessionId,
    required String profileId,
    required String modelId,
    required Usage usage,
    required int costMicros,
    DateTime? at,
  });

  /// Totals per local day, oldest first, only days with records.
  Future<List<UsageTotals>> totalsByDay({
    String? profileId,
    DateTime? from,
    DateTime? until,
  });

  /// Totals per local month, oldest first, only months with records.
  Future<List<UsageTotals>> totalsByMonth({
    String? profileId,
    DateTime? from,
    DateTime? until,
  });

  /// Cost of [profileId] since the start of the current local month, for
  /// the budget check.
  Future<int> monthToDateCostMicros(String profileId);
}

/// Typed settings stored as JSON.
abstract interface class SettingsRepository {
  /// The stored value of [key], or its default. Throws [FormatException] if
  /// the stored value does not match the key's type.
  Future<T?> get<T extends Object>(SettingKey<T> key);

  /// Stores [value] under [key].
  Future<void> set<T extends Object>(SettingKey<T> key, T value);

  /// Removes [key] (afterwards [get] returns the default).
  Future<void> remove(SettingKey<Object> key);
}

/// Full-text index over the notes of the Obsidian vault (SQLite FTS5).
///
/// Mirrors `NoteIndexPort` of `wendelin_integrations` method by method;
/// storage must not depend on integrations, so the app adapts it
/// (`RepositoryNoteIndexPort`) like `MemoryRepository` → `MemoryStorePort`.
abstract interface class NoteIndexRepository {
  /// Adds or replaces the note [path] (title, text, modification time).
  Future<void> upsert(
    String path, {
    required String title,
    required String body,
    required DateTime modifiedAt,
  });

  /// Removes [path]; no error if it is not indexed.
  Future<void> remove(String path);

  /// The best [limit] notes for [query] (bm25, title weighted ×10): every
  /// word with at least two characters that is not a stop word is a
  /// prefix term, terms are OR-ed; case and diacritics are ignored.
  Future<List<NoteSearchHit>> search(String query, {int limit = 10});

  /// Indexed paths with the modification time they were indexed at.
  Future<Map<String, DateTime>> knownFiles();

  /// Number of indexed notes.
  Future<int> count();

  /// Empties the index (e.g. after choosing another vault).
  Future<void> clear();
}
