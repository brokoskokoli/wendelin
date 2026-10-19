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
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
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
    expect(WendelinDatabase.version, 6);
  });

  test('neue Datenbank entspricht dem Schema-Dump v6', () async {
    final schema = await verifier.schemaAt(6);
    final db = WendelinDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 6);
  });

  test(
    'Upgrade v5 → v6: alte Einträge liegen im Standard-Gedächtnis',
    () async {
      final schema = await verifier.schemaAt(5);
      schema.rawDatabase.execute(
        'INSERT INTO memory_entries (id, body, category, source, created_at, '
        "last_used_at) VALUES ('m1', 'Mag Tee', 'preference', 'user', 1, 1)",
      );
      schema.rawDatabase.execute(
        'INSERT INTO sessions (id, started_at, last_activity_at) '
        "VALUES ('s1', 1, 1)",
      );
      final db = WendelinDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 6);
      await db.close();

      final storage = WendelinStorage(schema.newConnection());
      addTearDown(storage.close);
      expect((await storage.memory.list()).single.id, 'm1');
      expect((await storage.memory.search('Tee')).single.id, 'm1');
      expect(await storage.memory.list(owner: 'p:a'), isEmpty);
      expect(await storage.memory.count(), 1);
      // Alte Sitzungen gehören keiner Person.
      expect(await storage.conversations.sessionPerson('s1'), isNull);
    },
  );

  test('Upgrade v4 → v5: alte Sitzungen gelten als App-Sitzungen', () async {
    final schema = await verifier.schemaAt(4);
    schema.rawDatabase.execute(
      'INSERT INTO sessions (id, started_at, last_activity_at, title) '
      "VALUES ('s1', 1, 2, 'Alt')",
    );
    final db = WendelinDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);
    await db.close();

    final storage = WendelinStorage(schema.newConnection());
    addTearDown(storage.close);
    final old = await storage.conversations.session('s1');
    expect(old?.origin, SessionOrigin.app);
    final overlay = await storage.conversations.startNew(
      DateTime.utc(2026),
      origin: SessionOrigin.overlay,
    );
    expect(
      (await storage.conversations.sessions(origin: SessionOrigin.overlay))
          .map((s) => s.id),
      [overlay.id],
    );
  });

  test('Upgrade v3 → v4 legt das Prüfprotokoll an, Daten bleiben', () async {
    final schema = await verifier.schemaAt(3);
    schema.rawDatabase
      ..execute(
        'INSERT INTO sessions (id, started_at, last_activity_at, title) '
        "VALUES ('s1', 1, 2, 'Alt')",
      )
      ..execute(
        'INSERT INTO audit_log (at, kind, session_id, payload_json) '
        "VALUES (5, 'error', 's1', '{}')",
      );
    final db = WendelinDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 4);
    await db.close();

    final storage = WendelinStorage(schema.newConnection());
    addTearDown(storage.close);
    expect((await storage.conversations.session('s1'))?.title, 'Alt');
    expect(await storage.audit.query(), hasLength(1));
    expect(await storage.attestations.latest(), isEmpty);
    await storage.attestations.add(
      AttestationRecord(
        logId: 'l1',
        at: DateTime.utc(2026, 10, 14),
        profileId: 'tee',
        kind: AttestationRecordKind.session,
        status: AttestationStatus.green,
      ),
    );
    expect((await storage.attestations.latest()).single.logId, 'l1');
  });

  test(
    'Upgrade v2 → v3 ergänzt die Untergrenze, Nachrichten bleiben',
    () async {
      final schema = await verifier.schemaAt(2);
      schema.rawDatabase
        ..execute(
          'INSERT INTO sessions (id, started_at, last_activity_at, title) '
          "VALUES ('s1', 1, 2, 'Alt')",
        )
        ..execute(
          'INSERT INTO memory_entries (id, body, category, source, '
          "created_at, last_used_at) VALUES ('m1', 'Mag Tee', 'preference', "
          "'user', 1, 1)",
        )
        ..execute(
          'INSERT INTO messages (id, session_id, seq, role, content_json, '
          "created_at) VALUES ('m1', 's1', 1, 'user', "
          '\'[{"type":"text","text":"Hallo"}]\', 1)',
        );
      final db = WendelinDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 3);
      await db.close();

      final storage = WendelinStorage(schema.newConnection());
      addTearDown(storage.close);
      final old = (await storage.conversations.messages('s1')).single;
      expect(old.message, Message.user('Hallo'));
      expect(old.message.privacyFloor, isNull);
      final tea = (await storage.memory.search('Tee')).single;
      expect((tea.id, tea.privacyFloor), ('m1', null));
      await storage.conversations.append(
        's1',
        Message.user('privat: Befund').withPrivacyFloor(PrivacyLevel.tee),
      );
      final turns = await storage.conversations.lastTurns('s1', 1);
      expect(turns.single.message.privacyFloor, PrivacyLevel.tee);
      final memory = await storage.memory.save(
        'Knie-OP im März',
        category: StoredMemoryCategory.fact,
        source: 'session:s1',
        privacyFloor: PrivacyLevel.tee,
      );
      expect(memory.privacyFloor, PrivacyLevel.tee);
      final knee = (await storage.memory.search('Knie')).single;
      expect(knee.privacyFloor, PrivacyLevel.tee);
    },
  );

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
