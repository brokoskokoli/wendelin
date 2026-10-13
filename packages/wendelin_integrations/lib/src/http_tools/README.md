# HTTP-Tools (`http`, `http_sensitive`)

Nutzerdefinierte Tools (Konzept „Erweiterungswege 1. HTTP-Tool“), Entscheidungen in [ADR 0011](../../../../../docs/adr/0011-http-tools-netzziele.md).

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `http__<name>` | vom Nutzer gewählt, nie unter dem Vorschlag der Methode; `write` wird ohne `autoRun` bestätigt | eine `HttpToolDefinition` ausführen |

- **Integrationen**: `http` („HTTP-Tools“) enthält alle aktiven, nicht sensiblen Definitionen, `http_sensitive` („HTTP-Tools (sensibel)“, `sensitive = true`) die sensiblen. `HttpToolsIntegration.all(definitions, runner)` liefert beide (die zweite nur, wenn es sensible gibt). Der Tool-Name bleibt beim Umschalten gleich.
- **Risiko**: Vorschlag nach Methode, `GET`/`HEAD` → read, `POST`/`PUT`/`PATCH` → write, `DELETE` → external. `effectiveRisk` ist das Maximum aus Nutzerwahl und Vorschlag (K8 b, nur verschärfen). Es gibt kein Undo, deshalb wird `write` wie `external` bestätigt (K13 j). Nur mit `autoRun: true` („Ohne Nachfrage ausführen (kein Rückgängig)“ im Editor) bleibt es bei `write`, und das nur, wenn Vorschlag **und** Nutzerwahl `write` sind (also `POST`/`PUT`/`PATCH` mit Wahl `write`). Ein auf `write` verschärftes `GET` wird immer bestätigt.
- **Plattformen**: Android, iOS. **Berechtigung**: `INTERNET`. Ohne Einrichtung gibt es keine Tools.

## Definition (`HttpToolDefinition`, JSON mit `schemaVersion`)

```json
{
  "schemaVersion": 1, "id": "…", "name": "ha_light_on",
  "description": "Schaltet ein Licht in Home Assistant ein.",
  "method": "POST",
  "url": "http://homeassistant.local:8123/api/services/light/turn_on",
  "inputSchema": {"type": "object", "properties": {"entity": {"type": "string"}, "brightness": {"type": "integer"}}, "required": ["entity"]},
  "body": {"entity_id": "{entity}", "brightness": "{brightness}"},
  "auth": {"kind": "apiKey", "secretRef": "http.ha_light_on.token"},
  "risk": "write", "autoRun": true, "sensitive": false, "homeNetwork": true, "enabled": true, "timeoutSeconds": 15
}
```

`autoRun` ist optional (Standard `false`, wird nur bei `true` geschrieben). Die Schema-Version bleibt 1: Ältere Definitionen ohne das Feld lesen sich als `false`, also mit Bestätigung, und eine ältere App, die das Feld nicht kennt, ignoriert es.

`ApiKeyAuth` ohne `headerName` sendet `Authorization: Bearer <Secret>`, mit `headerName` den Wert roh in diesem Header. `CustomHeadersAuth` bildet Header auf Secret-Referenzen ab. OAuth wird nicht unterstützt. Export/Import über `exportHttpTools`/`importHttpTools`; ungültige Definitionen werden mit lesbarem Fehler abgelehnt.

Weitere Beispiele:
- **n8n-Webhook**: `POST https://n8n.tail1234.ts.net/webhook/einkauf`, Body `{"artikel": "{item}"}`, `ApiKeyAuth("…", headerName: "X-N8n-Key")`.
- **Home Assistant Zustand lesen**: `GET http://192.168.178.20:8123/api/states/{entity}`, `responsePath: "state"`.

## Platzhalter-Regeln

