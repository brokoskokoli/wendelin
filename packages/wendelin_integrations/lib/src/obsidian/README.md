# Obsidian (`obsidian`)

Notizen im Obsidian-Vault des Nutzers lesen, durchsuchen und ergänzen (Konzept „Eingebaute Integrationen → Obsidian“, WP16). Dateizugriff nur über den `VaultPort`, Volltextsuche über den `NoteIndexPort` (SQLite FTS5 in `wendelin_storage`). Sync bleibt bei Obsidian Sync, Syncthing oder Git.

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `obsidian__search_notes` | read | Volltextsuche (Titel, Pfad, Ausschnitt; Standard 8, höchstens 20). Synchronisiert vorher den Index, falls nötig; `index_incomplete: true`, solange der Index noch aufgebaut wird |
| `obsidian__read_note` | read | Notiz als Daten markiert, optional nur der Abschnitt unter `heading` (mit Unterabschnitten); gekürzt auf `max_chars` (Standard 20 000, höchstens 50 000), Kürzung markiert |
| `obsidian__list_folder` | read | Unterordner und Notizen eines Ordners (je höchstens 200), andere Dateien nur gezählt |
| `obsidian__create_note` | write | Neue Notiz; vorhandene werden nie überschrieben. Undo löscht sie, wenn sie unverändert ist |
| `obsidian__append_to_note` | write | Text ans Ende anhängen, mit `heading` ans Ende des eigenen Abschnittstexts (vor der ersten Unterüberschrift); fehlt die Überschrift, wird `## <heading>` am Dateiende angelegt. Undo entfernt genau die eingefügten Zeilen (und die angelegte Überschrift) |
| `obsidian__append_daily_note` | write | Wie `append_to_note` für die Tagesnotiz (heute in der Gerätezone oder `date`); fehlt sie, wird sie aus der Vorlage angelegt. Undo löscht eine dabei neu angelegte, unveränderte Tagesnotiz, sonst nur den Text |
| `obsidian__replace_section` | external | Ersetzt den eigenen Text unter einer Überschrift (bis zur nächsten Überschrift; Unterabschnitte bleiben). Immer mit Bestätigung, die einen **live gelesenen Zeilen-Diff** zeigt (`ConfirmationPreparer`). Undo stellt den alten Text wieder her |
| `obsidian__open_note` | write | `obsidian://open?vault=…&file=…`-Link; die App öffnet ihn über `openUri` (ohne Öffner nur der Link). Kein Undo |

## Auflösung von Notizen und Überschriften
- **Pfad** zuerst exakt (`.md` darf fehlen). Sonst unscharf über die Titel der indizierten Notizen, mit denselben drei Stufen wie bei den Listen (`common/matching.dart`: gleich, gleicher Wortstamm, ganze Wörter). Ein Ordner im Pfad schränkt die Kandidaten ein („archiv/garten“). Mehrere gleich gute Treffer → „Mehrdeutig“; schreibende Tools fragen bei einem Treffer nur über ganze Wörter nach („Meintest du die Notiz …?“).
- **Überschriften** ebenso unscharf („ideen“ → „💡 Ideen“, Plural). ATX (`## Titel`) und Setext (`Titel` + `===`/`---`, nur einzeilige Absätze). Dieselbe Überschrift zweimal → „Mehrdeutig“ mit Zeilennummern; schreibende Tools fragen bei Treffern nur über ganze Wörter nach.

## Markdown byte-genau
Gemeinsamer Kern mit den Listen: `markdown/markdown_doc.dart` (`MarkdownDoc`; `MarkdownList` der Listen baut darauf auf). Die Datei wird in Zeilen mit eigenem Zeilenende zerlegt; nur betroffene Zeilen ändern sich. Erhalten bleiben BOM, LF/CRLF/CR je Zeile, fehlender Schlussumbruch, Frontmatter (wird nie als Überschrift oder Ziel gelesen) und Codeblöcke (Überschriften darin zählen nicht). Neue Zeilen nutzen das erste Zeilenende der Datei. Text aus dem Modell: Zeilen rechts getrimmt, führende/abschließende Leerzeilen entfernt, höchstens 20 000 Zeichen; `replace_section` höchstens 400 Zeilen alt und neu.

