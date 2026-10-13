# WP22 – MCP-Client (neues Paket `packages/wendelin_mcp/`)

Abhängig von: core, integrations (bestehend; wiederverwendet werden `BaseTool`, `DataEnvelope`/Daten-Hülle, `tool_args`). Konzept-Bezug: „MCP-Integration“ (Client, Abbildung auf das Tool-System, Vorlagen), „Tool-System → Erweiterungswege“, „Sicherheit → Secrets, Prompt-Injection“, K8 (b), K10. Rein Dart (`package:http`), keine Flutter-Importe.

## Paketschnitt
- Neues Paket `wendelin_mcp` im Pub-Workspace; Abhängigkeitsregel `wendelin_mcp -> core, integrations` in `tool/check_deps.dart` und `docs/ENGINEERING.md` (Abschnitt Layout und Abhängigkeitsregeln); `app -> alle` gilt weiter.
- Der SSE-Parser wandert von `wendelin_providers/lib/src/sse/` nach `wendelin_core` (reines Dart, keine Abhängigkeit) und wird aus `wendelin_providers` weiter exportiert, damit sich dort nichts ändert. Bestehende Provider-Tests bleiben grün.

## Transport (warum kein stdio)
- **Streamable HTTP** (MCP-Spezifikation 2025-06-18 und neuer): ein Endpunkt, `POST` mit JSON-RPC 2.0, `Accept: application/json, text/event-stream`; Antwort als JSON oder als SSE-Stream (Antwort plus Benachrichtigungen); Header `Mcp-Session-Id` (vom Server vergeben, bei 404 neue Sitzung) und `MCP-Protocol-Version`; `DELETE` beendet die Sitzung. Kein dauerhafter `GET`-Stream (Akku), Verbindung nur bei Bedarf.
- **Legacy-SSE** (2024-11-05) als Fallback: erkannt, wenn `POST` mit 4xx (405/404) antwortet und `GET` ein `endpoint`-Ereignis liefert; Antworten kommen dann über den SSE-Kanal, der nur für die Dauer eines Aufrufs offen bleibt.
- **Kein stdio**: Android erlaubt keine fremden Server-Prozesse als Kind der App (keine Laufzeiten wie Node/Python, W^X-Regeln, Hintergrundbeschränkungen, Akku); stdio-Server laufen auf dem Homeserver hinter einem stdio-zu-HTTP-Proxy (Konzept). Kurz in ADR 0010 begründen.
- Zeitlimits (Verbindung, Antwort; Standard z. B. 10 s / 30 s, im Rahmen der 60 s der Agent-Schleife), Abbruch über `CancelToken`, Antwortgröße begrenzt (z. B. 1 MB), Fehler als typisierte `McpException` (Netz, Auth nötig, Protokoll, Server-Fehler, Zeitüberschreitung).

## Protokoll und Lebenszyklus
- `initialize` (Client-Info, Protokollversion aushandeln, nur Fähigkeit `tools`), `notifications/initialized`, `tools/list` mit Paginierung (`cursor`), `tools/call`, `ping`. Cache der Tool-Liste mit Zeitstempel (Persistenz über ein schmales `McpCacheStore`-Interface, Umsetzung in der App); bei `notifications/tools/list_changed` neu laden.
- **Erreichbarkeit**: `probe()` → erreichbar / Auth nötig / nicht erreichbar / Protokollfehler, mit Latenz (für Status-Anzeige).
- `resources`/`prompts`, Sampling und Elicitation werden nicht angeboten (Server-Anfragen an den Client mit JSON-RPC-Fehler „nicht unterstützt“ beantworten).

## Auth
- `Bearer` und **eigene Header** mit Secret-Referenzen (wie `ApiKeyAuth`/`CustomHeadersAuth` in core); aufgelöst über ein `McpSecrets`-Interface (Lesen/Schreiben per Referenz), App-seitig über den `SecretStore`. Keine Secrets im Konfigurations-JSON.
- **OAuth 2.1 nach MCP-Spezifikation**, reine Logik ohne Browser: 401 mit `WWW-Authenticate` → Protected Resource Metadata (RFC 9728) → Authorization Server Metadata (RFC 8414, mit OIDC-Fallback) → dynamische Client-Registrierung (RFC 7591), falls keine Client-Id konfiguriert → PKCE S256 + `state` + `resource`-Parameter (RFC 8707) → Token-Tausch, Refresh, Ablaufbehandlung. Der Browser-Schritt ist ein Interface `AuthorizationBrowser { Future<Uri> authorize(Uri url, Uri redirect) }`, die App setzt es in WP27 um. Tokens nur über `McpSecrets`.
- Ein abgelaufenes, nicht erneuerbares Token setzt die Integration auf „Fehler“ (Tools pausiert, `reportError`).

