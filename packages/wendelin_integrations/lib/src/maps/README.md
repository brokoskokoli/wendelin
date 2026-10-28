# Google Maps (`maps`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `maps__navigate` | write | Navigation in Google Maps oder Waze (`destination`, `mode`, `app`); Waze: Integration `waze` ohne eigene Tools, nur die App-Option (WP164 B) |
| `maps__search_place` | read | Suche in Google Maps öffnen (`query`); keine Treffer zurück ans Modell |

Aktiv nur, wenn Google Maps installiert ist (`KnownApps.googleMaps`). Kein API-Key, keine Berechtigung, nicht `sensitive`. Beide Tools `TrustedContentSource`. `maps__route_info` entfällt (Directions-API braucht einen Key). Port und Intent-Bau liegen in `../location/`. Siehe `docs/architecture/integrations/maps.md`.
