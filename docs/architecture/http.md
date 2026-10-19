# HTTP-Stacks (N3)

Bewusst getrennt, je mit eigenen Timeouts und Fehlerabbildung. **Keinen neuen Stack anlegen**, sondern den passenden erweitern:
- LLM-Aufrufe und SSE: `packages/wendelin_providers/lib/src/common/http_transport.dart`
- MCP: `packages/wendelin_mcp/lib/src/transport/http_call.dart`
- Web-Abruf mit Zielprüfung: `packages/wendelin_integrations/lib/src/web/web_fetcher.dart` (`fetch_guard.dart`)
- Bring!: `packages/wendelin_integrations/lib/src/bring/http_bring_api.dart`
- Spotify: `packages/wendelin_integrations/lib/src/spotify/http_spotify_api.dart`
- HTTP-Tools: `packages/wendelin_integrations/lib/src/http_tools/http_transport.dart` (`http_target.dart`, ADR 0011)
- Modell-Download: `packages/wendelin_voice/lib/src/models/model_downloader.dart`

Netzziele: Adressbereiche (Loopback, RFC 1918, CGNAT/Tailscale, ULA, Link-Local, IPv4 in IPv6 …) klassifiziert **nur** `packages/wendelin_integrations/lib/src/common/net_scope.dart` (`classifyNet`, `NetScope`, `HostResolver`). `fetch_guard.dart` und `http_target.dart` enthalten nur ihre Policy (welche Bereiche erlaubt sind, welche Meldung kommt). `packages/wendelin_mcp/lib/src/net_policy.dart` (MCP-Server-URLs, `isHomeNetworkHost`, `isLoopbackHost`) fragt ebenfalls nur den Kern ab (WP36 b).

Text-Faltung für Namensvergleiche (Listen, Obsidian, Routing, phonetische Suche): **nur** `packages/wendelin_core/lib/src/text/fold.dart` (`foldForMatch`, `foldFlat`, `foldLetter`). `matching.dart` (`normalizeText` = `foldForMatch(basicOnly: true)`) und `routing_text.dart` nutzen sie. Ausnahme: `packages/wendelin_mcp/lib/src/tools/naming.dart` transliteriert Tool-Namen bewusst ä→ae (stabile Namen).
