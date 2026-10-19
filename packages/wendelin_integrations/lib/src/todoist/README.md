# Todoist (`todoist`)

Aufgaben in Todoist mit dem **persönlichen API-Token** des Nutzers. Gleiche Tool-Form wie `tasks__*` (WP88), damit das Modell beides gleich nutzt. Projekte sind die Listen, die Fälligkeit ist natürlichsprachlich (`due_string`).

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `todoist__add` | write | `title`, `list` (Projekt, sonst Eingang), `due` (`2026-10-20`, `2026-10-20T14:30` oder natürliche Sprache wie „morgen 9 Uhr“), `priority` (`highest`…`lowest`). Undo löscht die Aufgabe |
| `todoist__list` | read | `filter` today/overdue/all, `list`, `include_done` (von Todoist nicht unterstützt, ignoriert). Antwort wie `tasks__list`, als Daten markiert |
| `todoist__complete` | write | `title` (unscharf), `list` (sonst alle Projekte). Wiederkehrende Aufgaben rücken zum nächsten Termin (`recurring: true`). Undo öffnet wieder (`reopen`) |

Auflösung wie bei den Listen (`common/matching.dart`): mehrere Treffer → „Mehrdeutig … Bitte nachfragen“; Projektnamen schreibender Tools, die nur über ganze Wörter passen, werden zurückgefragt.

Todoist kennt vier Prioritäten: highest = p1 (dringend, API 4), high = 3, medium = 2, low und lowest = normal.

## Dateien
`todoist_api.dart` (Port `TodoistApi`, `TodoistSecrets`, Modelle), `http_todoist_api.dart` (HTTP, API v1 `https://api.todoist.com/api/v1`, Cursor-Paginierung `next_cursor`, höchstens 25 Seiten), `todoist_session.dart` (Token je Aufruf, Fehlerzustand, Projektauflösung), `todoist_integration.dart`, `todoist_tools.dart`. Fake: `FakeTodoistApi` in `fakes.dart`.

## Sicherheit
Der Token liegt nur im `SecretStore` (App: Schlüssel `todoist.token`), geht nur als `Authorization: Bearer` an `api.todoist.com` und steht in keiner Fehlermeldung, keinem Log, Audit oder Export. Das Log des Clients enthält nur Operation und Status, keine Titel. 401/403 pausieren die Integration (`onError`), Netz-, 429- und 5xx-Fehler nur den Aufruf.
