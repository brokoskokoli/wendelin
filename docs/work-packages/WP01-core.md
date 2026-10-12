# WP01 – Core-Verträge (`packages/wendelin_core`)

Reines Dart, keine Abhängigkeiten außer `meta`, `collection`. Dieses Paket ist der Vertrag für alle anderen; Namen und Semantik unten sind verbindlich (Ergänzungen erlaubt, Umbenennungen nicht ohne ADR).

Konzept-Bezug: „LLM-Provider-Schicht → Internes Format/Interface“, „Agent-Schleife → Schnittstelle“, „Tool-System → Schnittstellen“, „Routing → Datenschutz-Grenze“.

## Inhalt

### Nachrichtenformat (`lib/src/messages/`)
- `enum Role { system, user, assistant, tool }`
- `sealed class ContentBlock` mit `TextBlock(text)`, `ImageBlock(mediaType, bytes | base64)`, `ToolCallBlock(id, name, argumentsJson)`, `ToolResultBlock(callId, content: List<ContentBlock>, isError)`, `ThinkingBlock(text, signature?)` (nur Anzeige / Durchreichen).
- `Message(role, content)` + Konstruktoren `Message.user(text)`, `Message.assistantText(text)`, …
- `ToolSpec(name, description, inputSchema: Map<String,Object?>)`
- `sealed class ToolChoice`: `auto`, `none`, `required`, `ToolChoice.tool(name)`
- `ChatRequest(messages, tools, model, maxTokens, temperature?, toolChoice, metadata, systemPrompt?)` – System-Prompt getrennt halten (Anthropic braucht ihn separat, Adapter für OpenAI setzt ihn als erste Nachricht).
- `sealed class ChatEvent`: `TextDelta(text)`, `ThinkingDelta(text)`, `ToolCallDelta(index, id?, name?, argumentsFragment)`, `ToolCallComplete(ToolCallBlock call)`, `UsageEvent(Usage)`, `Done(StopReason)`, `ErrorEvent(ProviderException)`
- `Usage(inputTokens, outputTokens, cachedInputTokens, cacheWriteTokens)` mit `+`
- `enum StopReason { endTurn, toolUse, maxTokens, stopSequence, refusal, other }`
- JSON-Serialisierung (`toJson`/`fromJson`) für `Message`/`ContentBlock` (für Speicherung), stabil und round-trip-getestet.

### Provider-Vertrag (`lib/src/provider/`)
- `abstract interface class LlmProvider { ProviderType get type; ProviderCapabilities get caps; Future<List<ModelInfo>> listModels(); Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}); Future<HealthCheck> test(); }`
- `enum ProviderType { anthropic, openaiCompatible, fake }`
- `ProviderCapabilities(tools, vision, streaming, promptCaching, tee)`
- `ModelInfo(id, displayName, contextWindow?, supportsTools?, supportsVision?)`
- `HealthCheck(ok, latency, message, models?)`
- `CancelToken` (eigene, schlanke Klasse: `cancel()`, `isCancelled`, `whenCancelled` Future)
- `enum PrivacyLevel { local, tee, eu, standard }` mit `bool isAtLeast(PrivacyLevel other)` (Ordnung local > tee > eu > standard)
- `ProviderProfile(id, name, type, baseUrl?, defaultModel, privacy, authMethod, budgetMonthly?, warnThreshold?, extraHeaders)` – ohne Secrets; Secret wird per `secretRef` (String-Schlüssel) referenziert.
- `sealed class AuthMethod`: `ApiKeyAuth(secretRef, headerName?)`, `NoAuth`, `CustomHeadersAuth(secretRefs map)`, `OAuthPkceAuth(…)` (nur Typ, keine Umsetzung).
- Fehler: `sealed class ProviderException implements Exception` mit `AuthException`, `RateLimitException(retryAfter?)`, `TimeoutException`-Analogon `ProviderTimeoutException`, `NetworkException`, `ServerException(statusCode)`, `InvalidRequestException`, `CancelledException`, `MalformedResponseException`. Feld `bool get retryable`.

