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

### 4. Signiertes und verschlüsseltes Thinking wird unverändert zurückgegeben
Reasoning-Text kommt als `ThinkingDelta` (nur Anzeige). Am Ende jedes Blocks folgt `ThinkingComplete(ThinkingBlock)` mit dem vollständigen Block inklusive `signature`. Verschlüsseltes („redacted“) Thinking hat leeren Text und die opake Nutzlast in `redactedData`.

- Anthropic verlangt bei Thinking mit Tool Use, dass die Thinking-Blöcke der letzten Assistant-Nachricht **unverändert** (Text, Signatur bzw. verschlüsselte Daten) zurückgeschickt werden. Die Signatur kommt erst am Ende des Blocks. Deshalb braucht es ein eigenes Abschluss-Event statt nur Deltas.
- Die Agent-Schleife speichert den Block aus `ThinkingComplete` in der Assistant-Nachricht. Adapter müssen jeden `ThinkingBlock` bit-genau wieder in ihr Wire-Format übersetzen können. Die App interpretiert den Inhalt nie.

### 5. Bestätigungen sind idempotent, Abbruch hinterlässt keine offenen Calls
- `ConfirmationNeeded.respond`, `ConfirmationRequired.respond` und `EscalationConfirmationRequired.respond`: Die erste Antwort gilt, spätere werden ignoriert, es gibt keinen `StateError`. Sprache und Tap können gleichzeitig antworten, und der Abbruch löst offene Fragen selbst auf.
- `ToolInvoker` beim Abbruch über `ctx.cancel`: Offene Bestätigungen gelten als abgelehnt, weitere Tools werden nicht mehr gestartet, und trotzdem bekommt jeder Call genau ein `ToolFinished` (`ToolOutcome.cancelled()`, Fehler). So hat jeder `tool_use` im Verlauf ein `tool_result`. Ohne das lehnen Provider die nächste Anfrage ab. Ein Tool, das trotz Abbruch fertig wurde, behält sein echtes Ergebnis, denn seine Wirkung ist eingetreten. Ablehnung durch den Nutzer ist kein Fehler (`ToolOutcome.declined()`). Die Regeln gelten für sequentielle und parallele Invoker gleichermaßen. Outcomes, die der Invoker selbst erzeugt (abgebrochen, abgelehnt, unbekanntes Tool, ungültige Argumente, Policy), gibt er unverändert weiter: keine Datenhülle, keine Kürzung. Der Vertrag wird von `toolInvokerContract` geprüft. Die core-Tests lassen die Suite gegen einen sequentiellen (`FakeToolInvoker`) und einen parallelen Referenz-Invoker laufen.

### 6. Eskalation unter die Datenschutzstufe nur mit Zustimmung
Das Konzept erlaubt eine Eskalation zu einem Provider mit niedrigerer Datenschutzstufe nur, wenn der Nutzer zustimmt. Dafür gibt es schon jetzt das `AgentEvent` `EscalationConfirmationRequired(fromProfile, toProfile, reason, respond)`. Vor der Zustimmung geht kein Byte an `toProfile`. Mit dem Event im Vertrag können WP05 (Schleife) und WP08 (UI) unabhängig voneinander bauen.

