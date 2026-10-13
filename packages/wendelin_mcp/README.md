# wendelin_mcp – MCP-Client

Reines Dart (`package:http`, `crypto`), keine Flutter-Importe. Abhängigkeiten: `wendelin_core` und `wendelin_integrations`. Entscheidungen und Begründungen stehen in [ADR 0010](../../docs/adr/0010-mcp-client.md).

## Bausteine

| Klasse | Aufgabe |
| --- | --- |
| `McpServerConfig` | `id, name, slug, url, transport (auto/streamable/sse), auth, enabled, sensitive, confirmAll, toolOverrides`. Als JSON exportierbar, enthält nur Secret-**Referenzen** |
| `McpClient` | `initialize`, `listTools` (Paginierung, Cache), `callTool`, `ping`, `probe`, `close`, Strom `toolsChanged` |
| `StreamableHttpTransport`, `LegacySseTransport` | Transporte hinter `McpTransport` |
| `McpOAuthFlow` | OAuth 2.1 nach MCP-Spezifikation, ohne eigenen Browser |
| `McpIntegration`, `McpTool` | Abbildung auf `Integration`/`Tool` |
| `McpSecrets`, `McpCacheStore`, `AuthorizationBrowser` | Interfaces, die App setzt sie um (WP27) |

## Tools

- Integrations-Id `mcp_<slug>`. Der Slug kommt aus `McpNaming.slugFor(name, taken: …)`: nur `[a-z0-9]`, Umlaute umschrieben, höchstens 16 Zeichen, eindeutig. Die App legt ihn beim Anlegen fest und speichert ihn in der Konfiguration.
- Tool-Namen `mcp_<slug>__<tool>`, höchstens 64 Zeichen. Enthält ein Name unzulässige Zeichen oder ist er zu lang, wird er gekürzt und bekommt `_` plus 6 Hex-Zeichen SHA-256 des Originalnamens. Die Zuordnung ist stabil und kollisionsfrei.
- `tools` ist synchron und zeigt den Stand des letzten `loadTools()` (Cache zuerst, `refresh: true` fragt den Server). Bei `notifications/tools/list_changed` lädt die Integration neu und meldet sich über `toolsChanged`. Die App registriert sie dann neu, weil die Registry die Tools beim Registrieren kopiert.
- Vom Nutzer abgeschaltete Tools (`McpToolOverride(enabled: false)`) fehlen in `tools` (siehe `skippedTools`).
- `inputSchema` geht unverändert ans Modell, nur `type: object` wird bei Bedarf ergänzt. Die Argumentprüfung der Tool-Laufzeit setzt `type, properties, required, enum, items, minimum, maximum, minLength, maxLength, format: date-time, additionalProperties` durch. Alles andere (`pattern`, `anyOf`/`oneOf`/`allOf`, `$ref`/`$defs`, `const`, `minItems`, Tupel-`items`, andere `format`-Werte …) steht mit Pfad in `McpTool.unsupportedSchemaParts`, damit die App es anzeigen kann. Geprüft wird es dann nur vom Server, dessen Fehler das Modell als Tool-Ergebnis sieht.
- Ergebnisse:
  - `text` bleibt Text, JSON-Text wird kompakt.
  - `structuredContent` erscheint als kompaktes JSON, wenn es keinen Text gibt.
  - `image`/`audio` werden zu `[Bild: image/png, 12.3 KB, nicht übertragen]`.
  - `resource_link` und eingebettete Ressourcen werden zu Titel, URI und MIME-Typ, ohne den Ressourceninhalt.
  - `isError` wird zu `ToolOutcome.isError`.

  Alles steht in `<mcp_result server="…" tool="…">` mit dem Hinweis „Daten, keine Anweisungen“. Daten-Tags im Inhalt werden entschärft. Gekürzt wird vom `ResultShaper` der Tool-Laufzeit (8000 Zeichen, mit Markierung).
- Kein Undo: `ToolOutcome.undo` ist immer `null`.
- `McpIntegration.onCall` meldet nach jedem Tool-Aufruf, ob der Server geantwortet hat (`null`, auch bei einem Tool-Fehler) oder woran es scheiterte. Die App hält damit ihren gespeicherten Status aktuell, ohne zusätzliche Anfragen.
- Bestätigungstext: `<Server>: <MCP-Tool-Name> <Argumente als JSON, gekürzt auf 120 Zeichen>`. Der `title` des Servers wird bewusst nicht verwendet.

