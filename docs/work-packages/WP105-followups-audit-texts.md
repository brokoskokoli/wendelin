# WP105 – Folgepunkte Audit und Texte (`app/`, `wendelin_integrations`, `wendelin_core`)

**Zuordnung:** M5 (Aufräumen).

Bezug: Folgepunkte aus WP84, WP88 und WP89 (STATUS.md).

## Inhalt
1. **Audit ohne Aufgabentitel (WP88):** `tasks__add`/`tasks__complete` (und weitere `tasks__*` mit Titel) ins Audit nur ohne Titel schreiben, wie `todoist__`/`gtasks__` seit WP89 (AuditArgumentsRedactor, Erlaubnisliste; Bestätigungszeile 1 ohne Titel).
2. **Spotify falscher OAuth-state (WP84):** eigene, klare Meldung statt nur „Anmeldung abgebrochen“, analog zur Lösung in WP89 (Google Tasks).
3. **Deutsche Resttexte (WP89):** `reconnect()`/`_retry`-Texte bzw. `PortException`-Meldungen über l10n (de/en/fr); weitere fest deutsche Nutzertexte in Integrationen mit `tool/`-Scan finden (Scan erkennt laut WP79 deutsche Ein-Wort-Texte ohne Umlaut nicht – wenn billig, Scan verbessern).

Nicht hierher: Anfrage-Audit mit diktiertem Text (Frage an Stefan, WP85), Stoppwort-Hinweis im Overlay (Sprach-Controller).

## Abnahmekriterien
- [ ] Unit-Tests je Punkt mit Mutationsbeleg; Audit-Test zeigt: kein Titel im Audit für alle Aufgaben-Tools.
- [ ] Gate grün; Gerätetest-Datei `docs/testing/m5/wp105.md` (kurz).
