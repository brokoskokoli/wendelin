# ADR 0010 – MCP-Client (`packages/wendelin_mcp/`)

Status: angenommen (umgesetzt, nachgezogen 2026-10-25) · 2026-10-13

## Kontext
Das Konzept („MCP-Integration“) verlangt einen eigenen MCP-Client, damit Tools von Remote-Servern mit jedem LLM-Provider funktionieren: jeder Server wird eine Integration in derselben `ToolRegistry`. M3 ist fertig, wenn ein MCP-Server auf dem Homeserver über Tailscale Tools liefert. Offen waren Paketschnitt, Transport, Lebensdauer der Verbindung, Umgang mit Server-Annotationen, Undo und Netzziele.

## Entscheidungen

### 1. Paketschnitt
Neues reines Dart-Paket `wendelin_mcp` mit `wendelin_mcp -> core, integrations` (in `tool/check_deps.dart` und `docs/ENGINEERING.md`). Aus `integrations` kommen die Daten-Hülle (`escapeDataTags`, `escapeDataAttr`) und `ellipsize`, aus `core` `Tool`, `Integration`, `ToolOutcome`, `CancelToken`, `Clock` und der SSE-Parser. Der Parser liegt seit WP22 in `wendelin_core` (reines Dart, keine neue Abhängigkeit) und wird aus `wendelin_providers` unverändert weiter exportiert. `wendelin_tools` ist bewusst keine Abhängigkeit: Argumentprüfung und Kürzung (`ArgumentValidator`, `ResultShaper`) wendet der `ToolExecutor` ohnehin auf alle Tools an. Geräte- und App-Teile (Secret-Speicher, Cache-Persistenz, Browser) sind Interfaces: `McpSecrets`, `McpCacheStore`, `AuthorizationBrowser`. Die App setzt sie in WP27 um.

### 2. Transport: Streamable HTTP, Legacy-SSE als Fallback, kein stdio
- **Streamable HTTP** (2025-03-26 und neuer) ist Standard: `POST` mit JSON-RPC 2.0, `Accept: application/json, text/event-stream`, Antwort als JSON oder SSE-Stream (Benachrichtigungen und Server-Anfragen vor der Antwort), `Mcp-Session-Id` vom Server, `MCP-Protocol-Version` nach `initialize`, `DELETE` beim Schließen. Bei 404 mit Sitzung baut der Client die Sitzung genau einmal neu auf und wiederholt den Aufruf.
- **Legacy-SSE** (2024-11-05) nur als Fallback: Bei `auto` antwortet der Server auf den `POST` mit 400, 404 oder 405 (Rückwärtskompatibilität laut Spezifikation), ein `GET` liefert ein `endpoint`-Ereignis. Die Wahl wird gemerkt.
- **Kein stdio.** Android startet keine fremden Server-Prozesse als Kind der App: Es gibt keine Laufzeiten wie Node oder Python, ausführbare Dateien aus dem App-Speicher sind durch W^X ab Android 10 gesperrt, Hintergrundprozesse werden beendet, und ein Dauerprozess kostet Akku. stdio-Server laufen auf dem Homeserver hinter einem stdio-zu-HTTP-Proxy (Konzept).
- Versionen: angefragt wird `2025-11-25`, akzeptiert werden auch `2025-06-18`, `2025-03-26` und `2024-11-05`. Andere Versionen sind ein Protokollfehler.

### 3. Keine dauerhafte Verbindung
Verbindungen gibt es nur bei Bedarf. Streamable HTTP behält zwischen den Aufrufen nur die Sitzungs-Id, es gibt keinen stehenden `GET`-Stream. Legacy-SSE öffnet seinen Stream je Vorgang (öffnen, `initialize`, Aufruf, schließen), weil die Sitzung dort an der Verbindung hängt. Parallele Aufrufe bekommen eigene Streams. Darum kommt `notifications/tools/list_changed` nur während eines Aufrufs an. Ergänzend hat der Tool-Cache ein Höchstalter (Standard 24 h). Zeitlimits: 10 s bis zu den Antwort-Headern, 30 s je Austausch (innerhalb der 60 s der Agent-Schleife). Antworten sind auf 1 MB begrenzt, bei SSE vor dem Parser (auch eine endlose Zeile ohne Ereignisende). Abbruch über `CancelToken`.

### 4. Annotationen, Risiko und Kontextbudget
Die Basisstufe folgt den Standardwerten der Spezifikation (2025-11-25: ein fehlender `destructiveHint` zählt als `true`):

| Annotationen | Basisstufe |
| --- | --- |
| `readOnlyHint: true` | `read` (`destructiveHint` wird dann nicht beachtet) |
| sonst nur explizit `destructiveHint: false` | `write` |
| alles andere, auch ganz ohne Annotationen | `external` |
| Server mit `confirmAll` | immer `external` |

Nutzer-Overrides (`McpToolOverride.risk`) heben die Stufe nur an (K8 b).

**Vertrauen**: Die Annotationen kommen vom Server. Weil der Nutzer jeden Server selbst einrichtet, reicht ein `readOnlyHint` für `read`, also für die Ausführung ohne Nachfrage. Restrisiko: Ein lügender oder kompromittierter Server kann ein schreibendes Tool als read-only ausgeben. Dann läuft es ohne Bestätigung. Gegenmittel sind `confirmAll` je Server und `risk`-Overrides je Tool. WP27 zeigt deshalb bei jedem Tool die *effektive* Stufe an.

