# WP86 – Standort, Navigation und Google-Maps-Adapter (`wendelin_integrations`, `app/`, Android)

**Zuordnung:** M5.

Bezug: Konzept (Standort und Navigation; Google Maps K15), Entscheidung Maintainer 2026-10-18: nur über die installierte Maps-App, kein Google-API-Key; ohne Google Maps `geo:`-Intent (Organic Maps, OsmAnd).

## Inhalt
1. `location__current` (r, sensibel) über `LocationManager` (kein Fused Location, K7), mit Ortsname per Geocoder falls verfügbar, sonst Koordinaten.
2. `location__navigate_to` (w), `location__distance_to` (r, Luftlinie, ggf. „ungefähr“).
3. `maps__navigate` (w), `maps__search_place` (r: öffnet Suche in Maps), `maps__route_info` nur, soweit ohne API-Key möglich (sonst weglassen und im Bericht nennen).
4. Berechtigung `ACCESS_FINE_LOCATION` erst bei Aktivierung; Hintergrundstandort nicht nötig.

## Abnahmekriterien
- [ ] Unit-Tests (Intent-Bau, Fallback ohne Maps), Emulator mit gesetzter Position.

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/ARCHITECTURE.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest in `docs/testing/m5-device.md` ergänzen. Gate grün.
