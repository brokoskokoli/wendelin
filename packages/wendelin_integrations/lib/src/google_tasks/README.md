# google_tasks (WP89b)

Google Tasks über die **Tasks API** (`https://tasks.googleapis.com/tasks/v1`), Tools `gtasks__add`, `gtasks__list`, `gtasks__complete` in der Form von `tasks__*` (WP88). Tasklisten sind die Listen. Google kennt nur ein **Datum** (keine Uhrzeit, keine Priorität): `due` wird lokal aufgelöst (`google_tasks_due.dart`: ISO, heute/morgen/übermorgen, Wochentage, „in 3 Tagen“, `20.10.`), eine Uhrzeit wird weggelassen und im Ergebnis vermerkt.

## Anmeldung (ohne Play-Dienste)
Der Nutzer legt in einem eigenen Google-Cloud-Projekt einen OAuth-Client vom Typ **Desktop** an (Tasks API aktivieren, Testnutzer-Modus reicht) und trägt Client-ID und Client-Secret in der Einrichtung ein. Google erlaubt für installierte Apps kein festes Schema wie `app.wendelin://`, daher gilt der **Loopback-Redirect** `http://127.0.0.1:<Port>/oauth2/callback`:

- `LoopbackReceiver` (`google_tasks_login.dart`): `HttpServer` nur an `InternetAddress.loopbackIPv4`, Port 0, nimmt genau eine Anfrage auf dem Pfad mit richtigem Host an (alles andere 404), schließt sich danach, bei Zeitüberschreitung (5 min) und bei `cancel()`.
- PKCE S256 (`common/pkce.dart`), zufälliger `state` (32 Zeichen), `access_type=offline`, `prompt=consent`.
- Der Browser kommt über den Port `GoogleBrowserOpener` (App: Kotlin `AuthChannel.open`).
- Je Fehlerfall eine eigene Meldung: falscher/fehlender `state` (verworfen), `access_denied` (abgebrochen, Hinweis Testnutzer), anderer `error`, kein Code, Zeitüberschreitung, Abbruch, kein Browser, Token-Tausch abgelehnt, Tasks-Scope nicht erteilt.

## Token
Refresh-Token, Client-ID und Client-Secret liegen nur im `SecretStore` (`GoogleTasksSecrets`). Das Access-Token liegt nur im Speicher (`GoogleTasksSession`): Erneuerung vor Ablauf und **einmal** nach HTTP 401. Lehnt Google den Refresh ab (`invalid_grant`; im Testnutzer-Modus endet das Refresh-Token nach 7 Tagen), wird das Refresh-Token gelöscht, die Integration pausiert und eine neue Anmeldung verlangt. Netzfehler pausieren nicht. Abmelden widerruft das Token (best effort) und löscht alles. Nichts davon steht in Meldungen, Logs, Audit oder Export; das Client-Log enthält nur Operation und Status, nie Titel oder IDs.