**Kontextbudget**: Tool-Specs gehen bei jeder Anfrage ans Modell. Darum gelten diese Grenzen:
- Ein Tool mit einem Schema über 8 KB (kodiertes JSON) wird nicht angeboten.
- Je Server werden höchstens 128 Tools angeboten. Der Client liest ohnehin höchstens 1024 Tools.
- Doppelte Tool-Namen: Das erste Vorkommen gilt.
- Beschreibungen werden auf 1024 Zeichen gekürzt.

Ausgelassene Tools stehen mit Grund in `McpIntegration.skippedTools`.

Ergebnisse stehen in `<mcp_result …>` mit Datenhinweis, Tags im Inhalt werden entschärft. Bilder und Audio gehen in M3 nicht ans Modell, es geht nur ein Hinweis mit MIME-Typ und Größe. Server-Anfragen (Sampling, Elicitation, Roots) werden mit `-32601` beantwortet, `ping` mit einem leeren Ergebnis.

### 5. Kein Undo, darum `write` standardmäßig bestätigen
MCP-Tools wirken auf dem Server, die App kann sie nicht zurücknehmen. `ToolOutcome.undo` bleibt `null`, und die Tool-Karte zeigt kein „Rückgängig“. Das Konzept sieht für `write` aber eine Rücknahme innerhalb von 10 s vor. Ohne Undo ist ein Tool mit Basisstufe `write` deshalb effektiv `external`, also wird jedes Mal nachgefragt.

Mit `McpToolOverride.autoRun` erlaubt der Nutzer je Tool die Ausführung ohne Nachfrage, die effektive Stufe ist dann `write`. `autoRun` wirkt nur bei Basisstufe `write`, nie bei `external` und nie unter `confirmAll`.

### 6. Netzziele
- MCP-Server: `https` überall. `http` nur ins Heimnetz: RFC 1918, `100.64.0.0/10` (Tailscale-CGNAT), `*.ts.net`, `*.local`, `*.home.arpa`, Loopback, Emulator `10.0.2.2`, IPv6 ULA (`fd7a:…` von Tailscale) und Link-local. Die Prüfung ist rein syntaktisch, ohne DNS. Ein öffentlicher Name, der auf eine private Adresse zeigt, braucht also `https` oder einen der Suffixe.
- Keine Zugangsdaten in der URL. Weiterleitungen werden nur auf denselben Origin verfolgt, höchstens 3, und das `endpoint` von Legacy-SSE muss ebenfalls auf demselben Origin liegen.
- OAuth-Endpunkte (Metadaten, Autorisierung, Token, Registrierung) nur über `https`. `http` gilt allein für Loopback (Tests).

### 7. Auth
Bearer und eigene Header werden über Secret-Referenzen aufgelöst. OAuth 2.1 läuft nach der MCP-Spezifikation:
1. 401 mit `WWW-Authenticate`, daraus die Protected Resource Metadata (RFC 9728), sonst Well-known-Pfade, sonst der Server selbst.
2. Authorization Server Metadata (RFC 8414 mit OIDC-Fallback). `issuer` muss passen, `S256` ist Pflicht.
3. Dynamische Registrierung (RFC 7591) als öffentlicher Client, falls keine Client-Id konfiguriert ist.
4. PKCE S256, `state` und gegebenenfalls `iss` werden geprüft, `resource` (RFC 8707) geht an Autorisierung, Token und Refresh.
5. Refresh vor Ablauf (30 s Puffer) und einmal nach einer 401.

Tokens und Registrierung liegen nur in `McpSecrets`. Alle Fehlermeldungen und Logzeilen laufen durch einen Redaktor, der jeden gesendeten Secret-Wert durch `***` ersetzt. Lässt sich ein Token nicht erneuern, setzt die Integration ihren Status auf „Fehler“ (`reportError`) und meldet den Einrichtungsschritt `auth` als offen.

### 8. Namen
Die Integrations-Id ist `mcp_<slug>`. Der Slug wird beim Anlegen aus dem Namen gebildet (`[a-z0-9]`, Umlaute umschrieben, höchstens 16 Zeichen, eindeutig) und in der Konfiguration gespeichert, damit Tool-Namen auch nach einer Umbenennung stabil bleiben. Tools heißen `mcp_<slug>__<tool>`. Namen mit unzulässigen Zeichen oder über 64 Zeichen werden gekürzt und bekommen `_` plus 6 Hex-Zeichen SHA-256 des Originalnamens. Die Zuordnung hängt nur vom Originalnamen ab, unveränderte Namen haben Vorrang, und bei einer Kollision wird der Hash länger.

## Folgen
- WP27 baut daraus die App-Seite: `McpSecrets` über `SecretStore`, `McpCacheStore`, `AuthorizationBrowser` mit Custom Tabs, Neuregistrierung der Integration bei `toolsChanged`, Status aus `probe()`.
- `FakeMcpServer` (`package:wendelin_mcp/testing.dart`) dient in WP29 als Testserver für den Emulator. Er lauscht dann auf `InternetAddress.anyIPv4`, der Emulator erreicht ihn unter `10.0.2.2`.
- Nicht enthalten: `resources`, `prompts`, Sampling, Elicitation und `notifications/cancelled` beim Abbruch. Der Abbruch schließt nur die HTTP-Verbindung.
