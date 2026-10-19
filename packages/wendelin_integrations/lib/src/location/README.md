# Standort und Navigation (`location`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `location__current` | read | Wo bin ich: Ortsname, sonst auf ~100 m gerundete Koordinaten; Genauigkeit in 10 m |
| `location__navigate_to` | write | Navigation starten (`destination`, `mode` driving/walking/bicycling/transit): Google Maps, sonst `geo:`-Intent |
| `location__distance_to` | read | Luftlinie vom Standort zu `destination` (Ortsname über den `Geocoder` oder „Breite,Länge“), „ca. …“ |

Keine Nachfrage. `sensitive`; kein Tool ist `TrustedContentSource`. Beschreibungen und Zusammenfassungen nennen weder Ziel noch Standort (Prüfprotokoll).

**Ports** (`location_port.dart`): `LocationPort` (`hasPermission`, `requestPermission`, `current` → `GeoFix`), `MapsLauncherPort` (`launch(MapsLaunch)`, `notFound` ohne App). Fehler als `PortException`: Berechtigung fehlt (`permissionDenied`), kein Fix/Standort aus (`unavailable`), keine Karten-App (`notFound`); nie mit Koordinaten im Text. Fakes: `FakeLocationPort`, `FakeMapsLauncherPort`.

**Reine Logik** (`maps_intents.dart`): `MapsIntents.navigate/search` (Google Maps vs. `geo:`), `haversineMeters`, `formatDistance`, `roundedCoordinate`. `LocationWeatherPort` füttert das Wetter mit dem Standort (`null` statt Fehler).

**Berechtigung:** Schritt `location_permission`, Anfrage beim Einschalten. **Kotlin:** `LocationChannel`, `LocationPick`. Siehe `docs/architecture/integrations/location.md`.
