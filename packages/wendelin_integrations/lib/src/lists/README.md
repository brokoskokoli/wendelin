# Listen (`lists`)

Vom Nutzer definierte Listen (Konzept K6), jede mit eigener Markdown-Datei, z. B. „Einkaufen“ → `Listen/Einkaufen.md`, „SmartSSH“ → `Projekte/SmartSSH.md` (Abschnitt „Todo“). Einträge sind Markdown-Aufgaben `- [ ] Milch` / `- [x] Milch`, damit die Dateien in Obsidian direkt nutzbar sind.

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `lists__list_lists` | read | Namen, Aliase und Anzahl offener Einträge (Fehler je Liste statt Gesamtfehler) |
| `lists__get_items` | read | Einträge einer Liste, erledigte nur mit `include_done: true`; als Daten markiert |
| `lists__add_items` | write | Mehrere Einträge auf einmal; offene Einträge mit gleichem Text (Groß/Klein, Umlaute egal) werden übersprungen. Undo entfernt genau die hinzugefügten Zeilen (und einen dabei angelegten Abschnitt) |
| `lists__complete_item` | write | Eintrag unscharf finden und abhaken; schon erledigt → Hinweis. Undo setzt das Häkchen zurück |
| `lists__remove_item` | write | Eintrag samt eingerückter Unterzeilen löschen (offene haben Vorrang vor erledigten gleichen Namens). Undo fügt die Zeilen an derselben Stelle wieder ein (hinter der früheren Vorgängerzeile) |
| `lists__clear_completed` | external | Erledigte Einträge samt Unterzeilen löschen, immer mit Bestätigung. Erledigte Einträge mit noch offenen Unteraufgaben bleiben stehen |

## Definition und Auflösung
`ListDefinition(id, name, aliases, target, section?)` kommt aus den Einstellungen (WP09); die Integration fragt sie bei jedem Aufruf über `definitions()` ab. Der Listenname wird unscharf aufgelöst: Groß/Klein, Umlaute (auch `ae/oe/ue`), Satzzeichen und Leerzeichen („Smart SSH“ = „SmartSSH“), Füllwörter („meine“, „die“, „Liste“), Plural/Singular und Komposita („Einkaufsliste“ ≈ „Einkaufen“). Stufen: gleich > gleicher Wortstamm > Teilwort. Mehrere Listen auf der höchsten Stufe → Fehler-Outcome mit den Kandidaten, damit das Modell nachfragt; keine → Fehler mit den vorhandenen Listen. Einträge werden genauso gefunden.

## Datei-Format
- Aufgabenzeilen: `-`, `*`, `+` oder `1.`/`1)` gefolgt von `[ ]`, `[x]` oder `[X]`; beliebig eingerückt (verschachtelte Unteraufgaben sind eigene Einträge und gehören beim Löschen zum Elterneintrag).
- Frontmatter (`---` … `---` am Anfang) und Codeblöcke (```` ``` ````, `~~~`) werden nie als Einträge gelesen.
- Neue Einträge kommen ans Ende des ersten Aufgabenblocks (inkl. Unterzeilen) mit dessen Markierung und Einrückung, sonst hinter die letzte nicht leere Zeile; mit `section` innerhalb des Abschnitts unter dieser Überschrift (bis zur nächsten gleich hohen oder höheren Überschrift). Fehlt der Abschnitt, wird `## <section>` am Dateiende angelegt.
- Alles andere bleibt **zeichengenau** erhalten: Zeilenenden je Zeile (LF, CRLF, CR), BOM, Leerzeichen, fehlender Zeilenumbruch am Dateiende (neue Zeilen am Ende bekommen ebenfalls keinen). Neue Zeilen nutzen das erste Zeilenende der Datei.

## Konfliktarm schreiben
Jedes Tool und jedes Undo liest die Datei unmittelbar vorher neu, ändert nur die betroffenen Zeilen und schreibt die ganze Datei atomar zurück. Undo sucht seine Zeilen über den Text (nächstgelegene Fundstelle), nicht über Zeilennummern; fremde Änderungen dazwischen (Obsidian Sync, Editor) bleiben erhalten. Ist die Zeile inzwischen geändert oder weg, wirft das Undo `PortException(notFound)` und schreibt nichts. Zwischen Lesen und Schreiben eines Tools bleibt ein kleines Fenster (Millisekunden), in dem eine parallele Änderung überschrieben werden kann.

## Port `ListFilePort` (Implementierung in der App, WP08/WP09)
`read(handle)`, `write(handle, content)`, `exists(handle)`; Fake: `FakeListFilePort`, Vertrag: `listFilePortContract` (Setup liefert Port, `newHandle()` für eine noch nicht existierende Datei und optional `delete`).

Anforderungen an die Android-Implementierung (SAF, z. B. über `shared_storage` oder einen eigenen Pigeon-Channel):
- **Handle** = Dokument-URI als String. Auswahl in den Einstellungen per `ACTION_OPEN_DOCUMENT` (bestehende Datei), `ACTION_CREATE_DOCUMENT` (neue Datei, MIME `text/markdown`) oder `ACTION_OPEN_DOCUMENT_TREE` (Ordner, z. B. Obsidian-Vault, plus relativer Dateiname).
- **Persistente Rechte**: `takePersistableUriPermission(READ | WRITE)` direkt nach der Auswahl; beim Start `getPersistedUriPermissions()` prüfen. Fehlen die Rechte, wirft der Port `PortException(permissionDenied)` mit Hinweis „in den Einstellungen neu auswählen“; die Integration geht dann auf „Einrichtung nötig“.
- **Datei neu anlegen**: `write` auf einen Handle ohne Datei legt sie an (bei Ordner-Handles `DocumentsContract.createDocument`).
- **Atomares Schreiben**: in eine temporäre Datei im selben Ordner schreiben und per `renameDocument`/Austausch ersetzen, wo der Provider das kann; sonst `openOutputStream(uri, "wt")` (**mit `t`**, sonst bleibt bei kürzerem Inhalt alter Rest stehen; der Vertrag prüft das) und vollständig in einem Rutsch schreiben.
- **Kodierung**: UTF-8 lesen und schreiben, ohne Zeilenenden oder BOM zu verändern (der Vertrag prüft CRLF, CR, BOM, fehlenden Schlussumbruch, Unicode, 300 KB).
- `read` einer fehlenden Datei → `PortException(notFound)`; `exists` darf keine Ausnahme für fehlende Dateien werfen.
- iOS (später): Security-Scoped Bookmark statt URI, gleiche Semantik.

## Eval-Fälle für WP10
- „Füge Milch und Eier zur Einkaufsliste hinzu“ → `lists__add_items(list: "Einkaufsliste"|"Einkaufen", items: ["Milch", "Eier"])`
- „Was steht auf der Liste SmartSSH?“ → `lists__get_items(list: "SmartSSH")`

**Berechtigung**: keine Laufzeitberechtigung (SAF-Rechte pro Datei). **Plattformen**: Android, iOS. **Sensibel**: nein (Listen enthalten Alltagsdinge; bei Bedarf als Folgepunkt konfigurierbar).
