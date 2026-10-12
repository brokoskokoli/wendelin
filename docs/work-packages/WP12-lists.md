# WP12 – Integration „Listen“ (`packages/wendelin_integrations/lib/src/lists/` + App-Port)

Abhängig von: WP06 (Integrationsmuster, Ports) für den Dart-Teil; der Android-Teil (SAF) wird in WP08/WP09 mit verdrahtet. Konzept-Bezug: „Eingebaute Integrationen → Listen (K6)“.

## Verhalten
- Der Nutzer definiert in den Einstellungen beliebig viele Listen: `ListDefinition(id, name, aliases, target)`; `target` ist ein vom Port vergebener Datei-Handle (Android: SAF-URI mit persistenten Rechten, ausgewählt über die Dateiauswahl; neue Datei anlegen möglich).
- Format der Zieldatei: Markdown. Einträge sind Aufgaben-Zeilen `- [ ] Milch` bzw. `- [x] Milch`. Alles andere in der Datei (Überschriften, Text, Frontmatter) bleibt unverändert. Neue Einträge kommen ans Ende des ersten Aufgabenblocks, sonst ans Dateiende. Optional pro Liste: Abschnitt (Überschrift), unter dem gearbeitet wird.
- Listenauflösung: Name oder Alias, unscharf (Groß/Klein, Umlaute, Plural/Singular, „Einkaufsliste“ ≈ „Einkaufen“); bei Mehrdeutigkeit Fehler-Outcome mit den Kandidaten, damit das Modell nachfragt.
- Schreiben konfliktarm: Datei vor jeder Änderung neu lesen, Änderung zeilenbasiert anwenden, atomar zurückschreiben (Obsidian-Sync kann parallel schreiben).

## Tools
- `lists__list_lists` (r) – Namen und Anzahl offener Einträge
- `lists__get_items` (r) – `list`, `include_done` (Standard false)
- `lists__add_items` (w) – `list`, `items: [string]`; Duplikate (offen, gleicher Text) werden nicht doppelt angelegt; Undo entfernt genau die hinzugefügten Zeilen
- `lists__complete_item` (w) – `list`, `item` (unscharfer Treffer); Undo setzt zurück
- `lists__remove_item` (w) – `list`, `item`; Undo fügt die Zeile wieder an derselben Stelle ein
- `lists__clear_completed` (e) – erledigte Einträge löschen, immer mit Bestätigung

## Port
`ListFilePort { Future<String> read(handle); Future<void> write(handle, content); Future<bool> exists(handle); }` + Fake + Contract-Suite. Android-Implementierung (WP08): SAF über ein schlankes Plugin (z. B. `shared_storage` oder eigener Platform Channel via Pigeon), Dateiauswahl in WP09 (Einstellungen → Listen: anlegen, umbenennen, Aliase, Ziel wählen/neu anlegen, löschen).

## Abnahmekriterien
- [ ] Markdown-Parser/Writer tabellengetestet (gemischte Inhalte, Frontmatter, verschachtelte Listen, CRLF, fehlender Zeilenumbruch am Ende, Abschnitt-Option) – Rest der Datei byte-genau erhalten.
- [ ] Listenauflösung tabellengetestet (≥ 15 Fälle de/en inkl. Mehrdeutigkeit).
- [ ] Alle Tools mit Fake-Port getestet inkl. Undo und gleichzeitiger externer Änderung zwischen Lesen und Undo.
- [ ] Sätze „Füge Milch und Eier zur Einkaufsliste hinzu“, „Was steht auf der Liste SmartSSH?“ als Eval-Fälle in WP10.
- [ ] README der Integration; Gate grün, Abdeckung ≥ 85 %.