**Grenzen**: Setext-Überschriften nur unter einzeiligen Absätzen; der Text unter einer Überschrift endet an der nächsten Überschrift jeder Ebene (Unterabschnitte gehören nicht zum ersetzten oder ergänzten Text); eingefügter Text wird nicht durch Leerzeilen vom vorigen Absatz getrennt.

## Konfliktarm schreiben
Jedes Tool und jedes Undo liest die Notiz unmittelbar vorher neu und schreibt sie atomar zurück. Lesen-Ändern-Schreiben läuft je Notiz nacheinander über die **prozessweite Warteschlange** `common/file_queue.dart` (dieselbe wie bei den Listen, Schlüssel `vault:<pfad>`; auch über mehrere Integrations-Instanzen). Undo sucht seine Zeilen über den Text (nächstgelegene Fundstelle), fremde Änderungen dazwischen bleiben erhalten; sind die eigenen Zeilen geändert oder weg, wirft das Undo `PortException` und schreibt nichts.

`replace_section` merkt sich den Abschnittstext, auf dem der Diff der Bestätigung beruht. Hat sich der Abschnitt bis zur Ausführung geändert (Sync, Editor), schreibt das Tool nichts und meldet „seit der Bestätigung geändert“; Änderungen außerhalb des Abschnitts stören nicht.

**Grenze**: Bearbeitet die Listen-Integration dieselbe Datei über einen anderen Handle (SAF-URI statt Vault-Pfad), serialisiert die Warteschlange beide nicht gegeneinander; es bleibt dann wie gegenüber fremden Programmen ein Fenster von Millisekunden.

## Inhalte sind Daten
Alle Notizinhalte, Suchtreffer und Ordnerlisten stehen hinter `noteDataNotice` in `<note_content …>`, `<note_search_results>` bzw. `<folder_listing>`. Öffnende und schließende Tags dieser Namen im Inhalt werden maskiert (`&lt;/note_content>`, auch mit Leerraum und anderer Schreibweise), Attribute escaped (`common/data_envelope.dart`, auch von `web` genutzt). `external`-Tools (hier `replace_section`) werden unabhängig vom Inhalt immer bestätigt.

## Pfadsicherheit
`VaultPath` prüft jeden Pfad, bevor ein Port aufgerufen wird; die Ports prüfen erneut. Abgewiesen (`PortException(rejected)`): `..` (auch `%2e%2e`), absolute Pfade (`/…`, `~/…`, Laufwerk `C:`), URIs (`file://`, `content://`), Backslashes, Steuerzeichen, versteckte Segmente (`.obsidian/`, `.trash/`, `.git/`, `.datei.md`), Segmente über 255 und Pfade über 1024 Zeichen. Neue Notizen zusätzlich ohne `* " < > : | ?`. Symlinks: `FileSystemVaultPort` folgt Verknüpfungen nur innerhalb des Vaults (Ziel nach `resolveSymbolicLinks` unter der Vault-Wurzel), andere werden nicht gelistet und beim Zugriff abgewiesen, auch kaputte. Tabellentests: `test/obsidian/vault_path_test.dart`.

## Index-Sync (`NoteIndexer`)
Inkrementell nach `modifiedAt`: alle Ordner ablaufen (höchstens 20 000 Einträge, sonst unvollständig und ohne Löschungen), nur `.md`, versteckte Ordner und Anhänge ignoriert; geänderte Notizen neueste zuerst, höchstens 200 pro Lauf; Dateien über 1 MB nur mit Titel, Text höchstens 100 000 Zeichen. Gelöschte Notizen werden entfernt. Nicht lesbare Dateien werden übersprungen und beim nächsten Lauf erneut versucht. Die Suche synchronisiert, wenn seit dem letzten Lauf 30 s vergangen sind, eigene Schreibvorgänge stattfanden oder der letzte Lauf unvollständig war. Gleichzeitige Läufe teilen sich einen.

