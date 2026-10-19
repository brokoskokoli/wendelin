# Voice Agent App – Gesamtkonzept

Oct 12, 2026 · @Stefan

## Ziel und Leitprinzipien

Ziel ist ein persönlicher Sprachassistent für Android und iOS, der per Wake Word, Assistenten-Geste oder Button startet, lokal transkribiert und Befehle über ein frei wählbares LLM in Tool-Aufrufe auf dem Handy oder auf MCP-Servern übersetzt. Abgerechnet wird über eigene API-Keys bzw. Provider-Accounts, nicht über ein Chat-Abo; Gespräche landen in keinem Chat-Verlauf eines Anbieters.

**Leitprinzipien**

- **Alles ist ein Plugin.** LLM-Provider, Tools, Wake-Word-Engines, STT und TTS hängen jeweils an einer eigenen Schnittstelle mit Registry. Neue Fähigkeiten kommen ohne Umbau des Kerns dazu.
- **Provider-agnostisch.** Ein internes Nachrichten- und Tool-Format; Adapter übersetzen zu Anthropic, OpenAI-kompatiblen APIs und weiteren.
- **Lokal zuerst.** Wake Word, VAD und STT laufen auf dem Gerät. Bis zum Wake Word verlässt kein Audio das Handy, danach nur Text.
- **Ohne Google-Dienste lauffähig (K7).** Die App braucht keine Google Play Services; alles Pflichtige nutzt AOSP-Schnittstellen. Funktionen, die eine Fremd-App voraussetzen (System-TTS, System-Spracherkennung, Uhr-App), sind optional oder haben eine Ausweichlösung.
- **Datenschutz wählbar.** Neben normalen APIs gibt es TEE-Provider mit Attestierungsprüfung in der App und sichtbarem Prüfprotokoll.
- **Kontrolle beim Nutzer.** Jedes Tool hat eine Risikostufe; riskante Aktionen brauchen Bestätigung. Die App führt Tools aus, nie das Modell.
- **Günstig per Default, stark bei Bedarf.** Ein kleines Modell antwortet standardmäßig; Regeln eskalieren zu einem stärkeren Modell.

**Scope**

| Bereich | MVP (v0.1–0.3) | Später |
| --- | --- | --- |
| Plattform | Android | iOS |
| Eingabe | Push-to-talk, Standard-Assistent | Wake Word, iOS Action Button, Siri-Intent |
| STT / TTS | Whisper lokal (sherpa-onnx), System-TTS | Cloud-STT optional, bessere Stimmen |
| Provider | Anthropic, OpenAI-kompatibel | TEE mit Attestierung, OAuth-Login, lokale Modelle |
| Tools | Kalender, Obsidian, Zwischenablage, Gedächtnis, Wecker/Timer, Web-Suche | Spotify, Kontakte/SMS, Standort, Kamera, Wetter/Meer, Aufgaben |
| Erweiterung | MCP-Client (Streamable HTTP) | Routing-Regeln mit Bedingungen, Tool-Pakete |

## Plattform und Tech-Stack

Entscheidung: **Flutter** für UI und gesamte Kernlogik (Agent-Schleife, Provider, Routing, Tool-Registry, MCP), plus native Plugins in Kotlin und Swift nur dort, wo das Betriebssystem es verlangt. So teilen Android und iOS etwa 85–90 % des Codes.

**Begründung**

- sherpa-onnx bietet Dart-Bindings für Keyword Spotting (Wake Word), VAD, Whisper-STT und TTS in einer Bibliothek.
- Kelivo zeigt, dass Flutter mit MCP, sherpa-onnx und Kalender-Tools auf beiden Plattformen funktioniert (nur als Referenz lesen, AGPL nicht kopieren).
- Die Systemteile, die ohnehin nativ sein müssen, sind überschaubar und klar abgrenzbar.

**Bausteine**

| Bereich | Wahl | Bemerkung |
| --- | --- | --- |
| State / DI | Riverpod | Provider-, Tool- und Settings-Registries als Riverpod-Provider |
| Persistenz | drift (SQLite) | Gesprächsverlauf, Gedächtnis, Audit-Log, Provider-Konfiguration |
| Secrets | flutter\_secure\_storage | Android Keystore / iOS Keychain für API-Keys und OAuth-Tokens |
| HTTP / Streaming | dio oder http + eigener SSE-Parser | für Anthropic-, OpenAI- und MCP-Streams |
| LLM-Clients | eigene schlanke Adapter | keine schweren SDKs; volle Kontrolle über Rohbytes (wichtig für TEE-Quittungen) |
| MCP | eigener Streamable-HTTP-Client (JSON-RPC 2.0) | vorhandene Dart-MCP-Pakete prüfen, sonst selbst implementieren; der Client-Teil ist klein |
| Audio | sherpa\_onnx, record / native Audio | 16 kHz Mono PCM |
| Kalender | device\_calendar o. ä. | Android CalendarContract, iOS EventKit |
| Dateien | eigenes Plugin | Android SAF mit persistenten URI-Rechten, iOS Security-Scoped Bookmarks |
| TEE-Prüfung | Rust-Kern via flutter\_rust\_bridge | DCAP-Quote-Verifikation (z. B. dcap-qvl), Signaturprüfung |

**Nativ zu implementieren**

- Android: `VoiceInteractionService` (Standard-Assistent), Foreground Service vom Typ `microphone` für das Wake Word, Intents für Wecker/Timer, SAF-Ordnerzugriff, Spotify App Remote SDK.
- iOS: App Intents (Siri, Kurzbefehle, Action Button, Kontrollzentrum), AlarmKit, Security-Scoped Bookmarks, Spotify iOS SDK.

Alternative: Kotlin Multiplatform mit Compose Multiplatform wäre auf Android etwas nativer und nutzt das offizielle MCP Kotlin SDK; dafür fehlen fertige Bindings für einige Audio-Bausteine auf iOS. Wenn "Jiggler" im Gespräch etwas anderes als Flutter meinte, ist das die erste Stelle zum Anpassen.

## Gesamtarchitektur

Die Agent-Schleife ist das Zentrum: Sie bekommt Text aus der Sprach-Pipeline, lässt das Routing den Provider wählen und führt Tool-Calls ausschließlich über die Tool-Registry aus.

&#91;embedded content: Architektur · 11 Komponenten in 4 Ebenen\]

Das Modell ruft nie selbst Tools auf; jede Ebene hängt an einem Interface mit Registry, sodass Provider, Integrationen und Sprachbausteine einzeln austauschbar sind.

**Datenfluss einer Anfrage**

1. Auslöser startet die Aufnahme; VAD beendet sie; Whisper liefert Text, Sprache und Konfidenz.
2. Die Agent-Schleife baut den Kontext (System-Prompt, Gedächtnis, aktive Tools, Verlauf).
3. Das Routing wählt Provider und Modell; die Provider-Schicht übersetzt ins API-Format, bei TEE mit Attestierung.
4. Tool-Calls des Modells laufen über Registry und Executor mit Risikoprüfung; Ergebnisse gehen zurück ans Modell.
5. Die Endantwort geht an TTS und Bildschirm; Verlauf, Kosten und Prüfergebnisse landen im lokalen Speicher.

## Sprach-Pipeline

Die Pipeline läuft in fünf Stufen, alle austauschbar: Auslöser → Aufnahme mit VAD → STT → Agent → TTS. Bis zur Agent-Stufe bleibt alles auf dem Gerät.

1. **Auslöser** (Interface `TriggerSource`)
   - Push-to-talk in der App und als Widget bzw. Schnellkachel.
   - Android: App als **Standard-Assistent** über `VoiceInteractionService` + `VoiceInteractionSessionService` (langer Druck auf Power-Taste, Assistenten-Geste, Bluetooth-Headset-Taste). Einstellung führt den Nutzer zu `Settings.ACTION_VOICE_INPUT_SETTINGS`.
   - Android: **Wake Word** im Foreground Service (Typ `microphone`, permanente Benachrichtigung). Start nur aus dem Vordergrund; Hinweis zur Akku-Optimierung. Optional nur aktiv beim Laden, im Auto (Bluetooth) oder in einem Zeitfenster.
   - iOS: App Intent "Frag \<Name>" für Siri und Kurzbefehle, Action Button, Control im Kontrollzentrum bzw. Sperrbildschirm. Kein Dauerzuhören im Hintergrund.
2. **Wake-Word-Engine** (Interface `WakeWordEngine`)
   - Standard: sherpa-onnx Keyword Spotting (Apache-2.0, eigene Schlüsselwörter per Text, kein Training nötig).
   - Optional: openWakeWord (eigene Modelle trainierbar; vortrainierte Modelle nur nicht-kommerziell), Porcupine (AccessKey nötig).
   - Konfigurierbar: Wake Word, Empfindlichkeit, Bestätigungston.
3. **Aufnahme und VAD**: Silero VAD (in sherpa-onnx enthalten) beendet die Aufnahme nach ca. 800 ms Stille, maximal 30 s. Pre-Roll-Puffer von 300 ms, damit das erste Wort nach dem Wake Word nicht abgeschnitten wird.
4. **STT** (Interface `SpeechToText`)
   - Standard: Whisper lokal über sherpa-onnx; Modellgröße wählbar (`base` schnell, `small` besser für Deutsch und Französisch; größere Modelle nach K64). Modelle werden beim ersten Start heruntergeladen, nicht ins APK gepackt.
   - Sprache: automatisch erkennen oder fest einstellen (de, fr, en).
   - Alternativen: System-Spracherkennung (Android `SpeechRecognizer`, iOS `SpeechAnalyzer`; nur angeboten, wenn eine Erkennungs-App installiert ist, K7), optional Cloud-STT.
   - Ausgabe: Text + erkannte Sprache + Konfidenz (für die Routing-Regeln).
5. **TTS** (Interface `TextToSpeech`): Systemstimme als Standard; ist keine Sprachausgabe installiert (z. B. Gerät ohne Google), automatisch sherpa-onnx-Stimmen (offline, K7); optional Cloud-TTS. Antworten werden für Sprache gekürzt; lange Inhalte nur auf dem Bildschirm.

**Gesprächsmodus**: Nach einer Antwort kann die App 5 s weiter zuhören (Folgefrage ohne Wake Word). Abbruchwort ("Stopp") und Antippen beenden jederzeit.

**Barge-in**: Spricht der Nutzer während der TTS-Ausgabe, wird die Ausgabe gestoppt (erst ab v0.4, Echo-Unterdrückung beachten).

## LLM-Provider-Schicht

Die App spricht intern nur ein eigenes Nachrichtenformat; Adapter übersetzen es pro API-Familie. Der Nutzer legt beliebig viele **Provider-Profile** an (z. B. "Claude API", "Phala GLM klein", "Ollama Homeserver") und wählt pro Profil ein Modell.

**Internes Format**

- `Message { role: system|user|assistant|tool, content: List<ContentBlock> }`
- `ContentBlock` = `Text` | `Image` | `ToolCall { id, name, argumentsJson }` | `ToolResult { callId, content, isError }` | `Thinking` (optional, nur Anzeige) | `ProviderBlock { provider, rawJson, summary? }` (K8: anbieterspezifische Blöcke wie Claudes serverseitige Web-Suche, werden nur an denselben Anbieter unverändert zurückgegeben, nie vorgelesen)
- `ToolSpec { name, description, inputSchema (JSON Schema) }`
- `ChatRequest { messages, tools, model, maxTokens, temperature, toolChoice, metadata }`
- `ChatEvent` (Stream) = `TextDelta` | `ThinkingDelta` | `ThinkingComplete` (K3) | `ToolCallDelta` | `ToolCallComplete` | `Usage { inputTokens, outputTokens, cachedTokens }` | `Done { stopReason }` | `Error`

**Interface**

```
abstract class LlmProvider {
  ProviderType get type;            // anthropic, openaiCompatible, ...
  ProviderCapabilities get caps;    // tools, vision, streaming, promptCaching, tee
  Future<List<ModelInfo>> listModels();
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel});
  Future<HealthCheck> test();       // für den Einrichtungs-Dialog
}
```

**Adapter**

| Adapter | Deckt ab | Besonderheiten |
| --- | --- | --- |
| `AnthropicMessagesAdapter` | Claude (Haiku, Sonnet, Opus, Fable) | Tool Use, Prompt Caching, serverseitige Web-Suche als optionales Tool, Remote-MCP-Connector optional |
| `OpenAiChatAdapter` | OpenAI, Mistral, OpenRouter, Phala, Tinfoil, Privatemode (über Proxy), Ollama, LM Studio, vLLM | Base-URL + Key frei; Function Calling; Fähigkeiten pro Modell aus Katalog oder Test |
| `OpenAiResponsesAdapter` (später) | neuere OpenAI-Modelle | nur falls nötig |
| `GeminiAdapter` (später) | Google | optional |

TEE-Provider sind keine eigene API-Familie, sondern ein **Decorator** um einen Adapter (siehe nächster Abschnitt).

**Einrichtung (Dialog pro Provider)**

1. Provider-Typ wählen: Vorlagen für Claude, OpenAI, OpenRouter, Mistral, Phala, Tinfoil, Ollama, "Eigener OpenAI-kompatibler Endpunkt".
2. Anmeldung je nach Typ: API-Key einfügen (mit Link zur Key-Seite des Anbieters), OAuth/PKCE wo der Anbieter das für Drittanbieter-Apps offiziell anbietet (z. B. OpenRouter), oder keine Auth (lokal).
3. Verbindungstest, Modelle laden, Standardmodell wählen; Fähigkeiten (Tools, Vision) werden mit einem Mini-Tool-Call geprüft.
4. Optional: Budget pro Monat und Warnschwelle.

**Wichtig zu Abo-Logins**: Ein Login mit einem Claude-Pro/Max-Abo oder einem ChatGPT/Codex-Abo ist für eigene Apps kein offiziell vorgesehener Weg; Claude wird über einen Console-API-Key angebunden, OpenAI über einen Platform-API-Key. Die Auth-Schicht (`AuthMethod` = `ApiKey` | `OAuthPkce` | `None` | `CustomHeaders`) ist so gebaut, dass ein offizieller OAuth-Flow später nur ein weiteres Modul ist.

**Kosten**: Jede Antwort liefert `Usage`; die App rechnet mit Preisen aus dem Modellkatalog (vom Nutzer pflegbar) und zeigt Kosten pro Anfrage, Tag und Monat. Bei erreichtem Budget: Warnung oder Sperre, einstellbar.

## TEE-Provider und Attestierung

TEE-Provider laufen über den normalen OpenAI-kompatiblen Adapter, umhüllt von einem `AttestedProvider`-Decorator, der vor der Nutzung die Enklave prüft und nach jeder Antwort die signierte Quittung verifiziert. Tools werden sofort ausgeführt; die Quittung wird danach geprüft (bewusste Entscheidung: Geschwindigkeit vor Strenge, Risiko eines falschen Kalendereintrags ist vertretbar).

