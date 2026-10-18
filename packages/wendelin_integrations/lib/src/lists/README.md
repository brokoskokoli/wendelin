# Listen (`lists`)

Vom Nutzer definierte Listen (Konzept K6), jede mit eigener Markdown-Datei, z. B. „Einkaufen“ → `Listen/Einkaufen.md`, „SmartSSH“ → `Projekte/SmartSSH.md` (Abschnitt „Todo“). Einträge sind Markdown-Aufgaben `- [ ] Milch` / `- [x] Milch`, damit die Dateien in Obsidian direkt nutzbar sind.

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `lists__list_lists` | read | Namen, Aliase und Anzahl offener Einträge (Fehler je Liste statt Gesamtfehler; `missing_file: true`, wenn die Datei noch fehlt) |
| `lists__get_items` | read | Einträge einer Liste, erledigte nur mit `include_done: true`; als Daten markiert; `missing_file: true`, wenn die Datei noch fehlt |
| `lists__add_items` | write | Mehrere Einträge auf einmal; offene Einträge mit gleichem Text (Groß/Klein, Umlaute egal) werden übersprungen. Undo entfernt genau die hinzugefügten Zeilen (und einen dabei angelegten Abschnitt) |
| `lists__complete_item` | write | Eintrag finden und abhaken; ein eindeutiger Treffer über ganze Wörter wird ohne Rückfrage genommen („Hak Milch ab“ → `Milch (1 l)`), das Ergebnis nennt den tatsächlichen Eintrag. Ist der beste Treffer schon erledigt → Hinweis. Undo setzt das Häkchen zurück |
| `lists__remove_item` | write | Eintrag samt eingerückter Unterzeilen löschen. Undo fügt die Zeilen an derselben Stelle wieder ein: hinter der früheren nicht leeren Vorgängerzeile (mit denselben Leerzeilen dazwischen), sonst vor der früheren Nachfolgezeile; gesucht wird nur im Abschnitt der Liste |
| `lists__clear_completed` | external | Erledigte Einträge samt Unterzeilen löschen, immer mit Bestätigung. Erledigte Einträge mit noch offenen Unteraufgaben bleiben stehen und werden im Ergebnis als `kept` genannt |

## Aufgaben (`tasks__…`, WP88)
Eigene Integration `tasks` (`TasksIntegration` in `tasks_tools.dart`, Registry-Zeile `tasksSpec`), weil Toolnamen das Präfix der Integration tragen müssen. Sie nutzt dieselben Dateien, Definitionen und dieselbe Schreibwarteschlange wie `lists` und wird in Einstellungen → Integrationen separat eingeschaltet.
Aufgaben sind normale Listeneinträge mit Obsidian-Tasks-Markierungen am Zeilenende: `- [ ] Steuer abgeben ⏰ 14:30 ⏫ 📅 2026-10-20`. Priorität `🔺 ⏫ 🔼 🔽 ⏬` (highest … lowest), Fälligkeit `📅 JJJJ-MM-TT`, Uhrzeit `⏰ HH:MM` (eigene Erweiterung, nur mit Fälligkeit; steht vor den Tasks-Marken, weil Obsidian Tasks Marken nur vom Zeilenende her liest, und bleibt dort im Beschreibungstext; der Parser liest auch die alte Reihenfolge mit `⏰` hinter `📅`; `due` ohne Zeitzone; Titel mit Marken werden abgelehnt), erledigt `✅ JJJJ-MM-TT`. Unbekannte Marken (`🔁`, `⏳`, `#tags`) bleiben unangetastet: der Parser (`task_format.dart`, `TaskInfo`) liest nur, die Tools hängen höchstens Marken an. Eine Liste kann `taskDefault` sein (Schalter „Standard-Aufgabenliste“ in der Listenbearbeitung, höchstens eine); ohne Angabe nehmen `tasks__add`/`tasks__complete` sie, sonst die einzige Liste, sonst Rückfrage.

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `tasks__add` | write | `title`, optional `list`, `due` (`2026-10-20` oder `2026-10-20T14:30`), `priority`. Nutzt `AddItemsTool.add` (Duplikate übersprungen, Undo entfernt die Zeile) |
| `tasks__list` | read | `filter` `today` (heute fällig) / `overdue` (vor heute, offen) / `all` (Standard), optional `list` (sonst alle Listen), `include_done`. Sortiert nach Fälligkeit, Uhrzeit, Priorität; Ausgabe als Daten markiert, `overdue: true` je Aufgabe |
| `tasks__complete` | write | Aufgabe über den Titel (ohne Marken) finden, abhaken und `✅ <heute>` anhängen; Undo stellt die Zeile genau wieder her |

