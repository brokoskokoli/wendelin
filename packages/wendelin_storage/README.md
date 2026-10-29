# wendelin_storage

Lokale Datenbank (SQLite über drift) mit Repositories für Sitzungen und Nachrichten, Gedächtnis (FTS5), Notizindex für Obsidian (FTS5), Audit-Log, Provider-Profile, Kosten und Einstellungen sowie das `SecretStore`-Interface.

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

- Tabellen: `lib/src/db/tables.dart`, FTS5-Tabellen: `lib/src/db/memory_fts.drift` (mit Triggern) und `lib/src/db/note_fts.drift`.
- Versionen: v1 (M1), v2 (WP16) = `note_files` + `note_fts` für den Obsidian-Notizindex. Upgrade-Schritte in `WendelinDatabase.migration` (`stepByStep` aus der generierten `database.steps.dart`), Upgrade-Test v1 → v2 mit Daten in `migration_test.dart`.
- Codegenerierung: `dart run build_runner build` (die erzeugte `database.g.dart` ist eingecheckt).
- Schema-Dumps: „drift_schemas/wendelin/drift_schema_vN.json“, Test-Helfer in `test/drift/wendelin/generated/`, Test in `test/drift/wendelin/migration_test.dart`.
- Schemaänderung: `WendelinDatabase.version` erhöhen, Migrationsschritt ergänzen, `dart run drift_dev make-migrations`, Upgrade-Test schreiben (Anleitung im Kopf von `migration_test.dart`).

Zeitpunkte werden als Mikrosekunden seit der Epoche gespeichert (exakt, als Integer vergleichbar) und als lokale `DateTime` gelesen. Tages- und Monatssummen der Kosten gelten in lokaler Zeit.

## Notizindex (`NoteIndexRepository`)

`storage.notes`: `upsert(path, title, body, modifiedAt)`, `upsertAll` (eine Transaktion je Stapel), `remove`, `search(query, limit)`, `knownFiles`, `count`, `clear`. Der Text steht nur in der FTS5-Tabelle `note_fts` (`path, title, body`, `unicode61 remove_diacritics 2`; der Pfad ist indexiert, damit Ordnernamen gefunden werden), Pfad, Titel und Änderungszeit zusätzlich in `note_files`; beides wird in einer Transaktion geschrieben. Suche: jedes Wort ab zwei Zeichen außer Stoppwörtern (de/en/fr) als Präfix, ODER-verknüpft (`ftsQuery`, wie beim Gedächtnis), Rang `bm25(note_fts, 2, 10, 1)` (Titel zählt zehnfach, Pfad doppelt), bei Gleichstand nach Pfad; Ausschnitt per `snippet()` (16 Tokens, einzeilig). Die Schnittstelle spiegelt `NoteIndexPort` aus `wendelin_integrations`; storage darf integrations nicht importieren, daher adaptiert die App (`app/lib/platform/repository_note_index_port.dart`, dort läuft `noteIndexPortContract`).