**Interface**

```
abstract class AttestationVerifier {
  Future<AttestationResult> attest();                 // pro Sitzung, mit frischer Nonce
  Future<ReceiptResult> verifyReceipt(ReceiptRef ref,  // pro Antwort
      Uint8List requestBytes, Uint8List responseBytes);
}
```

Implementierungen: `PhalaVerifier` zuerst; `TinfoilVerifier` und `PrivatemodeVerifier` später. Die kryptografische Prüfung (TDX-Quote gegen Intel DCAP, Signaturen) liegt in einem Rust-Modul, angebunden über flutter\_rust\_bridge.

**Ablauf am Beispiel Phala**

1. Modelle über `GET /v1/models` laden und nur solche mit `is_tee: true` zur Auswahl anbieten.
2. Sitzungsstart: zufällige Nonce (32 Byte) → `GET /v1/aci/attestation?nonce=…` (Gateway) bzw. `GET /v1/attestation/report?model=…&nonce=…` (inkl. NVIDIA-GPU-Evidenz), Base-URL `https://api.redpill.ai/v1` (K2).
3. Prüfen: TDX-Quote gegen DCAP-Kollateral; Report-Daten binden Nonce und Workload-Keyset; Keyset-Signatur unter dem Workload-Identity-Key; Keyset-`not_after` in der Zukunft (ein Feld `freshness.stale_after` gibt es nicht, K2); optional GPU-Evidenz (`nvidia_payload`); optional `source_provenance` (`repo_url`, `repo_commit`) gegen eine Liste vertrauenswürdiger Releases.
4. **Pinning**: `workload_keyset_digest` und `source_provenance.repo_commit` speichern (ein `workload_id` liefert die API nicht, K2). Ändern sie sich, neue Attestierung und Hinweis an den Nutzer ("Anbieter hat ein Update ausgerollt, neu geprüft"). TLS terminiert in der Enklave (`downstream_tls_binding`, `tls_public_keys`): TLS-Verbindung auf den SPKI-Hash aus dem Keyset pinnen, erzwungen und fail-closed (K37, WP61).
5. Pro Antwort: `x-receipt-id` lesen → `GET /v1/aci/receipts/{id}` → Ed25519-Signatur gegen `receipt_signing_keys` (signiert ist die Quittung ohne `signature` als JSON mit sortierten Schlüsseln, kompakt), `body_hash` von `request.received`/`response.returned` gegen die exakt gesendeten bzw. empfangenen Bytes, Eintrag `upstream.verified` mit `result: verified`. Im Test war `required: false` – wie `required: true` erzwungen wird, ist zu klären (K2).

**Fehlerverhalten**

| Situation | Verhalten |
| --- | --- |
| Attestierung schlägt fehl | Provider gesperrt, Fehlermeldung, kein Request wird gesendet; Fallback nur wenn der Nutzer das erlaubt hat |
| Quittung ungültig oder nicht verifiziert | Rotes Symbol am Gesprächsschritt, Warnung, Eintrag im Prüfprotokoll; weitere Anfragen an diesen Provider gesperrt bis zur neuen Attestierung |
| Quittung nicht abrufbar (Netzwerk) | Gelbes Symbol, bis zu 3 Wiederholungen, dann wie ungültig |
| Pinning-Wechsel | Neue Attestierung erzwingen, Nutzer informieren |

**Prüfprotokoll (UI)**: Liste pro Anfrage mit Zeit, Provider, Modell, `workload_id`, Commit bzw. Image-Digest, Ergebnis jeder Prüfstufe und Quittungs-ID; Statusanzeige grün / gelb / rot im Gespräch. Exportierbar als JSON.

**Hinweise**: Streaming-Antworten werden erst nach Ende des Streams geprüft. GPU-Attestierung (NVIDIA Hopper) ist im Report enthalten, wenn das Modell angegeben wird (K2). Anfragen, die nicht verifiziert werden können, dürfen keine sensiblen Folgeaktionen auslösen (z. B. keine SMS).

## Routing und Eskalation

Ein Default-Provider beantwortet alles; eine geordnete Regelliste wählt vor dem Start einen anderen Provider, und eine Eskalationskette übernimmt während der Bearbeitung, wenn das Modell scheitert.

**Regeln vor dem Start** (erste passende Regel gewinnt)

```
RoutingRule {
  name, enabled, priority,
  condition: Condition,        // kombinierbar mit and / or / not
  target: { profileId, modelId },
  stripTrigger: bool           // Schlüsselwort aus dem Text entfernen
}
```

Bedingungen (erweiterbar über ein `ConditionType`-Registry):

- `keyword` / `prefix` / `regex` im transkribierten Text (z. B. "Claude, …", "denk gründlich nach")
- `language` (erkannte Sprache)
- `sttConfidence < x` (unsichere Erkennung → stärkeres Modell)
- `needsTool` (Text passt zu einer Tool-Kategorie, z. B. Obsidian-Bearbeitung)
- `inputLength > n` Zeichen, `hasImage`
- `network` (offline → lokales Modell), `timeWindow`
- `privacy` (Schlüsselwort "privat" → nur TEE- oder lokale Provider)

Beispiele:

| Regel | Bedingung | Ziel |
| --- | --- | --- |
| Starkes Modell | Präfix "Claude" oder "Fable" | Claude API, Fable bzw. Opus |
| Privat | Schlüsselwort "privat" | Phala, kleines GLM |
| Offline | kein Netz | Ollama auf dem Homeserver bzw. lokales Modell |
| Notizen umschreiben | `needsTool = obsidian.edit` | Claude Sonnet |
| Default | immer | Phala, kleines GLM ohne Reasoning |

**Eskalation während der Bearbeitung** (Kette pro Profil, z. B. GLM klein → Claude Sonnet → Claude Fable)

Auslöser:

- API-Fehler, Timeout oder Rate-Limit
- zweimal ungültiges Tool-JSON oder unbekanntes Tool
- mehr als N Tool-Runden ohne Ergebnis (Standard 4)
- Modell meldet, dass es die Aufgabe nicht lösen kann (Antwortklassifikation per Schlüsselwörtern)
- Nutzer sagt "nochmal mit Claude" oder "das war falsch"

Verhalten:

- Das stärkere Modell bekommt den bisherigen Verlauf inklusive bereits ausgeführter Tool-Ergebnisse und einen Hinweis, dass diese Aktionen schon passiert sind. **Bereits ausgeführte Tools werden nie automatisch wiederholt.**
- Datenschutz-Grenze: Eine Anfrage, die über eine "privat"-Regel lief, eskaliert nur zu Providern mit gleicher oder höherer Datenschutzstufe (`local` > `tee` > `eu` > `standard`), außer der Nutzer bestätigt.
- Jede Eskalation erscheint im Gespräch ("an Claude Sonnet übergeben") und im Log.

**Regel-Editor**: Regeln als Liste mit Drag-and-drop, Bedingungen per Baukasten, Testfeld ("welche Regel greift für diesen Satz?"). Speicherung als JSON, import- und exportierbar.

## Agent-Schleife

Die Agent-Schleife ist provider-unabhängig: Sie baut den Kontext, ruft das gewählte Modell, führt angeforderte Tools über die Registry aus und wiederholt, bis eine Endantwort kommt oder ein Limit greift.

**Ablauf einer Anfrage**

1. **Kontext bauen**: System-Prompt mit Datum, Uhrzeit, Zeitzone, Gerätesprache, Name des Nutzers; relevante Einträge aus dem Gedächtnis; aktive Tool-Specs (nur aktivierte Integrationen); kurzer Gesprächsverlauf (letzte N Züge der aktuellen Sitzung).
2. **Routing**: Regeln wählen Provider und Modell.
3. **Modellaufruf** mit Streaming; Text wird live angezeigt, für TTS satzweise gepuffert.
4. **Tool-Calls**: Für jeden Call prüft der `ToolExecutor` Risikostufe und Berechtigung. Stufe `confirm` zeigt eine Bestätigungskarte (Sprache: "Soll ich das so eintragen?" – Antwort ja/nein per Stimme oder Tap). Unabhängige Calls laufen parallel.
5. **Ergebnisse** gehen als `ToolResult` zurück an das Modell; Fehler als `isError` mit lesbarer Meldung, damit das Modell reagieren kann.
6. **Wiederholen** bis `stopReason = endTurn` oder Limit: max. 8 Tool-Runden, max. 60 s Gesamtdauer, Token-Budget pro Anfrage.
7. **Abschluss**: Antwort per TTS (gekürzt) und Bildschirm; Usage und Kosten speichern; bei TEE: Quittungen asynchron prüfen; Gedächtnis-Kandidaten markieren.

**Schnittstelle**

```
class AgentRun {
  Stream<AgentEvent> run(UserInput input);   // Text, optional Bild
  void cancel();
}
// AgentEvent: Routed, TextDelta, ToolCallStarted, ConfirmationRequired,
//             EscalationConfirmationRequired (K3), ToolCallFinished,
//             Escalated, Usage, Verification, Done, Failed
```

**Tool-Auswahl bei vielen Tools**: Ab ca. 30 aktiven Tools sendet die App zuerst nur Kategorien bzw. ein `search_tools`-Meta-Tool; das Modell fordert die passenden Tools an. Spart Tokens und hilft kleinen Modellen bei der richtigen Wahl.

**Prompt Caching**: System-Prompt und Tool-Specs stehen stabil am Anfang des Kontexts, damit Provider mit Caching (Anthropic, einige OpenAI-kompatible) sie günstig wiederverwenden.

**Sitzungen**: Eine Sitzung endet nach 5 min Inaktivität oder auf Befehl ("neues Thema"). Verläufe bleiben lokal in SQLite und sind durchsuchbar; Aufbewahrungsdauer einstellbar.

## Tool-System

Tools sind in **Integrationen** gebündelt (z. B. "Kalender", "Spotify", "Bring!"). Der Nutzer aktiviert nur die Integrationen, die er will; die App bietet nur solche an, die auf dem Gerät verfügbar sind, und schickt nur Tools aktiver Integrationen ans Modell.

**Schnittstellen**

```
abstract class Integration {     // ohne Flutter-Typen, siehe K4
  String get id;                    // 'calendar', 'spotify', 'bring'
  String get displayName; String get iconId;
  Set<Platform> get platforms;      // android, ios
  Future<Availability> checkAvailability();  // App installiert? OS-Version?
  List<SetupStep> get setup;        // Berechtigung, Login, Ordnerwahl
  Future<SetupState> setupState();
  List<Tool> get tools;
  bool get sensitive;               // Einstellungsseite ordnet die App über id zu (K4)
}

abstract class Tool {
  String get name;                  // 'calendar__create_event'
  String get description;           // fürs Modell, kurz und präzise
  JsonSchema get inputSchema;
  RiskLevel get risk;               // read | write | external
  Future<ToolOutcome> execute(Map<String, dynamic> args, ToolContext ctx);  // Ergebnis + optional Undo + Kurztext (K4)
  String describeForConfirmation(Map<String, dynamic> args);  // "Termin 'Tauchen' Do 10–11 Uhr"
}
```

Namen folgen `integration__aktion` (nur Buchstaben, Ziffern, `_`, `-`), weil einige APIs keine Punkte in Tool-Namen erlauben.

**Zustand einer Integration**

| Zustand | Bedeutung | Anzeige |
| --- | --- | --- |
| Nicht verfügbar | App fehlt oder Plattform passt nicht | ausgegraut, mit Link zum Store |
| Verfügbar | nutzbar, aber nicht aktiviert | Schalter aus |
| Einrichtung nötig | aktiviert, aber Berechtigung, Login oder Ordner fehlt | gelb, "Einrichten" |
| Aktiv | Tools werden ans Modell geschickt | grün |
| Fehler | z. B. Token abgelaufen | rot, Tools pausiert |

**App-Erkennung**

- Android: bekannte Paketnamen in `<queries>` im Manifest deklarieren (z. B. Spotify, Bring!, Obsidian) und mit `PackageManager` prüfen; für generische Fälle Intent-Auflösung.
- iOS: URL-Schemes in `LSApplicationQueriesSchemes` deklarieren und mit `canOpenURL` prüfen (z. B. `spotify:`, `obsidian:`).
- Die Prüfung läuft beim Start und bei Rückkehr in die App; fällt eine App weg, wird die Integration pausiert.

**Risikostufen und Bestätigung**

| Stufe | Beispiele | Standard |
| --- | --- | --- |
| `read` | Kalender lesen, Notiz suchen, Wetter | ohne Nachfrage |
| `write` | Termin anlegen, Notiz anhängen, Artikel auf Einkaufsliste | ohne Nachfrage, mit Rückgängig-Option für 10 s |
| `external` | SMS, Anruf, Termin löschen, Notiz überschreiben | immer bestätigen |

Pro Tool überschreibbar. Bei TEE-Anfragen, deren Quittung fehlschlägt, werden `external`-Tools für den Rest der Sitzung gesperrt.

**Erweiterungswege** (vom einfachsten zum mächtigsten)

1. **HTTP-Tool (deklarativ)**: Nutzer definiert in der App Name, Beschreibung, JSON-Schema, Methode, URL-Vorlage, Header und Auth. Reicht für viele einfache APIs (Home Assistant, Webhooks, n8n).
2. **MCP-Server**: beliebige Remote-Server, Tools werden automatisch übernommen (eigener Abschnitt).
3. **Eingebaute Integration**: Dart-Klasse plus optional nativer Teil über Platform Channels; für alles, was Gerätezugriff braucht.

Alle drei Wege landen in derselben `ToolRegistry`; die Agent-Schleife unterscheidet sie nicht.

## Eingebaute Integrationen

Alle Integrationen sind einzeln aktivierbar; die Tabelle zeigt die geplanten Tools, die Umsetzung und die Phase. Risikostufen wie im Tool-System beschrieben (r = read, w = write, e = external).