## Abbildung auf das Tool-System
- `McpServerConfig { id, name, url, transport (auto|streamable|sse), auth, enabled, sensitive, confirmAll, toolOverrides }` – JSON-serialisierbar, Export ohne Secrets.
- `McpIntegration implements Integration`: `id` = `mcp_<slug>` (Slug aus dem Namen, nur `[a-z0-9]`, max. 16 Zeichen, eindeutig), Tools `mcp_<slug>__<tool>`; zu lange Namen (Grenze 64 Zeichen der Provider-APIs) gekürzt mit kurzem Hash-Suffix, kollisionsfrei, Zuordnung stabil.
- Risikostufe aus Annotationen: `readOnlyHint` → read, `destructiveHint` → external, sonst write. Annotationen sind Angaben des Servers (nicht vertrauenswürdig); die Override-Regel aus K8 (b) gilt: nur verschärfen. `confirmAll` am Server macht alle Tools `external`.
- MCP-Tools haben **kein Undo** (`ToolOutcome.undo == null`); die Tool-Karte zeigt dann kein „Rückgängig“.
- `inputSchema` wird übernommen und gegen das bestehende Argument-Prüfmodul validierbar gemacht (nicht unterstützte Schema-Teile dokumentiert, nicht still verworfen).
- Ergebnisse: `text` → Text, `structuredContent`/JSON → kompakter JSON-Text, `image` → Hinweistext mit MIME-Typ und Größe (keine Bilddaten ans Modell in M3), `resource_link`/eingebettete Ressourcen → Titel + URI; `isError` → `ToolOutcome.isError`. Alles in der Daten-Hülle (Inhalte sind Daten, keine Anweisungen); Kürzung über den bestehenden `ResultShaper` (Markierung).
- `describeForConfirmation`: Server-Name, Tool-Name, gekürzte Argumente.
- `checkAvailability`/`setupState`: Auth fehlt → „Einrichtung nötig“; nicht erreichbar → Status mit Grund.

## Netzziele
- Schema nur `https`, oder `http` ausschließlich für private/Heimnetz-Ziele (RFC 1918, `100.64.0.0/10` Tailscale-CGNAT, `*.ts.net`, `.local`/`.home.arpa`, Emulator `10.0.2.2`) – Klartext ins Internet wird abgelehnt. Keine Zugangsdaten in der URL (`userinfo`), Redirects nur auf denselben Origin. Gleiche Prüfung für OAuth-Endpunkte (dort nur `https`, außer `localhost`-Tests).

## Testhilfen
- `package:wendelin_mcp/testing.dart`: **`FakeMcpServer`** (In-Process-`HttpServer` aus `dart:io`, Streamable HTTP und Legacy-SSE umschaltbar, Bearer/OAuth-Endpunkte, skriptbare Tools, `list_changed`, Fehler, Verzögerung, Sitzungsablauf 404) – wird in WP29 auch als Testserver für den Emulator genutzt; `mcpClientContract` (Contract-Suite für Transport-Implementierungen); `package:wendelin_mcp/fakes.dart`: `FakeMcpSecrets`, `FakeAuthorizationBrowser`, In-Memory-Cache.
- ADR 0010 „MCP-Client“ (Transportwahl, kein stdio, keine dauerhafte Verbindung, Annotationen als Hinweis, kein Undo, Netzziel-Regeln, Paketschnitt).

## Abnahmekriterien
- [ ] Transport-Tests gegen `FakeMcpServer`: JSON- und SSE-Antworten, Benachrichtigungen im Stream, Paginierung, `Mcp-Session-Id`-Neuaufbau nach 404, Legacy-SSE-Fallback, Zeitlimit, Abbruch, zu große Antwort.
- [ ] Fixtures nach Spezifikation (`test/fixtures/`) für `initialize`, `tools/list`, `tools/call` (Text, JSON, Bild, Fehler, `isError`).
- [ ] OAuth-Ablauf vollständig gegen Fake-Server: Discovery (RFC 9728/8414), DCR, PKCE S256 (Verifier/Challenge geprüft), `state`-Prüfung, `resource`-Parameter, Refresh, abgelaufenes Token → Fehlerzustand. Tokens landen nur in `FakeMcpSecrets`.
- [ ] Namensabbildung tabellengetestet (Slug, Kürzung mit Hash, Kollisionen, ungültige Zeichen, Grenze 64).
- [ ] Risiko-Abbildung tabellengetestet (Annotationen, `confirmAll`, Overrides nur verschärfend).
- [ ] Netzziel-Prüfung tabellengetestet (https, http privat/Tailscale/öffentlich, `userinfo`, Redirect auf fremden Origin).
- [ ] Kein Secret in `toString`, Exceptions, Export-JSON oder Log-Ausgaben (Test mit Kanarienwert).
- [ ] SSE-Parser nach core verschoben, Provider-Tests unverändert grün; `check_deps` kennt `wendelin_mcp`; ENGINEERING.md aktualisiert.
- [ ] README des Pakets (Tools-Abbildung, Risiko, Auth, Netz, Grenzen); ADR 0010.
- [ ] Gate grün, Abdeckung `wendelin_mcp` ≥ 85 %.
