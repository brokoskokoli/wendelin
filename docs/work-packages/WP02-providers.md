# WP02 – Provider-Adapter (`packages/wendelin_providers`)

Abhängig von: `wendelin_core`, `http`. Konzept-Bezug: „LLM-Provider-Schicht“ (Adapter, Einrichtung, Kosten).

Vor dem Start die Skill `claude-api` laden (aktuelle Anthropic-Messages-API, Streaming-Events, Tool Use, Prompt Caching, Modell-IDs und Preise). Für OpenAI: Chat-Completions mit `stream: true`, `tools`, `tool_calls`-Deltas, `stream_options.include_usage`.

## Inhalt
- `SseParser` – wandelt `Stream<List<int>>` in `SseEvent(event?, data, id?)`; korrekt bei über Chunk-Grenzen geteilten UTF-8-Zeichen und Zeilen, `\r\n`, Kommentarzeilen, mehrzeiligen `data:`, `[DONE]`.
- `AnthropicMessagesAdapter implements LlmProvider`
  - POST `/v1/messages` mit `x-api-key`, `anthropic-version`, Streaming. Mapping aller Event-Typen (`message_start`, `content_block_start/delta/stop` für text, tool_use mit `input_json_delta`, thinking; `message_delta` mit stop_reason und usage; `error`; `ping`).
  - System-Prompt als `system`-Blöcke; Tool-Specs mit `cache_control` auf dem letzten Tool und dem System-Prompt (Prompt Caching).
  - Tool-Results als `user`-Nachricht mit `tool_result`-Blöcken; aufeinanderfolgende gleiche Rollen zusammenführen.
  - Optional serverseitige Web-Suche (`enableServerWebSearch`), Ergebnisblöcke werden als Text durchgereicht.
  - `listModels()` über `GET /v1/models`; `test()` = Mini-Anfrage mit Tool, prüft Tool-Fähigkeit.
- `OpenAiChatAdapter implements LlmProvider` – Base-URL frei, Auth per Bearer oder keine, zusätzliche Header. Mapping `tool_calls`-Deltas (Index-basiert zusammensetzen), `finish_reason` → `StopReason`, Usage aus letztem Chunk (`include_usage`; wenn Server das ablehnt: ohne erneut versuchen). System-Prompt als `system`-Nachricht, Tool-Results als `role: tool`.
- HTTP-Fehler-Mapping beider Adapter auf `ProviderException` (401/403 → Auth, 429 → RateLimit mit `retry-after`, 408/504/Timeout → Timeout, 5xx/529 → Server, 400 → InvalidRequest, Stream-Fehler-Events, kaputtes JSON → Malformed). Fehlermeldungen enthalten **nie** den Key.
- Abbruch über `CancelToken` schließt die HTTP-Verbindung (Client injizierbar: `http.Client`).
- `ProviderTemplate`-Katalog: Claude, OpenAI, OpenRouter, Mistral, Phala, Tinfoil, Ollama, Eigener Endpunkt – mit Base-URL, Auth-Art, Link zur Key-Seite, Standard-Datenschutzstufe.
- `ModelCatalog` mit Preisen (USD pro Mio. Tokens: input, output, cache-read, cache-write) für aktuelle Claude-Modelle (Haiku, Sonnet, Opus, Fable laut Skill) und gängige OpenAI-kompatible Modelle; vom Nutzer überschreibbar (Merge aus JSON). `CostCalculator.costMicros(modelId, Usage)` → Mikro-USD als `int`.
- `ProviderFactory.create(ProviderProfile, SecretReader)` → passender Adapter (SecretReader = `Future<String?> Function(String ref)`).

## Tests
- Fixtures unter `test/fixtures/{anthropic,openai}/*.sse|*.json`, spezifikationsgetreu (Text-Antwort, Tool-Call mit zerstückeltem JSON, mehrere parallele Tool-Calls, Thinking, Fehler-Event mitten im Stream, 401, 429, 529, kaputte Zeile).
- Request-Body-Snapshot-Tests: erzeugtes JSON für eine Beispielkonversation (System, User, Assistant mit Tool-Call, Tool-Result, Bild) exakt prüfen.
- Contract-Suite aus `wendelin_core/testing.dart` gegen beide Adapter (über `MockClient`).
- `SseParser`: Property-Test – beliebige Zerstückelung der Bytes ergibt dieselben Events.
- Live-Tests `@Tags(['live'])`: `ANTHROPIC_API_KEY` mit Haiku, `OPENAI_API_KEY` (oder `OPENAI_BASE_URL` + Key) – je eine Text- und eine Tool-Anfrage, max. ~200 Tokens.

## Abnahmekriterien
- [ ] Beide Adapter bestehen Contract-Suite und Fixture-Tests; Tool-Call-Argumente aus Deltas exakt rekonstruiert.
- [ ] Keine Anthropic/OpenAI-JSON-Strukturen außerhalb `lib/src/anthropic/` bzw. `lib/src/openai/`.
- [ ] Key taucht in keiner Exception-Message, `toString()` oder Logausgabe auf (Test!).
- [ ] Kostenberechnung tabellengetestet inkl. Cache-Tokens.
- [ ] Gate grün, Abdeckung ≥ 85 %.
