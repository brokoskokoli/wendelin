# WP93 – Wake Word bei sichtbarem Chat setzt das App-Gespräch fort (`app/`)

**Zuordnung:** M5.

Bezug: Wunsch Maintainer 2026-10-16, Entscheidung 2026-10-18: nur wenn der Chat der App sichtbar ist (App im Vordergrund, Chat-Bildschirm oben). Sonst wie heute Overlay mit neuem Gespräch (K41).

## Inhalt
1. Wake-Word-Dienst fragt den Vordergrundzustand ab (Chat sichtbar?) und startet dann das Zuhören im Chat mit bestehendem Kontext statt des Overlays.
2. Gesprächsmodus, Barge-in und Stopp verhalten sich im Chat wie im Overlay.

## Abnahmekriterien
- [ ] Widget-/Integrationstests (Chat sichtbar → Chat; Einstellungen offen → Overlay); Emulator-E2E.

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/architecture/checklists.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest als eigene Datei `docs/testing/m5/<wp>.md` anlegen (Index `docs/testing/m5/README.md` wird erzeugt). Gate grün.
