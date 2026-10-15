import 'package:wendelin_core/wendelin_core.dart';

import '../model/attestation_record.dart';
import '../model/audit_entry.dart';
import '../model/conversation.dart';
import '../model/note_search_hit.dart';
import '../model/setting_key.dart';
import '../model/stored_memory.dart';
import '../model/usage_record.dart';

/// Conversation sessions and their messages.
abstract interface class ConversationRepository {
  /// Default inactivity after which a session ends (concept: 5 min).
  static const defaultInactivity = Duration(minutes: 5);

  /// The most recently active session if its last activity is less than
  /// [inactivity] before [now]; otherwise a new session started at [now].
  /// Only sessions of the same [origin] count (WP67).
  Future<Session> currentOrNew(
    DateTime now, {
    Duration inactivity = defaultInactivity,
    SessionOrigin origin = SessionOrigin.app,
  });

  /// Starts a new session at [now] ("neues Thema").
  Future<Session> startNew(
    DateTime now, {
    String? title,
    SessionOrigin origin = SessionOrigin.app,
  });

  /// The session with [id], or `null`.
  Future<Session?> session(String id);

  /// Sessions, most recently active first; only those of [origin] if given.
  Future<List<Session>> sessions({int? limit, SessionOrigin? origin});

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
  /// Stores a new entry (with [privacyFloor] of a private run).
  Future<StoredMemory> save(
    String text, {
    required StoredMemoryCategory category,
    required String source,
    PrivacyLevel? privacyFloor,
  });

  /// Changes text and/or category of entry [id]; returns the updated entry
  /// or `null` if it does not exist.
  Future<StoredMemory?> update(
    String id, {
    String? text,
    StoredMemoryCategory? category,
  });

  /// Removes the privacy floor of entry [id] (the user confirmed that the
  /// entry may reach every target); returns the updated entry or `null` if
  /// it does not exist.
  Future<StoredMemory?> clearPrivacyFloor(String id);

  /// Deletes entry [id]; returns whether it existed.
  Future<bool> forget(String id);

  /// The entry with [id], or `null`.
  Future<StoredMemory?> get(String id);

  /// All entries (optionally of one [category]), newest first.
  Future<List<StoredMemory>> list({StoredMemoryCategory? category});

  /// Up to [limit] entries matching [query], most relevant first (FTS5
  /// bm25). Words are matched as prefixes and combined with OR; FTS syntax
  /// in [query] has no effect. Updates `lastUsedAt` of the returned entries.
  Future<List<StoredMemory>> search(String query, {int limit = 5});

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

/// Verification log (Prüfprotokoll) of the TEE attestation. Holds ids,
/// hashes and stage results only. Removed by „Alles löschen“ and by the
/// retention period.
abstract interface class AttestationLogRepository {
  /// Default retention (30 days, like the audit log).
  static const defaultRetention = Duration(days: 30);

  /// Stores [record]; a record with the same `logId` is replaced.
  Future<void> add(AttestationRecord record);

  /// Sets session and step of the record [logId] (they come with the agent
  /// event, after the record was written). `false` if there is no such
  /// record.
  Future<bool> attachStep(String logId, String sessionId, String stepId);

  /// The record with [logId], or `null`.
  Future<AttestationRecord?> byLogId(String logId);

  /// Records of [sessionId], oldest first.
  Future<List<AttestationRecord>> forSession(String sessionId);

  /// Records of the conversation step [stepId], oldest first.
  Future<List<AttestationRecord>> forStep(String stepId);

  /// The newest [limit] records, newest first.
  Future<List<AttestationRecord>> latest({int limit = 50});

  /// Deletes records older than [maxAge]; returns the number deleted.
  Future<int> purgeOlderThan([Duration maxAge = defaultRetention]);

  /// Deletes all records.
  Future<void> deleteAll();

  /// `{"version": 1, "entries": [...]}`, oldest first.
  Future<String> exportJson();
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

/// One note for [NoteIndexRepository.upsertAll]; the same record shape as
/// `IndexedNote` of `wendelin_integrations`.
typedef NoteIndexEntry = ({
  String path,
  String title,
  String body,
  DateTime modifiedAt,
});

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

  /// Adds or replaces all [notes] in one transaction (index sync).
  Future<void> upsertAll(List<NoteIndexEntry> notes);

  /// Removes [path]; no error if it is not indexed.
  Future<void> remove(String path);

  /// The best [limit] notes for [query] (bm25: title ×10, path ×2 so folder
  /// names are searchable, body ×1): every
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