| Integration | Tools (Auswahl) | Umsetzung Android / iOS | Phase |
| --- | --- | --- | --- |
| Kalender | `list_calendars` (r), `list_events` (r), `find_free_slots` (r), `create_event` (w), `update_event` (w), `delete_event` (e) | CalendarContract / EventKit; zeigt alle Systemkalender (also auch Business Calendar, Google, Exchange, CalDAV) | MVP |
| Obsidian | `search_notes` (r), `read_note` (r), `list_folder` (r), `create_note` (w), `append_to_note` (w, Ziel per Überschrift), `append_daily_note` (w), `replace_section` (e, mit Diff), `open_note` | SAF-Ordner mit persistenten Rechten / Security-Scoped Bookmark; lokaler Volltextindex (SQLite FTS5); `obsidian://`-Links; Sync bleibt bei Obsidian Sync, Syncthing oder Git | MVP |
| Zwischenablage | `read_clipboard` (r), `write_clipboard` (w) | Lesen nur, wenn die App im Vordergrund ist (Android 10+); iOS zeigt Einfüge-Hinweis | MVP |
| Gedächtnis | `memory_save` (w), `memory_search` (r), `memory_forget` (w) | SQLite mit FTS, später Embeddings; siehe unten | MVP |
| Wecker und Timer | `set_alarm` (w), `set_timer` (w), `list_alarms` (r, wo möglich) | `AlarmClock`-Intents / AlarmKit (iOS 26+), sonst Benachrichtigung | MVP |
| Erinnerungen | `remind_at` (w), `remind_when_arriving` (w, später), `list_reminders` (r) | Exakte lokale Benachrichtigung (`SCHEDULE_EXACT_ALARM`) / EventKit-Erinnerungen | v0.2 |
| Web | `web_search` (r), `web_fetch` (r) | Bei Claude die serverseitigen Tools; sonst Brave Search, Tavily oder eigenes SearXNG auf dem Homeserver | MVP |
| Bring! Einkaufsliste | `list_lists` (r), `get_items` (r), `add_items` (w, mit Mengenangabe), `remove_item` (w), `complete_item` (w) | Inoffizielle Bring!-API (wie in der Home-Assistant-Integration genutzt); Login mit Bring!-Konto; kann jederzeit brechen, daher eigenes Modul mit Fehleranzeige | v0.2 |
| Spotify | `search` (r), `play` (w: Playlist, Album, Titel, Künstler), `pause` / `next` / `previous` (w), `now_playing` (r), `queue_add` (w) | Web API mit OAuth/PKCE (Wiedergabesteuerung setzt Spotify Premium voraus); App Remote SDK bzw. iOS SDK, um die Spotify-App aufzuwecken, falls kein aktives Gerät | v0.3 |
| Wetter und Meer | `weather_forecast` (r), `marine_forecast` (r: Wellenhöhe, Dünung, Wassertemperatur) | Open-Meteo (Wetter- und Marine-API, ohne Key) | v0.3 |
| Kontakte | `find_contact` (r) | Contacts-Provider / Contacts-Framework | v0.3 |
| Nachrichten und Anrufe | `compose_sms` (e), `call` (e) | Intent mit vorausgefülltem Text bzw. Wählbildschirm; Nutzer sendet selbst | v0.3 |
| Standort und Navigation | `current_location` (r), `navigate_to` (w), `distance_to` (r) | Android `LocationManager` (kein Fused Location, K7) / CoreLocation; Geo-Intents bzw. Karten-URLs | v0.3 |
| Google Maps (K15) | `maps__navigate` (w), `maps__search_place` (r), `maps__route_info` (r: Dauer/Entfernung) | Adapter auf die Google-Maps-App per Intent (`google.navigation:`/Maps-URLs), nur wenn installiert (App-Erkennung, K7: keine Play-Services-Pflicht); optional Places/Routes-API mit eigenem Key des Nutzers; ohne Google Maps übernimmt `navigate_to` mit `geo:`-Intent (Organic Maps, OsmAnd) | nach M4, Phase offen |
| Taschenlampe (K16) | `flashlight__on` (w), `flashlight__off` (w), `flashlight__toggle` (w) | `CameraManager.setTorchMode` (ohne Kamera-Berechtigung, ohne Google-Dienste) / `AVCaptureDevice` Torch; Undo = Gegenschalten; ohne Bestätigung; auch auf dem Sperrbildschirm ohne Entsperren (K16) | M4 |
| Kamera und Bild | `take_photo` (r), `pick_image` (r) | Bild wird an Vision-fähige Modelle gegeben; nur wenn das gewählte Modell Vision kann | v0.4 |
| Apps und Links | `open_app` (w), `open_url` (w) | Intents / URL-Schemes; Liste erlaubter Apps einstellbar | v0.3 |
| Aufgaben | `add_task` (w), `list_tasks` (r), `complete_task` (w) | Erst als `Tasks.md` im Vault, später Todoist oder Google Tasks als eigene Integration | v0.4 |
| Listen (K6) | `lists__list_lists` (r), `lists__get_items` (r), `lists__add_items` (w, mehrere auf einmal), `lists__complete_item` (w), `lists__remove_item` (w), `lists__clear_completed` (e) | Vom Nutzer definierte Listen (Name + Ziel-Markdown-Datei, z. B. „Einkaufen“ → `Listen/Einkaufen.md`, „SmartSSH“ → `Projekte/SmartSSH.md`); Einträge als Markdown-Aufgaben `- [ ] …` / `- [x] …`; Dateizugriff über SAF mit persistenten Rechten (Datei oder Ordner, z. B. im Obsidian-Vault) bzw. Security-Scoped Bookmark; Listenname wird unscharf erkannt (Groß/Klein, Plural, Synonyme) | MVP |

**Gedächtnis im Detail**

- Einträge: `{ id, text, kategorie (person, vorliebe, fakt, projekt), quelle, erstellt, zuletzt_genutzt }`.
- Speichern nur auf ausdrücklichen Wunsch ("merk dir …") oder als Vorschlag am Ende eines Gesprächs, den der Nutzer bestätigt.
- Vor jeder Anfrage werden per Suche die 5 relevantesten Einträge in den System-Prompt gelegt; nicht der ganze Speicher.
- Ansicht in der App: alle Einträge lesen, bearbeiten, löschen; Export als Markdown, optional Spiegelung in eine Datei im Obsidian-Vault.
- Keine sensiblen Kategorien (Gesundheit, Finanzen, Zugangsdaten) automatisch speichern; Passwörter und Kartennummern werden gar nicht gespeichert.

**Kalender-Hinweis**: Neue Termine landen standardmäßig im vom Nutzer gewählten Standardkalender; Zeitzone ist die Gerätezeitzone, außer der Nutzer nennt eine andere.

## MCP-Integration

Die App enthält einen eigenen MCP-Client; jeder konfigurierte Server wird zu einer Integration, deren Tools in derselben Registry landen wie die eingebauten. Damit funktioniert MCP mit jedem LLM-Provider, nicht nur mit Claude.

**Client**

- Transport: Streamable HTTP (Standard), Legacy-SSE als Fallback. Kein stdio auf dem Handy; stdio-Server laufen auf dem Homeserver hinter einem stdio-zu-HTTP-Proxy.
- Auth: Bearer-Token, eigene Header oder OAuth 2.1 nach MCP-Spezifikation (Login-Dialog im In-App-Browser).
- Netzwerk: Server im Heimnetz über Tailscale oder WireGuard erreichbar; die App prüft Erreichbarkeit und zeigt den Status.
- Lebenszyklus: `initialize` beim Aktivieren, `tools/list` einmal laden und cachen, bei `notifications/tools/list_changed` neu laden; Verbindung bei Bedarf aufbauen, nicht dauerhaft halten (Akku).
- Später: `resources` und `prompts` des Protokolls; zunächst nur Tools.

**Abbildung auf das Tool-System**

- Name: `mcp_<server>__<tool>`, gekürzt falls nötig.
- Risikostufe aus den MCP-Tool-Annotationen: `readOnlyHint` → read, `destructiveHint` → external, sonst write. Pro Tool überschreibbar.
- Pro Server und pro Tool an- und abschaltbar; nur aktive Tools gehen ans Modell.
- Ergebnisse (Text, JSON, Bilder) werden ins interne `ToolResult` übersetzt; sehr lange Ergebnisse werden gekürzt und die Kürzung markiert.

**Alternative für Claude**: Bei öffentlich erreichbaren Servern kann der Anthropic-Adapter optional den Remote-MCP-Connector der API nutzen; dann ruft Anthropic den Server direkt auf. Standard bleibt der eigene Client, damit alle Provider gleich funktionieren.

**Empfohlene Server für den Start**

| Zweck | Server | Hinweis |
| --- | --- | --- |
| Obsidian auf dem Desktop | MCP-Endpunkt des Obsidian-Plugins Local REST API oder cyanheads/obsidian-mcp-server | Nur nötig, wenn der Vault nicht direkt auf dem Handy bearbeitet werden soll |
| Kalender per CalDAV | dav-mcp (HTTP, Bearer-Token) | Alternative zum Gerätekalender, z. B. für Kalender auf dem Homeserver |
| Smart Home | MCP-Server-Integration von Home Assistant | Licht, Szenen, Sensoren |
| Homeserver | eigener Server für Git, Docker-Status, Shell mit Whitelist | Shell-Tools immer `external` |

**Vorlagen**: In den Einstellungen gibt es Vorlagen für bekannte Server (Name, URL-Muster, Auth-Art) und einen Freitext-Eintrag für beliebige Server. Konfiguration ist exportierbar, damit sie auf ein zweites Gerät übertragen werden kann (ohne Secrets).

## Sicherheit, Datenschutz und Logging

Alle Secrets liegen im Android Keystore bzw. iOS Keychain, alle Verläufe nur lokal, und jeder Datenabfluss an einen Provider ist im Log nachvollziehbar.

**Secrets**

- API-Keys, OAuth-Tokens (Spotify, MCP, Provider) und Bring!-Zugangsdaten nur in `flutter_secure_storage`; nie in SQLite, Logs oder Exporten.
- Optional App-Sperre per Biometrie für Einstellungen und Verlauf.
- Keys werden nie ins APK gebaut; die App funktioniert ohne eigenen Backend-Server.

**Datenfluss**

- Audio verlässt das Gerät nie, außer der Nutzer wählt Cloud-STT oder Cloud-TTS aktiv.
- An den LLM-Provider gehen: Transkript, System-Prompt, ausgewählte Gedächtnis-Einträge, Tool-Specs und Tool-Ergebnisse. Die App zeigt pro Provider die Datenschutzstufe (`local`, `tee`, `eu`, `standard`).
- Integrationen können als "sensibel" markiert werden (z. B. Kontakte, Standort); ihre Tools werden nur an Provider ab Stufe `tee` geschickt, wenn der Nutzer das einstellt.
- Tool-Ergebnisse werden vor dem Senden gekürzt (z. B. Kalender: nur Titel, Zeit, Ort; keine Teilnehmerlisten, außer angefragt).

**Prompt-Injection**

- Inhalte aus Notizen, Webseiten, Einkaufslisten und MCP-Ergebnissen sind Daten, keine Anweisungen. Der System-Prompt sagt das ausdrücklich, und `external`-Tools brauchen immer eine Bestätigung, egal was in den Daten steht.
- MCP-Server und HTTP-Tools sind nur nach expliziter Einrichtung durch den Nutzer aktiv.

**Logging**

- Audit-Log (SQLite): Zeit, Auslöser, Transkript, Routing-Entscheidung, Provider und Modell, jeder Tool-Call mit Argumenten und Ergebnis-Status, Bestätigungen, Eskalationen, Kosten, TEE-Prüfergebnis.
- Aufbewahrung einstellbar (Standard 30 Tage), komplett löschbar, Export als JSON.
- Debug-Log getrennt davon, standardmäßig aus; enthält nie Secrets.

**Berechtigungen**: Jede Android- bzw. iOS-Berechtigung wird erst angefragt, wenn die zugehörige Integration aktiviert wird, mit einer kurzen Erklärung davor.

## UI/UX und Einstellungen

Die App ist in erster Linie ein Sprach-Overlay; der Hauptbildschirm zeigt Verlauf und Status, die Einstellungen sind der eigentliche Konfigurationskern.

**Oberflächen**

- **Assistenten-Overlay** (halber Bildschirm über anderen Apps, ausgelöst durch Wake Word oder Assistenten-Geste): Wellenform während der Aufnahme, Live-Transkript, Antwort, Tool-Karten ("Termin angelegt – Rückgängig"), Bestätigungskarten, kleines Symbol für Provider und Prüfstatus.
- **Hauptbildschirm**: Gesprächsverlauf, Texteingabe als Alternative zur Sprache, Mikrofon-Button, aktiver Provider.
- **Onboarding**: Sprache, erster Provider (Key einfügen, testen), Whisper-Modell herunterladen, Integrationen auswählen, optional Standard-Assistent setzen.
- **Widget und Schnellkachel** (Android), Control und Action-Button-Unterstützung (iOS).

**Stationsmodus** (M6, K62/K63): Das Handy liegt am Ladegerät und arbeitet wie ein Lautsprecher mit Display.

- **Start nur manuell:** Button auf dem Hauptbildschirm, Schnellkachel oder Sprachbefehl „Stationsmodus“ (bei entsperrtem Gerät). Kein automatischer Start beim Laden.
- **Ende:** Button „Beenden“, der das Entsperren verlangt. Danach bleibt das Gerät gesperrt. Abstecken oder ein Sprachbefehl beenden den Modus nicht.
- **Anzeige im Ruhezustand:**
  - Uhr, Datum und Wetter (WP87)
  - laufende Wiedergabe mit großen Knöpfen (Spotify WP84, Medien WP90)
  - nächste Termine und fällige Aufgaben (WP88), **mit Titeln**
  - Smart-Home-Kacheln für selbst gewählte Entitäten (WP91)
  - Einzelne Bereiche lassen sich ausblenden.
- **Gespräch:** Während eines Gesprächs zeigt die Station Transkript und Antwort groß, statt das Overlay zu öffnen. Wake Word ist Pflicht.
- **Sperre:** Das Gerät bleibt gesperrt, die Station läuft über dem Sperrbildschirm.
  - Sprachbefehle folgen der Freigabeliste aus K54, erkannte Sprecher (WP92) bekommen ihre Rechte.
  - Kacheln und Wiedergabe-Knöpfe sind ohne Entsperren antippbar, im selben Umfang wie die Sprache.
  - Schlösser, Alarm, Cover und Schalter mit „immer bestätigen“ erscheinen nicht als antippbare Kachel.
  - Termine und Aufgaben auf dem Display und in der Wecker-Ansage zeigt die Station bewusst mit Titeln.
  - Vorlesen auf Anfrage („was steht heute an?“) bleibt nach K54 gesperrt.
- **Bildschirm, auswählbar:**
  - „immer an, gedimmt“ (Standard): Helligkeit nach Umgebungslicht, Inhalt wandert leicht gegen Einbrennen
  - „aus, an bei Wake Word oder Berührung“
  - „tagsüber an, in den Ruhezeiten aus“
- **Ruhezeiten** (einstellbar, Standard 22–7 Uhr): leiser antworten, Display fast schwarz, kein Bestätigungston.
- **Ton:** Antworten und Musik laufen über einen gekoppelten Bluetooth-Lautsprecher, wenn er verbunden ist.
- **Gesprächsmodus:** Er bleibt länger offen als sonst (Standard 15 s statt 5 s).
- **Wecker mit Ansage:** Klingelt ein Wecker, während die Station läuft, sagt Wendelin danach Wetter, Termine und fällige Aufgaben des Tages an.

