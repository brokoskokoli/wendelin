# WP84 – Spotify (`wendelin_integrations`, `app/`, Android)

**Zuordnung:** M5.

Bezug: Konzept „Eingebaute Integrationen“ (Spotify), Entscheidung Maintainer 2026-10-18 (Premium vorhanden, Umfang wie Konzept).

## Inhalt
1. Tools: `spotify__search` (r), `spotify__play` (w: Playlist, Album, Titel, Künstler), `spotify__pause`/`next`/`previous` (w, Undo wo sinnvoll), `spotify__now_playing` (r), `spotify__queue_add` (w).
2. Web API mit OAuth/PKCE (Redirect per App-Link/Custom Scheme); der Nutzer legt eine Spotify-Entwickler-App an und trägt die Client-ID in der Einrichtung ein (Anleitung in der Einrichtungsseite). Token-Refresh.
3. Kein aktives Gerät: Spotify-App per Intent wecken (App Remote SDK nur, wenn ohne Play-Dienste nutzbar und lizenzrechtlich passend; sonst Intent `spotify:` + erneuter Versuch). App-Erkennung über `<queries>`.
4. Fehlertexte: kein Premium, kein Gerät, nicht angemeldet.

## Abnahmekriterien
- [ ] Unit-Tests mit aufgezeichneten API-Antworten (Suche, Play, Fehler 401/403/404), OAuth-Ablauf mit Fake.
- [ ] Prüfpunkte Gerät (Maintainer): „Spiel …“, „Pause“, „Was läuft gerade?“.

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/architecture/checklists.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest als eigene Datei `docs/testing/m5/<wp>.md` anlegen (Index `docs/testing/m5/README.md` wird erzeugt). Gate grün.