### 7. Weitere Festlegungen
- **Stream-Vertrag für `LlmProvider.chat`**: Jeder Stream endet mit genau einem terminalen Event, entweder `Done` (Erfolg) oder `ErrorEvent` (Fehler, auch Abbruch mit `CancelledException`). Provider senden nie Stream-Fehler. Konsumenten brauchen damit nur eine `await for`-Schleife ohne `try/catch`. `ToolCallDelta.index` ist die Ordnungszahl des Tool-Calls in der Antwort, nicht der Content-Block-Index des Providers. Der Vertrag wird von `llmProviderContract` geprüft.
- **Unvollständige Tool-Calls**: Der *k*-te `ToolCallComplete` gehört zu den `ToolCallDelta`s mit `index == k`. Endet der Stream mit `Done`, ist jeder Call vollständig. Endet er mit `ErrorEvent` (auch bei Abbruch), dürfen Calls unvollständig bleiben. Konsumenten verwerfen sie und führen sie nie aus.
- **Usage als Inkrement**: Jedes `UsageEvent` ist ein Zuwachs, Konsumenten summieren. Adapter, deren API kumulative Werte liefert (Anthropic `message_delta`), rechnen sie in Differenzen um.
- **`StopReason.pauseTurn`**: Der Provider hat einen langen Zug pausiert (Anthropic-Server-Tools). Das ist weder eine Endantwort noch eine Tool-Runde: Die Agent-Schleife schickt den Verlauf samt der unvollständigen Assistant-Nachricht erneut.
- **Contract-Suite mit Szenarien**: `llmProviderContract(create)` ruft `create(ContractScenario)` auf. Der Adapter liefert dann z. B. über einen Mock-HTTP-Client die passende Fixture. So kann dieselbe Suite den Fake und die echten Adapter prüfen. `expectWellFormedChatStream` ist zusätzlich einzeln für Fixture-Tests nutzbar.
- **Speicherformat**: `Message`/`ContentBlock.toJson` ist das eigene Speicherformat mit Diskriminator `type` (`text`, `image`, `toolCall`, `toolResult`, `thinking`), Bilder als Base64. Es ist kein Provider-Wire-Format. Unbekannte Typen führen zu einer `FormatException`.
- **Secrets**: `ProviderProfile` und `AuthMethod` enthalten nur `secretRef`-Schlüssel und sind deshalb gefahrlos als JSON speicherbar. `ProviderException.message` darf nie Schlüssel enthalten.
- **Geld**: Beträge sind ganzzahlige Mikro-USD (`costMicros`, `ProviderProfile.budgetMonthly`), damit es keine Rundungsfehler gibt.

## Folgen
- Adapter, Tool-Laufzeit und Agent-Schleife hängen nur von diesen Typen ab und können gegen `FakeLlmProvider`, `FakeTool`, `FakeIntegration`, `FakeToolCatalog` und `FakeToolInvoker` getestet werden.
- `package:wendelin_core/fakes.dart` enthält nur die Fakes, ohne `package:test`, und ist auch für Produktivcode erlaubt (Demo-Modus der App). `package:wendelin_core/testing.dart` enthält zusätzlich die Contract-Suiten `llmProviderContract` und `toolInvokerContract`. Nur sie brauchen `package:test`, das deshalb eine reguläre Abhängigkeit von `wendelin_core` ist.
- `ProviderProfile.options` nimmt adapterspezifische, JSON-fähige Einstellungen auf (z. B. `enableServerWebSearch`, `thinkingBudget`), ohne dass core die Adapter kennt. `HealthCheck.detected` meldet die im Test tatsächlich geprüften Fähigkeiten.
- `copyWith` kann nullable Felder nicht auf `null` setzen (`ChatRequest`, `ProviderProfile`); dafür wird ein neues Objekt gebaut. `ToolSpec.inputSchema` wird wegen des `const`-Konstruktors nicht kopiert und gilt als unveränderlich.
- Der Name eines Tools wird nur über `Tool.isValidToolName` geprüft (statisch, wie im WP-Dokument).
- Umbenennungen dieser Typen brauchen eine neue ADR.

## 8. Nachträge aus WP05 (2026-10-13)

`AgentEvent` ergänzt um `AgentTextReset(reason)` (bereits gestreamter Text der aktuellen Antwort wird verworfen, z. B. bei Retry oder Übergabe an einen anderen Provider – UI/TTS verwerfen ihn ebenfalls), `AgentThinkingDelta` (nur Anzeige) und `BudgetWarning` (Warnschwelle erreicht, Lauf geht weiter).

## 9. Provider-Blöcke (2026-10-13, Review WP02)

`ContentBlock` ergänzt um `ProviderBlock(provider, rawJson, summary?)`, `ChatEvent` um `ProviderBlockComplete`. Adapter legen Blöcke, die das interne Format nicht kennt (z. B. Anthropic `server_tool_use`/`web_search_tool_result`), unverändert als JSON ab und senden sie demselben Provider unverändert zurück (nötig für `pause_turn`). Andere Provider bekommen sie nie (der Agent verwirft sie beim Providerwechsel wie fremde Thinking-Blöcke). Inhalt ist Daten: nie gesprochen, nie als eigener Text des Assistenten; `summary` nur zur Anzeige.

