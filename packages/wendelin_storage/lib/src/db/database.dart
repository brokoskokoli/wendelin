import 'package:drift/drift.dart';

import '../model/audit_entry.dart';
import '../model/memory_entry.dart';
import 'tables.dart';

part 'database.g.dart';

/// The drift database (internal; the public API is `WendelinStorage`).
@DriftDatabase(
  tables: [
    Sessions,
    Messages,
    MemoryEntries,
    AuditLog,
    ProviderProfiles,
    UsageRecords,
    Settings,
  ],
  include: {'memory_fts.drift'},
)
final class WendelinDatabase extends _$WendelinDatabase {
  /// Opens the database on [executor].
  WendelinDatabase(super.executor);

  /// Current schema version. Bump it together with a migration step and a
  /// new schema dump (`dart run drift_dev make-migrations`).
  static const version = 1;

  @override
  int get schemaVersion => version;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
