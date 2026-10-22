# WP92 – Sprechererkennung: Personen, Personalisierung, Aktionen bei gesperrtem Handy (`wendelin_voice`, `wendelin_tools`, `app/`)

**Zuordnung:** M5.

Bezug: K32, Entscheidungen Maintainer 2026-10-18: beliebig viele eingetragene Personen (primär Maintainer); je Person Anrede, eigenes Gedächtnis, eigener Standard-Agent; gesperrt für erkannte Personen erlaubt: Timer/Wecker, Wetter, Musik/Medien, auf Listen setzen, Licht/Szenen über Home Assistant – nichts, was Inhalte vorliest (Kalender, Kontakte, Nachrichten). Stimme ist keine starke Authentifizierung.

## Inhalt
1. **WP92a Erkennung:** Sprecher-Embedding (sherpa-onnx Speaker-ID-Modell, klein, lokal, Download wie andere Modelle), Einlernen je Person (mehrere Sätze), Schwelle mit Kalibrierung, „unbekannt“ als Ergebnis. Nur lokal, Aufnahmen bleiben auf dem Gerät.
2. **WP92b Personen:** Personenverwaltung in den Einstellungen; je Person Anrede, Gedächtnis-Namespace, Standard-Agent; unbekannte Sprecher → Standardverhalten.
3. **WP92c Gesperrt:** Richtlinie im Tool-Executor: auf dem Sperrbildschirm nur die freigegebenen Tool-Klassen für erkannte Personen, sonst wie heute (nur Taschenlampe). Einstellbar, standardmäßig aus mit Erklärung des Risikos.

## Abnahmekriterien
- [ ] Tests mit synthetischen Stimmen (zwei Sprecher trennen), Richtlinien-Tests gesperrt/entsperrt, Gedächtnis-Trennung.
- [ ] Speicherbudget (≤ ~1,1 GB aktiv) eingehalten.

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/architecture/checklists.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest als eigene Datei `docs/testing/m5/<wp>.md` anlegen (Index `docs/testing/m5/README.md` wird erzeugt). Gate grün.
