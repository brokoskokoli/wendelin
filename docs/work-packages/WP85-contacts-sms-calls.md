# WP85 – Kontakte, SMS und Anrufe mit Vorschau in der App (`wendelin_integrations`, `app/`, Android)

**Zuordnung:** M5.

Bezug: Konzept (Kontakte, Nachrichten und Anrufe), Entscheidung Maintainer 2026-10-18: Statt Intent zum SMS-Programm zeigt die App selbst ein Vorschau-Popup mit Kontaktname und Nachrichtentext; der Text wird vorgelesen; „Absenden“ in der App sendet. Abweichung vom Konzept („Nutzer sendet selbst im SMS-Programm“) → Konzept-Eintrag.

## Inhalt
1. `contacts__find` (r, sensibel): Name → Nummern/Mail, mehrdeutige Treffer zur Auswahl.
2. `sms__compose` (e): Vorschau-Popup (Empfänger mit Name und Nummer, Text editierbar), Vorlesen „Nachricht an X: …“, Buttons „Absenden“ und „Abbrechen“; Senden über `SmsManager` (Berechtigung `SEND_SMS` erst bei Aktivierung). Kein Senden ohne Tipp auf „Absenden“, auch nicht im Gesprächsmodus oder gesperrt.
3. `phone__call` (e): Vorschau-Popup (Name, Nummer), „Anrufen“ startet den Anruf (`CALL_PHONE`), sonst Wählbildschirm.
4. Integration „sensibel“: nur an TEE-Anbieter und Claude, andere per Freigabe (bestehende Logik).
5. Audit-Eintrag mit Empfängername, ohne Nachrichtentext.

## Abnahmekriterien
- [ ] Unit-Tests (Kontaktsuche, Mehrdeutigkeit), Widget-Tests Popup, Test „kein Senden ohne Tipp oder gesprochene Bestätigung“.
- [ ] Sprachbestätigung (Nachtrag 2026-10-18, K49): Nach dem Vorlesen fragt Wendelin „Soll ich anrufen?“ bzw. „Soll ich sie absenden?“. „ja“/„anrufen“/„absenden“ führt aus, „nein“/„abbrechen“ bricht ab. Bei unklarer Antwort führt Wendelin nichts aus und fragt erneut. Gilt auch im Gesprächsmodus, bei gesperrtem Gerät nie. Tests für jede dieser Antworten.
- [ ] Emulator: Popup erscheint, Senden an Emulator-Nummer (E2E-Agent).

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/architecture/checklists.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest als eigene Datei `docs/testing/m5/<wp>.md` anlegen (Index `docs/testing/m5/README.md` wird erzeugt). Gate grün.