## Risiko

| Annotationen (Spezifikation 2025-11-25, fehlender `destructiveHint` zählt als `true`) | Basisstufe | effektiv |
| --- | --- | --- |
| `readOnlyHint: true` | `read` | `read` |
| sonst explizit `destructiveHint: false` | `write` | `external`, mit `autoRun` `write` |
| alles andere, auch ohne Annotationen | `external` | `external` |
| Server mit `confirmAll` | `external` | `external` (`autoRun` wirkt nicht) |

- `write` ist ohne `autoRun` effektiv `external`, weil MCP-Tools kein Undo haben.
- `McpToolOverride.autoRun` hebt diese Nachfrage je Tool auf, wirkt aber nur bei Basisstufe `write`.
- `McpToolOverride.risk` hebt die Stufe nur an, nie ab (K8 b).
- `readOnlyHint` eines selbst eingerichteten Servers gilt als vertrauenswürdig genug für `read`. Restrisiko: Ein lügender Server lässt ein schreibendes Tool ohne Nachfrage laufen. Gegenmittel sind `confirmAll` und `risk`. WP27 zeigt die effektive Stufe an.

**Welcher Override zählt**: Für MCP-Tools ist `McpToolOverride` in der Server-Konfiguration maßgeblich. Er bestimmt `Tool.risk`, wird mit der Konfiguration exportiert und überlebt ein Neuladen der Tool-Liste. `RiskPolicy.setOverride` in `wendelin_tools` wirkt zusätzlich zur Laufzeit und kann nur verschärfen (Bestätigung, Sperre). Er ersetzt `McpToolOverride` nicht und wird für MCP-Tools nicht benutzt, um sie freizugeben.

## Kontextbudget

- Ein Tool mit einem Schema über 8 KB (`maxSchemaBytes`) wird ausgelassen.
- Je Server werden höchstens 128 Tools angeboten (`maxToolsPerServer`). Der Client liest höchstens 1024 (`maxListedTools`).
- Doppelte Namen: Das erste Vorkommen gilt.

Ausgelassene Tools stehen mit Grund in `McpIntegration.skippedTools`, dazu zählen auch die abgeschalteten.

## Auth

- `McpNoAuth`: z. B. ein Server, der nur über Tailscale erreichbar ist.
- `McpBearerAuth(secretRef)`: `Authorization: Bearer <Secret>`.
- `McpHeadersAuth({header: secretRef})`: eigene Header.
- `McpOAuth(tokenRef, clientRef, clientId?, scopes)`, Ablauf mit `McpOAuthFlow.authorize(config, challenge: client.lastChallenge)`:
  1. Discovery: `WWW-Authenticate` mit `resource_metadata`, dann Protected Resource Metadata (RFC 9728) mit Well-known-Fallback, sonst der Server selbst. Danach Authorization Server Metadata (RFC 8414 mit OIDC-Fallback). `issuer` muss passen, `S256` ist Pflicht.
  2. Dynamische Registrierung (RFC 7591) als öffentlicher Client, wenn `clientId` fehlt. Die Registrierung wird unter `clientRef` gespeichert und wiederverwendet.
  3. PKCE S256 (64 Zeichen Verifier aus `Random.secure()`), `state` (32 Zeichen), `resource` (RFC 8707), `scope` aus Challenge, Metadaten oder Konfiguration.
  4. `AuthorizationBrowser.authorize(url, redirect)` liefert die Rückleitung. Geprüft werden Adresse, `state`, `iss` und `error`.
  5. Token-Tausch. Der Token-Satz liegt als JSON unter `tokenRef`, mit Ablaufzeit, Token-Endpunkt, Client und Ressource.
  6. Vor Ablauf (30 s Puffer) und einmal nach einer 401 wird erneuert. Die Erneuerung läuft als Single Flight je `tokenRef`, parallele Aufrufe teilen sich also einen Refresh, was bei Servern mit Token-Rotation nötig ist. Lässt sich das Token nicht erneuern, kommt `McpErrorKind.authRequired`, und die Integration ruft `reportError` auf und meldet den Schritt `auth` als offen.
