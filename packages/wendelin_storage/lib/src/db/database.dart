import 'package:drift/drift.dart';

import '../model/audit_entry.dart';
import '../model/memory_entry.dart';
import 'database.steps.dart';
import 'epoch_micros_converter.dart';
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
    NoteFiles,
  ],
  include: {'memory_fts.drift', 'note_fts.drift'},
)
final class WendelinDatabase extends _$WendelinDatabase {
  /// Opens the database on [executor].
  WendelinDatabase(super.executor);

  /// Current schema version. Bump it together with a migration step and a
  /// new schema dump (`dart run drift_dev make-migrations`).
  static const version = 3;

  @override
  int get schemaVersion => version;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: stepByStep(
      // v2 (WP16): Suchindex für Obsidian-Notizen.
      from1To2: (m, schema) async {
        await m.createTable(schema.noteFiles);
        await m.createTable(schema.noteFts);
      },
      // v3 (WP21): Datenschutz-Untergrenze privater Gesprächszüge.
      from2To3: (m, schema) async {
        await m.addColumn(schema.messages, schema.messages.privacyFloor);
      },
    ),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