## 10. Sicherheit: eine Quelle für die Gedächtnis-Schutzregel (2026-10-13, WP13)

`detectSensitiveContent(text) → SensitiveFinding?` (Art `SensitiveKind` cardNumber/iban/credential plus deutscher Grund) und `luhnValid` liegen in `wendelin_core` (`lib/src/safety/`). Speicher (`MemoryRepository` in wendelin_storage), Gedächtnis-Tool und Fakes (wendelin_integrations) nutzen nur diese Funktion; eigene Kopien gibt es nicht mehr. Die Erkennung ist eine reine Funktion ohne Abhängigkeiten. Zu viel ablehnen ist hier die sichere Seite. Die Fälle stehen als Tabellentest in core.

## 11. Folgepunkte aus WP06/WP08 (2026-10-13, WP14)

- **Effektive Risikostufe in der Bestätigung**: `ConfirmationNeeded` und `ConfirmationRequired` tragen `risk`, also die Stufe, mit der die Laufzeit den Call behandelt, nicht `Tool.risk`. Eine von der Policy verlangte Bestätigung zählt als `external`, auch für ein `read`- oder `write`-Tool, das der Nutzer verschärft hat (`RiskPolicy.effectiveRisk`). Der `ToolExecutor` setzt die Stufe, der `AgentRunner` reicht sie durch, und die App zeigt sie an. Der Parameter ist optional mit Standard `external` und damit abwärtskompatibel.
- **Bestätigungstext mit Kontext**: Neue optionale Fähigkeit `ConfirmationPreparer.prepareConfirmation(args, ctx)` (asynchron). Laufzeiten fragen den Text über die Erweiterung `Tool.confirmationText(args, ctx)` ab. Sie nutzt den Preparer, wenn das Tool ihn implementiert, sonst `describeForConfirmation`. Schlägt der Preparer fehl, dauert er länger als 5 s, liefert er leeren Text oder wird der Lauf abgebrochen, gilt der synchrone Text. Gefragt wird in jedem Fall. Eine Default-Methode in `Tool` war nicht möglich: Dart vererbt sie bei `implements` nicht, das hätte jede Tool-Implementierung gebrochen. Invoker bauen den Text erst, wenn die Bestätigung an der Reihe ist. So bleibt die Reihenfolge erhalten, und der Text zeigt den aktuellen Stand nach früheren Calls. `toolInvokerContract` prüft das mit `preparedConfirmation`.
- **Optionale Setup-Schritte**: `SetupStep.optional`. `SetupState.requiredComplete(setup)` ist wahr, wenn alle offenen Schritte optional sind. Die Registry setzt eine solche Integration auf aktiv (z. B. web ohne Suchdienst mit nur `web__fetch`); der Schritt bleibt in `missingSteps` sichtbar.
- **Katalog je Ziel**: `ToolContext.privacyLevel` (optional) nennt die Stufe des Modells, von dem die Calls kommen. Invoker, die mehrere Stufen bedienen (`ToolExecutor.catalogFor`), suchen Tools nur im Katalog dieser Stufe. Die Auswahl je Ziel und das Ausblenden geschützter Inhalte macht die Agent-Schleife (ADR 0003).

## 12. Prüfstatus von TEE-Antworten (2026-10-14, WP46)

`AttestationStatus` (grün/gelb/rot), `AttestationReport(logId, status, detail)` und die Fähigkeit `AttestationAware` (`reports`, `pendingReport()`) liegen in `wendelin_core` (`lib/src/provider/attestation.dart`). Neues `AgentEvent` `AttestationStatusChanged(stepId, status, logId, detail)`: je Modellaufruf eines Providers mit `AttestationAware` einmal, sobald die Prüfung der Antwort feststeht. Neue `ProviderException` `AttestationFailedException(message, stage, unavailable)`; `retryable` ist nur bei `unavailable` wahr (nicht prüfbar, nicht fehlgeschlagen). Das Verhalten der Schleife (externe Tools warten auf grüne Quittung) steht in ADR 0014 §7. Der Platzhalter `Verification` bleibt unverändert und ungenutzt. Konzeptabweichung 11 und 8.
