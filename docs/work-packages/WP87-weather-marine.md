# WP87 – Wetter und Meer mit wählbarem Wetterdienst (`wendelin_integrations`, `app/`)

**Zuordnung:** M5.

Bezug: Konzept (Wetter und Meer, Open-Meteo), Wunsch Maintainer 2026-10-18: Wetterdienst wählbar.

## Inhalt
1. `weather__forecast` (r: heute, morgen, Stunden, Tage; Regen, Wind, Temperatur), `weather__marine` (r: Wellenhöhe, Dünung, Periode, Wassertemperatur; nur Open-Meteo Marine).
2. Wetterdienste ohne Key: **Open-Meteo** (Standard), **Bright Sky** (DWD-Daten), **MET Norway** (yr.no, User-Agent mit Kontakt nötig – App-Name + Repo-URL). Auswahl in der Einrichtung; gemeinsames Datenmodell, Adapter je Dienst.
3. Ort: Ortsname aus der Frage (Geocoding über Open-Meteo), sonst aktueller Standort (über WP86-Port, falls aktiv), sonst einstellbarer Heimatort.
4. Antworten sprachfreundlich (kurz, gerundet).

## Abnahmekriterien
- [ ] Unit-Tests mit aufgezeichneten Antworten je Dienst; Live-Test je Dienst (eine Abfrage).

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/ARCHITECTURE.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest in `docs/testing/m5-device.md` ergänzen. Gate grün.
