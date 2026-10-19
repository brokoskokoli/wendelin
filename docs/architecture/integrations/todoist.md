# Todoist (`todoist`)

Aufgaben in Todoist über die **API v1** (`https://api.todoist.com/api/v1`; die REST API v2 ist abgeschaltet) mit persönlichem API-Token. Tools `todoist__add`, `todoist__list`, `todoist__complete` in der Form von `tasks__*` (WP88). Einzelheiten: `packages/wendelin_integrations/lib/src/todoist/README.md`.

| Teil | Ort |
| --- | --- |
| Port, HTTP, Fake, Session | `packages/wendelin_integrations/lib/src/todoist/`, Einstieg `todoist.dart` |
| Token | `app/lib/di/todoist.dart` (`SecretStoreTodoistSecrets`, Schlüssel `todoist.token`) |
| Spec | `app/lib/di/integrations/todoist_spec.dart` (nicht im Demo-Modus) |
| Einrichtung | `app/lib/ui/settings/todoist_screen.dart`, Route `AppRoutes.todoist` |
| Texte | `app/lib/l10n/src/todoist/` |
| Vertrauen | `app/test/trust/todoist.json` (nur `todoist__add` vertrauenswürdig, wie `tasks__add`) |

Gerätetests: `docs/testing/m5/wp89.md`. Google Tasks (WP89b) bekommt einen eigenen Ordner unter `packages/wendelin_integrations/lib/src/` und eine eigene Datei hier.