- `{name}` (Buchstaben, Ziffern, `_`) muss eine Eigenschaft im `inputSchema` sein.
- Erlaubt nur in **Pfad** und **Query-Werten**, nie in Schema, Host, Port, Zugangsdaten, Query-Namen oder Anker. Host, Schema und Port stammen allein aus der Vorlage.
- Pfadwerte werden als ein Segment kodiert (`Uri.encodeComponent`). `/` und `\` im Wert, leere Werte und Segmente `.`/`..` werden abgelehnt. `%2F` wird zu `%252F`.
- Query-Werte werden URL-kodiert. Ein Parameter, dessen Wert nur aus einem fehlenden Platzhalter besteht, fällt weg.
- Header: Platzhalter nur in nicht geheimen Headern. Werte mit CR/LF/Steuerzeichen oder Nicht-ASCII werden abgelehnt. `Authorization`, `Cookie` und Namen mit `token`, `secret`, `key`, `auth`, `bearer`, `credential`, `session` … sind als Klartext-Header verboten, sie gehören in die Anmeldung. `Host`, `Content-Length` und andere Rahmen-Header setzt die App.
- JSON-Body: Ein String, der genau `{name}` ist, wird typgerecht ersetzt (Zahl bleibt Zahl, Liste bleibt Liste). In längeren Strings wird der Wert als Text eingesetzt. Fehlende optionale Werte fallen aus Objekten und Listen heraus. Der Body wird als Baum aufgebaut und kodiert, nie durch String-Zusammenbau. Formular-Body (`bodyFormat: form`): flaches Objekt aus Texten, Zahlen und Ja/Nein.
- Fehlende Pflichtargumente ergeben ein Fehler-Ergebnis „Ungültige Argumente: „x“ fehlt“.

## Netzziel (`checkHttpTarget`, `PinnedHttpToolTransport`)

- Nur `https`. `http` nur für Heimnetz-Ziele: private IP-Literale (RFC 1918, Tailscale `100.64.0.0/10`, ULA), Namen auf `.local`, `.lan`, `.home`, `.home.arpa`, `.internal`, `.ts.net` oder als „Heimnetz“ markierte Definitionen. Außerdem müssen alle aufgelösten Adressen privat sein.
- Der Name wird aufgelöst. Ein nicht als Heimnetz geltender Name, der privat auflöst, wird abgelehnt (DNS-Rebinding).
- Loopback und Link-Local (`127/8`, `::1`, `169.254/16`, `fe80::/10`) werden immer abgelehnt, außer im Test-Modus (`allowLoopback`). `0.0.0.0`, Multicast, `100::/64` und reservierte Bereiche sind immer verboten. IPv4 in IPv6 (mapped, SIIT `::ffff:0:a.b.c.d`, NAT64 `64:ff9b::/96` und `64:ff9b:1::/48`, 6to4) wird nach dem IPv4-Teil bewertet, ebenso ungewöhnliche Schreibweisen (`2130706433`, `0x7f.1`, `127.1`, `010.0.0.1`) und IPv6-Zonen.
- `PinnedHttpToolTransport` verbindet nur zu den geprüften Adressen. Der Name wird kein zweites Mal aufgelöst, TLS prüft trotzdem gegen den Hostnamen. Es gibt keinen Proxy.
- Weiterleitungen nur auf denselben Origin, höchstens 3. Bei 303 (und 301/302 bei Nicht-GET) wird auf `GET` ohne Body gewechselt.

## Ausführung und Ergebnis

- Zeitlimit je Definition (Standard 15 s, 1–120 s) für den ganzen Aufruf. Danach (und nach Abbruch oder Ende) schließt der Pinning-Transport die Verbindung hart. Außer Abbruch entkommt keine Ausnahme aus `call()`: Unerwartetes wird zu „Unerwarteter Fehler beim HTTP-Aufruf“ (Programmierfehler, also `Error`, meldet der Runner zusätzlich über `Zone.current.handleUncaughtError`), ein kaputter `Location`-Header zu „Ungültige Weiterleitung“. Antwort höchstens 256 KB, danach Abbruch und Hinweis „abgeschnitten“. Nur Text, JSON und XML werden gelesen.
- `responsePath` (`data.items.0.name`) wählt einen Teil der JSON-Antwort aus. Fehlt der Pfad, ist das ein Fehler.
- Das Ergebnis steht mit Daten-Hinweis in `<http_response …>`. Tags im Inhalt werden entschärft, das Kürzen übernimmt der `ResultShaper`. Bei Status ≥ 400 kommt `isError` mit Status und einem Ausschnitt von 300 Zeichen. Den Reason-Phrase des Servers sieht das Modell nicht.

## Secrets

`HttpToolSecrets.read(ref)` wird erst nach Vorlagen- und Zielprüfung aufgerufen, unmittelbar vor dem Senden. Secrets stehen nie in Ergebnis, Fehlertext, `toString`, Export-JSON, `SentRequest` (Wert `••••••`), Audit-Argumenten oder `describeForConfirmation`. Spiegelt ein Server das Secret zurück (roh, JSON-escaped oder URL-kodiert), wird es durch `[geheim]` ersetzt. Bei Secrets unter 4 Zeichen und anderen Kodierungen (z. B. Base64) greift das nicht.

## Editor-Test

`HttpToolTester(runner).run(definition, args)` liefert Status, Dauer, eine gekürzte Vorschau (4000 Zeichen) und die gesendete Anfrage ohne Secrets.

## Testhilfen

`FakeHttpToolSecrets` (zeichnet Lesezugriffe auf), `httpToolSecretsContract` (auch für den `SecretStore`-Adapter der App), `ClientHttpToolTransport` mit `MockClient` und einem eigenen Resolver.
