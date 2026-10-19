# Integration `location` (WP86)

Wo bin ich, Navigation starten, Entfernung in Luftlinie. Spec `app/lib/di/integrations/location_spec.dart`, Tools in `packages/wendelin_integrations/lib/src/location/` (README dort), `sensitive: true`.

| Kanal (`app.wendelin/…`) | Dart | Kotlin |
| --- | --- | --- |
| location | `app/lib/platform/channel_location_port.dart` (`ChannelLocationPort`, `ChannelMapsLauncherPort`) | `LocationChannel.kt` (`LocationPick.kt`) |

- **Position:** `LocationManager`, kein Fused Location, keine Play-Dienste, kein API-Key, kein Hintergrundstandort. Ein gespeicherter Fix (höchstens 2 Minuten alt, genaueste Quelle) wird bevorzugt, sonst eine frische Einzelmessung (12 s Zeitlimit). Ortsname über `Geocoder` (Stadtteil, Ort; keine Straße), nur wenn das Gerät ein Backend hat; sonst liefert `location__current` auf etwa 100 m gerundete Koordinaten.
- **Berechtigung:** `ACCESS_FINE_LOCATION` und `ACCESS_COARSE_LOCATION` im Manifest, Anfrage erst beim Einschalten der Integration (`requestPermission` der Spec). „Ungefähr“ genügt (Ortsname, Luftlinie, Wetter), dann ohne GPS.
- **Navigation:** Dart baut die Intents (`MapsIntents`, rein, getestet), Kotlin startet sie nur. Google Maps (`com.google.android.apps.maps`, optionale App, `KnownApps.googleMaps`): `google.navigation:` für Auto, Fuß, Rad, die Routenseite `https://www.google.com/maps/dir/` für ÖPNV. Ohne Google Maps (oder wenn es den Intent nicht annimmt) `geo:0,0?q=…` an jede Karten-App (Organic Maps, OsmAnd); das zeigt das Ziel, startet aber keine Führung. Keine passende App: „Keine Karten-App gefunden …“. Kotlin lässt nur `geo:`, `google.navigation:`, `https://www.google.com/maps/…` und höchstens das Maps-Paket zu (`LocationPick.isAllowedLaunch`).
- **Entfernung:** Haversine auf den Standort, Ziel per Ortsname (Geocoder der Wetter-Integration, `OpenMeteoGeocoder`: der Name geht raus, nie die Position) oder „Breite,Länge“ als Text; Ergebnis „ca. 12 km“, ausdrücklich Luftlinie.
- **Wetter:** `weatherLocationPortProvider` (`app/lib/di/weather.dart`) liefert `LocationWeatherPort`, solange `location` eingeschaltet ist. Ohne Berechtigung oder Fix antwortet er `null`, das Wetter nimmt den Heimatort.
- **Datenschutz:** `sensitive: true`, die Tools gehen nur an Anbieter ab der Datenschutzstufe (bestehende TEE-Logik). Das Prüfprotokoll (`AuditRecorder`) speichert bei Tool-Aufrufen nur Name und Status, bei Bestätigungen die Beschreibung: `describe` der Navigations-Tools nennt das Ziel deshalb nicht („Navigation starten“). Zusammenfassungen der Tool-Karten und alle Fehlertexte (auch aus Kotlin) enthalten weder Koordinaten noch Ortsnamen; Kotlin loggt nichts. Die Antwort des Tools selbst steht im Gespräch (wie jede Tool-Antwort), das ist der Zweck der Integration.
- **Vertrauen:** alle drei Tools nicht vertrauenswürdig (Ortsnamen aus Geocoder und Geocoding-Dienst), `app/test/trust/location.json`.
- **Nicht dabei:** Hintergrundstandort, Geofencing, Route/Fahrzeit (braucht die Directions-API und damit einen Key).