**Einstellungen**

| Bereich | Inhalt |
| --- | --- |
| Provider | Profile anlegen, bearbeiten, testen; Standardmodell; Budget; Datenschutzstufe; TEE-Prüfung an/aus |
| Routing | Default-Provider, Regelliste mit Editor und Testfeld, Eskalationsketten |
| Integrationen | Liste aller Integrationen mit Zustand (nicht verfügbar, verfügbar, Einrichtung nötig, aktiv, Fehler); Schalter; Einrichtungsassistent pro Integration; einzelne Tools an/aus; Risikostufen |
| MCP-Server | Server hinzufügen (Vorlage oder frei), Auth, Status, Tool-Liste |
| HTTP-Tools | eigene Tools definieren und testen |
| Sprache | Wake Word an/aus, Wort, Empfindlichkeit, aktive Zeiten; STT-Engine und Modell; Sprache; TTS-Stimme und Tempo; Gesprächsmodus |
| Assistent | Standard-Assistent setzen (Link zu den Systemeinstellungen), Name des Assistenten, Persönlichkeit / System-Prompt-Zusatz |
| Gedächtnis | Einträge ansehen, bearbeiten, löschen; automatische Vorschläge an/aus; Spiegelung in Obsidian |
| Datenschutz und Logs | Aufbewahrung, Prüfprotokoll, Audit-Log, Export, alles löschen |
| Kosten | Verbrauch pro Provider und Monat |

**Integrationen auswählen** (Wunsch aus dem Gespräch): Beim Onboarding und in den Einstellungen sieht der Nutzer nur Integrationen, die auf seiner Plattform möglich sind. Solche, deren App fehlt, erscheinen ausgegraut mit Hinweis "App nicht installiert". Erst nach dem Aktivieren werden Berechtigungen angefragt bzw. Logins durchgeführt. Deaktivierte Integrationen kosten keine Tokens, weil ihre Tools nicht ans Modell gehen.

**Barrierefreiheit und Sprache**: UI auf Deutsch, Französisch und Englisch (Flutter-Lokalisierung); große Touch-Ziele im Overlay; alles auch ohne Sprache per Text bedienbar.

## Umsetzung: Struktur, Roadmap, Tests

Umgesetzt wird in sechs Meilensteinen, Android zuerst; jeder Meilenstein endet mit einer benutzbaren App.

**Projektstruktur** (geändert, siehe Änderungsprotokoll K1)

```
wendelin/
  packages/                    # reine Dart-Pakete, einzeln testbar (ADR 0001)
    wendelin_core/             # Nachrichtenformat, Interfaces (LlmProvider, Tool, Integration, AgentRun), Events, Fakes
    wendelin_providers/        # anthropic/, openai/, Modellkatalog, Kosten (später tee/)
    wendelin_tools/            # ToolRegistry, ToolExecutor, Risiko, Undo (später http_tool/, mcp/)
    wendelin_agent/            # Agent-Schleife, Kontext, Limits, Eskalation (später Routing-Regeln)
    wendelin_storage/          # drift-Datenbank, Repositories, SecretStore-Interface, Audit-Log
    wendelin_integrations/     # calendar/, clipboard/, alarms/, memory/, web/ … über Ports
  app/                         # Flutter-App: UI, Riverpod-Verdrahtung, Plattform-Ports
    android/  ios/             # native Teile
  native/attest/               # Rust-Crate: DCAP-Quote, Signaturen (flutter_rust_bridge)
  evals/                       # Testsätze und Auswertung pro Provider-Profil
  docs/                        # Design, ADRs, Arbeitspakete, Notizen
```

**Meilensteine** (Umsetzungsstand: `docs/work-packages/STATUS.md`; Stand 2026-10-18: M0–M4 erledigt, M5 in Arbeit, M6/M7 geplant)

1. **M0 Gerüst**: Flutter-Projekt, Riverpod, drift, Secure Storage, Kern-Interfaces (`LlmProvider`, `Integration`, `Tool`, `AgentRun`) mit Fake-Implementierungen; Text-Chat-UI. *Fertig, wenn* ein Fake-Provider einen Fake-Tool-Call auslöst und das Ergebnis angezeigt wird.
2. **M1 Text-Agent (Android)**: Anthropic- und OpenAI-kompatibler Adapter, Provider-Einrichtung mit Test, Agent-Schleife mit Bestätigungen, Integrationen Kalender, Zwischenablage, Wecker/Timer, Gedächtnis, Web-Suche; Audit-Log. *Fertig, wenn* "Trag mir morgen um 10 Tauchen ein" per Text mit Claude Haiku und einem OpenAI-kompatiblen Modell funktioniert.
3. **M2 Sprache und Assistent**: Push-to-talk, Silero VAD, Whisper über sherpa-onnx (Modell-Download), System-TTS, Overlay, Standard-Assistent über `VoiceInteractionService`, Obsidian-Integration. *Fertig, wenn* der lange Druck auf die Power-Taste die App öffnet und ein gesprochener Befehl eine Notiz im Vault ergänzt.
4. **M3 Routing, MCP, Erweiterung**: Regeln und Eskalation mit Editor, MCP-Client (Streamable HTTP, Bearer, OAuth), HTTP-Tools, Bring!, Integrationsauswahl mit App-Erkennung. *Fertig, wenn* "Claude, …" zu Claude routet und ein MCP-Server auf dem Homeserver über Tailscale Tools liefert.
5. **M4 Wake Word und TEE**: Wake Word im Foreground Service, Gesprächsmodus; `AttestedProvider` mit Phala, Rust-Prüfmodul, Prüfprotokoll-UI. *Fertig, wenn* das Wake Word bei ausgeschaltetem Bildschirm auslöst und jede Phala-Antwort einen grünen oder roten Prüfstatus hat.
6. **M5 Ausbau (Android)**: App-Sprache, Spotify, Wetter/Meer (wählbarer Dienst), Mediensteuerung, Kontakte/SMS/Anrufe mit Vorschau, Standort/Google Maps, Aufgaben (Listen mit Fälligkeit), Todoist/Google Tasks, Home Assistant, Sprechererkennung, Wake Word im Chat, Schnellwechsel des Agenten (Plan: `docs/work-packages/M5-PLAN.md`).
7. **M6 Ausbau 2 (Android)**: Kamera/Bild, Stationsmodus, Vergleich alternativer Wake Words, Empfehlung von Modellen (Evals live).
8. **M7 iOS**: iOS-Build mit App Intents, Action Button, AlarmKit, EventKit, Bookmarks.

**Teststrategie**

- Unit-Tests für Adapter mit aufgezeichneten Antworten (Streaming, Tool-Calls, Fehler) je Provider.
- Agent-Schleife mit Fake-Provider: Limits, Abbruch, Bestätigungen, Eskalation ohne doppelte Tool-Ausführung.
- Routing: Tabellentests "Satz → erwartete Regel".
- **Modell-Eval**: 30–50 typische Befehle (Deutsch, Französisch, Englisch) mit erwarteten Tool-Calls; Kommando, das ein Provider-Profil dagegen laufen lässt und Trefferquote, Latenz und Kosten ausgibt. Grundlage für die Wahl des Default-Modells.
- STT: kurze eigene Aufnahmen als Fixtures, Wortfehlerrate pro Modellgröße.
- Integrationstests auf Emulator bzw. Gerät für Kalender, SAF und Intents – auf einem AOSP-Image **ohne** Google Play Services (K7).

**Offene Fragen**

- Ist mit "Jiggler" Flutter gemeint? Falls Kotlin Multiplatform, Abschnitt Plattform anpassen.
- Phala: TLS terminiert in der Enklave, GPU-Attestierung ist enthalten (geklärt, K2). Offen: Ableitung von `report_data` aus der Nonce beim Gateway-Endpunkt, Erzwingen von `required: true`, Performance der DCAP-Prüfung auf dem Handy.
- Bring!: Inoffizielle API, Nutzungsbedingungen prüfen; Fallback über Share-Intent in die Bring!-App.
- Spotify: Entwickler-App im Entwicklungsmodus reicht für den Eigengebrauch; für eine Veröffentlichung Freigabe nötig.
- Verteilung: nur privat (APK, TestFlight) oder Play Store / App Store? Betrifft Wake-Word-Dauerbetrieb und Review.
- Name und Wake Word der App.

**Hinweise für den Coding-Agenten**

- Interfaces zuerst, dann Implementierungen; keine Provider- oder SDK-Typen außerhalb der Adapter.
- Jede Integration in einem eigenen Ordner mit kurzer README (Tools, Berechtigungen, Plattformen).
- Native Teile minimal halten und über klar typisierte Platform Channels (z. B. Pigeon) anbinden.
- Keine Secrets im Repo; Beispielkonfiguration mit Platzhaltern.
- Architekturentscheidungen als kurze ADRs in `docs/` festhalten.
- Pro Meilenstein: Tests grün, Definition of Done erfüllt, kurze Demo-Anleitung im README.


## Änderungsprotokoll

Abweichungen, die sich bei der Umsetzung ergeben haben. Status `offen` = noch nicht vom Maintainer bestätigt.

