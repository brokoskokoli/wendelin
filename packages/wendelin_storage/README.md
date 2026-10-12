# wendelin_storage

Lokale Datenbank (SQLite über drift) mit Repositories für Sitzungen und Nachrichten, Gedächtnis (FTS5), Audit-Log, Provider-Profile, Kosten und Einstellungen sowie das `SecretStore`-Interface.

## Nutzung

```dart
// App (Flutter): Executor aus drift_flutter
final storage = WendelinStorage(driftDatabase(name: 'wendelin'));

// Tests, Evals, Demo-Modus
final storage = openInMemoryStorage(); // package:wendelin_storage/fakes.dart
```

Öffentlich sind nur `WendelinStorage`, die Repository-Interfaces und reine Dart-Wertobjekte. Die einzige drift-Klasse in der API ist der `QueryExecutor` im Konstruktor. Tabellen, Companions und Zeilenklassen liegen in `lib/src/db/` und werden nicht exportiert (geprüft in `test/public_api_test.dart`).

## SQLite und FTS5

`package:sqlite3` ab 3.x bündelt SQLite über einen Build-Hook (vorgebaute, per Hash geprüfte Bibliothek mit FTS5). Lokal auf macOS, in CI auf Ubuntu und in der App über `drift_flutter` läuft dieselbe SQLite-Version, ohne Systembibliothek (`libsqlite3`). `test/sqlite_test.dart` prüft, dass FTS5 und `bm25` verfügbar sind.

App: `drift_flutter` ≥ 0.3 verwenden (nutzt `sqlite3` 3.x mit Build-Hook). Kein `sqlite3_flutter_libs` ≤ 0.5 einbinden, das würde eine zweite, eigene SQLite-Bibliothek mitbringen.

## Schema und Migrationen

- Tabellen: `lib/src/db/tables.dart`, FTS5-Tabelle und Trigger: `lib/src/db/memory_fts.drift`.
- Codegenerierung: `dart run build_runner build` (die erzeugte `database.g.dart` ist eingecheckt).
- Schema-Dumps: `drift_schemas/wendelin/drift_schema_vN.json`, Test-Helfer in `test/drift/wendelin/generated/`, Test in `test/drift/wendelin/migration_test.dart`.
- Schemaänderung: `WendelinDatabase.version` erhöhen, Migrationsschritt ergänzen, `dart run drift_dev make-migrations`, Upgrade-Test schreiben (Anleitung im Kopf von `migration_test.dart`).

Zeitpunkte werden als Mikrosekunden seit der Epoche gespeichert (exakt, als Integer vergleichbar) und als lokale `DateTime` gelesen. Tages- und Monatssummen der Kosten gelten in lokaler Zeit.
