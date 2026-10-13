# WP23 – HTTP-Tools (`packages/wendelin_integrations/lib/src/http_tools/`)

Abhängig von: core, integrations (bestehend; `BaseTool`, Daten-Hülle, `web/fetch_guard.dart` als Vorbild für die Zielprüfung). Konzept-Bezug: „Tool-System → Erweiterungswege 1. HTTP-Tool (deklarativ)“, „Einstellungen → HTTP-Tools“, „Sicherheit“, K8 (b), K10. Rein Dart.

## Modell
- `HttpToolDefinition { id, name, description, inputSchema, method, urlTemplate, headers, bodyTemplate?, auth, risk, sensitive, enabled, timeout, responsePath? }` – JSON-serialisierbar mit Schema-Version, Export/Import ohne Secrets (Auth nur als Secret-Referenz wie `ApiKeyAuth`/`CustomHeadersAuth`).
- Eine Integration `http` („HTTP-Tools“) mit allen aktiven Definitionen als Tools `http__<name>`; Name nach Tool-Namensregel, eindeutig. Alternativ je Definition eine eigene Integration, falls `sensitive` pro Tool sauberer abbildbar ist – Entscheidung im ADR 0011 festhalten.

## URL-, Header- und Body-Vorlagen
- Platzhalter `{arg}` nur in **Pfad** und **Query**, nie in Schema, Host oder Port. Pfadwerte werden als einzelnes Segment kodiert (kein `/`, kein `..`), Query-Werte URL-kodiert; Platzhalter in Headern nur für nicht-geheime Header und ohne Zeilenumbrüche (Header-Injection).
- Body-Vorlage als JSON mit Platzhaltern auf Werte-Ebene (typgerecht eingesetzt, kein String-Zusammenbau); Formular-Body optional.
- Fehlende Pflichtargumente → Fehler-Outcome, das das Modell lesen kann.

## Ausführung und Netzziel (SSRF)
- Host, Schema und Port kommen **nur** aus der vom Nutzer gespeicherten Vorlage. Das ist die Allowlist: genau dieser Origin; Redirects nur innerhalb desselben Origins, höchstens 3.
- Private Ziele (Home Assistant im LAN, n8n auf dem Homeserver, Tailscale `100.64.0.0/10`, `*.ts.net`) sind erlaubt, weil der Nutzer sie ausdrücklich eingetragen hat; DNS-Auflösung wird trotzdem geprüft: Ein als öffentlich eingetragener Host, der auf eine private oder Loopback-Adresse auflöst, wird abgelehnt (DNS-Rebinding), außer der Nutzer hat das Ziel als „Heimnetz“ markiert. Loopback/Link-Local (`127.0.0.0/8`, `169.254.0.0/16`, `::1`) immer abgelehnt, außer im Test-Modus.
- `http` nur für Heimnetz-Ziele (gleiche Regel wie WP22), sonst `https`.
- Zeitlimit (Standard 15 s), Antwortgröße begrenzt (z. B. 256 kB, dann Abbruch und Kürzungshinweis), nur Text/JSON-Antworten; optional `responsePath` (einfacher Punkt-Pfad) zum Auswählen eines Teils der JSON-Antwort.
- Ergebnis in der Daten-Hülle, Kürzung über `ResultShaper`; HTTP-Status ≥ 400 → `isError` mit Status und kurzem Ausschnitt.
- Secrets werden erst beim Senden aus einem `HttpToolSecrets`-Interface gelesen; sie erscheinen nie in Tool-Ergebnis, Fehlermeldung, Audit-Argumenten oder `describeForConfirmation`.

## Risiko und Bestätigung
- Der Nutzer legt die Risikostufe fest; Vorschlag nach Methode: `GET`/`HEAD` → read, `POST`/`PUT`/`PATCH` → write, `DELETE` → external. HTTP-Tools haben kein Undo.
- `describeForConfirmation`: Methode, Host, Pfad mit eingesetzten Werten (ohne Secrets), gekürzter Body.

## Test-Funktion für den Editor
- `HttpToolTester.run(definition, args)` führt eine Definition ohne Agent aus und liefert Status, Dauer, gekürzte Antwort und die tatsächlich gesendete Anfrage ohne Secrets (für die Vorschau im Editor, WP28).

## Testhilfen
- `package:wendelin_integrations/fakes.dart`: `FakeHttpToolSecrets`; Tests mit `MockClient` aus `package:http/testing.dart` und Fake-Resolver.
- ADR 0011 „HTTP-Tools und Netzziele“ (Allowlist = gespeicherter Origin, Heimnetz-Markierung, DNS-Rebinding, http nur im Heimnetz; gilt sinngemäß auch für MCP).
- README der Integration (Beispiele: Home Assistant Service-Aufruf, n8n-Webhook, Platzhalter-Regeln).

## Abnahmekriterien
- [ ] Vorlagen-Engine tabellengetestet (≥ 20 Fälle): Pfad-Segment-Kodierung, `/` und `..` in Werten, Query-Kodierung, Unicode, fehlende Argumente, Header-Injection mit `\r\n`, JSON-Body typgerecht.
- [ ] Zielprüfung tabellengetestet: Host aus Argument unmöglich, Redirect auf fremden Origin, DNS-Rebinding, Loopback/Link-Local, http öffentlich vs. Heimnetz, numerische IP-Schreibweisen.
- [ ] Ausführung mit `MockClient`: Erfolg, 4xx/5xx, Zeitlimit, zu große Antwort, Nicht-Text-Antwort, `responsePath`.
- [ ] Kanarienwert-Test: Secret erscheint in keinem Ergebnis, Fehlertext, `toString`, Export-JSON.
- [ ] JSON-Rundreise der Definitionen inkl. Schema-Version; Import lehnt ungültige Definitionen mit lesbarem Fehler ab.
- [ ] Risiko-Vorschlag nach Methode und Override nur verschärfend getestet.
- [ ] README, ADR 0011; Gate grün, Abdeckung `wendelin_integrations` ≥ 85 %.
