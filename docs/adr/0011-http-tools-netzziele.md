# ADR 0011 – HTTP-Tools und Netzziele

Status: vorgeschlagen · 2026-10-13

## Kontext
Mit HTTP-Tools (WP23, Konzept „Erweiterungswege 1“) definiert der Nutzer eigene Tools aus Methode, URL-Vorlage, Headern, Body und Anmeldung. Das Modell füllt die Argumente. Daraus folgen drei Risiken:
- **SSRF**: Modell-Argumente (auch aus Prompt-Injection) könnten das Ziel umlenken, etwa auf andere Hosts, Loopback, Cloud-Metadaten oder Geräte im LAN.
- **DNS-Rebinding**: Ein öffentlicher Name kann nach der Prüfung auf eine private Adresse zeigen.
- **Secret-Abfluss**: Tokens dürfen nicht in Ergebnisse, Fehlertexte, Audit-Log, Exporte oder Bestätigungstexte gelangen.

Gleichzeitig sind private Ziele der Hauptzweck: Home Assistant im LAN, n8n auf dem Homeserver, Tailscale.

## Entscheidung

### 1. Allowlist = gespeicherter Origin
Schema, Host und Port stehen nur in der gespeicherten Vorlage. Platzhalter sind nur in Pfad und Query-Werten erlaubt und werden kodiert: ein Pfadsegment pro Wert, ohne `/`, `\`, `.` und `..`. Die ausgedehnte URL wird gegen den Origin der Vorlage geprüft. Weiterleitungen sind nur auf denselben Origin erlaubt, höchstens 3. Eine fremde Weiterleitung bricht ab, bevor eine weitere Anfrage mit Secret rausgeht. Eine weitere Allowlist gibt es nicht. Was der Nutzer einträgt, ist erlaubt, sofern es die Regeln unten einhält.

### 2. Heimnetz-Markierung
Eine Definition kann als „Heimnetz“ markiert werden (`homeNetwork`). Ohne Markierung gelten als Heimnetz nur private IP-Literale (RFC 1918, `100.64.0.0/10`, ULA, also auch `10.0.2.2` im Emulator) und Namen auf `.local`, `.lan`, `.home`, `.home.arpa`, `.internal` und `.ts.net`.
- Heimnetz-Ziele dürfen auf private Adressen auflösen.
- Andere Namen müssen auf öffentliche Adressen auflösen, sonst wird abgelehnt (DNS-Rebinding). Das gilt für jede Adresse der Antwort und auch für IPv4 in IPv6 (mapped, compatible, SIIT, NAT64 inkl. `64:ff9b:1::/48`, 6to4).
- Loopback und Link-Local werden immer abgelehnt. Nur der Test-Modus (`allowLoopback`) erlaubt sie, für Tests und den Emulator mit lokalem Testserver. `0.0.0.0`, Multicast, Broadcast, `100::/64` und reservierte Bereiche sind immer verboten. Numerische Sonderschreibweisen (`2130706433`, `0x7f.1`, `127.1`, führende Nullen) und IPv6-Zonen werden abgelehnt, weil Resolver sie unterschiedlich deuten.

### 3. Pinning statt zweiter Auflösung
`checkHttpTarget` liefert die geprüften Adressen. `PinnedHttpToolTransport` (dart:io `HttpClient.connectionFactory`) verbindet nur dorthin. Der Name wird nicht noch einmal aufgelöst, TLS prüft das Zertifikat trotzdem gegen den Hostnamen (SNI), und es gibt keinen Proxy. Damit ist die Lücke zwischen Prüfung und Verbindung geschlossen, die `web__fetch` noch hat (siehe `web/README.md`). Weiterleitungen nutzen dieselben Adressen. Nach Ende, Zeitlimit oder Abbruch eines Aufrufs wird der `HttpClient` hart geschlossen (`close(force: true)`). `ClientHttpToolTransport` (beliebiger `http.Client`) pinnt nicht und ist für Tests mit `MockClient` gedacht.

### 4. `http` nur im Heimnetz
`https` ist Pflicht. `http` ist nur für Heimnetz-Ziele erlaubt, und dann müssen alle aufgelösten Adressen privat sein, damit kein Klartext ins Internet geht. Das wird schon beim Speichern geprüft (Vorlage) und bei jedem Aufruf noch einmal (Auflösung).

### 5. Secrets erst beim Senden
Die Definition enthält nur Secret-Referenzen (`ApiKeyAuth`, `CustomHeadersAuth` aus core, kein OAuth). `HttpToolSecrets.read` wird erst nach Vorlagen- und Zielprüfung aufgerufen. Bestätigungstexte und `SentRequest` entstehen ohne Secret-Zugriff, geheime Header erscheinen dort als `••••••`. Antworten, Fehlertexte, Content-Type und Reason-Phrase werden von gespiegelten Secrets bereinigt (roh, JSON-escaped, URL-kodiert). Klartext-Header mit geheim wirkenden Namen (`Authorization`, `Cookie`, `*token*`, `*key*`, `*auth*`, `*bearer*`, `*credential*`, `*secret*`, `*session*` …) werden abgelehnt, damit Tokens nicht über den Export abfließen. Header-Werte aus Argumenten dürfen weder CR/LF noch Steuerzeichen enthalten und müssen ASCII sein.

### 6. Zwei Integrationen statt einer je Definition
Ob Tools an einen Provider gehen, entscheidet die Registry über `Integration.sensitive` (K10). Ein einzelnes `http` könnte „sensibel“ nicht pro Tool abbilden. Deshalb gibt es zwei Integrationen: `http` („HTTP-Tools“) für die nicht sensiblen und `http_sensitive` („HTTP-Tools (sensibel)“) für die sensiblen Definitionen. Beide nennen ihre Tools `http__<name>`. Verworfen wurde eine Integration je Definition (`http_<name>`): Die Integrationsliste würde unübersichtlich, und Präfix und Tool-Name passten ebenfalls nicht zusammen. Kleine Abweichung: Bei `http_sensitive` ist die Integrations-Id nicht der Tool-Präfix. Dafür bleibt der Tool-Name stabil, wenn der Nutzer „sensibel“ umschaltet, und Einstellungen pro Tool gehen nicht verloren.

### 7. Risiko
Der Nutzer wählt die Stufe. Vorgeschlagen wird nach Methode: `GET`/`HEAD` → read, `POST`/`PUT`/`PATCH` → write, `DELETE` → external. Wirksam ist das Maximum aus Wahl und Vorschlag (K8 b, nur verschärfen). Einen Undo gibt es nicht. Deshalb wird `write` standardmäßig wie `external` bestätigt (gleiche Regel wie MCP, K13 j, Nachtrag WP28). Das Feld `autoRun` (Standard `false`, im Editor „Ohne Nachfrage ausführen (kein Rückgängig)“) stellt die effektive Stufe ausdrücklich auf `write` zurück, aber nur, wenn Vorschlag und Nutzerwahl `write` sind. Dann läuft das Tool ohne Bestätigung und ohne Rückgängig-Knopf. Die Schema-Version bleibt 1: Das Feld ist optional, fehlt es (alte Definitionen, Exporte), gilt `false`, also die sichere Seite.

## Gilt sinngemäß für MCP (WP22)
Origin aus der Konfiguration, `http` nur im Heimnetz, Weiterleitungen nur auf denselben Origin, Rebinding-Prüfung und Pinning. `checkHttpTarget`, `classifyAddress`, `isHomeNetworkHost` und `PinnedHttpToolTransport` werden aus `wendelin_integrations` exportiert und können wiederverwendet werden. Seit WP36 klassifiziert ein gemeinsamer Kern (`src/common/net_scope.dart`, `classifyNet`) die Adressbereiche für alle Netzziel-Prüfungen; `http_target.dart`, `fetch_guard.dart` und `wendelin_mcp/src/net_policy.dart` behalten nur ihre Policy. Beide Policies sperren dabei dieselben Bereiche: Der Web-Abruf lässt SIIT (`::ffff:0:a.b.c.d`), 6to4 (`2002::/16`) und `100::/64` nicht mehr durch, sondern bewertet sie wie die HTTP-Tools (Sicherheitsfix nach WP36).

## Folgen
- Antworten sind Daten in `<http_response>` mit Hinweis. Bei Status ≥ 400 gibt es nur einen Ausschnitt.
- Grenzen: Bereinigt werden Secrets ab 4 Zeichen in den genannten Kodierungen, Base64 und andere Umformungen nicht. Die Unit-Tests prüfen das Pinning mit echtem Socket (HTTP, gescheiterter TLS-Handshake). HTTPS mit Zertifikatsprüfung gegen den Namen deckt ein schlüsselloser Live-Test ab (`test/live/http_tools_live_test.dart`).
- Die App (WP28) implementiert `HttpToolSecrets` auf dem `SecretStore` (`httpToolSecretsContract`), nutzt `PinnedHttpToolTransport` und registriert `HttpToolsIntegration.all(...)`.
