# Integration `maps` (WP86)

Google-Maps-Adapter über die installierte App, ohne API-Key und ohne Berechtigung. Spec `app/lib/di/integrations/maps_spec.dart`, Tools in `packages/wendelin_integrations/lib/src/maps/` (README dort). Teilt Port (`MapsLauncherPort`), Intent-Bau (`MapsIntents`) und Kanal mit `location` (Kanal `location`, siehe `location.md`).

- **Aktiv nur mit Google Maps:** `requiredApp: KnownApps.googleMaps` (`com.google.android.apps.maps`, in `<queries>`). Fehlt die App, ist die Integration „nicht verfügbar“ und ihre Tools fehlen im Katalog; `location__navigate_to` bleibt über `geo:` nutzbar.
- **Tools:** `maps__navigate` (write; Ziel und Modus), `maps__search_place` (read; öffnet die Suche in Maps, die Treffer sieht nur der Nutzer, das Modell bekommt keine Ortsdaten). Beide TrustedContentSource (Ergebnis ist ein fester Text), `app/test/trust/maps.json`. `sensitive: false`: kein Standort und kein Ort steht im Ergebnis; die Beschreibung für Bestätigungen nennt das Ziel nicht (Prüfprotokoll).
- **Abweichung:** `maps__route_info` (Entfernung und Dauer einer Route) entfällt, es bräuchte die Directions-API mit Key.

## Waze und Navigations-App (WP164 B)

- **Ein Tool für beide Apps:** `maps__navigate` hat das optionale Argument `app` (`google_maps` | `waze`); angeboten werden nur Apps, deren Integration an ist und die installiert sind (Schema liest `NavigationApps.active` je Anfrage). Ohne `app` gilt die Einstellung „Navigations-App“ (`AppSettings.navigationApp`, Standard: Google Maps, sonst Waze). Ist die gewählte App nicht verfügbar (Integration aus, nicht installiert, Prüfung fehlgeschlagen), kommt ein Fehler, nie ein stiller Wechsel zur anderen App (fail-closed). Das Ergebnis nennt die tatsächliche App.
- **Integration `waze`** (`waze_spec.dart`, `requiredApp: KnownApps.waze`, `com.waze` in `<queries>`) hat keine eigenen Tools: sie trägt dieselbe `MapsNavigateTool`-Instanz wie `maps` (gebaut in `mapsSpec.prepare`). Die `ToolRegistry` erlaubt dieselbe Tool-Instanz in mehreren Integrationen und bietet sie einmal an, solange eine davon aktiv ist. Themenwörter: eigener Schlüssel `waze` (gleiche Wörter wie `maps`), damit das Vorab-Freischalten auch mit nur Waze greift.
- **Link:** `https://waze.com/ul?q=<Ziel>&navigate=yes`, Paket `com.waze` (`MapsIntents.navigateWaze`). Waze kennt keine Fortbewegungsart: nur `driving`, sonst Fehler. `LocationPick.isAllowedLaunch` lässt Host `waze.com`, Pfad `/ul` nur mit Paket `com.waze` zu.
- **Einstellung** in den Details von Google Maps und Waze (`navigation_app_section.dart`).