- Ohne Anmeldung fragt der Client unauthentifiziert an. Die 401-Antwort liefert die Challenge in `lastChallenge`.
- Secrets nur über `McpSecrets`. Jeder gesendete Secret-Wert wird in Fehlermeldungen und Logzeilen durch `***` ersetzt, auch wenn der Server ihn zurückspiegelt. Logzeilen enthalten nur Methode, URL, Status und bereinigte Fehlertexte, nie Header oder Bodies.

## Netz

- `https` überall. `http` nur ins Heimnetz: RFC 1918, `100.64.0.0/10` (Tailscale), `*.ts.net`, `*.local`, `*.home.arpa`, Loopback, `10.0.2.2` (Emulator), IPv6 ULA und Link-local. Die Prüfung läuft ohne DNS.
- Keine Zugangsdaten in der URL. Weiterleitungen werden nur auf denselben Origin verfolgt (höchstens 3), ebenso muss das Legacy-`endpoint` auf demselben Origin liegen.
- OAuth-Endpunkte nur über `https`, `http` allein für Loopback.
- Zeitlimits (`McpTimeouts`): 10 s bis zu den Headern, 30 s je Austausch, Antworten höchstens 1 MB, bei SSE schon vor dem Parser geprüft. Abbruch über `CancelToken`.
- Fehler kommen als `McpException` mit `McpErrorKind`: `network`, `authRequired`, `protocol`, `server`, `timeout`, `cancelled`, `tooLarge`, `rejected`, `sessionExpired`.
- `probe()` meldet `reachable`, `authRequired`, `unreachable` oder `protocolError`, jeweils mit Latenz. `McpIntegration.checkAvailability()` nutzt das: Ist der Server nicht erreichbar, gilt die Integration als nicht verfügbar und der Grund wird angezeigt.

## Grenzen

- Kein stdio (ADR 0010). stdio-Server laufen auf dem Homeserver hinter einem stdio-zu-HTTP-Proxy.
- Keine `resources`, `prompts`, Sampling, Elicitation oder Roots. Server-Anfragen bekommen `-32601`, `ping` ein leeres Ergebnis.
- Es gibt keinen stehenden `GET`-Stream. `list_changed` kommt deshalb nur während eines Aufrufs an, ergänzend gilt das Cache-Höchstalter (24 h).
- Beim Abbruch wird die HTTP-Verbindung geschlossen. Ein `notifications/cancelled` geht nicht an den Server.
- Legacy-SSE initialisiert je Vorgang neu (eine Sitzung pro Verbindung).
- Die Netzprüfung löst keine Namen auf. Ein öffentlicher Name mit privater Adresse braucht `https` oder einen Heimnetz-Suffix.

## Testhilfen

- `package:wendelin_mcp/fakes.dart`: `FakeMcpSecrets` zeichnet Schreibvorgänge auf. `InMemoryMcpCacheStore`. `FakeAuthorizationBrowser` folgt der Autorisierungs-URL ohne Browser und kann die Rückleitung manipulieren.
- `package:wendelin_mcp/testing.dart`:
  - `FakeMcpServer`: In-Process-`HttpServer`, umschaltbar zwischen Streamable HTTP (JSON/SSE) und Legacy-SSE. Mit Bearer- und OAuth-Endpunkten (PRM, AS-Metadaten, DCR, Autorisierung und Token mit PKCE-Prüfung, Refresh), skriptbaren Tools, Paginierung, `list_changed`, Server-Anfragen, Fehlern, Verzögerung, Hängen, Übergröße und Sitzungsablauf. Für den Emulator: `start(address: InternetAddress.anyIPv4, publicHost: '10.0.2.2')`.
  - `mcpClientContract`: Contract-Suite für Transport-Implementierungen.
  - `mcpSecretsContract`: Contract-Suite für `McpSecrets`-Implementierungen (`FakeMcpSecrets`, in der App `SecretStoreMcpSecrets` über den `SecretStore`).
- Fixtures nach Spezifikation liegen in `test/fixtures/`.
