# WP24 – Integration „Bring! Einkaufsliste“ (`packages/wendelin_integrations/lib/src/bring/`)

Abhängig von: core, integrations (bestehend; `common/matching.dart` für unscharfe Treffer wie bei Listen, `BaseTool`, Daten-Hülle). Konzept-Bezug: „Eingebaute Integrationen → Bring!“ (inoffizielle API, Login, eigenes Modul mit Fehleranzeige), „Offene Fragen → Bring!“ (Nutzungsbedingungen, Fallback Share-Intent), „Secrets“. Rein Dart. Die Einrichtung in der App folgt in WP28.

## Client
- Interface `BringApi` (login, refresh, lists, items, saveItem, removeItem, completeItem) + `HttpBringApi` gegen die inoffizielle REST-API (wie sie die Home-Assistant-Integration nutzt; Endpunkte und Felder in der README dokumentieren, Quelle angeben, nicht deren Code kopieren).
- Zugangsdaten (E-Mail, Passwort) und Tokens nur über ein `BringSecrets`-Interface (App: `SecretStore`). Token-Ablauf → einmal neu anmelden, sonst Fehlerzustand.
- Robustheit, weil die API jederzeit brechen kann: unerwartete Antworten (fehlende Felder, andere Typen, HTML statt JSON, 401/403/429/5xx) führen zu einem klaren `PortException` mit Art, nie zu einem Absturz; die Integration meldet dann „Fehler“ (`reportError`, Tools pausiert) mit verständlichem Text und Hinweis auf den Fallback.
- Zeitlimit, Rate-Limit-Behandlung (kein automatisches Wiederholen schreibender Aufrufe).

## Tools (Risikostufen laut Konzept)
- `bring__list_lists` (r)
- `bring__get_items` (r) – `list` (optional, sonst Standardliste), offene und zuletzt gekaufte
- `bring__add_items` (w) – `list`, `items: [{ name, spec? }]` (Mengenangabe als `spec`, z. B. „2 Liter“); bereits offene Artikel werden nicht doppelt angelegt; Undo entfernt genau die hinzugefügten
- `bring__remove_item` (w) – Undo legt den Artikel mit gleicher Angabe wieder an
- `bring__complete_item` (w) – Undo legt ihn zurück auf die offene Liste
- Listen- und Artikelauflösung unscharf (Groß/Klein, Umlaute, Plural/Singular) mit Rückfrage bei Mehrdeutigkeit, gleiches Verhalten wie Listen (K6).
- Ergebnisse in der Daten-Hülle (Artikelnamen sind Daten).

## Integration
- `BringIntegration`: Setup-Schritt „Login“ (fehlt → „Einrichtung nötig“), `sensitive` Standard aus; `checkAvailability` unabhängig von der installierten App (API reicht), Hinweis auf App-Fallback nur informativ.
- Fallback-Beschreibung für die App (WP28): Share-Intent mit Artikeltext an `ch.publisheria.bring`, wenn die API scheitert.

## Testhilfen
- `package:wendelin_integrations/fakes.dart`: `FakeBringApi`, `FakeBringSecrets`; `testing.dart`: `bringApiContract` (Contract-Suite, die `FakeBringApi` und `HttpBringApi` gegen aufgezeichnete Fixtures bestehen).
- Fixtures in `test/fixtures/bring/` sind nachgebaut bzw. anonymisiert (keine echten Konten, UUIDs oder Tokens).
- Live-Test `@Tags(['live'])` nur, wenn `BRING_EMAIL`/`BRING_PASSWORD` gesetzt sind: Login, Listen lesen, einen Testartikel anlegen und wieder entfernen. Nie Zugangsdaten ausgeben.

## Abnahmekriterien
- [ ] Alle Tools mit `FakeBringApi` getestet inkl. Undo, Duplikaten, Mehrdeutigkeit, Mengenangabe.
- [ ] `HttpBringApi` gegen Fixtures: Login, Token-Erneuerung, Listen, Artikel; Fehlerfälle (401 nach Erneuerung, 429, 5xx, HTML-Antwort, fehlende Felder) → definierter Fehler, Integration auf „Fehler“.
- [ ] Contract-Suite `bringApiContract` von Fake und HTTP-Implementierung bestanden.
- [ ] Kanarienwert-Test: Passwort/Token in keinem Ergebnis, Fehlertext, `toString`, Log.
- [ ] Eval-Fälle für WP29 in der README (de/fr/en, je 2, z. B. „Setz 2 Liter Milch auf die Bring-Liste“).
- [ ] README (Tools, Risiko, inoffizielle API, Nutzungsbedingungen-Hinweis, Fallback); Gate grün, Abdeckung ≥ 85 %.
