# Web (`web`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `web__search` | read | Websuche über den konfigurierten Dienst (1–10 Treffer: Titel, URL, Snippet) |
| `web__fetch` | read | Seite als Text lesen (Standard 20 000, höchstens 50 000 Zeichen) |

**Suchdienste** (`WebSearchBackend`): `BraveSearchBackend` (Header `X-Subscription-Token`), `TavilyBackend` (Bearer), `SearxngBackend` (eigene Instanz, `format=json` muss in `settings.yml` aktiv sein). Schlüssel kommen als Konstruktorparameter aus dem `SecretStore` der App und erscheinen nie in Fehlermeldungen. Ohne Suchdienst gibt es nur `web__fetch`: Der Setup-Schritt `search_backend` ist optional (`SetupStep.optional`) und bleibt offen, die Integration gilt in der Registry trotzdem als aktiv. Getestet gegen Fixtures in `test/fixtures/web/` (kein Live-Zugriff). Vertrag: `webSearchBackendContract` mit Szenarien, Fake: `FakeWebSearchBackend`.

**`web__fetch`-Schutz** (`WebFetcher`, `checkFetchTarget`):
- nur `http`/`https`, keine Zugangsdaten in der URL;
- keine lokalen oder privaten Ziele: `localhost`, `*.local`, `*.lan`, `*.internal`, `*.home.arpa`, Loopback, `10/8`, `172.16/12`, `192.168/16`, Link-local (`169.254/16`, `fe80::/10`), CGNAT `100.64/10`, IPv6 ULA `fc00::/7`, Multicast, reserviert, IPv4-mapped IPv6 und numerische Sonderschreibweisen (`2130706433`, `0x7f.1`);
- Hostnamen werden aufgelöst; zeigt eine Adresse ins private Netz, wird geblockt;
- Ausnahmen nur über `allowedHosts` (z. B. Homeserver);
- jede Weiterleitung wird erneut geprüft (höchstens 5);
- höchstens 2 MB Körper, danach Abbruch mit Hinweis „gekürzt“;
- nur Text-Inhalte; HTML wird ohne Skripte, Stile, Navigation, Formulare zu Text.

Grenze: Der HTTP-Client löst den Namen nach der Prüfung selbst noch einmal auf (DNS-Rebinding mit sehr kurzer TTL ist nicht vollständig ausgeschlossen).

**Daten statt Anweisungen**: Ergebnisse beginnen mit einem Hinweis und stehen in `<web_content …>`/`<web_search_results>`; öffnende und schließende Daten-Tags im Inhalt werden in jeder Schreibweise (Groß/klein, Leerraum wie `< /WEB_CONTENT >`) zu `&lt;…` entschärft.

**`serverSideAvailable`**: Bei Anthropic-Profilen mit serverseitiger Websuche braucht es die Integration nicht; die App entscheidet und setzt das Flag.

**Berechtigung**: `INTERNET`. **Plattformen**: Android, iOS. **Sensibel**: nein.
