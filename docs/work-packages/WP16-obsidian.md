# WP16 – Obsidian-Integration (`wendelin_integrations/lib/src/obsidian/` + Index in `wendelin_storage`)

Abhängig von: core, integrations (Listen-Markdown-Logik wiederverwenden, wo sinnvoll), storage (FTS5). Konzept-Bezug: „Eingebaute Integrationen → Obsidian“, „Sicherheit → Prompt-Injection“, K6 (Listen teilen sich ggf. den Vault).

## Tools (Risikostufen laut Konzept)
- `obsidian__search_notes` (r) – Volltextsuche über den Index (Titel, Pfad, Ausschnitt)
- `obsidian__read_note` (r) – Inhalt (gekürzt, als Daten markiert), optional Abschnitt
- `obsidian__list_folder` (r)
- `obsidian__create_note` (w, Undo = löschen, wenn unverändert)
- `obsidian__append_to_note` (w, Ziel per Überschrift; Undo)
- `obsidian__append_daily_note` (w; Tagesnotiz-Pfad/Format konfigurierbar wie Obsidian „Daily notes“: Ordner, Datumsformat, Vorlage; Undo)
- `obsidian__replace_section` (e, Bestätigung zeigt Diff)
- `obsidian__open_note` (w) – `obsidian://open?vault=…&file=…`-Link für die App

## Ports
- `VaultPort` (Ordnerbaum: list, read, write atomar, create, exists, modifiedAt, size) – Android SAF-Tree (WP18), Fake + Contract-Suite.
- `NoteIndexPort` (upsert(path, title, body, modifiedAt), remove, search(query, limit), knownFiles) – Implementierung in wendelin_storage (drift, FTS5, Schema-Migration v2 mit Migrationstest), Fake + Contract-Suite.
- Index-Sync: inkrementell nach `modifiedAt`, begrenzt (z. B. max. N Dateien pro Lauf, nur `.md`, `.obsidian/` und Anhänge ignorieren).

## Verhalten
- Markdown-Rest byte-genau erhalten (wie Listen), Frontmatter respektieren, Überschriften-Suche (ATX, optional setext), Einfügen am Abschnittsende.
- Pfade nur innerhalb des Vaults (keine `..`, absolute Pfade, Symlinks).
- Inhalte sind Daten: Hülle + Escaping wie bei web/lists.
- Gleichzeitige Zugriffe je Datei serialisieren (gleiches Muster wie Listen, prozessweit).

## Abnahmekriterien
- [ ] Tools mit Fake-Ports getestet inkl. Undo, externer Änderung, parallelen Calls.
- [ ] Index-Implementierung in storage mit Migration v1→v2 und FTS-Ranking-Tests.
- [ ] Pfad-Sicherheit tabellengetestet.
- [ ] Contract-Suites für VaultPort und NoteIndexPort.
- [ ] README; Eval-Fälle (de/fr/en, je 2) für WP10 im README als Vorlage.
- [ ] Gate grün, Abdeckung ≥ 85 %.
