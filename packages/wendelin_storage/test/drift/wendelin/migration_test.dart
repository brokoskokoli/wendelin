// Migration tests against the checked-in schema dumps in drift_schemas/.
//
// When the schema changes:
// 1. bump WendelinDatabase.version and add the step in `migration`
//    (`onUpgrade: stepByStep(...)`),
// 2. run `dart run drift_dev make-migrations` (writes
//    drift_schemas/wendelin/drift_schema_vN.json and test/drift/wendelin/
//    generated/, plus lib/src/db/database.steps.dart),
// 3. add an upgrade test below (`verifier.migrateAndValidate(db, N)` on a
//    connection from `verifier.schemaAt(N - 1)`), ideally with data from
//    `generated/schema_v<N-1>.dart` that must survive the upgrade.
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:test/test.dart';
import 'package:wendelin_storage/src/db/database.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'generated/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('aktuelle Schema-Version ist eingecheckt', () {
    expect(GeneratedHelper.versions.last, WendelinDatabase.version);
    expect(WendelinDatabase.version, 2);
  });

  test('neue Datenbank entspricht dem Schema-Dump v2', () async {
    final schema = await verifier.schemaAt(2);
    final db = WendelinDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);
  });

  test('Upgrade v1 → v2 legt den Notizindex an, Daten bleiben', () async {
    final schema = await verifier.schemaAt(1);
    final raw = schema.rawDatabase;
    raw
      ..execute(
        'INSERT INTO sessions (id, started_at, last_activity_at, title) '
        "VALUES ('s1', 1, 2, 'Alt')",
      )
      ..execute(
        'INSERT INTO memory_entries (id, body, category, source, created_at, '
        "last_used_at) VALUES ('m1', 'Taucht gern auf Malta', 'preference', "
        "'session:s1', 1, 1)",
      )
      ..execute("INSERT INTO settings (key, value_json) VALUES ('k', '\"v\"')");
    final db = WendelinDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    await db.close();

    // Mit der echten Storage-Schicht auf der migrierten Datei weiterarbeiten.
    final storage = WendelinStorage(schema.newConnection());
    addTearDown(storage.close);
    expect((await storage.conversations.session('s1'))?.title, 'Alt');
    final memory = await storage.memory.search('Malta');
    expect(memory.single.id, 'm1');
    expect(await storage.notes.count(), 0);
    await storage.notes.upsert(
      'Reisen/Malta.md',
      title: 'Malta',
      body: 'Tauchen in Sliema',
      modifiedAt: DateTime.utc(2026, 10, 13),
    );
    expect(
      (await storage.notes.search('Sliema')).single.path,
      'Reisen/Malta.md',
    );
    // FTS-Trigger des Gedächtnisses arbeiten nach dem Upgrade weiter.
    await storage.memory.forget('m1');
    expect(await storage.memory.search('Malta'), isEmpty);
  });

  test('Schema-Dump v2 enthält FTS5-Tabellen und Trigger', () async {
    final schema = await verifier.schemaAt(2);
    final names = schema.rawDatabase
        .select(
          "SELECT name FROM sqlite_master WHERE type IN ('table','trigger')",
        )
        .map((r) => r['name'] as String)
        .toSet();
    expect(
      names,
      containsAll([
        'sessions',
        'messages',
        'memory_entries',
        'memory_fts',
        'memory_entries_ai',
        'memory_entries_ad',
        'memory_entries_au',
        'audit_log',
        'provider_profiles',
        'usage_records',
        'settings',
        'note_files',
        'note_fts',
      ]),
    );
  });
}
