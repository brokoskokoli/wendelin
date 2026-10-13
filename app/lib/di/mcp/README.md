# MCP-Server in der App (WP27)

App-Seite des MCP-Clients aus `packages/wendelin_mcp` (ADR 0010), angebunden als `UserIntegrationSource` (ADR 0012).

| Datei | Inhalt |
| --- | --- |
| `mcp_source.dart` | `McpServerSource`: Server anlegen (`add`, vorher `probeDraft`), ändern (`update`), `reload`, OAuth `signIn`/`signOut`, `setSecret`, `remove`, Export/Import. `McpServerIntegration` ist die Fassung für die Registry. |
| `mcp_persistence.dart` | Einstellungsschlüssel (`mcp.servers`, `mcp.<id>.tools`, `mcp.<id>.check`), `McpCheck` (letzte Prüfung), `SettingsMcpCacheStore` |
| `mcp_secrets.dart` | `SecretStoreMcpSecrets` (besteht `mcpSecretsContract`), Secret-Referenzen `mcp.<id>.bearer`, `.header.<n>`, `.oauth.token`, `.oauth.client` |
| `mcp_templates.dart` | Vorlagen: Home Assistant, Obsidian (obsidian-mcp-server), Kalender (dav-mcp), eigener Server |
| `mcp_providers.dart` | Riverpod: Quelle, Browser für OAuth, Debug-Log |

## Regeln

- **Secrets** nur im `SecretStore`. Einstellungen, Export, Audit-Log und Debug-Log enthalten nur Referenzen (Kanarienwert-Test `test/mcp/mcp_canary_test.dart`).
- **Schalter**: einzige Quelle ist `AppSettings.integrationEnabled` (über `IntegrationActivator`). `McpServerConfig.enabled` wird nicht benutzt; der Export schreibt den aktuellen Schalter, der Import legt Server ausgeschaltet an.
- **Netz nur bei Bedarf**: `checkAvailability()` antwortet ohne Netz (Rückkehr in die App). Verbunden wird beim Einschalten (`initialize`, `tools/list`), mit „Neu laden“, bei der Anmeldung und bei jedem Tool-Aufruf. `list_changed` während eines Aufrufs lädt die Liste neu, die Quelle gibt der Registry eine neue Fassung.
- **Risiko**: `McpToolOverride` in der Konfiguration (nur verschärfen; „ohne Nachfrage“ nur bei Basisstufe `write`, kein Rückgängig). Die Oberfläche zeigt die effektive Stufe.
- **Status**: Auth-Fehler setzen die Integration auf „Fehler“ (`reportError`). „Nicht erreichbar“ aus der letzten Prüfung erscheint nur in der Anzeige; die Tools bleiben angeboten, jeder Aufruf versucht es neu.
- **Löschen** entfernt Konfiguration, Tool-Cache, Prüfergebnis und alle Secrets sofort. `deleteSecrets` des Abgleichs ist nur Nachsorge und rührt nie einen noch konfigurierten Server an.
- **OAuth**: `ChannelAuthorizationBrowser` → Kotlin `AuthChannel` (Custom Tab über `androidx.browser`, sonst ein beliebiger Browser), Rückleitung `app.wendelin://oauth/mcp` über `OAuthRedirectActivity`. `state` und `iss` prüft `McpOAuthFlow`. Ohne Browser gibt es einen Hinweis.
- **Audit**: Prüfungen als `verification`, Verbindungs- und Anmeldefehler als `error`, jeweils ohne Header, Tokens und ohne Query von Adressen (`sanitizeMcpDetail`). Tool-Aufrufe protokolliert der `ToolExecutor` wie alle anderen (`mcp_<slug>__<tool>`).

Gerätetest: `DEVICE=emulator-xxxx tool/e2e_mcp.sh` (Test-MCP-Server `app/tool/mcp_test_server.dart` auf dem Rechner, erreichbar als `http://10.0.2.2:<port>`).
