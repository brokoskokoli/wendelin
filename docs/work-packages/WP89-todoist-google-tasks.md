# WP89 – Todoist und Google Tasks (`wendelin_integrations`, `app/`)

**Zuordnung:** M5.

Bezug: Wunsch Maintainer 2026-10-18 (eigene Integrationen zusätzlich zu WP88). Gleiche Tool-Form wie WP88 (`add`, `list`, `complete`), damit das Modell beides gleich nutzt; eigener Präfix je Integration.

## Inhalt
1. **WP89a Todoist:** REST API v2 mit persönlichem API-Token (Einrichtung), Projekte als Listen, Fälligkeit natürlichsprachlich.
2. **WP89b Google Tasks:** Tasks API mit OAuth (installierte App, PKCE, ohne Play-Dienste); der Nutzer legt ein Google-Cloud-Projekt mit OAuth-Client an (Anleitung; Testnutzer-Modus reicht für Eigengebrauch).

## Abnahmekriterien
- [ ] Unit-Tests mit aufgezeichneten Antworten; Live-Test nur mit vorhandenem Token (sonst übersprungen).

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/ARCHITECTURE.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest in `docs/testing/m5-device.md` ergänzen. Gate grün.