### Tool-Vertrag (`lib/src/tools/`)
- `enum RiskLevel { read, write, external }`
- `enum AppPlatform { android, ios }`
- `abstract interface class Tool { String get name; String get description; Map<String,Object?> get inputSchema; RiskLevel get risk; Future<ToolOutcome> execute(Map<String,Object?> args, ToolContext ctx); String describeForConfirmation(Map<String,Object?> args); }`
- `ToolOutcome(content: List<ContentBlock>, isError, undo: UndoAction?, summary: String?)` – `summary` ist der kurze UI-Text („Termin angelegt: Tauchen, Di 10:00“). `UndoAction` = `Future<void> Function()` plus Label.
- `ToolContext(sessionId, clock, locale, timeZone, cancel)`
- `abstract interface class Integration { String get id; String get displayName; String get iconId; Set<AppPlatform> get platforms; bool get sensitive; Future<Availability> checkAvailability(); List<SetupStep> get setup; Future<SetupState> setupState(); List<Tool> get tools; }` (kein Flutter: Icon/Settings-Seite werden in der App über `id` zugeordnet).
- `Availability(available, reason?, storeUrl?)`, `SetupStep(id, kind: permission|login|folder|config, label)`, `SetupState(complete, missingSteps)`
- `enum IntegrationStatus { unavailable, available, setupRequired, active, error }`
- `static bool isValidToolName(String)` – Regex `^[a-zA-Z0-9_-]{1,64}$`; Namensschema `integration__aktion`.
- Interfaces, die von der Agent-Schleife genutzt werden (Implementierung in WP03):
  - `abstract interface class ToolCatalog { List<ToolSpec> activeSpecs(); Tool? lookup(String name); }`
  - `abstract interface class ToolInvoker { Stream<ToolInvocationEvent> invokeAll(List<ToolCallBlock> calls, ToolContext ctx); }` mit Events `ToolStarted(call)`, `ConfirmationNeeded(call, description, Completer<bool>)`, `ToolFinished(call, ToolOutcome, Duration)`.

### Agent-Vertrag (`lib/src/agent/`)
- `UserInput(text, images, source: InputSource {text, voice}, sttConfidence?, language?)`
- `sealed class AgentEvent`: `Routed(profileId, modelId, reason)`, `AgentTextDelta(text)`, `ToolCallStarted(call)`, `ConfirmationRequired(call, description, respond: void Function(bool))`, `ToolCallFinished(call, outcome)`, `Escalated(fromProfile, toProfile, reason)`, `UsageReported(profileId, modelId, usage, costMicros?)`, `Verification(…)` (Platzhalter für TEE), `AgentDone(finalText, stopReason)`, `AgentFailed(error, message)`
- `abstract interface class AgentRun { Stream<AgentEvent> run(UserInput input); void cancel(); }`

### Hilfen (`lib/src/util/`)
- `abstract interface class Clock { DateTime now(); }` + `SystemClock`, `FixedClock`
- `abstract interface class IdGenerator { String next(); }` + `UuidV4Generator` (ohne externe Abhängigkeit, `Random.secure`), `SequentialIdGenerator` für Tests.

### Testing (`lib/testing.dart`)
- `FakeLlmProvider` – wird mit einer Liste geskripteter „Züge“ gefüttert (`ScriptedTurn.text(...)`, `ScriptedTurn.toolCalls([...])`, `ScriptedTurn.error(...)`), streamt sie als `ChatEvent`s inklusive Deltas, zeichnet alle empfangenen `ChatRequest`s auf.
- `FakeTool`/`FakeIntegration` – konfigurierbares Risiko, Ergebnis, Verzögerung, Fehler, Aufrufzähler.
- `llmProviderContract(LlmProvider Function() create, …)` – Contract-Testsuite (Event-Reihenfolge: Deltas vor `ToolCallComplete`, genau ein `Done` am Ende, `Usage` vor `Done`, Abbruch beendet den Stream mit `CancelledException`).

## Abnahmekriterien
- [ ] Alle oben genannten Typen existieren mit Doc-Kommentar, exportiert über `package:wendelin_core/wendelin_core.dart`; Fakes über `package:wendelin_core/testing.dart`.
- [ ] JSON round-trip Tests für alle `ContentBlock`-Varianten und `Message`.
- [ ] `PrivacyLevel.isAtLeast` tabellengetestet (16 Kombinationen).
- [ ] `isValidToolName` tabellengetestet (gültig/ungültig inkl. Punkt, Leerzeichen, 65 Zeichen).
- [ ] `FakeLlmProvider` besteht die Contract-Suite; Contract-Suite ist so geschrieben, dass WP02 sie für echte Adapter wiederverwendet.
- [ ] Gate grün, Abdeckung ≥ 85 %.
- [ ] Kurze ADR `docs/adr/0002-core-contracts.md` (warum System-Prompt separat, warum kein Flutter in Integration, ToolOutcome statt nacktem ToolResult).
