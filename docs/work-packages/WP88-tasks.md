# WP88 – Aufgaben als Listen mit Fälligkeit (`wendelin_integrations`, `app/`)

**Zuordnung:** M5.

Bezug: Konzept (Aufgaben: erst `Tasks.md` im Vault), Entscheidung Maintainer 2026-10-18: Aufgaben auf Basis der vorhandenen Listen (K6) statt zweiter Ablage.

## Inhalt
1. Listen-Einträge bekommen optional Fälligkeit (Datum, ggf. Uhrzeit) und Priorität, Markdown-kompatibel (z. B. Obsidian-Tasks-Format `📅 2026-10-20`), damit Vault-Apps sie lesen.
2. Tools: `tasks__add` (w, Undo), `tasks__list` (r: heute/überfällig/alle, je Liste), `tasks__complete` (w, Undo). Standard-Aufgabenliste einstellbar.
3. Optional Erinnerung über Wecker/Timer-Integration (nur wenn einfach, sonst Folgepunkt).

## Abnahmekriterien
- [ ] Unit-Tests Parser/Writer (Rundreise ohne Verlust bestehender Einträge), Tools.

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/architecture/checklists.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest als eigene Datei `docs/testing/m5/<wp>.md` anlegen (Index `docs/testing/m5/README.md` wird erzeugt). Gate grün.