Nicht enthalten: Erinnerung per Wecker (Folgepunkt; `alarms__…` hat keinen Datum-Bezug zu Listen) und wiederkehrende Aufgaben (`🔁` wird beim Abhaken nicht fortgeschrieben).

## Definition und Auflösung
`ListDefinition(id, name, aliases, target, section?)` kommt aus den Einstellungen (WP09); die Integration fragt sie bei jedem Aufruf über `definitions()` ab.

Listennamen und Einträge werden in drei Stufen verglichen, nach einheitlicher Normalisierung (Groß/Klein, Umlaute auch als `ae/oe/ue`, `ß` = `ss`, Akzente, Satzzeichen, Leerzeichen):
1. **gleich**: „Smart SSH“ = „SmartSSH“, „Muesli“ = „Müsli“;
2. **gleicher Wortstamm**: Plural/Singular („Aufgabe“/„Aufgaben“, „groceries“/„grocery“), Füllwörter („meine“, „die“, „Liste“, „my“, „list“) und das Kompositum-Suffix „-liste“ („Einkaufsliste“ ≈ „Einkaufen“);
3. **ganze Wörter**: alle Wörter des einen kommen als ganze Wörter im anderen vor („Urlaub“ ≈ „Urlaub Ideen“). Wortteile in Komposita zählen nie („Arbeit“ ≠ „Hausarbeit“, „Eier“ ≠ „Eierlikör“, „Ideen“ ≠ „Geschenkideen“), Wörter unter 3 Zeichen auch nicht.

Die höchste Stufe gewinnt. Mehrere Kandidaten auf derselben Stufe → Fehler „Mehrdeutig“ mit den Kandidaten. Einen Treffer nur über ganze Wörter (dritte Stufe) nehmen lesende Tools und `lists__complete_item` für Einträge (Abhaken ist rückgängig machbar). Die Listenauflösung aller schreibenden Tools und `lists__remove_item` für Einträge antworten stattdessen „Meintest du …?“, damit das Modell nachfragt. Bei Einträgen gilt offen vor erledigt nur auf derselben Stufe: `- [x] Milch` schlägt `- [ ] Milchreis` für „Milch“. Steht derselbe Text mehrfach in der Datei, gilt der erste.

**Verhaltensänderung (WP16)**: Die Normalisierung faltet zusätzlich `ë`, `í ì î ï`, `ç`, `ñ` (vorher nur Umlaute und `à á â`, `ò ó ô`, `ù ú û`, `é è ê`). „Noel“ trifft jetzt „Noël“ auf Stufe 1 (gleich), „Creme brulee“ trifft „Crème brûlée“. Test: `test/lists/write_conflict_test.dart`.

