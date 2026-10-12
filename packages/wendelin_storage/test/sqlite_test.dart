import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// The bundled SQLite (package:sqlite3 build hook) must provide FTS5 with
/// bm25 on every platform the gate runs on (macOS locally, Ubuntu in CI).
void main() {
  test('SQLite hat FTS5 mit bm25', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    db.execute('CREATE VIRTUAL TABLE t USING fts5(x)');
    db.execute("INSERT INTO t VALUES ('hallo welt')");
    final rows = db.select("SELECT bm25(t) AS r FROM t WHERE t MATCH 'hallo'");
    expect(rows, hasLength(1));
    expect(sqlite3.version.versionNumber, greaterThanOrEqualTo(3045000));
  });
}
