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
   - Standard: Whisper lokal über sherpa-onnx; Modellgröße wählbar (`base` schnell, `small` besser für Deutsch und Französisch). Modelle werden beim ersten Start heruntergeladen, nicht ins APK gepackt.
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
4. **Pinning**: `workload_keyset_digest` und `source_provenance.repo_commit` speichern (ein `workload_id` liefert die API nicht, K2). Ändern sie sich, neue Attestierung und Hinweis an den Nutzer ("Anbieter hat ein Update ausgerollt, neu geprüft"). TLS terminiert in der Enklave (`downstream_tls_binding`, `tls_public_keys`): TLS-Verbindung auf den SPKI-Hash aus dem Keyset pinnen.
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

**Meilensteine**

1. **M0 Gerüst**: Flutter-Projekt, Riverpod, drift, Secure Storage, Kern-Interfaces (`LlmProvider`, `Integration`, `Tool`, `AgentRun`) mit Fake-Implementierungen; Text-Chat-UI. *Fertig, wenn* ein Fake-Provider einen Fake-Tool-Call auslöst und das Ergebnis angezeigt wird.
2. **M1 Text-Agent (Android)**: Anthropic- und OpenAI-kompatibler Adapter, Provider-Einrichtung mit Test, Agent-Schleife mit Bestätigungen, Integrationen Kalender, Zwischenablage, Wecker/Timer, Gedächtnis, Web-Suche; Audit-Log. *Fertig, wenn* "Trag mir morgen um 10 Tauchen ein" per Text mit Claude Haiku und einem OpenAI-kompatiblen Modell funktioniert.
3. **M2 Sprache und Assistent**: Push-to-talk, Silero VAD, Whisper über sherpa-onnx (Modell-Download), System-TTS, Overlay, Standard-Assistent über `VoiceInteractionService`, Obsidian-Integration. *Fertig, wenn* der lange Druck auf die Power-Taste die App öffnet und ein gesprochener Befehl eine Notiz im Vault ergänzt.
4. **M3 Routing, MCP, Erweiterung**: Regeln und Eskalation mit Editor, MCP-Client (Streamable HTTP, Bearer, OAuth), HTTP-Tools, Bring!, Integrationsauswahl mit App-Erkennung. *Fertig, wenn* "Claude, …" zu Claude routet und ein MCP-Server auf dem Homeserver über Tailscale Tools liefert.
5. **M4 Wake Word und TEE**: Wake Word im Foreground Service, Gesprächsmodus; `AttestedProvider` mit Phala, Rust-Prüfmodul, Prüfprotokoll-UI. *Fertig, wenn* das Wake Word bei ausgeschaltetem Bildschirm auslöst und jede Phala-Antwort einen grünen oder roten Prüfstatus hat.
6. **M5 iOS und Ausbau**: iOS-Build mit App Intents, Action Button, AlarmKit, EventKit, Bookmarks; Spotify, Wetter/Meer, Kontakte, Standort, Kamera, Aufgaben.

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
| K6 | 2026-10-13 | Eingebaute Integrationen | Neue Integration **Listen**: beliebig viele benannte Listen, jede mit eigener Ziel-Markdown-Datei auf dem Gerät; Tools zum Anzeigen, Hinzufügen, Abhaken, Entfernen; Einträge als Markdown-Checkboxen, damit die Dateien in Obsidian direkt nutzbar sind. Phase MVP (M1), Dateizugriff per Android-Dateiauswahl (SAF) | Wunsch Maintainer; Ergänzungen aus WP12: optionaler Abschnitt je Liste (wird angelegt), Aliase + Wortstamm-Ähnlichkeit statt Synonymliste, Rückfrage bei unsicheren Treffern für Schreib-Tools (Abhaken nimmt eindeutige Treffer), „Erledigte löschen“ behält Einträge mit offenen Unteraufgaben | offen |
| K7 | 2026-10-13 | Leitprinzipien, Sprach-Pipeline, Integrationen, Teststrategie | App läuft ohne Google Play Services: Standort über `LocationManager` statt Fused Location; TTS-Ausweichlösung sherpa-onnx, wenn keine System-Sprachausgabe installiert ist; System-Spracherkennung nur, wenn vorhanden (Whisper lokal bleibt Standard); Wecker über AOSP-Intents mit Benachrichtigungs-Fallback; E2E-Tests auf AOSP-Image ohne GMS | Wunsch Maintainer (entgoogelte Geräte) | bestätigt 2026-10-13 |
| K8 | 2026-10-13 | Agent-Schleife, Routing/Eskalation, Tool-System, Integrationen, Provider | (a) Tool-Namen der eingebauten Integrationen einheitlich `integration__aktion` (z. B. `memory__save`, `clipboard__read`, `web__search`); Meta-Tool heißt `tools__search`, greift ab 30 aktiven Tools (nach Datenschutzfilter), Freischaltung je Sitzung, aktive Tools bleiben direkt aufrufbar. (b) Risikostufen pro Tool lassen sich nur verschärfen, nie lockern. (c) Token-Budget je Anfrage: Summe über alle Modellaufrufe, Standard 50 000, Cache-Lesen zählt nicht. (d) Eskalation nur bei wiederholbaren Fehlern (nach 1 Retry); Datenschutz-Untergrenze ist die Stufe der ursprünglich gewählten (privaten) Route und bleibt über alle Eskalationen gleich; ein „Nein“ zur Eskalation unter diese Stufe gilt für die ganze Anfrage. (e) System-Prompt: stabiler Teil (Rolle, Regeln, Tools) zuerst, Datum/Uhrzeit/Gedächtnis danach (Prompt Caching); der Übergabe-Hinweis nach Eskalation nennt nur Tool-Namen und Status, keine Argumente (Prompt-Injection). (f) Anbieterspezifische Blöcke (z. B. Claudes serverseitige Web-Suche) als `ProviderBlock`: nur an denselben Anbieter zurück, nie vorgelesen; Suchergebnisse landen nicht im Antworttext. (g) Phala-Standardmodell: Bei `glm-5.3-flash` lässt sich Reasoning auf RedPill nicht sauber abschalten; Default wird per Modell-Eval gewählt, `qwen-2.5-7b-instruct` (TEE) funktioniert inkl. Tool-Calls. (h) Kalender: Serientermine werden nicht teilweise geändert (Zeitänderung an einer Serie wird abgelehnt mit Hinweis auf die Kalender-App), Löschen betrifft die ganze Serie und wird so angezeigt. (i) Gedächtnis: Gesundheit/Finanzen werden nicht inhaltlich erkannt; geschützt wird über Kategorien und „nur auf ausdrücklichen Wunsch“; Passwörter/PINs, Karten- und IBAN-Nummern werden abgewiesen. | Umsetzung Welle 2 (WP02–WP07) | offen |
| K9 | 2026-10-13 | UI/UX, Einstellungen | (a) Kosten werden in USD angezeigt (Preise liegen in USD vor, keine Umrechnung). (b) Rückfrage vor Eskalation unter die Datenschutzstufe nutzt die gelbe Bestätigungskarte (kein eigener Entwurf). (c) Bis M2 im Bestätigungs-Sheet „Antworte per Tipp“ statt Sprachhinweis. (d) „Alles löschen“ entfernt Verläufe und Prüfprotokoll; Gedächtnis, Einstellungen und Kostendaten bleiben; Aufbewahrungsfrist gilt auch für Verläufe. (e) Kein OAuth/PKCE-Login in M1 (vorbereitet). (f) Sprachwahl im Onboarding wird gespeichert, Oberfläche bleibt Deutsch bis zur Lokalisierung. (g) „sensibel“ ist je Integration vom Nutzer umschaltbar (Standard aus der Integration). | Umsetzung WP08/WP09 | offen |
| K10 | 2026-10-13 | Sicherheit/Datenfluss, Routing/Eskalation, Tool-System | (a) Tool-Katalog richtet sich nach der Datenschutzstufe des jeweiligen Ziels (auch nach Eskalation); Calls auf nicht sichtbare Tools werden abgelehnt und protokolliert; Tool-Suche zeigt nur Tools der Stufe. (b) Für Ziele, die ein Tool nicht sehen dürfen, wird nach dessen Ergebnis bis zur nächsten Nutzernachricht alles ausgeblendet (Text, Thinking, Provider-Blöcke, weitere Tool-Aufrufe samt Argumenten/Ergebnissen). (c) Enthält eine laufende Anfrage solche geschützten Ergebnisse, fragt die App vor jeder Eskalation auf ein Ziel ohne diese Tools nach, auch ohne private Route; „Nein“ beendet die Anfrage. (d) Gedächtnis-Einträge im System-Prompt nur, wenn alle Ziele der Kette die Gedächtnis-Integration sehen dürfen. (e) Restrisiko: Was der Nutzer selbst schreibt/kopiert, wird nicht ausgeblendet. (f) Bestätigungskarte zeigt die effektive Risikostufe; Bestätigungstexte dürfen live nachschlagen (Kalender). (g) Optionale Einrichtungsschritte: Web ohne Suchdienst bietet nur `web__fetch`. | Umsetzung/Review WP14 | offen |
