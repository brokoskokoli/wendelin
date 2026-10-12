import 'package:drift/drift.dart' show QueryExecutor;
import 'package:wendelin_core/wendelin_core.dart';

import 'db/audit_log_repository_impl.dart';
import 'db/conversation_repository_impl.dart';
import 'db/database.dart';
import 'db/memory_repository_impl.dart';
import 'db/provider_profile_repository_impl.dart';
import 'db/settings_repository_impl.dart';
import 'db/usage_repository_impl.dart';
import 'repositories/repositories.dart';

/// Wendelin's local database (SQLite via drift) and its repositories.
///
/// The only drift type in the public API is the [QueryExecutor] passed to
/// the constructor: the app supplies one from `drift_flutter`
/// (`driftDatabase(name: 'wendelin')`), tests use `NativeDatabase.memory()`
/// (see `openInMemoryStorage` in `package:wendelin_storage/fakes.dart`).
final class WendelinStorage {
  /// Opens the storage on [executor]. [clock] supplies "now" for default
  /// timestamps and retention; [ids] creates session, message and memory
  /// ids (default: random UUIDs).
  factory WendelinStorage(
    QueryExecutor executor, {
    Clock clock = const SystemClock(),
    IdGenerator? ids,
  }) {
    final db = WendelinDatabase(executor);
    final idGen = ids ?? UuidV4Generator();
    return WendelinStorage._(
      db,
      DriftConversationRepository(db, clock, idGen),
      DriftMemoryRepository(db, clock, idGen),
      DriftAuditLogRepository(db, clock),
      DriftProviderProfileRepository(db),
      DriftUsageRepository(db, clock),
      DriftSettingsRepository(db),
    );
  }

  WendelinStorage._(
    this._db,
    this.conversations,
    this.memory,
    this.audit,
    this.providerProfiles,
    this.usage,
    this.settings,
  );

  /// Current schema version of the database.
  static const schemaVersion = WendelinDatabase.version;

  final WendelinDatabase _db;

  /// Sessions and messages.
  final ConversationRepository conversations;

  /// Long-term memory.
  final MemoryRepository memory;

  /// Audit log.
  final AuditLogRepository audit;

  /// Provider profiles.
  final ProviderProfileRepository providerProfiles;

  /// Token usage and cost.
  final UsageRepository usage;

  /// Typed settings.
  final SettingsRepository settings;

  /// Closes the database.
  Future<void> close() => _db.close();
}
