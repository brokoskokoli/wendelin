# WP28 – HTTP-Tool-Editor und Bring!-Einrichtung (`app/`)

Abhängig von: WP23 (HTTP-Tools), WP24 (Bring!), WP25 (`UserIntegrationSource`, Einstellungszeile „HTTP-Tools“, Knopf „+ HTTP-Tool“, App-Erkennung). Andockpunkte: `builtInIntegrationSpecs`, `SecureSecretStore`, `IntegrationDetailScreen`, Export. Konzept-Bezug: „Tool-System → Erweiterungswege 1“, „Einstellungen → HTTP-Tools“, „Eingebaute Integrationen → Bring!“, „Offene Fragen → Bring!“ (Share-Intent-Fallback), Design `integrationen` (Bring! „Login fehlt – Einrichten“).

## HTTP-Tools
- **Quelle** für `UserIntegrationSource`: Definitionen als JSON in den Einstellungen, Secrets im `SecretStore`, Löschen räumt beides auf.
- **Editor**: Name (Tool-Namensregel live geprüft), Beschreibung fürs Modell, Methode, URL-Vorlage mit Platzhalter-Hervorhebung, Header (geheime Header maskiert, nur ersetzbar), Body-Vorlage, Argumente als einfache Liste (Name, Typ, Pflicht, Beschreibung) mit Erzeugung des JSON-Schemas plus Rohmodus für eigenes Schema, Risikostufe (Vorschlag nach Methode), „sensibel“, „Heimnetz-Ziel“, Zeitlimit.
- **Testen**: Testargumente eingeben, `HttpToolTester` ausführen, gesendete Anfrage (ohne Secrets), Status, Dauer und gekürzte Antwort anzeigen. Ablehnung durch die Zielprüfung mit verständlichem Text.
- **Import/Export** ohne Secrets (wie MCP).

## Bring!
- Spec in `builtInIntegrationSpecs` mit `HttpBringApi` und Secrets aus dem `SecretStore`; Login-Dialog (E-Mail, Passwort, Hinweis „inoffizielle Schnittstelle, kann brechen“), Abmelden löscht Zugangsdaten und Tokens.
- Zustände laut Design: „Login fehlt – Einrichten“, aktiv, „Fehler – Schnittstelle nicht erreichbar“ mit Grund.
- **Fallback**: Scheitert die API, bietet die Tool-Karte „An Bring! senden“ (Share-Intent mit dem Artikeltext an `ch.publisheria.bring`, nur wenn die App installiert ist, App-Erkennung aus WP25), sonst nur die Fehlermeldung.

## Nachtrag aus den Reviews WP22/WP23 (Orchestrator)
- **`write` ohne Undo wird bestätigt** (gleiche Regel wie MCP, Review WP22): HTTP-Tools haben kein Undo. Effektive Stufe für Methoden mit Vorschlag `write` (POST/PUT/PATCH) ist standardmäßig `external` (Bestätigung). Neues Feld `autoRun` (Standard `false`) in `HttpToolDefinition` stellt die effektive Stufe ausdrücklich auf `write` zurück, nur wenn Vorschlag und Nutzerwahl `write` sind. Umsetzung in `packages/wendelin_integrations/lib/src/http_tools/` mit Tabellentests, JSON-Rundreise (Schema-Version beachten, alte Definitionen ohne Feld → `false`), ADR 0011 und README anpassen; im Editor als Schalter „Ohne Nachfrage ausführen (kein Rückgängig)“.
- Kleinigkeit aus Review WP23: Der Catch-all in `HttpToolRunner.call` soll Programmierfehler zusätzlich über `Zone.current.handleUncaughtError` melden.

## Abnahmekriterien
- [ ] Widget-Tests Editor: Anlegen, Validierung (Name, Platzhalter ohne Argument, Platzhalter im Host → Fehler), Testlauf gegen `MockClient`, Speichern registriert `http__<name>` im Katalog, Löschen entfernt Tool und Secrets.
- [ ] Agent-Integrationstest mit Fake-Provider: HTTP-Tool `write` läuft ohne Bestätigung und ohne Undo-Knopf, `external` zeigt Bestätigungskarte mit Methode/Host/Pfad, sensible Definition wird Standard-Zielen nicht angeboten.
- [ ] Bring!: Login/Logout mit `FakeBringApi`, Fehlerzustand bei API-Fehler, Share-Fallback nur mit installierter App (Fake-`AppPresencePort`), Undo auf der Tool-Karte.
- [ ] Kanarienwert-Test: geheime Header und Bring!-Passwort nie in Einstellungen-JSON, Export, Audit-Log, Debug-Log, Testlauf-Anzeige.
- [ ] Goldens: HTTP-Tool-Editor, Testergebnis, Bring!-Kachel in den Zuständen „Login fehlt“ und „Fehler“ (gegen `integrationen@1x.png` für die Kachel).
- [ ] Gate grün, APK baut.
- [ ] HTTP-`write` ohne `autoRun` verlangt Bestätigung; `autoRun` wirkt nur bei `write` (Tabellentest).