## Datei-Format
- Aufgabenzeilen: `-`, `*`, `+` oder `1.`/`1)` gefolgt von `[ ]`, `[x]` oder `[X]`; beliebig eingerückt (verschachtelte Unteraufgaben sind eigene Einträge und gehören beim Löschen zum Elterneintrag).
- Frontmatter (`---` … `---` am Anfang) und Codeblöcke (```` ``` ````, `~~~`) werden nie als Einträge gelesen.
- Neue Einträge kommen ans Ende des ersten Aufgabenblocks (inkl. Unterzeilen) mit dessen Markierung und Einrückung, sonst hinter die letzte nicht leere Zeile; mit `section` innerhalb des Abschnitts unter dieser Überschrift (bis zur nächsten gleich hohen oder höheren Überschrift). Fehlt der Abschnitt, wird `## <section>` am Dateiende angelegt.
- **Grenzen**: Aufgaben in Zitaten und Callouts (`> - [ ] …`) zählen nicht; Sonderstatus wie `[-]` oder `[/]` werden ignoriert (bleiben unverändert stehen); Abschnitte nur über ATX-Überschriften (`## Titel`), nicht über Setext-Überschriften (`Titel` + `---`); Codezäune werden in jeder Einrückung erkannt (auch in Listen), eingerückte Codeblöcke ohne Zaun nicht; in nummerierten Blöcken bekommen neue Einträge die Nummer des ersten Eintrags (Markdown nummeriert beim Anzeigen selbst).
- Alles andere bleibt **zeichengenau** erhalten: Zeilenenden je Zeile (LF, CRLF, CR), BOM (wird beim Einlesen abgetrennt und beim Schreiben wieder vorangestellt, auch wenn die erste Zeile gelöscht wird), Leerzeichen, fehlender Zeilenumbruch am Dateiende (neue Zeilen am Ende bekommen ebenfalls keinen). Neue Zeilen nutzen das erste Zeilenende der Datei.

**Gemeinsamer Code**: Zeilen, BOM, Frontmatter, Codeblöcke und Überschriften liegen in `markdown/markdown_doc.dart` (`MarkdownDoc`, auch von Obsidian genutzt); `MarkdownList` ergänzt die Aufgabenlogik. Der unscharfe Abgleich liegt in `common/matching.dart`.

## Konfliktarm schreiben
Jedes Tool und jedes Undo liest die Datei unmittelbar vorher neu, ändert nur die betroffenen Zeilen und schreibt die ganze Datei atomar zurück. Lesen-Ändern-Schreiben läuft **je Datei nacheinander** (eine prozessweite Warteschlange pro `target`, `common/file_queue.dart`, gemeinsam mit Obsidian, auch über mehrere Integrations-Instanzen hinweg, z. B. wenn die App die Integration nach einer Einstellungsänderung neu baut; Einträge werden nach Abschluss entfernt), auch wenn die Tool-Laufzeit mehrere Calls einer Runde parallel ausführt und für Undos; ein Fehler in einem Aufruf hält die Warteschlange nicht an. Ein **hängender** Port-Aufruf blockiert dagegen die Warteschlange dieser Datei; die Port-Implementierung sollte deshalb Zeitlimits setzen (empfohlen: einige Sekunden je `read`/`write`, dann `PortException(unavailable)`). Undo sucht seine Zeilen über den Text (nächstgelegene Fundstelle im Abschnitt), nicht über Zeilennummern; fremde Änderungen dazwischen (Obsidian Sync, Editor) bleiben erhalten. Ist eine Zeile inzwischen geändert oder weg, wirft das Undo `PortException(notFound)`: ganz ohne Treffer ohne zu schreiben, teilweise („Nur teilweise rückgängig: 1 von 2 …“) nach dem Schreiben der übrigen. **Optimistische Sperre (WP16)**: Vor dem Schreiben liest `save` die Datei erneut; hat sie sich seit dem Laden geändert (Obsidian Sync, Editor, die Obsidian-Integration auf derselben Datei), wird nicht geschrieben, sondern der ganze Schritt (Lesen, Ändern, Schreiben) bis zu dreimal neu ausgeführt (`WriteConflict` in `common/file_queue.dart`); danach Fehler „wird gerade von außen geändert“. Zwischen dieser Prüfung und dem Schreiben bleibt ein Fenster von Millisekunden.

## Port `ListFilePort` (Implementierung in der App, WP08/WP09)
`read(handle)`, `write(handle, content)`, `exists(handle)`; Fake: `FakeListFilePort`, Vertrag: `listFilePortContract` (Setup liefert Port, `newHandle()` für eine noch nicht existierende Datei, optional `delete` und `reopen` – eine zweite Port-Instanz auf demselben Speicher, z. B. nach Neustart, die das Geschriebene wieder lesen muss).

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
