# WP94 – Schnellwechsel des Standard-Agenten per langem Druck (`app/`)

**Zuordnung:** M5.

Bezug: Wunsch Maintainer 2026-10-16: oben auf den aktuellen Agenten (Profil-/Modell-Anzeige) gedrückt halten → Element wird markiert (kurze Vibration, wenn Vibration aktiv), nach ~2 s Popup mit allen eingerichteten Agenten; Auswahl setzt den neuen Standard und leert den Chat direkt (Auswahl = Bestätigung, keine extra Rückfrage).

## Abnahmekriterien
- [ ] Widget-Tests (Markierung, Popup nach Haltezeit, Abbruch beim Loslassen vorher, Standard gesetzt, Chat leer); Golden des Popups.

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/ARCHITECTURE.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest in `docs/testing/m5-device.md` ergänzen. Gate grün.
