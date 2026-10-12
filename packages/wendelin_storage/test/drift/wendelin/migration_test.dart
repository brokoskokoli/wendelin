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

import 'generated/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('aktuelle Schema-Version ist eingecheckt', () {
    expect(GeneratedHelper.versions.last, WendelinDatabase.version);
    expect(WendelinDatabase.version, 1);
  });

  test('neue Datenbank entspricht dem Schema-Dump v1', () async {
    final schema = await verifier.schemaAt(1);
    final db = WendelinDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 1);
  });

  test('Schema-Dump v1 enthält FTS5-Tabelle und Trigger', () async {
    final schema = await verifier.schemaAt(1);
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
      ]),
    );
  });
}