| Nr. | Datum | Abschnitt | Änderung | Grund | Status |
| --- | --- | --- | --- | --- | --- |
| K1 | 2026-10-12 | Umsetzung → Projektstruktur | Kernlogik in eigenen reinen Dart-Paketen unter `packages/` statt in `app/lib/`; App nur UI, Verdrahtung, Plattform | Einzeln testbare Module, erzwingbare Abhängigkeitsregeln (ADR 0001) | bestätigt 2026-10-13 |
| K2 | 2026-10-13 | TEE-Provider → Ablauf Phala, Hinweise, Offene Fragen | Echte Endpunkte und Felder eingetragen; kein `workload_id`/`freshness.stale_after` → Pinning auf Keyset-Digest + Commit, Frische über `not_after`; TLS terminiert in der Enklave (Pinning möglich); GPU-Attestierung vorhanden; `required: false` beobachtet | Live-Probe, siehe `docs/notes/phala-aci-probe-2026-10-13.md` | bestätigt 2026-10-13 |
| K3 | 2026-10-13 | LLM-Provider-Schicht → Internes Format; Agent-Schleife → Schnittstelle | `ChatEvent` um `ThinkingDelta`/`ThinkingComplete` (signierte Thinking-Blöcke müssen unverändert zurück an Anthropic), `StopReason.pauseTurn`; `AgentEvent` um `EscalationConfirmationRequired` (Nutzerbestätigung bei Eskalation unter die Datenschutzstufe) | Review WP01 (ADR 0002) | bestätigt 2026-10-13 |
| K4 | 2026-10-13 | Tool-System → Schnittstellen | `Integration` ohne Flutter-Typen (`iconId` statt `IconData`, Einstellungsseite über `id` in der App, plus `sensitive`); `Tool.execute` liefert `ToolOutcome` (Inhalt, Fehler, optionales Undo, Kurztext für die Tool-Karte) | Kernpakete ohne Flutter testbar; Undo-Option für `write`-Tools braucht einen Rückweg (ADR 0002) | bestätigt 2026-10-13 |
| K5 | 2026-10-13 | LLM-Provider-Schicht, Agent-Schleife, Tool-System | Vertragsdetails präzisiert: System-Prompt als eigenes Feld in `ChatRequest`; `Usage` mit 4 Zählern (inkl. Cache-Schreiben), Usage-Events als Zuwachs; Stream endet mit genau einem `Done` oder `Error`, Abbruch als Fehler-Event; `ProviderProfile` mit Budget in Mikro-USD, Warnschwelle 0–1 und adapterspezifischen `options` (z. B. serverseitige Web-Suche, Thinking-Budget); `HealthCheck.detected` (geprüfte Fähigkeiten); Abbruchvertrag der Tool-Ausführung (offene Bestätigungen gelten als abgelehnt, nach Abbruch startet kein Tool mehr, fertige Tools behalten ihr Ergebnis, Bestätigungen immer nacheinander); `UserInput.requestEscalation` für „nochmal mit …“ | Review WP01 (ADR 0002) | bestätigt 2026-10-13 |
| K6 | 2026-10-13 | Eingebaute Integrationen | Neue Integration **Listen**: beliebig viele benannte Listen, jede mit eigener Ziel-Markdown-Datei auf dem Gerät; Tools zum Anzeigen, Hinzufügen, Abhaken, Entfernen; Einträge als Markdown-Checkboxen, damit die Dateien in Obsidian direkt nutzbar sind. Phase MVP (M1), Dateizugriff per Android-Dateiauswahl (SAF) | Wunsch Maintainer; Ergänzungen aus WP12: optionaler Abschnitt je Liste (wird angelegt), Aliase + Wortstamm-Ähnlichkeit statt Synonymliste, Rückfrage bei unsicheren Treffern für Schreib-Tools (Abhaken nimmt eindeutige Treffer), „Erledigte löschen“ behält Einträge mit offenen Unteraufgaben | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K7 | 2026-10-13 | Leitprinzipien, Sprach-Pipeline, Integrationen, Teststrategie | App läuft ohne Google Play Services: Standort über `LocationManager` statt Fused Location; TTS-Ausweichlösung sherpa-onnx, wenn keine System-Sprachausgabe installiert ist; System-Spracherkennung nur, wenn vorhanden (Whisper lokal bleibt Standard); Wecker über AOSP-Intents mit Benachrichtigungs-Fallback; E2E-Tests auf AOSP-Image ohne GMS | Wunsch Maintainer (entgoogelte Geräte) | bestätigt 2026-10-13 |
| K8 | 2026-10-13 | Agent-Schleife, Routing/Eskalation, Tool-System, Integrationen, Provider | (a) Tool-Namen der eingebauten Integrationen einheitlich `integration__aktion` (z. B. `memory__save`, `clipboard__read`, `web__search`); Meta-Tool heißt `tools__search`, greift ab 30 aktiven Tools (nach Datenschutzfilter), Freischaltung je Sitzung, aktive Tools bleiben direkt aufrufbar. (b) Risikostufen pro Tool lassen sich nur verschärfen, nie lockern. (c) Token-Budget je Anfrage: Summe über alle Modellaufrufe, Standard 50 000, Cache-Lesen zählt nicht. (d) Eskalation nur bei wiederholbaren Fehlern (nach 1 Retry); Datenschutz-Untergrenze ist die Stufe der ursprünglich gewählten (privaten) Route und bleibt über alle Eskalationen gleich; ein „Nein“ zur Eskalation unter diese Stufe gilt für die ganze Anfrage. (e) System-Prompt: stabiler Teil (Rolle, Regeln, Tools) zuerst, Datum/Uhrzeit/Gedächtnis danach (Prompt Caching); der Übergabe-Hinweis nach Eskalation nennt nur Tool-Namen und Status, keine Argumente (Prompt-Injection). (f) Anbieterspezifische Blöcke (z. B. Claudes serverseitige Web-Suche) als `ProviderBlock`: nur an denselben Anbieter zurück, nie vorgelesen; Suchergebnisse landen nicht im Antworttext. (g) Phala-Standardmodell: Bei `glm-5.3-flash` lässt sich Reasoning auf RedPill nicht sauber abschalten; Default wird per Modell-Eval gewählt, `qwen-2.5-7b-instruct` (TEE) funktioniert inkl. Tool-Calls. (h) Kalender: Serientermine werden nicht teilweise geändert (Zeitänderung an einer Serie wird abgelehnt mit Hinweis auf die Kalender-App), Löschen betrifft die ganze Serie und wird so angezeigt. (i) Gedächtnis: Gesundheit/Finanzen werden nicht inhaltlich erkannt; geschützt wird über Kategorien und „nur auf ausdrücklichen Wunsch“; Passwörter/PINs, Karten- und IBAN-Nummern werden abgewiesen. | Umsetzung Welle 2 (WP02–WP07) | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K9 | 2026-10-13 | UI/UX, Einstellungen | (a) Kosten werden in USD angezeigt (Preise liegen in USD vor, keine Umrechnung). (b) Rückfrage vor Eskalation unter die Datenschutzstufe nutzt die gelbe Bestätigungskarte (kein eigener Entwurf). (c) Bis M2 im Bestätigungs-Sheet „Antworte per Tipp“ statt Sprachhinweis. (d) „Alles löschen“ entfernt Verläufe und Prüfprotokoll; Gedächtnis, Einstellungen und Kostendaten bleiben; Aufbewahrungsfrist gilt auch für Verläufe. (e) Kein OAuth/PKCE-Login in M1 (vorbereitet). (f) Sprachwahl im Onboarding wird gespeichert, Oberfläche bleibt Deutsch bis zur Lokalisierung. (g) „sensibel“ ist je Integration vom Nutzer umschaltbar (Standard aus der Integration). | Umsetzung WP08/WP09 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K10 | 2026-10-13 | Sicherheit/Datenfluss, Routing/Eskalation, Tool-System | (a) Tool-Katalog richtet sich nach der Datenschutzstufe des jeweiligen Ziels (auch nach Eskalation); Calls auf nicht sichtbare Tools werden abgelehnt und protokolliert; Tool-Suche zeigt nur Tools der Stufe. (b) Für Ziele, die ein Tool nicht sehen dürfen, wird nach dessen Ergebnis bis zur nächsten Nutzernachricht alles ausgeblendet (Text, Thinking, Provider-Blöcke, weitere Tool-Aufrufe samt Argumenten/Ergebnissen). (c) Enthält eine laufende Anfrage solche geschützten Ergebnisse, fragt die App vor jeder Eskalation auf ein Ziel ohne diese Tools nach, auch ohne private Route; „Nein“ beendet die Anfrage. (d) Gedächtnis-Einträge im System-Prompt nur, wenn alle Ziele der Kette die Gedächtnis-Integration sehen dürfen. (e) Restrisiko: Was der Nutzer selbst schreibt/kopiert, wird nicht ausgeblendet. (f) Bestätigungskarte zeigt die effektive Risikostufe; Bestätigungstexte dürfen live nachschlagen (Kalender). (g) Optionale Einrichtungsschritte: Web ohne Suchdienst bietet nur `web__fetch`. | Umsetzung/Review WP14 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K11 | 2026-10-13 | Sprach-Pipeline, Auslöser, Overlay, Sicherheit | (a) Whisper wird als int8-Variante geladen (base ≈ 160 MB, small ≈ 375 MB); Vorschlag: Standard **small mit fester Sprache** (WER Deutsch 9 % statt 30 % bei base, Emulator 0,54 s/Satz) – endgültig nach Messung auf dem Gerät. (b) Erkennungssprache standardmäßig fest „wie die App“ statt automatisch (automatische Erkennung macht aus „Ja“/„Oui“ oft andere Sprachen); automatisch bleibt wählbar. (c) Endpointing: Mindestsprechdauer 200 ms, kurze Geräusche werden verworfen; nach 8 s ohne Sprache „nichts verstanden“. (d) „Stopp“ bricht nur ab, wenn die Äußerung ausschließlich aus Stopp-/Füllwörtern bzw. Stopp-Phrasen besteht („Stopp bitte“, „Hör auf!“); während der Sprachausgabe wirkt bis zum Barge-in (v0.4) nur Antippen. (e) Sprachausgabe nur mit Offline-Stimmen (Netzstimmen ausgeblendet); ohne Offline-Systemstimme automatisch sherpa-Stimme; englische Stimme LJSpeech (gemeinfrei) statt Amy, SIWIS (fr) mit Attribution. (f) Overlay ist eine eigene transparente Activity (nicht das Session-Fenster); bei gesperrtem Gerät zuerst Entsperren, vorher keine Inhalte und keine Sprache; Overlay mit Bildschirmschutz (FLAG_SECURE), Haupt-App per Einstellung. (g) Bestätigung per Stimme nur bei Sprach-Anfragen; für `external`-Tools und Eskalationen nur eindeutiges „Ja“ (1–2 Ja-Wörter), sonst Tippen. (h) Als Standard-Assistent bietet Wendelin eine lokale System-Spracherkennung (Whisper) für andere Apps an (abschaltbar, nur mit Assistenten-Rolle aktiv). (i) Release-APK ≈ 28 MB größer (onnxruntime); Modelle werden nach der Installation geladen. | Umsetzung M2 (WP15–WP20) | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: (a) bestätigt 2026-10-13: Standard small, base wählbar; Rest offen) |
| K12 | 2026-10-13 | Routing/Eskalation, Tool-System (MCP, HTTP-Tools), Integrationen | (a) Eskalationskette pro Routing-Profil statt global; die bisherige Kette wird die des Default-Profils. (b) `needsTool` erkennt Tool-Bedarf über Schlüsselwortlisten je Kategorie (ohne Modellaufruf); `stripTrigger` bereinigt nur den Text an das Modell, der Verlauf bleibt original. (c) MCP- und HTTP-Tools ohne Undo; Risiko-Hinweise des MCP-Servers gelten nur als Hinweis und lassen sich nur verschärfen; zusätzlich Schalter „alle Tools bestätigen“. (d) Nach einem geschützten (sensiblen) Ergebnis brauchen weitere Aufrufe an MCP-/HTTP-Ziele in derselben Anfrage eine Bestätigung (Argumente könnten sensible Daten an Dritte tragen). (e) Klartext-`http` nur zu Heimnetz-/Tailscale-Zielen (private Bereiche, `100.64.0.0/10`, `*.ts.net`), sonst nur `https`; HTTP-Tools nur zum gespeicherten Host (SSRF/DNS-Rebinding). (f) Bilder aus MCP-Ergebnissen gehen in M3 nur als Hinweistext an das Modell. (g) MCP-Client als eigenes Paket `wendelin_mcp`; SSE-Parser wandert nach `wendelin_core`; MCP nur über Streamable HTTP (Legacy-SSE als Fallback), kein stdio auf dem Telefon. (h) Store-Links auf F-Droid oder Herstellerseite statt Play Store (K7). | Planung M3 (WP21–WP29) | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K13 | 2026-10-13 | Routing/Eskalation, Datenschutz, Tool-System (MCP, HTTP), Bring!, Integrationen | **Routing (WP21):** (a) Privacy-Bedingungen gelten unabhängig von der Regelreihenfolge und fail-closed: Ist kein ausreichend geschütztes Ziel verfügbar, wird nichts gesendet. (b) „nochmal mit X“ zählt nur am Satzanfang (höchstens 4 Füllwörter davor, 2 Wörter danach), übernimmt die Untergrenze des vorigen Zugs; „nochmal mit <aktuelles Ziel>“ wiederholt beim selben Ziel. (c) Nachrichten speichern ihre Datenschutz-Untergrenze; private Gesprächsteile werden für schwächere Ziele durch „[privater Gesprächsteil ausgeblendet]“ ersetzt. (d) Taint-Propagation: Ein Lauf, der private Inhalte sieht, wird selbst privat (Antworten, Gedächtnis-Einträge, Eskalationen) – dadurch bleibt eine Unterhaltung nach einer privaten Anfrage bis Sitzungsende privat (Anzeige + „Neue Unterhaltung“ in WP26). (e) Gedächtnis-Einträge privater Läufe erscheinen nur für Ziele ab ihrer Stufe. (f) Restrisiko: Was ein privater Lauf in Notizen/Listen/Kalender schreibt, trägt keine Untergrenze (Schutz nur über Tool-Katalog je Stufe, K10). (g) Regex-Bedingungen ohne Rückverweise/verschachtelte Wiederholungen, max. 2 offene Wiederholungen, Suche in den ersten 300 Zeichen. (h) `timeWindow` zählt den Wochentag des Fensterbeginns; getaktetes Netz gilt als online. **MCP (WP22):** (i) Tools ohne Annotation gelten als `external` (MCP-Standard: destruktiv); `write` nur bei ausdrücklichem `destructiveHint: false`; `readOnlyHint` eines selbst eingerichteten Servers genügt für `read` (Restrisiko lügender Server). (j) `write` ohne Undo (MCP und HTTP-Tools) wird standardmäßig bestätigt; „ohne Nachfrage“ je Tool nur per ausdrücklichem Schalter. (k) Grenzen gegen bösartige Server: 1 MB je Antwort, Schema ≤ 8 KB je Tool, ≤ 128 Tools je Server; kein `notifications/cancelled`, keine SSE-Wiederaufnahme. **HTTP-Tools (WP23):** (l) Zwei Integrationen `http`/`http_sensitive` mit gemeinsamem Präfix `http__`; Risiko = Maximum aus Nutzerwahl und Methoden-Vorschlag; Klartext-`http` nur, wenn alle aufgelösten Adressen privat sind; geheim wirkende Klartext-Header werden abgelehnt; Zeitlimit 1–120 s (Standard 15 s). **Bring! (WP24):** (m) Nur dauerhafte Fehler (Login abgelehnt, unpassendes Format) pausieren die Integration; Offline/5xx/429 ergeben nur einen Tool-Fehler. Teilerfolg bietet Undo für den eingetragenen Teil. Fester öffentlicher Client-Key `X-BRING-API-KEY` im Code. **App-Erkennung (WP25):** (n) Fehlt eine Pflicht-App, wird die Integration „nicht verfügbar · pausiert“, der Schalter bleibt gespeichert; Store-Links auf F-Droid/Hersteller; nur `<queries>` + PackageManager (keine generische Intent-Auflösung); kollidierende Tool-Namen eigener Integrationen werden abgewiesen. | Umsetzung/Reviews M3 Welle A (WP21–WP25) | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K14 | 2026-10-13 | Sprach-Pipeline, Overlay, UI/UX, Integrationen | **Nachbesserungen aus dem Gerätetest (WP30–WP33):** (a) Whisper `small` ist Standard, `base` wählbar; fehlt das gewählte Modell, nimmt die Erkennung ein installiertes. (b) Pro Prozess läuft höchstens ein Whisper; Vorwärmen nur, wenn Sprache in den letzten 24 h genutzt wurde; nach 2 min im Hintergrund wird das Modell freigegeben. (c) **Speicherziel:** höchstens ca. 1,1 GB bei aktiver Sprachnutzung, unter 200 MB im Hintergrund (onnxruntime-Arena lässt sich in sherpa-onnx nicht abschalten). (d) Lokale, zurückhaltende Vokabular-Korrektur nach der Erkennung und lautähnlicher Abgleich von Notiznamen. (e) „Rückgängig“ stoppt auch die laufende Sprachausgabe; „Neues Gespräch“ beendet die private Fortsetzung (K13 d). (f) Die angebotene System-Spracherkennung folgt der Assistentenrolle nur, wo Android `voice_recognition_service` mit umstellt. (g) Berechtigung `ACCESS_NETWORK_STATE` für Netzbedingungen im Routing. (h) Gesprächsmodus (fortlaufendes Zuhören) wird auf M4 verschoben. | Gerätetest M2 (Xiaomi), Umsetzung WP30–WP33 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: (a), (c), (h) bestätigt 2026-10-13; Rest offen) |
| K15 | 2026-10-13 | Eingebaute Integrationen | Neue Integration **Google Maps** als Adapter: Navigation, Ortssuche und Routeninfo über die Google-Maps-App (Intent) bzw. optional die Maps-API mit eigenem Key; nur aktiv, wenn die App installiert bzw. ein Key hinterlegt ist, damit K7 (ohne Google-Dienste lauffähig) erhalten bleibt. Zeitpunkt noch offen (nach M4). | Wunsch Maintainer | bestätigt 2026-10-13 (Aufnahme), Umfang offen |
| K16 | 2026-10-13 | Eingebaute Integrationen | Neue Integration **Taschenlampe**: an, aus, umschalten per Sprache oder Text; Risiko `write` mit Undo, ohne Nachfrage; Android über `CameraManager.setTorchMode`, kein Netz, alle Datenschutzstufen. Phase M4 (passt zum freihändigen Sprechen). Einzige Ausnahme zu K11 (f): Die Taschenlampen-Tools funktionieren auch bei gesperrtem Gerät ohne Entsperren; Wendelin zeigt dabei keine Inhalte und führt sonst nichts aus. | Wunsch Maintainer | bestätigt 2026-10-13 |
| K17 | 2026-10-13 | Sprach-Pipeline (Notizsuche, Vokabular) | Die gemeinsame Textfaltung (WP36 c) faltet `ý` zu `y` jetzt auch in der lautähnlichen Notizsuche und der Vokabular-Korrektur (vorher nur im Routing); `ÿ` wurde dort schon gefaltet. Listen- und Obsidian-Abgleich bleiben unverändert. | Aufräumpaket WP36 c, Review | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K18 | 2026-10-13 | UI/UX, Sprach-Pipeline, Einstellungen | **Sprach-Bedienung (WP31), Abweichungen vom Design:** (a) Zuhör-Leiste über der Eingabezeile. (b) Mikrofon-Zustände „Moment …“ (Vorbereiten) und „spricht“ (bewegte Punkte, mit Animationen abschaltbar). (c) Knopf „Neues Gespräch“ im Kopf des Hauptbildschirms, sichtbar nur bei nicht leerem Verlauf; app-weit heißt es „Neues Gespräch“ statt „Neue Unterhaltung“; auch per Sprache („Neues Thema“, „Vergiss das“, „New topic“), wird vor dem Routing abgefangen und nie ans Modell gesendet. (d) Solange Text im Eingabefeld steht, ersetzt ein Senden-Knopf das Mikrofon. (e) Neue Einstellung „Stopp schließt das Overlay“ (Standard an). (f) Zurückgenommene Ergebniskarten werden durchgestrichen und gedämpft dargestellt. | Gerätetest M2, Umsetzung WP31 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K19 | 2026-10-13 | Sprach-Pipeline (TTS), Agent-Schleife | **Vorlesefreundliche Antworten:** Bei Sprach-Anfragen soll die Antwort so formuliert sein, dass sie vorgelesen natürlich klingt (keine Doppelpunkt-Aufzählungen, Überschriften, Tabellen; Uhrzeiten/Zahlen sprechbar). Stufe 1 (Standard): Stil-Hinweis im dynamischen Prompt-Teil nur bei Sprach-Anfragen. Stufe 2 (Einstellung): Modell liefert zusätzlich einen Sprechtext `<spoken>…</spoken>` vor der geschriebenen Antwort; angezeigt wird die geschriebene, vorgelesen der Sprechtext; Rückfall auf Stufe 1. Stufe 0: lokale Aufbereitung in `SpokenAnswer` als Netz. Umsetzung WP41. | Wunsch Maintainer | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: Wunsch bestätigt 2026-10-13; Stufen-Aufteilung offen) |
| K20 | 2026-10-14 | Sprach-Pipeline, Agent-Schleife, Tool-System, Sicherheit | **Umsetzung K19 (WP41):** (a) Neues Ereignis `AgentSpokenText` (Sprechtext getrennt vom Anzeigetext), `AgentConfig.spokenVersions`, Einstellung `VoiceSettings.twoVersions` („Antwort in zwei Fassungen“, Standard aus). (b) Lokale Aufbereitung: Doppelpunkt vor Großbuchstabe/Zahl → Punkt, sonst Komma; Uhrzeiten nur nach Zeit-Einleitungen (um/ab/bis/von/…; at/from/until/…; à/de/vers/…), mit „Uhr“/„h“ oder mit führender Null umgeformt; englische Zeiten im 12-Stunden-Format mit a.m./p.m., vorhandene Angaben bleiben. (c) **Sicherheitsregel (fail-closed):** Tools tragen den Marker `TrustedContentSource` nur, wenn ihr Ergebnis ausschließlich eigene Daten enthält (Wecker, Timer, Termin anlegen – nur Kalender-ID –, Listen-Eintrag hinzufügen, Gedächtnis speichern/vergessen, Zwischenablage schreiben). Hat die Unterhaltung (auch frühere Züge) ein anderes Tool-Ergebnis, einen Fehlertext oder einen Provider-Block (z. B. serverseitige Websuche) gesehen, wird der unsichtbare Sprechtext verworfen und aus der sichtbaren Antwort vorgelesen; ein Registry-Test erzwingt die Einstufung jedes neuen Tools. (d) Restrisiko: eingeschleuster Text im Gedächtnis aus früheren Läufen. | Umsetzung/Reviews WP41 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K21 | 2026-10-14 | Sprach-Pipeline, Einstellungen, Sicherheit | Eine Einstellung „Sprechfassung“ mit vier Stufen statt Schalter: **Aus** (Standard), **Immer** (Sprechtext auch nach fremden Inhalten), **Geschützt** (nach fremden Inhalten sichtbare Antwort vorlesen, K20 c), **Mit KI-Prüfung** (nach fremden Inhalten prüft ein frischer Aufruf an dasselbe Modell ohne Kontext, ob Sprechtext und geschriebene Antwort inhaltlich übereinstimmen; nur dann wird der Sprechtext vorgelesen, fail-closed). Umsetzung WP55. | Wunsch Maintainer | bestätigt 2026-10-14 (Wunsch), Bezeichnungen offen |
| K22 | 2026-10-14 | Overlay, Einstellungen, Plattform | **Power-Taste nach längerer Pause (WP56):** (a) Neue Permission `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (ohne Play Store unkritisch, K7) und fünf Hersteller-Pakete in `<queries>` für Deep-Links zu Akku-/Autostart-Einstellungen. (b) Einstellungen → Assistent → „Zuverlässig öffnen“: Status Akku-Optimierung mit Ausnahme-Knopf, App-Standby-Bucket, Hersteller-Checkliste (Werte wie Autostart sind nicht auslesbar, daher Checkliste statt Status). (c) Overlay zeigt beim Kaltstart nativ „Wendelin startet …“, nach 10 s ohne erstes Bild schließt es sich. (d) Ursache auf AOSP nicht reproduzierbar, Vermutung HyperOS-Akkusparer; Diagnose-Skript für den Handytest. | Rückmeldung Maintainer, Umsetzung WP56 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K23 | 2026-10-14 | Sprach-Pipeline (Wake Word, Barge-in, Gesprächsmodus), TEE-Provider und Attestierung, Integrationen | **Planung M4 (`docs/work-packages/M4.md`, WP42–WP54) und Spikes WP42/WP43:** (a) Porcupine gestrichen; sherpa-onnx-Phonem-KWS reicht für „Wendelin“ nicht (62 % Treffer, 56 Falschauslösungen/h) → eigenes openWakeWord-Modell (WP58). (b) Wake Word setzt die Assistentenrolle voraus, Start auch über `VoiceInteractionService`, kein `BOOT_COMPLETED`; Treffer öffnet das Overlay über `showSession`; Standard „nur beim Laden“, wählbar „immer“. (c) Barge-in nur über „Wendelin“/„Stopp“ während der Ausgabe (ändert K11 d), freie Sprache experimentell. (d) Gesprächsmodus Standard aus; einmalige Nachfrage nach der ersten gesprochenen Antwort, Einstellung unter Sprache und im Onboarding. (e) TEE-Endstatus je Antwort grün/rot, gelb nur Zwischenstand; TCB `OutOfDate` = rot mit Hinweis; `external`-Tools warten auf die geprüfte Quittung; neues `AgentEvent` für den Prüfstatus. (f) GPU-Prüfung über NVIDIA NRAS: Aus (Standard) / Vorher (blockierend, fail-closed) / Nachher (asynchron, Warnung). (g) Kollateral direkt von Intel PCS, Cache bis `nextUpdate`, danach offline. (h) Rust über `flutter_rust_bridge` (Weg A, ~0,4 MB je ABI, 3 ms Prüfzeit). (i) API liefert kein `workload_id`/`stale_after`/`keyset_endorsement` → Pinning auf `workload_keyset_digest` + Compose-Hash; TLS-SPKIs passen derzeit nicht zum Keyset (offen, WP46). (j) Bei gesperrtem Gerät erkennt das Wake Word nur Taschenlampen-Befehle lokal (K16). | Planung/Spikes M4, Entscheidungen Maintainer 2026-10-14 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: (b)–(h) teils bestätigt 2026-10-14 (siehe M4.md „Entscheidungen“); Rest offen) |
| K24 | 2026-10-14 | Sprach-Pipeline (Gesprächsmodus, Barge-in) | **Umsetzung WP45 (ADR 0016):** (a) Barge-in-Modi `off` (Standard) / `keywords` („Wendelin“, „Stopp“) / `speech` (experimentell, Adapter muss echo-unterdrücktes Pre-Roll liefern); K11 d („während der Ausgabe nur Antippen“) gilt nur noch bei `off`. (b) Gesprächsmodus: höchstens 5 Folgefragen; Ende bei Stille, „Stopp“, Abschlussphrasen („Danke“, „Das war’s“, „Merci“, „Thanks“ – nur im Folgefenster, als erste Äußerung gehen sie an den Agenten), Antippen, Bestätigungskarte, Fehler; neuer Abbruchgrund `bargeIn`. (c) Kein neuer Pipeline-Zustand; das Folgefenster ist ein Ereignis. | Umsetzung/Review WP45 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K25 | 2026-10-14 | UI/UX, Sprach-Pipeline, Einstellungen | **Gesprächsmodus in der App (WP51, ADR 0015):** (a) Einmalige Nachfrage als Karte im Hauptbildschirm nach der ersten gesprochenen Antwort, die mit einer Rückfrage endet, oder bei einer zweiten Sprachanfrage innerhalb von 2 min (Antwortende → Antwortende); aus dem Overlay heraus wird sie gespeichert und beim nächsten Öffnen der App gezeigt. (b) Onboarding hat einen fünften Schritt „Gespräch“; Einstellung unter Sprache (unter dem Mikrofon-Block). (c) Echo-Unterdrückung über die Aufnahme-Option des `record`-Plugins (Quelle `VOICE_COMMUNICATION` nur während der Sprachausgabe, sonst `VOICE_RECOGNITION`). (d) Barge-in bleibt „nicht verfügbar“, bis ein Wake-Word-Detektor existiert. | Umsetzung/Review WP51 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K26 | 2026-10-14 | Sprach-Pipeline, Agent-Schleife, Einstellungen | **Umsetzung K21 (WP55):** Einstellung `spokenVersion` (Enum `SpokenVersion`: Aus/Immer/Geschützt/Mit KI-Prüfung) ersetzt `twoVersions` (Migration true→Geschützt, false→Aus) und `AgentConfig.spokenVersions` (K20 a). Neue Ereignisse `AgentSpokenHold`/`AgentSpokenVerdict`. KI-Prüfung: Sprechtext wird bis zum Urteil gehalten (≈ 1 s nur nach fremden Inhalten); Urteil zählt nur bei vollständig beendetem Prüfaufruf; Markierungen mit Zufallswert; lokale Vorprüfung von Zahlen/Nummern/Adressen; im Audit-Log nur feste Gründe (`match`, `model_no`, `local_mismatch`, `timeout`, `unreadable`, `error`). Eval: Haiku 10/10, Phala Qwen 9/10 (eine passende frz. Fassung abgelehnt), alle Manipulationen erkannt. | Umsetzung/Reviews WP55 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen (Bezeichnungen der Stufen offen)) |
| K27 | 2026-10-14 | TEE-Provider und Attestierung, Routing/Eskalation | Nach einer fehlgeschlagenen oder nicht durchführbaren Prüfung (Phala-Session, Quittung, GPU/NVIDIA) geht die Anfrage **nie** an einen anderen Anbieter – weder still noch nach Rückfrage; keine Option „Ausweichen“. Die Anfrage endet rot mit Grund; eine neue Anfrage des Nutzers (z. B. „nochmal mit Claude“) folgt den normalen Regeln. „Ohne GPU-Prüfung senden“ (nur diese Anfrage, derselbe Phala-Knoten) bleibt erlaubt. | Review WP52, Entscheidung Maintainer | bestätigt 2026-10-14 |
| K28 | 2026-10-14 | Routing und Eskalation, Agent-Schleife, LLM-Provider | **Kein automatischer Anbieterwechsel:** Das gewählte Modell bzw. der gewählte Anbieter (direkt, per Profil oder eigener Routing-Regel vor dem Aufruf) ist verbindlich. Ist es nicht verfügbar, offline, fehlerhaft oder die Prüfung rot, gibt es eine klare Fehlermeldung – nie einen automatischen Wechsel zu einem anderen Modell/Anbieter, auch nicht nach Rückfrage. Eine Wiederholung beim selben Ziel (1 Retry) bleibt. Eskalationsketten (K8 d, K12 a) entfallen; „nochmal mit X“ bleibt als ausdrückliche neue Nutzeranfrage (mit Datenschutz-Untergrenze, K13). Umsetzung WP59. | Entscheidung Maintainer | bestätigt 2026-10-14 |
| K29 | 2026-10-14 | Sprach-Pipeline (Wake Word) | Aktivierungswort bleibt „Wendelin“. Erkennung zweistufig: Kandidat aus openWakeWord-Features (eigenes Modell aus WP58 mit niedriger Schwelle oder Ähnlichkeit zu persönlichen Vorlagen), Bestätigung durch Whisper-Nachprüfung. Persönliches Einlernen in der App („Wendelin lernt deine Stimme“: 15–20 Aufnahmen, optional 30 min Kalibrieren); gespeichert werden nur Embeddings und Schwelle, nie Rohaudio; mehrere Personen möglich. Vergleich anderer Aktivierungswörter später. Umsetzung WP44 (Nachtrag 2), WP60. | Entscheidung Maintainer | bestätigt 2026-10-14 |
| K30 | 2026-10-14 | Overlay, Sicherheit (K11 f) | **Folge aus K16 (WP53):** Bei gesperrtem Gerät hört das Overlay zu (Whisper wird dafür geladen, beim Schließen freigegeben), erkennt lokal ausschließlich Taschenlampen-Befehle (strenger Abgleich de/fr/en, jedes unbekannte Wort → abgelehnt) und antwortet sonst nur mit dem festen Satz „Bitte entsperre das Telefon“; die Äußerung wird verworfen, kein Modell, kein Routing, kein Verlauf, im Audit nur `whileLocked`/`refused` ohne Text. Das Entsperren wird erst nach einer abgewiesenen Äußerung angeboten. | Umsetzung/Review WP53 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K31 | 2026-10-14 | Sprach-Pipeline (Wake Word) | **Umsetzung K29 (WP44):** Merkmale aus openWakeWord-Mel/Embedding (statt sherpa-KWS); Kandidat bei Ähnlichkeit zu persönlichen Vorlagen (Kalibrierung: 10 %-Quantil, Untergrenze 0,85, mind. 2 Vorlagen und Hintergrund-Negativa) oder WP58-Modell; Whisper-Nachprüfung über ~3 s (0,9 s Nachlauf nach dem Treffer, ~1 s Zusatzlatenz) mit Schreibvarianten und Kölner Phonetik. `TriggerEvent.preRoll`, `SpeechModelKind.wake`. Messung mit synthetischen Stimmen: Stufe 1 84 % bei 2,8 Kandidaten/h, nach Stufe 2 42 %, 0 Fehlalarme/h; unter Rauschen/Hall bestätigt Stufe 2 kaum – endgültige Bewertung mit echten Stimmen in WP60, ggf. Nachprüfung lockerbar/abschaltbar. | Umsetzung/Reviews WP44 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K32 | 2026-10-14 | Sprach-Pipeline, Sicherheit, UI/UX | **Wunsch für M5 (Ausgestaltung gemeinsam mit dem Maintainer):** Sprechererkennung – erkennt, wer spricht, für Personalisierung und zusätzliche, rechtlich unkritische Aktionen, auch bei gesperrtem Gerät. Hinweis: Stimmerkennung ist keine starke Authentifizierung (Aufnahmen/Nachahmung möglich) und eignet sich nur für Aktionen mit geringem Risiko. Anknüpfung an die eingelernten Stimmabdrücke aus WP60. | Wunsch Maintainer | bestätigt 2026-10-14 (Aufnahme in M5), Umfang offen |
| K33 | 2026-10-14 | Routing und Eskalation, Datenschutz | **Umsetzung K28 (WP59):** Eskalationsketten entfernt (Einstellungen, Import, Agent); nach Fehlern nur 1 Retry beim selben Ziel, dann Fehlermeldung mit Grund (de/fr/en, nie die rohe Fehlermeldung vorgelesen). „nochmal mit X“ / „X, …“ bei abgeschaltetem oder unvollständigem Profil X → „X ist nicht verfügbar“. Lehnt der Nutzer die Rückfrage bei „nochmal mit X“ unter der Datenschutz-Untergrenze ab, endet die Anfrage mit „Nicht gesendet“ (das zuerst geroutete Ziel antwortet nicht). Die Rückfrage zu geschützten Tool-Ergebnissen im laufenden Lauf (K10 c) entfällt, weil kein Wechsel mitten im Lauf mehr stattfindet; Ausblendung früherer Züge, Taint und Untergrenze (K13) bleiben. | Umsetzung/Review WP59 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K34 | 2026-10-14 | Sprach-Pipeline (Wake Word), UI/UX | **Umsetzung K29 (WP60):** Einlernen „Wendelin lernt deine Stimme“ (Sprechen, Kalibrieren, Ausprobieren) in den Einstellungen; gespeichert werden nur Merkmalsvektoren (Embeddings), keine Aufnahmen. Schwelle vorläufig 0,85, Obergrenze 0,95; Treffer beim Ausprobieren fließen gewichtet in die Kalibrierung ein. Einlernen im Onboarding noch nicht enthalten (später, nach Gerätetest). Die Merkmale laufen über die libonnxruntime 1.28.2 aus sherpa-onnx (FFI, Element-Typen geprüft), vorerst auf dem UI-Isolate. Das Mikrofon wird beim Wechsel in den Hintergrund freigegeben. | Umsetzung/Review WP60 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K35 | 2026-10-14 | Sprach-Pipeline (Wake Word), Plattform Android | **Umsetzung WP50 a (Wake-Word-Dienst):** Aufnahme im Foreground-Dienst nativ (`AudioRecord`, `VOICE_RECOGNITION`), Erkennung in einer kopflosen Dart-Engine; Whisper-Nachprüfung im Dienst (lazy geladen, nach 60 s freigegeben; Ruhe-PSS 107,5 MB im Emulator). Neue Berechtigung `WAKE_LOCK`: bei einem Treffer schaltet ein kurzer Screen-Wake-Lock den Bildschirm ein, damit das Overlay erscheint; das Gerät bleibt gesperrt (WP53-Pfad). Kann die Nachprüfung nicht entscheiden (Modell fehlt, Fehler), gilt der Kandidat als nicht bestätigt. Ohne Rolle kein Dienst nach dem Neustart; „Wieder einschalten“ nur mit Benachrichtigungs-Berechtigung. Das WP58-Modell ist im Dienst nicht verdrahtet (nur eingelernte Stimmen). Konflikte (Telefonat, fremde Aufnahme, Overlay) halten das Mikrofon geschlossen. | Umsetzung/Reviews WP50 a | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K36 | 2026-10-14 | UI/UX (Wake Word), Sprach-Pipeline | **Umsetzung WP50 b (Einstellungen):** Seite „Aktivierungswort“ mit Status, Schalter (gesperrt ohne Assistentenrolle bzw. ohne eingelernte Stimme), Bedingung „Nur beim Laden“ (Standard)/„Immer“, Bestätigungston (Standard an), Nachprüfung; Erklärdialog einmalig vor dem ersten Einschalten („Zuhören bleibt auf dem Gerät“; Gesagtes nach „Wendelin“ geht als Text an den gewählten Anbieter); Onboarding-Schritt optional. Abweichungen: keine Empfindlichkeit in drei Stufen (die Engine kennt nur die Schwelle je eingelernter Stimme), kein Akku-Messwert im Dialog, Texte nur deutsch (wie die ganze UI). Der Bestätigungston wird mit ca. 200 ms Stummschaltung des Mikrofons aus der Aufnahme gehalten. „Aus“ in der Benachrichtigung bleibt aus, bis der Nutzer in der App wieder einschaltet. | Umsetzung/Reviews WP50 b | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K37 | 2026-10-14 | Datenschutz/TEE (Phala) | **Phala nur Ende-zu-Ende-verschlüsselt (WP61–63):** (a) Der TLS-Schlüssel der Verbindung muss zu `tls_public_keys` aus der Attestierung passen, sonst geht keine Anfrage raus (fail-closed); bisher war der Pin nicht verdrahtet. Die frühere Aussage, der SPKI von RedPill passe nicht, ist veraltet (Live-Messung 2026-10-14 passt). (b) Phala-Anfragen nur mit E2EE v2 (x25519, AES-256-GCM, Schlüssel aus der geprüften Attestierung), keine Klartext-Variante; Fehler ohne Anbieterwechsel (K28). (c) Grenzen: v2 verschlüsselt keine Tool-Definitionen und Tool-Argumente (nur gepinntes TLS), die Verschlüsselung endet im Gateway-CVM, nicht im Modell; die App zeigt das als Hinweis an („Tool-Aufrufe sind über die geprüfte Verbindung bis in die Enklave geschützt, aber nicht zusätzlich verschlüsselt.“); der zeitweise eingebaute Schalter „Phala ohne Tools“ ist wieder entfallen (Entscheidung Maintainer 2026-10-15, WP71). (d) Umstellung auf E2EE v3 bis 10.02.2027. (e) Umsetzung WP62: Suite x25519 (die Phala-Doku nennt nur secp256k1; x25519 ist über Referenz-Spec und Live-Keyset belegt), Auswahl per `algo`, Ablauf `not_after` des Keysets erzwingt Neu-Attestierung. Verschlüsselt werden alle String-Inhalte inkl. System-, Tool-Ergebnis-, Bild- und Audio-Teile; ein String, der wie ein JSON-Array aussieht, geht als Ein-Teil-Array (sonst passt der Quittungs-Hash nicht). E2EE-Fehler verwerfen die Sitzung und attestieren neu, ohne Anbieterwechsel. Live belegt: der Dienst entschlüsselt unsere Anfrage (402 statt `e2ee_decryption_failed`); Antwort-Entschlüsselung und Streaming live noch offen (Key ohne Guthaben). ADR 0018. | Wunsch Maintainer 2026-10-14, Recherche Phala-E2EE | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K38 | 2026-10-15 | Sprach-Pipeline (Sprachausgabe), UI/UX | **Stimmen (WP66):** je Sprache eine weibliche und eine männliche Offline-Stimme (Piper int8 über sherpa-onnx, alle CC0): de Thorsten (m) + Kerstin (w), fr Siwis (w) + Gilles (m), en LJSpeech (w) + Joe (m), je ~21 MB, Download bei Bedarf. Auswahl im Untermenü „Stimmen“ mit „Probe hören“; die Offline-Stimme wird je Sprache gespeichert (`sherpaVoices`), `ttsVoice` gilt nur noch für die Systemstimme. Ist die gewählte Stimme nicht geladen, spricht die erste geladene der Sprache mit Hinweis. | Wunsch Maintainer 2026-10-15 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K39 | 2026-10-15 | Sprach-Pipeline (Wake Word), Plattform Android | **„Wendelin, mach …“ in einem Atemzug (WP68):** Das Dienst-Mikrofon bleibt nach einem bestätigten Treffer offen, bis das Overlay übernimmt (ändert WP50 a „gibt das Mikrofon frei, bevor das Overlay aufnimmt“); Puffer höchstens 15 s, verworfen bei Ablehnung, Timeout, Dienstende oder laufendem Agenten. Das Wake Word wird aus dem Transkript entfernt; bleibt nichts übrig, wartet das Overlay. Die Stille-Erkennung beginnt erst nach dem Wake Word. Der Bestätigungston entfällt, wenn nach dem Wake Word schon gesprochen wird (Schwelle relativ zum Grundrauschen). Offen: Barge-in „Wendelin“ während der Ausgabe liefert noch keinen Vorlauf (kurze Lücke). | Wunsch Maintainer 2026-10-15 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K40 | 2026-10-15 | Sprach-Pipeline (Barge-in), Wake Word | **„Stopp“ allein (WP64b):** „Stopp“ wird wie „Wendelin“ eingelernt (10 Aufnahmen, nur Merkmale, verschlüsselt) und gilt nur während der Sprachausgabe (Barge-in „Schlüsselwörter“), nicht im Hintergrund-Dienst. Feste Startschwelle 0,9 (+0,05 im Barge-in), Treffer erst bei zwei Fenstern in Folge; keine eigene Kalibrierung (Abweichung vom WP). Ohne eingelerntes „Stopp“ unterbricht nur „Wendelin, stopp“. | Gerätetest Maintainer 2026-10-15 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K41 | 2026-10-15 | Agent/Unterhaltung, UI/UX | **Neues Gespräch je Aufruf (WP67):** Jeder Aufruf des Assistenten-Overlays beginnt ein leeres Gespräch; Folgefragen, Barge-in, erneutes Auslösen bei offenem Overlay und Entsperren gehören zum selben Aufruf. Sitzungen tragen eine Herkunft (`app`/`overlay`, Schema v5); der App-Chat setzt nie eine Overlay-Sitzung fort. Datenschutz-Untergrenze beginnt mit dem neuen Gespräch neu. | Gerätetest Maintainer 2026-10-15 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K42 | 2026-10-15 | Plattform Android | **Mindestversion Android 10 (API 29, WP69):** vorher installierbar ab Android 8 (API 26). Assistenten-Rolle (RoleManager) und Diensttyp „Mikrofon“ für das Wake Word gibt es erst ab Android 10; ohne sie fehlen Wake Word, Overlay und Taschenlampe bei gesperrtem Gerät. Getestet ist bisher nur Android 15 (Emulator, Samsung). | Frage Maintainer 2026-10-15 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K43 | 2026-10-16 | Datenschutz, Audit-Log | **Export des Prüfprotokolls ohne Inhalte (WP71):** Das lokale Prüfprotokoll speichert weiter Transkript und Tool-Argumente (Konzept Audit-Log), der JSON-Export enthält aber nur eine Positivliste fester Felder je Eintragsart (keine Texte, Argumente, Beschreibungen, freien Meldungen). Einträge mit Sitzung zeigen beim Antippen die zugehörigen TEE-Prüfungen und Stufen. Lokales Speichern der Transkripte bestätigt (Maintainer 2026-10-16). | Gerätetest 2026-10-15 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: Speichern bestätigt 2026-10-16, Rest offen) |
| K44 | 2026-10-16 | TEE-Provider (Phala), Datenschutz | **Quittung nicht bestätigt (WP70, Entscheidung Maintainer (b)):** Ist die Quittung einer Antwort nach allen Versuchen (6 über ~24 s) nur nicht abrufbar (nicht gefunden, nicht erreichbar, fehlt) und es gibt keinen Prüffehler, endet die Antwort grau als „nicht bestätigt“; der Anbieter wird nicht gesperrt, `external`-Tools laufen trotzdem nicht. Gesperrt (rot) wird nur bei echten Prüffehlern (Signatur, Prüfsumme, Schlüsselsatz, Bindung, Upstream, abgewiesener Abruf). Der Quittungsabruf sendet den API-Key, aber nur über die an die Sitzung gepinnte Verbindung (Gateway gibt Quittungen nur dem Besitzer, sonst 401 – Ursache der roten Antworten im Gerätetest). Attest-Logs (`Wendelin/attest`, nur Stufen/Codes) auch im Release. | Gerätetest 2026-10-15, Live-Beleg | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: offen) |
| K45 | 2026-10-16 | TEE-Provider (NEAR AI), Datenschutz | **NEAR AI Cloud als zweiter TEE-Anbieter (WP75, ADR 0019):** zusätzlich zu Phala, nur NEAR-eigene Modelle (z. B. `z-ai/glm-5.3-flash`, Qwen3.6-35B, Qwen3.8-27B), kein Routing über Drittanbieter. E2EE mit `X-Encrypt-All-Fields` (X25519, HKDF-SHA256, XChaCha20-Poly1305) – verschlüsselt auch `tools`, `tool_calls` und Tool-Ergebnisse, Entschlüsselung im Modell-TEE; Quittung mit `x-no-aliasing: true` vom Modell-TEE signiert (auch beim Streaming). Attestierung TDX (dcap-qvl) + NVIDIA NRAS, `report_data` = sha256(Schlüssel ‖ TLS-SPKI) ‖ Nonce, TLS-Pin. Abweichungen: (a) **Gateway-TCB `OutOfDate` nur Hinweis** (Modell-TEE `OutOfDate` bleibt rot; das Gateway sieht nur Chiffrat) – bestätigt 2026-10-16; (b) kein Ablaufdatum des Schlüssels → Sitzung 30 min; (c) kein E2EE-Antwortheader, Beweis über entschlüsselte Felder; unbekannte Felder → Abbruch; (d) Restrisiken: keine AAD/Bindung Antwort↔Anfrage, kein Replay-Schutz, Fehlerobjekte im Klartext, erster Attestierungsabruf mit Key ungepinnt. | Entscheidung Maintainer 2026-10-15, Spike/Live 2026-10-16 | bestätigt 2026-10-16 (Sammelbestätigung Maintainer; vorher: (a) bestätigt 2026-10-16, Rest offen) |
| K46 | 2026-10-16 | TEE-Provider, Agent-Schleife, UI/UX | **TEE schneller und Anzeige (WP77, WP78):** (a) Overlay wärmt die Attestierung beim Öffnen vor; geprüfte Sitzungen werden beim Neuaufbau der Profile übernommen (gleicher Endpunkt/Modell, gültig, Pin gesetzt); im GPU-Modus „Aus“ kein GPU-Abruf mehr (damit auch keine lokale Nonce-Bindung der GPU-Evidenz, ADR 0014 §8), sonst parallel zur Attestierung; Verbindung bleibt 5 min offen. (b) Tools mit Undo laufen sofort; ist die Quittung nicht grün (rot oder nicht bestätigt), werden sie automatisch zurückgenommen und der Nutzer informiert (scheitert das, Audit-Eintrag und gesprochener Hinweis); `external` wartet weiter auf Grün. (c) Fehlt der GPU-Nachweis beim Anbieter (Phala liefert ihn z. B. für GLM 5.2/DeepSeek/Gemma nicht), Grund „kein Nachweis“ sichtbar; „Vorher“ blockiert dann. (d) Im Chat nur das Schild ohne Zusatztext; Einschränkungen eines Anbieters (nur protokollierte Stufen) werden einmal bei Einrichtung/„Modell prüfen“ je Profil und Modell akzeptiert, neue Einschränkungen erneut gezeigt; Tool-Hinweis nur im Prüfprotokoll; Erklärseite „Details“ je Stufe. (e) Nur der manuelle Modell-/Profilwechsel beginnt ein neues Gespräch (mit Rückfrage), „Nochmal mit X“ und Routing-Regeln nicht. | Gerätetest/Messung 2026-10-16, Entscheidungen Maintainer | bestätigt (2026-10-18) |
| K47 | 2026-10-16 | Sprach-Pipeline (Barge-in) | **„Stopp“ während der Ausgabe (WP80):** bewertet nur das Fensterende (9/16 Merkmale), braucht hörbare Sprache (Pegel deutlich über dem Grundpegel) und Abstand zum Hintergrund-Niveau; Einstellungen unter „Erweitert“ statt verstecktem Menü (Texte vorerst nur deutsch, App-Sprache in M5). | Gerätetest 2026-10-16 | offen |
| K48 | 2026-10-18 | Meilensteine | **M5 nur Android.** Alles Weitere aus dem M5-Gespräch kommt nach **M6** (Ausbau 2): Kamera/Bild, Stationsmodus, Vergleich alternativer Wake Words, Empfehlung von Modellen. **iOS wird M7** (Entscheidung Maintainer 2026-10-18). | Entscheidung Maintainer 2026-10-18 | bestätigt 2026-10-18 (geändert: Kamera/Bild nicht gestrichen, sondern M6; iOS M7) |
| K49 | 2026-10-18 | Eingebaute Integrationen, Sicherheit | **SMS und Anrufe mit Vorschau in der App (WP85):** statt Intent zum SMS-Programm zeigt Wendelin ein Popup (Kontaktname, Nachrichtentext editierbar), liest es vor und fragt nach („Soll ich anrufen?“ / „Soll ich sie absenden?“). Ausgeführt wird erst nach Tipp auf „Absenden“/„Anrufen“ **oder** nach gesprochener Bestätigung („ja“, „anrufen“, „absenden“), auch im Gesprächsmodus. Bei gesperrtem Gerät nie. Undeutliche Antwort: nicht ausführen, nochmal fragen. Senden selbst (`SEND_SMS`), Anruf (`CALL_PHONE`). Audit ohne Nachrichtentext. | Entscheidung Maintainer 2026-10-18 | bestätigt 2026-10-18 (ergänzt: Bestätigung auch per Sprache) |
| K50 | 2026-10-18 | Eingebaute Integrationen | **Wetter mit wählbarem Dienst (WP87):** Open-Meteo (Standard), Bright Sky (DWD), MET Norway; Meer nur Open-Meteo. Ort: aus der Frage, sonst Standort, sonst Heimatort. | Entscheidung Maintainer 2026-10-18 | bestätigt 2026-10-18 |
| K51 | 2026-10-18 | Eingebaute Integrationen | **Aufgaben auf Basis der Listen (WP88)** mit Fälligkeit/Priorität im Obsidian-Tasks-Format statt eigener `Tasks.md`; zusätzlich eigene Integrationen **Todoist** (API-Token) und **Google Tasks** (OAuth, eigenes Cloud-Projekt) (WP89). | Entscheidung Maintainer 2026-10-18 | bestätigt 2026-10-18 |
| K52 | 2026-10-18 | Eingebaute Integrationen | **Mediensteuerung statt Audible-Schnittstelle (WP90):** allgemeine Steuerung der aktiven Medien-Session (Benachrichtigungszugriff), Audible nur öffnen/suchen per Intent; keine inoffiziellen APIs. | Entscheidung Maintainer 2026-10-18 | bestätigt 2026-10-18 |
| K53 | 2026-10-18 | Eingebaute Integrationen, Sicherheit | **Eigene Home-Assistant-Integration (WP91)** zusätzlich zum MCP-Weg: Heimnetz/Tailscale, Token, freigegebene Entitäten, Risiko je Domain (Licht/Szenen/Medien ohne Nachfrage mit Undo, Klima mit Undo, Schloss/Alarm/Garage immer bestätigen); `http` nur für private/Tailscale-Adressen. | Entscheidung Maintainer 2026-10-18 | bestätigt 2026-10-18 |
| K54 | 2026-10-18 | Sprach-Pipeline, Sicherheit | **Umfang Sprechererkennung (WP92, zu K32):** beliebig viele Personen; je Person Anrede, Gedächtnis, Standard-Agent; gesperrt für erkannte Personen nur Timer/Wecker, Wetter, Musik/Medien, Listen ergänzen, Licht/Szenen (HA), nichts, was Inhalte vorliest; standardmäßig aus. | Entscheidung Maintainer 2026-10-18 | bestätigt 2026-10-18 |
| K55 | 2026-10-18 | UI/UX, Sprach-Pipeline | **Wake Word bei sichtbarem Chat (WP93)** setzt das App-Gespräch fort statt Overlay (ergänzt K41). **Schnellwechsel (WP94):** langer Druck auf den Agenten oben, Popup nach ~2 s, Auswahl = neuer Standard und leerer Chat ohne Rückfrage (ergänzt K46 e). | Entscheidung Maintainer 2026-10-18 | bestätigt 2026-10-18 |
| K56 | 2026-10-18 | TEE-Provider, Sicherheit | **NRAS-Token-Signatur (WP83):** das GPU-Ergebnis von NVIDIA wird nur aus einem gegen das NVIDIA-JWKS geprüften ES384-Token gelesen (Prüfung in Dart statt Rust, keine neue Abhängigkeit); die `x5c`-Kette der JWKS-Schlüssel bis zur NVIDIA-Wurzel wird vorerst nicht geprüft, das Vertrauen in die Schlüssel ruht auf TLS zu NVIDIA (offener Punkt, ADR 0014). Logzeile `gpu gpu=pass via=nras|local`. | Gerätetest 2026-10-16, Review | bestätigt 2026-10-18 |
| K57 | 2026-10-18 | Eingebaute Integrationen, Sicherheit | **HA-Schalter (WP91, zu K53):** `switch` läuft standardmäßig ohne Nachfrage mit Undo; je freigegebener Entität lässt sich „immer bestätigen“ einschalten (z. B. Garagen- oder Torrelais). Szenen, die Schloss, Alarm oder Cover enthalten, laufen nur mit Bestätigung und sind bei gesperrtem Gerät nicht freigegeben. | Review WP91, Entscheidung Maintainer 2026-10-18 | bestätigt 2026-10-18 |
| K58 | 2026-10-18 | Eingebaute Integrationen, Sicherheit | **Umsetzung HA (WP91, zu K53/K57):** zwei Tools `ha__call` (w, Undo) und `ha__call_secure` (immer bestätigen) statt Risiko je Argument; alle `cover` bestätigen; Alarm ohne Code; Szenen mit Schloss/Alarm/Cover/`group.*`/bestätigten Schaltern oder unklarer Mitgliederliste nur mit Bestätigung, Szenen ohne `entity_id` (z. B. Hue) entsperrt ohne Nachfrage, gesperrt verboten; `http` auch für Loopback; Integration gilt als sensibel; neue Android-Berechtigung `CHANGE_WIFI_MULTICAST_STATE` für die mDNS-Suche. | WP91 Umsetzung und Review | bestätigt 2026-10-19 |
| K59 | 2026-10-18 | TEE-Provider, Sicherheit | **Tinfoil-Release-Prüfung (WP76b):** keine SCT-Prüfung (Leaf über Rekor gebunden); nur Rekor v1, Rekor v2/TSA werden fail-closed abgelehnt (Umstellung bei GitHub würde Tinfoil brechen, beobachten); Sigstore-Trust-Root wird nur per App-Update erneuert (`tool/update_sigstore_root.dart` vergleicht zwei Quellen, prüft TUF-Signaturen nicht); Bundle-Quellen api.github.com und api-github-proxy.tinfoil.sh. **Offen:** „neuestes Release“ kommt aus nicht vertrauenswürdiger Quelle, Downgrade auf ein älteres gültig signiertes Release ist möglich; Lösung in WP76d. | WP76b Umsetzung und Review | bestätigt 2026-10-19 |
| K60 | 2026-10-19 | UI/UX, Sprache | **App-Sprache (WP79):** UI-Sprache System/Deutsch/Englisch/Französisch, nicht unterstützte Systemsprache → Englisch; gesprochene Texte, Sprachbefehle und Texte an das Modell folgen der Sprech-Sprache bzw. bleiben deutsch, nicht der UI-Sprache; Sprachnamen immer als Endonyme; Beträge en „$1.50“, de/fr „1,50 $“; Modellgrößen mit einer Dezimalstelle. Technik: generierte l10n-Dateien werden committet, Tests laufen mit Systemsprache Deutsch. | WP79 Umsetzung | bestätigt 2026-10-19 |
| K61 | 2026-10-19 | Eingebaute Integrationen | **Aufgaben (WP88):** statt `add_task`/`list_tasks`/`complete_task` auf einer festen `Tasks.md` eine eigene Integration `tasks` mit `tasks__add`/`tasks__list`/`tasks__complete` auf den Listen aus K6; Einstellung „Standard-Aufgabenliste“ (höchstens eine); Uhrzeit als eigene Erweiterung `⏰ HH:MM` vor den Obsidian-Tasks-Marken. Erinnerung über Wecker/Timer und Fortschreiben wiederkehrender Aufgaben (🔁) folgen später. | WP88 Umsetzung und Review | bestätigt 2026-10-19 |
| K62 | 2026-10-19 | UI/UX, Sicherheit | **Stationsmodus (M6), Entscheidungen Maintainer:** Start nur manuell; Ende nur per Button mit Entsperren; Anzeige mit Uhr/Datum/Wetter, Wiedergabe, Terminen/Aufgaben mit Titeln und Smart-Home-Kacheln; Sprache nach K54; Kacheln ohne Entsperren antippbar wie Sprache nach K54; Bildschirmverhalten auswählbar; Ruhezeiten, Bluetooth-Lautsprecher, längerer Gesprächsmodus, Wecker mit Ansage. | Gespräch mit Maintainer 2026-10-19 | bestätigt 2026-10-19 |
| K63 | 2026-10-19 | UI/UX, Sicherheit | **Stationsmodus, Vorschläge Orchestrator:** Start auch per Schnellkachel und Sprachbefehl (nur entsperrt); Abstecken beendet nicht; Station läuft über dem Sperrbildschirm statt Overlay; Wake Word Pflicht; Vorlesen von Terminen auf Anfrage bleibt gesperrt (nur Display und Wecker-Ansage mit Titeln); kritische HA-Entitäten nicht als Kachel; Bildschirm-Standard „immer an, gedimmt“; Ruhezeiten einstellbar (Standard 22–7 Uhr, Ergänzung Maintainer); Gesprächsmodus 15 s; Bereiche einzeln ausblendbar. | Gespräch mit Maintainer 2026-10-19 | bestätigt 2026-10-19 |
| K64 | 2026-10-19 | Sprach-Pipeline | **Bessere Sprache (WP102, WP103):** größere lokale STT-Modelle (z. B. Parakeet, Whisper turbo) und bessere Stimmen (z. B. Piper high, Kokoro) wählbar, 2–3 GB RAM sind in Ordnung; erst Messvergleich (WP102), dann Einbau. Dazu Modell im Speicher halten (im Stationsmodus standardmäßig an), Rauschunterdrückung vor der Erkennung, eigene Begriffe (Kontakte, HA-Räume, Listen, Agenten) lokal als Hinweis an die Erkennung. Keine Cloud-Stimme. | Wunsch Maintainer 2026-10-19 | bestätigt 2026-10-19 |
| K65 | 2026-10-19 | Eingebaute Integrationen, Sprach-Pipeline | **Mediensteuerung (WP90):** andere Wiedergabe wird während der ganzen Antwort leiser (Audiofokus „transient, may duck“, 1,5 s Nachlauf); beim Zuhören eigener Audiofokus, Aufnahme pausiert nur bei echtem Fokusverlust, nicht bei Ansagen mit Ducking (ersetzt das Verhalten aus WP72); `media__next`/`previous` ohne Nachfrage und ohne Undo (wie Spotify); `open_audible` mit Suche = suchen und abspielen; Medien-Listener nur mit Benachrichtigungszugriff. | WP90 Umsetzung, Entscheidungen Maintainer in der Paket-Sitzung | bestätigt 2026-10-19 |
| K66 | 2026-10-19 | Sprach-Pipeline | **Ergebnis Messvergleich (WP102, zu K64):** STT-Standard bleibt Whisper small; „groß“ wählbar Parakeet TDT 0.6B v3 int8 (de-WER 3,9 % statt 10,9 %, deutlich schneller, ~1,4 GB RAM), Französisch optional Canary-180m-flash; eigene Begriffe nur als Hotwords bei Parakeet/Transducer-Modellen (Whisper in sherpa-onnx ohne Prompt); **keine Rauschunterdrückung** (GTCRN verschlechtert die Erkennung); TTS-Standard bleibt Piper medium/low, wählbar Thorsten high (de) und Kokoro (en/fr). Lizenzen: Parakeet/Canary CC-BY-4.0 mit Namensnennung in der App, Stimmen mit NC-Lizenz ausgeschlossen. Wahl Stefan offen, bis dahin gilt die Empfehlung. | WP102 | offen |
| K67 | 2026-10-19 | Integrationen (Standort/Maps) | **Umsetzung WP86:** `maps__route_info` entfällt (ohne Google-API-Key nicht machbar); `location__distance_to` nimmt das Ziel als Text „lat,lon“ (Tool-Schema kennt kein number); ohne Google Maps nur `geo:`-Intent ohne Routenführung; describe/Audit der Navigations-Tools ohne Ziel; Wetter nutzt die Geräteposition nur, wenn der Provider die Mindeststufe erfüllt (ohne gesetzte Mindeststufe nur `tee`/`local`) oder `location` als nicht sensibel markiert ist, sonst den Heimatort – strenger als die Registry („keine Mindeststufe“ = alle), Frage an Stefan offen; Koordinaten an den Wetterdienst auf 2 Nachkommastellen; check_apk erlaubt ACCESS_FINE/COARSE_LOCATION, ACCESS_BACKGROUND_LOCATION bleibt verboten | WP86 | offen |
| K68 | 2026-10-19 | Sprach-Pipeline | **Umsetzung WP103 (zu K64/K66):** Rauschunterdrückung entfällt (K66); Hinweis-Begriffe gehen als Text mit bpe-Vokabular (aus tokens.txt abgeleitet, kein zusätzliches Hosting) an sherpa-onnx, weil vortokenisierte Hotwords in 1.13.8 nicht wirken; Quellen der Hinweis-Begriffe: Assistentenname (nur „Wendelin“), Listen, freigegebene HA-Räume/-Entitäten, Kontaktnamen (über WP85); „Modell im Speicher halten“ standardmäßig aus, im Stationsmodus (WP99) vorgesehen; Kokoro ist ein Modell mit mehreren Sprechern (Stimmen-ID Modell/Sprecher); Messwerte-Seite (Latenz/RTF/RAM, nur Zahlen) auch im Release; Canary ohne feste Sprache nimmt die App-Sprache, der Wake-Dienst bleibt bei 'de' und ohne Hinweis-Begriffe | WP103 | offen |
