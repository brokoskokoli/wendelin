# Integration `maps` (WP86)

Google-Maps-Adapter über die installierte App, ohne API-Key und ohne Berechtigung. Spec `app/lib/di/integrations/maps_spec.dart`, Tools in `packages/wendelin_integrations/lib/src/maps/` (README dort). Teilt Port (`MapsLauncherPort`), Intent-Bau (`MapsIntents`) und Kanal mit `location` (Kanal `location`, siehe `location.md`).

- **Aktiv nur mit Google Maps:** `requiredApp: KnownApps.googleMaps` (`com.google.android.apps.maps`, in `<queries>`). Fehlt die App, ist die Integration „nicht verfügbar“ und ihre Tools fehlen im Katalog; `location__navigate_to` bleibt über `geo:` nutzbar.
- **Tools:** `maps__navigate` (write; Ziel und Modus), `maps__search_place` (read; öffnet die Suche in Maps, die Treffer sieht nur der Nutzer, das Modell bekommt keine Ortsdaten). Beide TrustedContentSource (Ergebnis ist ein fester Text), `app/test/trust/maps.json`. `sensitive: false`: kein Standort und kein Ort steht im Ergebnis; die Beschreibung für Bestätigungen nennt das Ziel nicht (Prüfprotokoll).
- **Abweichung:** `maps__route_info` (Entfernung und Dauer einer Route) entfällt, es bräuchte die Directions-API mit Key.
