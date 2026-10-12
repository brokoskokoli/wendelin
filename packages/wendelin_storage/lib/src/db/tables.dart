// Table declarations are drift DSL read only by the code generator; the
// getters never run.
// coverage:ignore-file
import 'package:drift/drift.dart';

import '../model/audit_entry.dart';
import '../model/memory_entry.dart';
import 'epoch_micros_converter.dart';

/// Conversation sessions.
@TableIndex(name: 'sessions_last_activity', columns: {#lastActivityAt})
@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get id => text()();
  IntColumn get startedAt => integer().map(epochMicros)();
  IntColumn get lastActivityAt => integer().map(epochMicros)();
  TextColumn get title => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Messages of a session in order of [seq].
@TableIndex(
  name: 'messages_session_seq',
  columns: {#sessionId, #seq},
  unique: true,
)
@DataClassName('MessageRow')
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get seq => integer()();
  TextColumn get role => text()();

  /// `Message.toJson()['content']`, JSON-encoded.
  TextColumn get contentJson => text()();
  IntColumn get createdAt => integer().map(epochMicros)();
  TextColumn get profileId => text().nullable()();
  TextColumn get modelId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Long-term memory; mirrored into the FTS5 table `memory_fts` by triggers
/// (see `memory_fts.drift`).
@DataClassName('MemoryRow')
class MemoryEntries extends Table {
  TextColumn get id => text()();

  /// The remembered text. Named `body` (not `text`) because drift's
  /// schema-dump code generator cannot name a column getter `text`.
  TextColumn get body => text()();
  TextColumn get category => textEnum<MemoryCategory>()();
  TextColumn get source => text()();
  IntColumn get createdAt => integer().map(epochMicros)();
  IntColumn get lastUsedAt => integer().map(epochMicros)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Audit log (redacted before insert).
@TableIndex(name: 'audit_log_at', columns: {#at})
@DataClassName('AuditRow')
class AuditLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get at => integer().map(epochMicros)();
  TextColumn get kind => textEnum<AuditKind>()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get payloadJson => text()();
}

/// Serialised `ProviderProfile`s (no secrets).
@DataClassName('ProfileRow')
class ProviderProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get json => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Token usage and cost per model call (or agent run).
///
/// No foreign key to `sessions`: costs must survive the retention purge of
/// conversations.
@TableIndex(name: 'usage_records_profile_at', columns: {#profileId, #at})
@TableIndex(name: 'usage_records_at', columns: {#at})
@DataClassName('UsageRow')
class UsageRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get at => integer().map(epochMicros)();
  TextColumn get sessionId => text()();
  TextColumn get profileId => text()();
  TextColumn get modelId => text()();
  IntColumn get inputTokens => integer()();
  IntColumn get outputTokens => integer()();
  IntColumn get cachedTokens => integer()();
  IntColumn get cacheWriteTokens => integer()();
  IntColumn get costMicros => integer()();
}

/// Key/value settings, values JSON-encoded.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