## Tagesnotizen
`ObsidianSettings.dailyNotes` wie im Obsidian-Plugin „Daily notes“: Ordner, Datumsformat (Moment.js-Tokens `YYYY YY Q MMMM MMM MM M DDDD DDD DD Do D dddd ddd dd d E W WW w ww GGGG gggg HH H hh h mm m ss s A a` und `[Text]`; `/` im Format ergibt Unterordner; Wochen als ISO-Wochen) und Vorlage. Monats- und Wochentagsnamen nach `ObsidianSettings.locale` (`de`, `en`, `fr`). Vorlagen-Platzhalter: `{{title}}`, `{{date}}`, `{{time}}`, `{{date:FORMAT}}`, `{{time:FORMAT}}`. Fehlt die Vorlage, wird die Notiz leer angelegt und `template_missing` gemeldet.

## Ports
**`VaultPort`** (`list`, `read`, `write` atomar, `create` exklusiv, `delete`, `exists`, `modifiedAt`, `size`). `delete` ist gegenüber dem WP-Dokument ergänzt (für das Undo von `create_note`). Implementierungen: `FakeVaultPort` (Fake), `FileSystemVaultPort` (`dart:io`, Desktop/Tests/iOS später), Android-SAF in WP18. Vertrag: `vaultPortContract` (Setup: leerer Vault, optional `reopen` und `dispose`).

Anforderungen an die SAF-Implementierung (WP18): Vault = Tree-URI aus `ACTION_OPEN_DOCUMENT_TREE` mit `takePersistableUriPermission(READ | WRITE)`; Pfade über `DocumentsContract` Segment für Segment auflösen (nie `..` an den Provider geben); `list` über eine Abfrage mit `COLUMN_LAST_MODIFIED` und `COLUMN_SIZE` (spart Einzelabfragen beim Sync); atomar schreiben wie bei den Listen (temporäre Datei + Umbenennen, sonst `openOutputStream(uri, "wt")`); UTF-8 **ohne** BOM-Verlust lesen (Dart: `utf8.decode` entfernt eine führende BOM – der Vertrag prüft das); `modifiedAt` muss sich bei jedem `write` ändern; fehlende Rechte → `PortException(permissionDenied)`; Zeitlimits je Aufruf (hängende Aufrufe blockieren die Warteschlange).

**`NoteIndexPort`** (`upsert`, `remove`, `search`, `knownFiles`). Implementierung: `NoteIndexRepository` in `wendelin_storage` (Schema v2: `note_files` + FTS5 `note_fts`, bm25 mit Titelgewicht 10, Präfixsuche, `remove_diacritics 2`). storage darf integrations nicht importieren; die App adaptiert wie beim Gedächtnis (`RepositoryMemoryPort`): `app/lib/platform/repository_note_index_port.dart`, dort läuft auch `noteIndexPortContract`. Fake: `FakeNoteIndex`.

## Einstellungen und Einrichtung
`ObsidianSettings(vaultName, dailyNotes, locale)`, bei jedem Aufruf gelesen. Ohne `vaultName` fehlt der Einrichtungsschritt `vault_folder` (Ordnerwahl). **Berechtigung**: keine Laufzeitberechtigung (SAF-Rechte). **Plattformen**: Android, iOS (später). **Sensibel**: ja (Tagebuch, Projekte; nach K9 umschaltbar).

## Eval-Fälle für WP10 (Vorlage)
- de: „Schreib in meine Tagesnotiz, dass ich den Zahnarzt angerufen habe“ → `obsidian__append_daily_note(text: "Zahnarzt angerufen" …)`
- de: „Was steht in meiner Notiz Wendelin unter Ideen?“ → `obsidian__read_note(path: "Wendelin", heading: "Ideen")`
- fr: « Ajoute "acheter du bois" à ma note Abri de jardin » → `obsidian__append_to_note(path: "Abri de jardin", text: "acheter du bois")`
- fr: « Cherche dans mes notes le voyage à Malte » → `obsidian__search_notes(query: "Malte voyage" …)`
- en: “Create a note called Gift ideas with books for Anna” → `obsidian__create_note(path: "Gift ideas", content: "- books for Anna" …)`
- en: “Replace the status section of my Wendelin note with: on track” → `obsidian__replace_section(path: "Wendelin", heading: "Status", content: "on track")` (Bestätigung mit Diff)
