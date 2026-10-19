# Google Tasks (`gtasks`)

Aufgaben in Google Tasks über die **Tasks API** (`https://tasks.googleapis.com/tasks/v1`). Tools `gtasks__add`, `gtasks__list`, `gtasks__complete` in der Form von `tasks__*` (WP88) und `todoist__*` (WP89a). Einzelheiten: `packages/wendelin_integrations/lib/src/google_tasks/README.md`.

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `gtasks__add` | write | `title`, `list` (Aufgabenliste, sonst die erste/Standardliste), `due` (`2026-10-20` oder einfache Wörter: morgen, Freitag, in 3 Tagen, `20.10.`; **nur Datum**, Uhrzeit wird weggelassen und vermerkt). Keine Priorität. Undo löscht die Aufgabe |
| `gtasks__list` | read | `filter` today/overdue/all, `list`, `include_done` (nicht unterstützt). Antwort wie `tasks__list`, als Daten markiert |
| `gtasks__complete` | write | `title` (unscharf), `list` (sonst alle Listen). Undo setzt `needsAction` zurück |

## Anmeldung ohne Play-Dienste
Eigenes Cloud-Projekt des Nutzers, OAuth-Client Typ **Desktop** (Client-ID und Client-Secret auf der Einrichtungsseite, Testnutzer-Modus reicht). Google erlaubt kein festes App-Schema, daher **Loopback-Redirect** `http://127.0.0.1:<Zufallsport>/oauth2/callback`: `HttpServer` nur an `loopbackIPv4`, Port 0, genau eine Anfrage auf dem Pfad (Host geprüft), Timeout 5 min, danach geschlossen. PKCE S256, zufälliger `state`, `access_type=offline`, `prompt=consent`. Den Browser öffnet Kotlin `AuthChannel.open` (Custom Tab, sonst beliebiger Browser; antwortet sofort). Fehlerfälle haben je eine eigene Meldung: falscher state ≠ `access_denied` ≠ Zeitüberschreitung ≠ kein Code ≠ Abbruch ≠ kein Browser.

| Teil | Ort |
| --- | --- |
| Ports, HTTP, Session, Login, Fälligkeit, Fake | `packages/wendelin_integrations/lib/src/google_tasks/`, Einstieg `google_tasks.dart`, Fakes in `fakes.dart` |
| Secrets | `app/lib/di/google_tasks.dart` (`SecretStoreGoogleTasksSecrets`, Schlüssel `gtasks.client_id`, `gtasks.client_secret`, `gtasks.refresh_token`) |
| Spec | `app/lib/di/integrations/google_tasks_spec.dart` (nicht im Demo-Modus) |
| Browser | `app/lib/platform/google_tasks_platform.dart`, `channel_authorization_browser.dart` (`open`), Kotlin `AuthChannel.kt` |
| Einrichtung | `app/lib/ui/settings/google_tasks_screen.dart`, Route `AppRoutes.googleTasks` |
| Texte | `app/lib/l10n/src/google_tasks/` |
| Vertrauen | `app/test/trust/gtasks.json` (nur `gtasks__add` vertrauenswürdig, wie `tasks__add`) |

## Sicherheit
Refresh-Token, Client-ID und Client-Secret nur im `SecretStore`; das Access-Token nur im Speicher. Nichts davon in Meldungen, Logs, Audit oder Export (Canary-Tests); das Client-Log hat nur Operation und Status, nie Titel. Erneuerung vor Ablauf und einmal nach 401; `invalid_grant` (im Testmodus nach 7 Tagen) löscht das Refresh-Token und pausiert die Integration. Abmelden widerruft das Token (best effort) und löscht alles.

Gerätetests: `docs/testing/m5/wp89.md`.
