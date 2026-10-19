# WP90 – Allgemeine Mediensteuerung (Audible, Podcasts, beliebige Player) (`wendelin_integrations`, `app/`, Android)

**Zuordnung:** M5.

Bezug: Wunsch Audible (Maintainer 2026-10-15), Entscheidung 2026-10-18: keine inoffizielle Audible-Schnittstelle, sondern allgemeine Mediensteuerung.

## Inhalt
1. `media__now_playing` (r: App, Titel, Position), `media__play`/`pause`/`next`/`previous` (w, Undo = Gegenteil), `media__seek` (w: „spul 30 Sekunden zurück“).
2. Umsetzung über `MediaSessionManager.getActiveSessions` mit `NotificationListenerService` (Berechtigung „Benachrichtigungszugriff“, Anleitung in der Einrichtung); Fallback Medientasten-Events über `AudioManager.dispatchMediaKeyEvent`.
3. `media__open_audible` (w): Audible-App öffnen bzw. Titel-Suche per Intent/Deep Link, falls installiert.
4. Zusammenspiel mit Spotify (WP84) und der Sprachausgabe: Audiofokus während der Antwort (Ducking), danach weiter.

## Abnahmekriterien
- [ ] Unit-Tests über Port-Fake; Emulator mit einer Test-Medien-Session.

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/architecture/checklists.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest als eigene Datei `docs/testing/m5/<wp>.md` anlegen (Index `docs/testing/m5/README.md` wird erzeugt). Gate grün.
