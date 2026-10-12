import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// Files exported (transitively, via `export`) by the library at [path].
Set<String> _exportedFiles(String path) {
  final result = <String>{};
  void visit(String file) {
    if (!result.add(file)) return;
    final dir = File(file).parent.path;
    final text = File(file).readAsStringSync();
    for (final m in RegExp(
      r"^export '([^']+)'",
      multiLine: true,
    ).allMatches(text)) {
      visit(File('$dir/${m.group(1)}').uri.normalizePath().toFilePath());
    }
  }

  visit(path);
  return result;
}

void main() {
  test('öffentliche API enthält keine drift-Typen außer QueryExecutor', () {
    final files = _exportedFiles('lib/wendelin_storage.dart');
    expect(files, contains('lib/src/storage.dart'));
    for (final file in files) {
      final text = File(file).readAsStringSync();
      final driftImports = RegExp(
        r"^import 'package:(drift|sqlite3)[^']*'([^;]*);",
        multiLine: true,
      ).allMatches(text).toList();
      if (file == 'lib/src/storage.dart') {
        expect(driftImports, hasLength(1), reason: file);
        expect(driftImports.single.group(2), ' show QueryExecutor');
      } else {
        expect(driftImports, isEmpty, reason: file);
      }
      // Nothing from the internal drift layer is re-exported.
      expect(text, isNot(contains("export 'db/")), reason: file);
      expect(text, isNot(contains("export 'src/db/")), reason: file);
    }
  });

  test('fakes.dart und exportierte Dateien importieren kein package:test', () {
    final files = _exportedFiles('lib/fakes.dart');
    expect(files, hasLength(greaterThan(1)));
    for (final file in files) {
      final text = File(file).readAsStringSync();
      expect(text, isNot(contains("import 'package:test")), reason: file);
      expect(text, isNot(contains('_contract.dart')), reason: file);
    }
  });

  test('openInMemoryStorage liefert eine nutzbare Datenbank', () async {
    final storage = openInMemoryStorage(clock: FixedClock(DateTime(2026)));
    addTearDown(storage.close);
    final s = await storage.conversations.startNew(DateTime(2026));
    expect(s.id, hasLength(36));
    expect(WendelinStorage.schemaVersion, 1);
  });

  test('Wertobjekte: Gleichheit, hashCode, toString', () {
    final t = DateTime(2026);
    final s = Session(id: 's', startedAt: t, lastActivityAt: t, title: 'x');
    expect(s, Session(id: 's', startedAt: t, lastActivityAt: t, title: 'x'));
    expect(
      s.hashCode,
      Session(id: 's', startedAt: t, lastActivityAt: t, title: 'x').hashCode,
    );
    expect(s, isNot(Session(id: 's', startedAt: t, lastActivityAt: t)));
    expect(s.toString(), contains('s'));

    final m = StoredMessage(
      id: 'm',
      sessionId: 's',
      seq: 1,
      message: Message.user('hi'),
      createdAt: t,
    );
    final m2 = StoredMessage(
      id: 'm',
      sessionId: 's',
      seq: 1,
      message: Message.user('hi'),
      createdAt: t,
    );
    expect(m, m2);
    expect(m.hashCode, m2.hashCode);
    expect(m.toString(), contains('s#1'));

    final e = MemoryEntry(
      id: 'e',
      text: 'Tee',
      category: MemoryCategory.preference,
      source: 'user',
      createdAt: t,
      lastUsedAt: t,
    );
    final e2 = MemoryEntry(
      id: 'e',
      text: 'Tee',
      category: MemoryCategory.preference,
      source: 'user',
      createdAt: t,
      lastUsedAt: t,
    );
    expect(e, e2);
    expect(e.hashCode, e2.hashCode);
    expect(e.toString(), contains('preference'));
  });
}
