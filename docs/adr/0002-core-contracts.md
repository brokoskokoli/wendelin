# ADR 0002 – Core-Verträge (`wendelin_core`)

Status: angenommen · 2026-10-12

## Kontext
`wendelin_core` ist der gemeinsame Vertrag für Provider-Adapter, Tool-Laufzeit, Storage, Agent-Schleife, Integrationen und App. Diese Pakete werden parallel entwickelt und kennen sich gegenseitig nicht (ADR 0001). Einige Schnittstellen weichen bewusst von der Skizze im Gesamtkonzept ab; das wird hier begründet.

## Entscheidungen

### 1. System-Prompt getrennt von den Nachrichten
`ChatRequest.systemPrompt` ist ein eigenes Feld und keine `Message(Role.system, …)` am Anfang der Liste.

- Die Anthropic-Messages-API erwartet den System-Prompt als eigenes Feld `system` (dort mit `cache_control` für Prompt Caching). Für OpenAI-kompatible APIs muss der Adapter ihn nur als erste `system`-Nachricht voranstellen. Getrennt gehalten ist die Umwandlung in beide Richtungen trivial. Andersherum müsste der Anthropic-Adapter Nachrichten herausfiltern und mit gemischten Positionen umgehen.
- Der Verlauf in `messages` bleibt unverändert speicherbar (Storage) und wiederverwendbar (Eskalation an einen anderen Provider). Der System-Prompt wird pro Aufruf frisch gebaut (Datum, Uhrzeit, Gedächtnis).
- `Role.system` bleibt für Sonderfälle erhalten, wird aber von der Agent-Schleife nicht genutzt.

### 2. Kein Flutter in `Integration`
Das Konzept skizziert `IconData get icon` und `Widget? settingsPage()`. In core stehen stattdessen `String get iconId` und die stabile `id`; die App ordnet Icon und Einstellungsseite über diese Schlüssel zu.

- core und alle `packages/` laufen mit `dart test` ohne Flutter-SDK (ADR 0001, `check_deps`).
- Integrationen lassen sich mit Fakes und Contract-Suites testen, und die Evals-CLI kann sie ohne UI laden.
- UI-Darstellung ist Sache des Design-Systems (WP07); eine Integration soll nicht über Widgets entscheiden.

### 3. `ToolOutcome` statt nacktem `ToolResult`
`Tool.execute` liefert ein `ToolOutcome(content, isError, undo?, summary?)` und keinen `ToolResultBlock`.

- Das Ergebnis hat zwei Empfänger: Das **Modell** bekommt nur `content` und `isError` (über `toResultBlock(callId)`). Die **UI** braucht zusätzlich einen kurzen Text für die Tool-Karte (`summary`, „Termin angelegt: Tauchen, Di 10:00“) und für `write`-Tools die Rückgängig-Aktion (`UndoAction` mit Label) für das 10-s-Fenster.
- `UndoAction` ist eine Closure und gehört nie in den Verlauf oder die Datenbank. Wäre sie Teil des Nachrichtenformats, wäre `ContentBlock` nicht mehr serialisierbar.
- Die Call-Id kennt das Tool nicht; sie wird erst in der Tool-Laufzeit zugeordnet.

### 4. Weitere Festlegungen
- **Stream-Vertrag für `LlmProvider.chat`**: Jeder Stream endet mit genau einem terminalen Event, entweder `Done` (Erfolg) oder `ErrorEvent` (Fehler, auch Abbruch mit `CancelledException`). Provider senden nie Stream-Fehler. Konsumenten brauchen damit nur eine `await for`-Schleife ohne `try/catch`. `ToolCallDelta.index` ist die Ordnungszahl des Tool-Calls in der Antwort, nicht der Content-Block-Index des Providers. Der Vertrag wird von `llmProviderContract` geprüft.
- **Contract-Suite mit Szenarien**: `llmProviderContract(create)` ruft `create(ContractScenario)` auf. Der Adapter liefert dann z. B. über einen Mock-HTTP-Client die passende Fixture. So kann dieselbe Suite den Fake und die echten Adapter prüfen. `expectWellFormedChatStream` ist zusätzlich einzeln für Fixture-Tests nutzbar.
- **Speicherformat**: `Message`/`ContentBlock.toJson` ist das eigene Speicherformat mit Diskriminator `type` (`text`, `image`, `toolCall`, `toolResult`, `thinking`), Bilder als Base64. Es ist kein Provider-Wire-Format. Unbekannte Typen führen zu einer `FormatException`.
- **Secrets**: `ProviderProfile` und `AuthMethod` enthalten nur `secretRef`-Schlüssel und sind deshalb gefahrlos als JSON speicherbar. `ProviderException.message` darf nie Schlüssel enthalten.
- **Geld**: Beträge sind ganzzahlige Mikro-USD (`costMicros`, `ProviderProfile.budgetMonthly`), damit es keine Rundungsfehler gibt.

## Folgen
- Adapter, Tool-Laufzeit und Agent-Schleife hängen nur von diesen Typen ab und können gegen `FakeLlmProvider`, `FakeTool`, `FakeIntegration`, `FakeToolCatalog` und `FakeToolInvoker` aus `package:wendelin_core/testing.dart` getestet werden.
- `package:test` ist eine reguläre Abhängigkeit von `wendelin_core`, weil die Contract-Suite `test`/`group` registriert. Produktivcode importiert `testing.dart` nicht (Ausnahme: Demo-Modus der App mit `FakeLlmProvider`).
- Umbenennungen dieser Typen brauchen eine neue ADR.
