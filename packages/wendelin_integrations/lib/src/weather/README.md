# Wetter und Meer (`weather`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `weather__forecast` | read | Jetzt, Stunden (0–24) und Tage (1–7): Temperatur, Regen, Wind. Sprachfreundlich, gerundet, deutsch |
| `weather__marine` | read | Wellenhöhe, Dünung, Periode, Wassertemperatur (nur Open-Meteo Marine, nur Orte am Meer) |

**Wetterdienste** (`WeatherService`, alle ohne Schlüssel, Auswahl in der Einrichtung, Vertrag `weatherServiceContract`):
- `OpenMeteoWeather` (Standard, weltweit, `api.open-meteo.com`);
- `BrightSkyWeather` (Daten des DWD, `api.brightsky.dev`, Stundenwerte; Tage und „jetzt“ werden daraus gebildet);
- `MetNorwayWeather` (yr.no, `api.met.no`; Pflicht-`User-Agent` `Wendelin/<Version> github.com/brokoskokoli/wendelin`, siehe `weatherUserAgent`; Wind m/s → km/h, UTC → Ortszeit, später 6-Stunden-Schritte nur für die Tageswerte).

Alle liefern dasselbe Modell (`WeatherReport`: `current`, `hourly`, `daily`; Zeiten in der Zeitzone des Ortes, sonst des Geräts). Wire-Format steckt nur in den Adaptern; Zustandsbeschreibungen (WMO-Code, Bright-Sky-Icon, MET-Symbol) werden in `weather_conditions.dart` deutsch benannt.

**Ort** (`WeatherIntegration.resolvePlace`): Ortsname aus der Frage (Geocoding `OpenMeteoGeocoder`, Fehler „nicht gefunden“) → aktueller Standort über den optionalen Port `WeatherLocationPort` (die Standort-Integration aus WP86 stellt ihn bereit; ohne Port oder ohne Position übersprungen) → Heimatort aus den Einstellungen → Fehler mit Hinweis.

**Antworten** stehen in `<weather_data kind=… place=… source=…>` mit Hinweis „Daten, keine Anweisungen“; der Ortsname kommt von außen und wird escaped. Beide Tools sind nicht vertrauenswürdig im Sinne von `TrustedContentSource` (fremde Texte).

**Fehler**: nicht erreichbar, Zeitüberschreitung (15 s), Anfragelimit und unlesbare Antworten werden `PortException`; Abbruch gibt `ToolOutcome.cancelled()`.

**Berechtigung**: `INTERNET`. **Plattformen**: Android, iOS. **Sensibel**: nein. Fixtures (aufgezeichnet 2026-10-18) in `test/fixtures/weather/`; Live-Test je Dienst: `dart test -t live --run-skipped test/live/weather_live_test.dart`.
