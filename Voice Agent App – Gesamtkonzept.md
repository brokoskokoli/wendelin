# Voice Agent App – Gesamtkonzept

Oct 12, 2026 · Maintainer

## Ziel und Leitprinzipien

Ziel ist ein persönlicher Sprachassistent für Android und iOS, der per Wake Word, Assistenten-Geste oder Button startet, lokal transkribiert und Befehle über ein frei wählbares LLM in Tool-Aufrufe auf dem Handy oder auf MCP-Servern übersetzt. Abgerechnet wird über eigene API-Keys bzw. Provider-Accounts, nicht über ein Chat-Abo; Gespräche landen in keinem Chat-Verlauf eines Anbieters.

**Leitprinzipien**

- **Alles ist ein Plugin.** LLM-Provider, Tools, Wake-Word-Engines, STT und TTS hängen jeweils an einer eigenen Schnittstelle mit Registry. Neue Fähigkeiten kommen ohne Umbau des Kerns dazu.
- **Provider-agnostisch.** Ein internes Nachrichten- und Tool-Format; Adapter übersetzen zu Anthropic, OpenAI-kompatiblen APIs und weiteren.
- **Lokal zuerst.** Wake Word, VAD und STT laufen auf dem Gerät. Bis zum Wake Word verlässt kein Audio das Handy, danach nur Text.
- **Ohne Google-Dienste lauffähig (K7).** Die App braucht keine Google Play Services; alles Pflichtige nutzt AOSP-Schnittstellen. Funktionen, die eine Fremd-App voraussetzen (System-TTS, System-Spracherkennung, Uhr-App), sind optional oder haben eine Ausweichlösung.
- **Datenschutz wählbar.** Neben normalen APIs gibt es TEE-Provider mit Attestierungsprüfung in der App und sichtbarem Prüfprotokoll.
- **Kontrolle beim Nutzer.** Jedes Tool hat eine Risikostufe; riskante Aktionen brauchen Bestätigung. Die App führt Tools aus, nie das Modell.
- **Günstig per Default, stark bei Bedarf.** Ein kleines Modell antwortet standardmäßig; Routing-Regeln oder „nochmal mit X“ wählen ein stärkeres, einen automatischen Wechsel gibt es nicht (K33, K100). Empfehlung je Rolle (gemessen): normal Claude Haiku 5.5, privat/TEE und Station Phala gemma-4-31b, Fallback gpt-5-mini bzw. Tinfoil gemma4-31b (K87).

**Scope**

| Bereich | MVP (v0.1–0.3) | Später |
| --- | --- | --- |
| Plattform | Android | iOS |
| Eingabe | Push-to-talk, Standard-Assistent | Wake Word, iOS Action Button, Siri-Intent |
| STT / TTS | Whisper lokal (sherpa-onnx), System-TTS | Cloud-STT optional, bessere Stimmen |
| Provider | Anthropic, OpenAI-kompatibel | TEE mit Attestierung, OAuth-Login, lokale Modelle |
| Tools | Kalender, Obsidian, Zwischenablage, Gedächtnis, Wecker/Timer, Web-Suche | Spotify, Kontakte/SMS, Standort, Wetter/Meer, Aufgaben (Kamera entfällt, K99) |
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

- Android: `VoiceInteractionService` (Standard-Assistent), Foreground Service vom Typ `microphone` für das Wake Word, Intents für Wecker/Timer, SAF-Ordnerzugriff, Spotify App Remote SDK. Mindestversion Android 10 (API 29), weil Assistentenrolle und Mikrofon-Diensttyp erst ab dort existieren (K42).
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
   - Android: **Wake Word** im Foreground Service (Typ `microphone`, permanente Benachrichtigung). Start nur aus dem Vordergrund; Hinweis zur Akku-Optimierung, dazu Einstellungen → Assistent → „Zuverlässig öffnen“ (Akku-Ausnahme, Hersteller-Checkliste); das Overlay zeigt beim Kaltstart „Wendelin startet …“ (K22). Ein Treffer schaltet den Bildschirm kurz ein, das Gerät bleibt gesperrt (K35). Optional nur aktiv beim Laden, im Auto (Bluetooth) oder in einem Zeitfenster. Wake Word und Befehl in einem Atemzug („Wendelin, mach …“): Der Dienst puffert höchstens 15 s weiter und übergibt an das Overlay, das Wake Word wird aus dem Transkript entfernt (K39). Ist der Chat sichtbar, setzt das Wake Word das App-Gespräch fort statt das Overlay zu öffnen (K55).
   - iOS: App Intent "Frag \<Name>" für Siri und Kurzbefehle, Action Button, Control im Kontrollzentrum bzw. Sperrbildschirm. Kein Dauerzuhören im Hintergrund.
2. **Wake-Word-Engine** (Interface `WakeWordEngine`)
   - Standard: zweistufig. Stufe 1 ist ein trainiertes Modell auf openWakeWord-Merkmalen bzw. der Vergleich mit eingelernten Stimm-Vorlagen, Stufe 2 prüft unsichere Treffer mit einem Prüfer (Vorlagen-Vergleich bzw. Erkenner); Vorlagen und Modell sind wählbar (K31, K117). sherpa-KWS ist nicht der Standard.
   - Eingelernt werden Stimm-Vorlagen („Wendelin lernt deine Stimme“) in den Einstellungen; gespeichert werden nur Merkmalsvektoren, keine Aufnahmen (K34). Eingelernt wird „Hey Wendelin“; eine Aufnahme gilt nur, wenn der Erkenner „hey“ + „Wendelin“ hört (K116). Angezeigt und genannt wird überall „Hey Wendelin“; vorerst wecken technisch beide Wörter (K115: Hey-Pflicht erst nach Messung mit echten Weckwort-Daten). Unsichere Erkennung geht nicht ans Modell: freihändig unter 0,5 still verworfen, bewusst ausgelöst unter 0,3 Nachfrage (K114).
   - Optional: openWakeWord (eigene Modelle trainierbar; vortrainierte Modelle nur nicht-kommerziell), Porcupine (AccessKey nötig).
   - Konfigurierbar: Status, Schalter (nur mit Assistentenrolle und eingelernter Stimme), „Nur beim Laden“/„Immer“, Bestätigungston, Nachprüfung; keine Empfindlichkeitsstufen (K36).
3. **Aufnahme und VAD**: Silero VAD (in sherpa-onnx enthalten) beendet die Aufnahme nach ca. 800 ms Stille, maximal 30 s. Pre-Roll-Puffer von 300 ms, damit das erste Wort nach dem Wake Word nicht abgeschnitten wird.
4. **STT** (Interface `SpeechToText`)
   - Standard: Whisper lokal über sherpa-onnx; Modellgröße wählbar (`base` schnell, `small` besser für Deutsch und Französisch; größere Modelle nach K64): wählbar Parakeet TDT 0.6B v3 (de-WER 3,9 %), Französisch optional Canary; Standard bleibt Whisper small; keine Rauschunterdrückung (K66). Modelle werden beim ersten Start heruntergeladen, nicht ins APK gepackt.
   - Sprache: automatisch erkennen oder fest einstellen (de, fr, en).
   - Alternativen: System-Spracherkennung (Android `SpeechRecognizer`, iOS `SpeechAnalyzer`; nur angeboten, wenn eine Erkennungs-App installiert ist, K7), optional Cloud-STT.
   - Ausgabe: Text + erkannte Sprache + Konfidenz (für die Routing-Regeln).
5. **TTS** (Interface `TextToSpeech`): Systemstimme als Standard; ist keine Sprachausgabe installiert (z. B. Gerät ohne Google), automatisch sherpa-onnx-Stimmen (offline, K7); optional Cloud-TTS. Antworten werden für Sprache gekürzt; lange Inhalte nur auf dem Bildschirm. Bei Sprach-Anfragen formuliert das Modell vorlesefreundlich (keine Aufzählungen/Tabellen, sprechbare Zahlen) und liefert optional einen eigenen Sprechtext (K19). Einstellung „Sprechfassung“: Aus (Standard), Immer, Geschützt, Mit KI-Prüfung (ein frischer Aufruf prüft, ob Sprech- und Anzeigetext übereinstimmen; fail-closed, K21). Offline-Stimmen (Piper, CC0): je Sprache eine weibliche und eine männliche, Download bei Bedarf, Probehören, wählbar je Sprache; dazu die deutschen Frauenstimmen Ramona und Eva (K38, K86). Standard Piper medium/low, wählbar Thorsten high und Kokoro (K66).

**Gesprächsmodus**: Nach einer Antwort kann die App 5 s weiter zuhören (Folgefrage ohne Wake Word). Das gesprochene „Stopp“/„Ende“ (aus dem Transkript) und Antippen beenden jederzeit (K107). In der App fragt eine einmalige Karte nach der ersten Antwort mit Rückfrage bzw. bei zwei Sprachanfragen innerhalb 2 min, ob der Gesprächsmodus gewünscht ist; Echo-Unterdrückung über die Aufnahmequelle (K25).

**Barge-in**: Während der Antwort unterbricht nur das Aktivierungswort (K107); ein eigenes Stopp-Wort entfällt. Es wird zweistufig erkannt (Kandidat, dann Prüfung mit Prüfer B gegen die eingelernten Vorlagen; der große Erkenner nur als Rückfall ohne Vorlagen oder wenn die Antwort selbst „Wendelin“ enthält, K124); die eigene Ausgabe wird per Echo-Unterdrückung und Textabgleich herausgefiltert; die Oberfläche zeigt, dass Wendelin mithört (K84). Die Antwort läuft immer als normale Assistenten-Ausgabe; den früheren Gesprächston (Telefonie-Pfad, K88) gibt es nicht mehr (K132).

**Sprechererkennung** (M5, standardmäßig aus): erkennt, wer spricht, für Personalisierung und risikoarme Aktionen auch bei gesperrtem Gerät; keine starke Authentifizierung (K32). Was bei gesperrtem Gerät mit erkannter Stimme läuft, bestimmt die Sicherheitsstufe B je Tool; Stufe B ist keine starke Authentifizierung, eine abgespielte Aufnahme kann sie täuschen (K123). Beliebig viele Personen mit Anrede, Gedächtnis und Standard-Agent (K54). Jede Person hat einen eigenen Gedächtnis-Namespace (wahlweise Standard), Löschen einer Person löscht ihre Einträge, eine andere bekannte Person startet eine neue Unterhaltung (K77).

## LLM-Provider-Schicht

Die App spricht intern nur ein eigenes Nachrichtenformat; Adapter übersetzen es pro API-Familie. Der Nutzer legt beliebig viele **Provider-Profile** an (z. B. "Claude API", "Phala GLM klein", "Ollama Homeserver") und wählt pro Profil ein Modell.

**Internes Format**

- `Message { role: system|user|assistant|tool, content: List<ContentBlock> }`
- `ContentBlock` = `Text` | `Image` | `ToolCall { id, name, argumentsJson }` | `ToolResult { callId, content, isError }` | `Thinking` (optional, nur Anzeige) | `ProviderBlock { provider, rawJson, summary? }` (K8: anbieterspezifische Blöcke wie Claudes serverseitige Web-Suche, werden nur an denselben Anbieter unverändert zurückgegeben, nie vorgelesen)
- `ToolSpec { name, description, inputSchema (JSON Schema) }`
- `ChatRequest { system, messages, tools, model, maxTokens, temperature, toolChoice, metadata }` (`system` als eigenes Feld, K5)
- `ChatEvent` (Stream) = `TextDelta` | `ThinkingDelta` | `ThinkingComplete` (K3) | `ToolCallDelta` | `ToolCallComplete` | `Usage` (4 Zähler inkl. Cache-Schreiben, als Zuwachs) | `Done { stopReason }` | `Error` (der Stream endet mit genau einem `Done` oder `Error`, K5)

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
| `OpenAiChatAdapter` | OpenAI, Mistral, OpenRouter, Phala, Tinfoil, NEAR AI, Privatemode (über Proxy), Ollama, LM Studio, vLLM | Base-URL + Key frei; Function Calling; Fähigkeiten pro Modell aus Katalog oder Test |
| `OpenAiResponsesAdapter` (später) | neuere OpenAI-Modelle | nur falls nötig |
| `GeminiAdapter` (später) | Google | optional |

TEE-Provider sind keine eigene API-Familie, sondern ein **Decorator** um einen Adapter (siehe nächster Abschnitt).

**Einrichtung (Dialog pro Provider)**

1. Provider-Typ wählen: Vorlagen für Claude, OpenAI, OpenRouter, Mistral, Phala, Tinfoil, NEAR AI, Ollama, "Eigener OpenAI-kompatibler Endpunkt".
2. Anmeldung je nach Typ: API-Key einfügen (mit Link zur Key-Seite des Anbieters), OAuth/PKCE wo der Anbieter das für Drittanbieter-Apps offiziell anbietet (z. B. OpenRouter), oder keine Auth (lokal).
3. Verbindungstest, Modelle laden, Standardmodell wählen (gemessene Empfehlungen oben als „Empfohlen“ markiert und vorausgewählt, freie Wahl bleibt, K100); Fähigkeiten (Tools, Vision) werden mit einem Mini-Tool-Call geprüft.
4. Optional: Budget pro Monat und Warnschwelle.

**Wichtig zu Abo-Logins**: Ein Login mit einem Claude-Pro/Max-Abo oder einem ChatGPT/Codex-Abo ist für eigene Apps kein offiziell vorgesehener Weg; Claude wird über einen Console-API-Key angebunden, OpenAI über einen Platform-API-Key. Die Auth-Schicht (`AuthMethod` = `ApiKey` | `OAuthPkce` | `None` | `CustomHeaders`) ist so gebaut, dass ein offizieller OAuth-Flow später nur ein weiteres Modul ist.

**Kosten**: Jede Antwort liefert `Usage`; die App rechnet mit Preisen aus dem Modellkatalog (vom Nutzer pflegbar) und zeigt Kosten pro Anfrage, Tag und Monat. Bei erreichtem Budget: Warnung oder Sperre, einstellbar.

## TEE-Provider und Attestierung

TEE-Provider laufen über den normalen OpenAI-kompatiblen Adapter, umhüllt von einem `AttestedProvider`-Decorator, der vor der Nutzung die Enklave prüft und nach jeder Antwort die signierte Quittung verifiziert. Geschwindigkeit geht vor Strenge, aber nicht bei Außenwirkung: Tools mit Undo laufen sofort, `external`-Tools erst nach grüner Quittung; ist sie nicht grün, werden die Aktionen zurückgenommen (K46). Der nächste Modellaufruf startet parallel zur Prüfung, seine Antwort wird sofort angezeigt und vorgelesen; bei roter Quittung wird sie verworfen und der Aufruf läuft sequentiell neu (K70).

**Interface**

```
abstract class AttestationVerifier {
  Future<AttestationResult> attest();                 // pro Sitzung, mit frischer Nonce
  Future<ReceiptResult> verifyReceipt(ReceiptRef ref,  // pro Antwort
      Uint8List requestBytes, Uint8List responseBytes);
}
```

Implementierungen: `PhalaVerifier` zuerst, dazu NEAR-AI- und Tinfoil-Verifier; `PrivatemodeVerifier` später. NEAR AI Cloud ist zweiter TEE-Anbieter neben Phala: nur NEAR-eigene Modelle, E2EE auch für Tools, Attestierung TDX + NVIDIA, TLS-Pin; Gateway-TCB „OutOfDate“ nur Hinweis, Sitzung 30 min (K45). Tinfoil: Rückschrittschutz (höchste je gesehene Release-Version, fail-closed), keine Quittung je Antwort, daher Info-Stufe „keine Quittung“ und kein paralleler Modellaufruf (K73). Die kryptografische Prüfung (TDX-Quote gegen Intel DCAP, Signaturen) liegt in einem Rust-Modul, angebunden über flutter\_rust\_bridge.

**Ablauf am Beispiel Phala**

1. Modelle über `GET /v1/models` laden und nur solche mit `is_tee: true` zur Auswahl anbieten.
2. Sitzungsstart: zufällige Nonce (32 Byte) → `GET /v1/aci/attestation?nonce=…` (Gateway) bzw. `GET /v1/attestation/report?model=…&nonce=…` (inkl. NVIDIA-GPU-Evidenz), Base-URL `https://api.redpill.ai/v1` (K2).
3. Prüfen: TDX-Quote gegen DCAP-Kollateral; Report-Daten binden Nonce und Workload-Keyset; Keyset-Signatur unter dem Workload-Identity-Key; Keyset-`not_after` in der Zukunft (ein Feld `freshness.stale_after` gibt es nicht, K2); optional GPU-Evidenz (`nvidia_payload`); optional `source_provenance` (`repo_url`, `repo_commit`) gegen eine Liste vertrauenswürdiger Releases.
4. **Pinning**: `workload_keyset_digest` und `source_provenance.repo_commit` speichern (ein `workload_id` liefert die API nicht, K2). Ändern sie sich, neue Attestierung und Hinweis an den Nutzer ("Anbieter hat ein Update ausgerollt, neu geprüft"). TLS terminiert in der Enklave (`downstream_tls_binding`, `tls_public_keys`): TLS-Verbindung auf den SPKI-Hash aus dem Keyset pinnen, erzwungen und fail-closed (K37, WP61).
5. Pro Antwort: `x-receipt-id` lesen → `GET /v1/aci/receipts/{id}` → Ed25519-Signatur gegen `receipt_signing_keys` (signiert ist die Quittung ohne `signature` als JSON mit sortierten Schlüsseln, kompakt), `body_hash` von `request.received`/`response.returned` gegen die exakt gesendeten bzw. empfangenen Bytes, Eintrag `upstream.verified` mit `result: verified`. Im Test war `required: false` – wie `required: true` erzwungen wird, ist zu klären (K2).

**Fehlerverhalten**

| Situation | Verhalten |
| --- | --- |
| Attestierung schlägt fehl | Provider gesperrt, Fehlermeldung, kein Request wird gesendet; die Anfrage geht nie an einen anderen Anbieter, auch nicht nach Rückfrage, sie endet rot mit Grund; „Ohne GPU-Prüfung senden“ (nur diese Anfrage, derselbe Knoten) bleibt erlaubt (K27) |
| Quittung ungültig oder nicht verifiziert | Rotes Symbol am Gesprächsschritt, Warnung, Eintrag im Prüfprotokoll; weitere Anfragen an diesen Provider gesperrt bis zur neuen Attestierung; ein parallel gestarteter Folgeaufruf wird verworfen (Text zurückgesetzt, Tokens zählen zum Budget), Undo der laufenden Tools, dann sequentieller Neuaufruf (K70) |
| Quittung nicht abrufbar (Netzwerk) | Gelbes Symbol, bis zu 6 Versuche (~24 s); danach grau „nicht bestätigt“, der Anbieter wird nicht gesperrt, `external`-Tools laufen trotzdem nicht; gesperrt (rot) wird nur bei echten Prüffehlern (K44) |
| Pinning-Wechsel | Neue Attestierung erzwingen, Nutzer informieren |

Das Overlay wärmt die Attestierung beim Öffnen vor; geprüfte Sitzungen bleiben beim Profil-Neuaufbau erhalten (K46). Fehlt der GPU-Nachweis beim Anbieter, zeigt die App „kein Nachweis“ (K46).

**Prüfprotokoll (UI)**: Liste pro Anfrage mit Zeit, Provider, Modell, `workload_id`, Commit bzw. Image-Digest, Ergebnis jeder Prüfstufe und Quittungs-ID; Statusanzeige grün / gelb / rot im Gespräch. Exportierbar als JSON, nur eine Positivliste fester Felder, keine Texte, Argumente oder Beschreibungen (K43).

**Hinweise**: Streaming-Antworten werden erst nach Ende des Streams geprüft. GPU-Attestierung (NVIDIA Hopper) ist im Report enthalten, wenn das Modell angegeben wird (K2). Anfragen, die nicht verifiziert werden können, dürfen keine sensiblen Folgeaktionen auslösen (z. B. keine SMS).

## Routing und Eskalation

Ein Default-Provider beantwortet alles; eine geordnete Regelliste wählt vor dem Start einen anderen Provider. Nach Fehlern wechselt die App nie automatisch (K33, K100).

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

**Fehler und Wechsel** (K33, K100, K104): Nach Fehlern gibt es einen Retry beim selben Ziel, dann eine Fehlermeldung mit Grund. Ein Wechsel geschieht nur auf Wunsch („nochmal mit X“) oder nach Rückfrage: Fällt ein Anbieter aus, fragt die App „Mit <Anbieter> nochmal?“, nur bei eingerichteten Anbietern mit mindestens gleicher Datenschutzstufe (`local` > `tee` > `eu` > `standard`); die Sprachantwort muss ein klares Ja sein (K100). Das Angebot erscheint nur bei Zeitüberschreitung, 5xx, Netzwerkfehler und TEE-Prüffehler, nicht bei 4xx/429, Abbruch, Budget oder GPU-Prüffehler; die Datenschutz-Untergrenze des Laufs bleibt (K104). Bereits ausgeführte Tools werden nie wiederholt; jeder Wechsel erscheint im Gespräch und im Log.

**Regel-Editor**: Regeln als Liste mit Drag-and-drop, Bedingungen per Baukasten, Testfeld ("welche Regel greift für diesen Satz?"). Speicherung als JSON, import- und exportierbar.

## Agent-Schleife

Die Agent-Schleife ist provider-unabhängig: Sie baut den Kontext, ruft das gewählte Modell, führt angeforderte Tools über die Registry aus und wiederholt, bis eine Endantwort kommt oder ein Limit greift.

**Ablauf einer Anfrage**

1. **Kontext bauen**: System-Prompt mit Datum, Uhrzeit, Zeitzone, Gerätesprache, Name des Nutzers; relevante Einträge aus dem Gedächtnis; aktive Tool-Specs (nur aktivierte Integrationen); kurzer Gesprächsverlauf (letzte N Züge der aktuellen Sitzung).
2. **Routing**: Regeln wählen Provider und Modell.
3. **Modellaufruf** mit Streaming; Text wird live angezeigt, für TTS satzweise gepuffert.
4. **Tool-Calls**: Für jeden Call prüft der `ToolExecutor` Risikostufe und Berechtigung. Stufe `confirm` zeigt eine Bestätigungskarte (Sprache: "Soll ich das so eintragen?" – Antwort ja/nein per Stimme oder Tap). Unabhängige Calls laufen parallel. Nach Abbruch gelten offene Bestätigungen als abgelehnt und es startet kein Tool mehr; Bestätigungen laufen nacheinander (K5).
5. **Ergebnisse** gehen als `ToolResult` zurück an das Modell; Fehler als `isError` mit lesbarer Meldung, damit das Modell reagieren kann.
6. **Wiederholen** bis `stopReason = endTurn` oder Limit: max. 8 Tool-Runden, max. 60 s Gesamtdauer, Token-Budget pro Anfrage; der dritte gleiche Fehlaufruf (Werkzeug und Argumente) bricht ab, Zahl-Strings werden bei Zahl-Parametern normalisiert, und der Nutzer hört bei jedem Abbruch nur einen allgemeinen Fehlertext, der Grund steht im Log (K121).
7. **Abschluss**: Antwort per TTS (gekürzt) und Bildschirm; Usage und Kosten speichern; bei TEE: Quittung parallel zum nächsten Modellaufruf prüfen, dessen Quittungs- und Tool-Ereignisse erst nach Grün, Abbruch wartet nicht auf die Quittung (K70); Gedächtnis-Kandidaten markieren. Nach eindeutigen, erfolgreichen Aktionen (Taschenlampe, Wecker, Liste, SMS) bildet die App den Antwortsatz aus einer festen Vorlage je Tool und Sprache, ohne zweiten Modellaufruf; Fehler, Rückfragen und Lese-Tools gehen weiter ans Modell (K94).

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

**Tool-Auswahl bei vielen Tools**: Ab ca. 30 aktiven Tools schickt die App vor dem ersten Aufruf die Tools der per Wortliste erkannten Integrationen (höchstens ~3, Wortlisten je Sprache) direkt mit; `tools__search` bleibt Fallback, der Datenschutzfilter bleibt unverändert (K89). Spart Tokens und hilft kleinen Modellen bei der richtigen Wahl.

**Prompt Caching**: System-Prompt und Tool-Specs stehen stabil am Anfang des Kontexts, damit Provider mit Caching (Anthropic, einige OpenAI-kompatible) sie günstig wiederverwenden.

**Sitzungen**: Eine Sitzung endet nach 5 min Inaktivität, im App-Chat auch, wenn das Fenster 1 min oder länger nicht sichtbar war (auch nach App-Kill, K125), oder auf Befehl ("neues Thema", wird vor dem Routing abgefangen und nie ans Modell gesendet, K18). Jeder Aufruf des Assistenten-Overlays beginnt ein leeres Gespräch; Folgefragen und Entsperren gehören zum selben Aufruf, der App-Chat setzt nie eine Overlay-Sitzung fort (K41). Verläufe bleiben lokal in SQLite und sind durchsuchbar; Aufbewahrungsdauer einstellbar.

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

Pro Tool überschreibbar. Zusätzlich hat jedes Tool und jedes HA-Gerät eine Sicherheitsstufe: A immer, B erkannte Stimme, C entsperrt, D entsperrt mit Bestätigung. Der Standard ist die Empfehlung (confirm/external = D, Licht/Medien/unkritische Szenen = B), frei lockerbar mit Hinweis bei gefährlichen Geräten, sensitiven Integrationen und external; fehlt die Stufe, gilt D (K123). `external`-Tools laufen bei TEE nie vor grüner Quittung (K46, K70); schlägt sie fehl (rot, auch bei geändertem Pin), sind sie für den Rest der Unterhaltung gesperrt, auch über Neustart, bis zum Ende der Unterhaltung oder einer grünen Neuprüfung (K122); ist sie nur nicht abrufbar (grau), laufen sie in dieser Runde nicht (K44). Nach fremden Inhalten (Websuche, Webabruf, Zwischenablage, HTTP-/MCP-Tools mit Haken „Kann unsichere Inhalte enthalten“) brauchen Tools mit Netzziel eine Rückfrage, zusätzlich zur Sicherheitsstufe; Notizen, Listen, Kalender, Kontakte, HA und strukturierte Daten gelten als sicher (K122).

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
| Wecker und Timer | `set_alarm` (w), `set_timer` (w), `list_alarms` (r, wo möglich) | `AlarmClock`-Intents / AlarmKit (iOS 26+), sonst Benachrichtigung; unter Android liefert `alarms__list` nur den nächsten Wecker (K89) | MVP |
| Erinnerungen | `remind_at` (w), `remind_when_arriving` (w, später), `list_reminders` (r) | Exakte lokale Benachrichtigung (`SCHEDULE_EXACT_ALARM`) / EventKit-Erinnerungen | v0.2 |
| Web | `web_search` (r), `web_fetch` (r) | Bei Claude die serverseitigen Tools; sonst Brave Search, Tavily oder eigenes SearXNG auf dem Homeserver | MVP |
| Bring! Einkaufsliste | `list_lists` (r), `get_items` (r), `add_items` (w, mit Mengenangabe), `remove_item` (w), `complete_item` (w) | Inoffizielle Bring!-API (wie in der Home-Assistant-Integration genutzt); einmaliger Login mit Bring!-Konto, gespeichert werden nur Sitzungs-Tokens, kein Passwort; abgelehnter Refresh-Token führt zu „Bitte neu anmelden“ (K75); kann jederzeit brechen, daher eigenes Modul mit Fehleranzeige | v0.2 |
| Spotify | `search` (r), `play` (w: Playlist, Album, Titel, Künstler), `pause` / `next` / `previous` (w), `now_playing` (r), `queue_add` (w) | Web API mit OAuth/PKCE (Wiedergabesteuerung setzt Spotify Premium voraus); App Remote SDK bzw. iOS SDK, um die Spotify-App aufzuwecken, falls kein aktives Gerät | v0.3 |
| Wetter und Meer | `weather_forecast` (r), `marine_forecast` (r: Wellenhöhe, Dünung, Wassertemperatur) | Wetter: Open-Meteo (Standard), Bright Sky (DWD) oder MET Norway wählbar; Meer nur Open-Meteo. Ort: aus der Frage, sonst Standort, sonst Heimatort (K50) | v0.3 |
| Kontakte (Integration `contacts`, K49) | `find_contact` (r) | Contacts-Provider / Contacts-Framework | v0.3 |
| Nachrichten und Anrufe | `sms__compose` (e), `phone__call` (e) | Vorschau-Popup in der App (Kontakt, editierbarer Text), wird vorgelesen; ausgeführt erst nach Tipp oder gesprochener Bestätigung, bei gesperrtem Gerät nie; undeutliche Antwort führt nicht aus (K49) | v0.3 |
| Standort und Navigation | `current_location` (r), `navigate_to` (w), `distance_to` (r) | Android `LocationManager` (kein Fused Location, K7) / CoreLocation; Geo-Intents bzw. Karten-URLs; `distance_to` nimmt das Ziel als Text „lat,lon“; Wetter nutzt die Geräteposition nur bei erfüllter Datenschutz-Mindeststufe, Koordinaten auf 2 Nachkommastellen (K67) | v0.3 |
| Google Maps (K15) | `maps__navigate` (w), `maps__search_place` (r) | Adapter auf die Google-Maps-App per Intent (`google.navigation:`/Maps-URLs), nur wenn installiert (App-Erkennung, K7: keine Play-Services-Pflicht); ohne Google Maps übernimmt `navigate_to` mit `geo:`-Intent (Organic Maps, OsmAnd), ohne Routenführung; `maps__route_info` entfällt (ohne Google-API-Key nicht machbar, K67) | M5 |
| Taschenlampe (K16) | `flashlight__on` (w), `flashlight__off` (w), `flashlight__toggle` (w) | `CameraManager.setTorchMode` (ohne Kamera-Berechtigung, ohne Google-Dienste) / `AVCaptureDevice` Torch; Undo = Gegenschalten; ohne Bestätigung; auch auf dem Sperrbildschirm ohne Entsperren (K16); dort hört das Overlay zu und schaltet die Taschenlampe lokal über Policy und Executor; ein Modell läuft nur, wenn weitere Tools gesperrt erlaubt sind, und nur mit diesen, ohne Namen, Verlauf und Sitzung, sonst „Bitte entsperre das Telefon“ (K30, K123); Gnadenfrist nach dem Entsperren 1,5 s, eine gemerkte Anfrage gilt 30 s und wird nach dem Entsperren auch vorgelesen, die gemerkte Anfrage nur, wenn gesperrt nichts lief (K92, K123) | M4 |
| Apps und Links | `open_app` (w), `open_url` (w) | Intents / URL-Schemes; Liste erlaubter Apps einstellbar | v0.3 |
| Aufgaben | `tasks__add` (w), `tasks__list` (r), `tasks__complete` (w) | Auf Basis der Listen (Obsidian-Tasks-Format mit Fälligkeit/Priorität, Uhrzeit `⏰ HH:MM`), Einstellung „Standard-Aufgabenliste“; Todoist (API-Token) und Google Tasks (OAuth) als eigene Integrationen (K51, K61) | M5 |
| Mediensteuerung | `media__next` / `media__previous` (w) u. a. | Allgemeine Steuerung der aktiven Medien-Session über Benachrichtigungszugriff; Audible nur öffnen/suchen per Intent, keine inoffiziellen APIs (K52); andere Wiedergabe wird während der Antwort leiser (Audiofokus „ducking“), `next`/`previous` ohne Nachfrage und ohne Undo (K65) | M5 |
| Home Assistant | Entitäten je Domain (Licht, Szenen, Schalter, Medien, Klima, Schloss …) | Heimnetz/Tailscale, Token, freigegebene Entitäten; Licht, Szenen, Medien, Klima ohne Nachfrage mit Undo, Schloss/Alarm/Garage/Tor immer bestätigen, Rollläden je Gerät optional ohne Rückfrage; `http` nur für private/Tailscale-Adressen (K53, K108). Schalter laufen mit Undo, je Entität „immer bestätigen“; Szenen mit Schloss/Alarm/Cover nur mit Bestätigung, bei gesperrtem Gerät nicht freigegeben (K57). Das Modell bekommt die freigegebenen Geräte kompakt, Gerätetyp-Synonyme je Sprache; Schnellweg ohne Modell nur für eindeutige einfache Befehle, nie für Schloss/Alarm/Garage/Tor, abschaltbar (K108) | M5 |
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
- Risikostufe aus den MCP-Tool-Annotationen: `readOnlyHint` → read, `destructiveHint` → external, sonst write. Pro Tool überschreibbar; Hinweise des Servers lassen sich nur verschärfen, ein Schalter „alle Tools bestätigen“ ist möglich (K12).
- MCP- und HTTP-Tools haben kein Undo; nach einem geschützten Ergebnis brauchen weitere MCP-/HTTP-Aufrufe in derselben Anfrage eine Bestätigung. Klartext-`http` nur zu Heimnetz/Tailscale (private Bereiche, `100.64.0.0/10`, `*.ts.net`), sonst `https`; HTTP-Tools nur zum gespeicherten Host (K12).
- Pro Server und pro Tool an- und abschaltbar; nur aktive Tools gehen ans Modell.
- Ergebnisse (Text, JSON, Bilder) werden ins interne `ToolResult` übersetzt; sehr lange Ergebnisse werden gekürzt und die Kürzung markiert.

**Alternative für Claude**: Bei öffentlich erreichbaren Servern kann der Anthropic-Adapter optional den Remote-MCP-Connector der API nutzen; dann ruft Anthropic den Server direkt auf. Standard bleibt der eigene Client, damit alle Provider gleich funktionieren.

**Empfohlene Server für den Start**

| Zweck | Server | Hinweis |
| --- | --- | --- |
| Obsidian auf dem Desktop | MCP-Endpunkt des Obsidian-Plugins Local REST API oder cyanheads/obsidian-mcp-server | Nur nötig, wenn der Vault nicht direkt auf dem Handy bearbeitet werden soll |
| Kalender per CalDAV | dav-mcp (HTTP, Bearer-Token) | Alternative zum Gerätekalender, z. B. für Kalender auf dem Homeserver |
| Smart Home | MCP-Server-Integration von Home Assistant | Licht, Szenen, Sensoren; alternativ die eigene Integration Home Assistant (K53) |
| Homeserver | eigener Server für Git, Docker-Status, Shell mit Whitelist | Shell-Tools immer `external` |

**Vorlagen**: In den Einstellungen gibt es Vorlagen für bekannte Server (Name, URL-Muster, Auth-Art) und einen Freitext-Eintrag für beliebige Server. Konfiguration ist exportierbar, damit sie auf ein zweites Gerät übertragen werden kann (ohne Secrets).

## Sicherheit, Datenschutz und Logging

Alle Secrets liegen im Android Keystore bzw. iOS Keychain, alle Verläufe nur lokal, und jeder Datenabfluss an einen Provider ist im Log nachvollziehbar.

**Secrets**

- API-Keys, OAuth-Tokens (Spotify, MCP, Provider) und Bring!-Sitzungs-Tokens (kein Passwort, K75) nur in `flutter_secure_storage`; nie in SQLite, Logs oder Exporten.
- Optional App-Sperre per Biometrie für Einstellungen und Verlauf.
- Keys werden nie ins APK gebaut; die App funktioniert ohne eigenen Backend-Server.

**Datenfluss**

- Audio verlässt das Gerät nie, außer der Nutzer wählt Cloud-STT oder Cloud-TTS aktiv.
- An den LLM-Provider gehen: Transkript, System-Prompt, ausgewählte Gedächtnis-Einträge, Tool-Specs und Tool-Ergebnisse. Die App zeigt pro Provider die Datenschutzstufe (`local`, `tee`, `eu`, `standard`).
- Integrationen können als "sensibel" markiert werden (z. B. Kontakte, Standort); ihre Tools werden nur an Provider ab Stufe `tee` geschickt, wenn der Nutzer das einstellt.
- Tool-Ergebnisse werden vor dem Senden gekürzt (z. B. Kalender: nur Titel, Zeit, Ort; keine Teilnehmerlisten, außer angefragt).

**Prompt-Injection**

- Inhalte aus Notizen, Webseiten, Einkaufslisten und MCP-Ergebnissen sind Daten, keine Anweisungen. Der System-Prompt sagt das ausdrücklich, und `external`-Tools brauchen immer eine Bestätigung, egal was in den Daten steht. Ein Sprechtext vom Modell wird nur vorgelesen, wenn die Unterhaltung keine fremden Inhalte enthält (Marker `TrustedContentSource`, fail-closed, K20).
- MCP-Server und HTTP-Tools sind nur nach expliziter Einrichtung durch den Nutzer aktiv.

**Logging**

- Audit-Log (SQLite): Zeit, Auslöser, Transkript, Routing-Entscheidung, Provider und Modell, jeder Tool-Call mit Argumenten und Ergebnis-Status, Bestätigungen, Eskalationen, Kosten, TEE-Prüfergebnis.
- Aufbewahrung einstellbar (Standard 30 Tage), komplett löschbar, Export als JSON ohne Texte und Argumente (K43).
- Ausnahme Entwicklermodus (bewusst eingeschaltet): Inhalte im Log und WAV-Ausschnitte lokal für höchstens 1 Tag, Zugangsdaten geschwärzt (K120); dazu ein Weckwort-Archiv als Trainingsdaten (Treffer nur mit Vorlauf, ohne Befehl), bis 1 GB, ohne Ablauf; beim Ausschalten werden die Dev-Aufnahmen gelöscht, das Archiv nur nach Rückfrage (K126).
- Debug-Log getrennt davon, standardmäßig aus; enthält nie Secrets.

**Berechtigungen**: Jede Android- bzw. iOS-Berechtigung wird erst angefragt, wenn die zugehörige Integration aktiviert wird, mit einer kurzen Erklärung davor.

## UI/UX und Einstellungen

Die App ist in erster Linie ein Sprach-Overlay; der Hauptbildschirm zeigt Verlauf und Status, die Einstellungen sind der eigentliche Konfigurationskern.

**Oberflächen**

- **Assistenten-Overlay** (halber Bildschirm über anderen Apps, ausgelöst durch Wake Word oder Assistenten-Geste): Wellenform während der Aufnahme, Live-Transkript, Antwort, Tool-Karten ("Termin angelegt – Rückgängig"), Bestätigungskarten, kleines Symbol für Provider und Prüfstatus.
- **Hauptbildschirm**: Gesprächsverlauf, Texteingabe als Alternative zur Sprache, Mikrofon-Button, aktiver Provider. Langer Druck auf den Agenten oben öffnet den Schnellwechsel; die Auswahl wird Standard mit leerem Chat (K55).
- **Onboarding**: Sprache, erster Provider (Key einfügen, testen), Whisper-Modell herunterladen, Integrationen auswählen, optional Standard-Assistent setzen.
- **Widget und Schnellkachel** (Android), Control und Action-Button-Unterstützung (iOS).

**Stationsmodus** (M6, K62/K63): Das Handy liegt am Ladegerät und arbeitet wie ein Lautsprecher mit Display.

- **Start nur manuell:** Button auf dem Hauptbildschirm, Schnellkachel oder Sprachbefehl „Stationsmodus“ (eigene Integration `station`, standardmäßig aus; bei entsperrtem Gerät). Die Kachel verlangt bei gesperrtem Gerät zuerst das Entsperren (K82). Kein automatischer Start beim Laden.
- **Ende:** Button „Beenden“, der das Entsperren verlangt. Danach ist das Gerät entsperrt (ohne Device-Admin nicht erzwingbar, K82). Abstecken oder ein Sprachbefehl beenden den Modus nicht.
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
  - „immer an, gedimmt“ (Standard): Helligkeit nach Umgebungslicht (normal/gedämpft per Lichtsensor, K82), Inhalt wandert leicht gegen Einbrennen
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
| Routing | Default-Provider, Regelliste mit Editor und Testfeld |
| Integrationen | Liste aller Integrationen mit Zustand (nicht verfügbar, verfügbar, Einrichtung nötig, aktiv, Fehler); Schalter; Einrichtungsassistent pro Integration; einzelne Tools an/aus; Risikostufen |
| MCP-Server | Server hinzufügen (Vorlage oder frei), Auth, Status, Tool-Liste |
| HTTP-Tools | eigene Tools definieren und testen |
| Sprache | Wake Word (Status, Schalter, „Nur beim Laden“/„Immer“, Bestätigungston, Nachprüfung, Stimme einlernen, K34, K36), aktive Zeiten; STT-Engine und Modell; Sprache; TTS-Stimme und Tempo; Sprechfassung (K21); Gesprächsmodus |
| Assistent | Standard-Assistent setzen (Link zu den Systemeinstellungen), Name des Assistenten, Persönlichkeit / System-Prompt-Zusatz |
| Gedächtnis | Einträge ansehen, bearbeiten, löschen; automatische Vorschläge an/aus; Spiegelung in Obsidian |
| Datenschutz und Logs | Aufbewahrung, Prüfprotokoll, Audit-Log, Export, alles löschen |
| Kosten | Verbrauch pro Provider und Monat |

**Integrationen auswählen** (Wunsch aus dem Gespräch): Beim Onboarding und in den Einstellungen sieht der Nutzer nur Integrationen, die auf seiner Plattform möglich sind. Solche, deren App fehlt, erscheinen ausgegraut mit Hinweis "App nicht installiert". Erst nach dem Aktivieren werden Berechtigungen angefragt bzw. Logins durchgeführt. Deaktivierte Integrationen kosten keine Tokens, weil ihre Tools nicht ans Modell gehen.

**Barrierefreiheit und Sprache**: UI-Sprache System/Deutsch/Englisch/Französisch (Flutter-Lokalisierung), nicht unterstützte Systemsprache wird Englisch; Sprechtexte und Befehle folgen der Sprech-Sprache (K60); große Touch-Ziele im Overlay; alles auch ohne Sprache per Text bedienbar.

## Umsetzung: Struktur, Roadmap, Tests

Umgesetzt wird in sechs Meilensteinen, Android zuerst; jeder Meilenstein endet mit einer benutzbaren App.

**Projektstruktur** (geändert, siehe Änderungsprotokoll K1)

```
wendelin/
  packages/                    # reine Dart-Pakete, einzeln testbar (ADR 0001)
    wendelin_core/             # Nachrichtenformat, Interfaces (LlmProvider, Tool, Integration, AgentRun), Events, Fakes
    wendelin_providers/        # anthropic/, openai/, Modellkatalog, Kosten (später tee/)
    wendelin_tools/            # ToolRegistry, ToolExecutor, Risiko, Undo (später http_tool/, mcp/)
    wendelin_agent/            # Agent-Schleife, Kontext, Limits, Retry (später Routing-Regeln)
    wendelin_storage/          # drift-Datenbank, Repositories, SecretStore-Interface, Audit-Log
    wendelin_integrations/     # calendar/, clipboard/, alarms/, memory/, web/ … über Ports
  app/                         # Flutter-App: UI, Riverpod-Verdrahtung, Plattform-Ports
    android/  ios/             # native Teile
  native/attest/               # Rust-Crate: DCAP-Quote, Signaturen (flutter_rust_bridge)
  evals/                       # Testsätze und Auswertung pro Provider-Profil
  docs/                        # Design, ADRs, Arbeitspakete, Notizen
```

**Meilensteine** (Umsetzungsstand: `docs/work-packages/STATUS.md`; Stand 2026-10-26: M0–M4 erledigt, M5/M6 in Arbeit, M7 zurückgestellt, K99)

1. **M0 Gerüst**: Flutter-Projekt, Riverpod, drift, Secure Storage, Kern-Interfaces (`LlmProvider`, `Integration`, `Tool`, `AgentRun`) mit Fake-Implementierungen; Text-Chat-UI. *Fertig, wenn* ein Fake-Provider einen Fake-Tool-Call auslöst und das Ergebnis angezeigt wird.
2. **M1 Text-Agent (Android)**: Anthropic- und OpenAI-kompatibler Adapter, Provider-Einrichtung mit Test, Agent-Schleife mit Bestätigungen, Integrationen Kalender, Zwischenablage, Wecker/Timer, Gedächtnis, Web-Suche; Audit-Log. *Fertig, wenn* "Trag mir morgen um 10 Tauchen ein" per Text mit Claude Haiku und einem OpenAI-kompatiblen Modell funktioniert.
3. **M2 Sprache und Assistent**: Push-to-talk, Silero VAD, Whisper über sherpa-onnx (Modell-Download), System-TTS, Overlay, Standard-Assistent über `VoiceInteractionService`, Obsidian-Integration. *Fertig, wenn* der lange Druck auf die Power-Taste die App öffnet und ein gesprochener Befehl eine Notiz im Vault ergänzt.
4. **M3 Routing, MCP, Erweiterung**: Regeln mit Editor (Eskalationsketten entfielen, K33), MCP-Client (Streamable HTTP, Bearer, OAuth), HTTP-Tools, Bring!, Integrationsauswahl mit App-Erkennung. *Fertig, wenn* "Claude, …" zu Claude routet und ein MCP-Server auf dem Homeserver über Tailscale Tools liefert.
5. **M4 Wake Word und TEE**: Wake Word im Foreground Service, Gesprächsmodus; `AttestedProvider` mit Phala, Rust-Prüfmodul, Prüfprotokoll-UI. *Fertig, wenn* das Wake Word bei ausgeschaltetem Bildschirm auslöst und jede Phala-Antwort einen grünen oder roten Prüfstatus hat.
6. **M5 Ausbau (Android)** (K48): App-Sprache, Spotify, Wetter/Meer (wählbarer Dienst), Mediensteuerung, Kontakte/SMS/Anrufe mit Vorschau, Standort/Google Maps, Aufgaben (Listen mit Fälligkeit), Todoist/Google Tasks, Home Assistant, Sprechererkennung, Wake Word im Chat, Schnellwechsel des Agenten (Plan: `docs/work-packages/M5-PLAN.md`).
7. **M6 Ausbau 2 (Android)**: Stationsmodus, Vergleich alternativer Wake Words, Empfehlung von Modellen (Evals live).
8. **M7 iOS** (zurückgestellt, bis die Android-Version komplett und rund ist, K99): iOS-Build mit App Intents, Action Button, AlarmKit, EventKit, Bookmarks.

**Teststrategie**

- Unit-Tests für Adapter mit aufgezeichneten Antworten (Streaming, Tool-Calls, Fehler) je Provider.
- Agent-Schleife mit Fake-Provider: Limits, Abbruch, Bestätigungen, Retry und Wechsel ohne doppelte Tool-Ausführung.
- Routing: Tabellentests "Satz → erwartete Regel".
- **Modell-Eval**: 30–50 typische Befehle (Deutsch, Französisch, Englisch) mit erwarteten Tool-Calls; Kommando, das ein Provider-Profil dagegen laufen lässt und Trefferquote, Latenz und Kosten ausgibt. Grundlage für die Wahl des Default-Modells.
- STT: kurze eigene Aufnahmen als Fixtures, Wortfehlerrate pro Modellgröße.
- Integrationstests auf Emulator bzw. Gerät für Kalender, SAF und Intents – auf einem AOSP-Image **ohne** Google Play Services (K7).

**Offene Fragen**

- Ist mit "Jiggler" Flutter gemeint? Falls Kotlin Multiplatform, Abschnitt Plattform anpassen.
- Phala: TLS terminiert in der Enklave, GPU-Attestierung ist enthalten (geklärt, K2). Offen: Ableitung von `report_data` aus der Nonce beim Gateway-Endpunkt, Erzwingen von `required: true`, Performance der DCAP-Prüfung auf dem Handy.
- Bring!: Inoffizielle API, Nutzungsbedingungen prüfen; Fallback über Share-Intent in die Bring!-App.
- Spotify: Entwickler-App im Entwicklungsmodus reicht für den Eigengebrauch; für eine Veröffentlichung Freigabe nötig.
- Verteilung: entschieden – nur privat (K102, K103): Release-APK mit eigenem Zertifikat, später Varianten frei/Store.
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

Bestätigte Einträge stehen im Archiv `docs/concept-changelog/` (eine Datei je Meilenstein, Übersicht in der README dort); hier bleiben die offenen, zurückgestellten und teilweise bestätigten Einträge.

| Nr. | Datum | Abschnitt | Änderung | Grund | Status |
| --- | --- | --- | --- | --- | --- |
| K15 | 2026-10-13 | Eingebaute Integrationen | Neue Integration **Google Maps** als Adapter: Navigation, Ortssuche und Routeninfo über die Google-Maps-App (Intent) bzw. optional die Maps-API mit eigenem Key; nur aktiv, wenn die App installiert bzw. ein Key hinterlegt ist, damit K7 (ohne Google-Dienste lauffähig) erhalten bleibt. Zeitpunkt noch offen (nach M4). | Wunsch Maintainer | bestätigt 2026-10-13 (Aufnahme), Umfang offen |
| K21 | 2026-10-14 | Sprach-Pipeline, Einstellungen, Sicherheit | Eine Einstellung „Sprechfassung“ mit vier Stufen statt Schalter: **Aus** (Standard), **Immer** (Sprechtext auch nach fremden Inhalten), **Geschützt** (nach fremden Inhalten sichtbare Antwort vorlesen, K20 c), **Mit KI-Prüfung** (nach fremden Inhalten prüft ein frischer Aufruf an dasselbe Modell ohne Kontext, ob Sprechtext und geschriebene Antwort inhaltlich übereinstimmen; nur dann wird der Sprechtext vorgelesen, fail-closed). Umsetzung WP55. | Wunsch Maintainer | bestätigt 2026-10-14 (Wunsch), Bezeichnungen offen |
| K32 | 2026-10-14 | Sprach-Pipeline, Sicherheit, UI/UX | **Wunsch für M5 (Ausgestaltung gemeinsam mit dem Maintainer):** Sprechererkennung – erkennt, wer spricht, für Personalisierung und zusätzliche, rechtlich unkritische Aktionen, auch bei gesperrtem Gerät. Hinweis: Stimmerkennung ist keine starke Authentifizierung (Aufnahmen/Nachahmung möglich) und eignet sich nur für Aktionen mit geringem Risiko. Anknüpfung an die eingelernten Stimmabdrücke aus WP60. | Wunsch Maintainer | bestätigt 2026-10-14 (Aufnahme in M5), Umfang offen |
| K91 | 2026-10-21 | Tool-System, Routing (zu K89) | (1) Die Routing-Regeln (Provider-Wahl) nutzen die Wortlisten aller Sprachen gemischt; nur die Vorab-Freischaltung und die Tool-Suche nutzen die aktuelle Sprache (Sprache der Anfrage, sonst des Geräts, sonst Englisch). (2) Der nächste Wecker kommt als Feld `only_next` in `alarms__list`, kein eigenes Tool. (3) Die Wortlisten liegen je Sprache in `wendelin_core/lib/src/tools/topic_words/{de,en,fr}.dart`, mit README für neue Sprachen. (4) „ruf“ allein schaltet Kontakte nicht vorab frei, „anrufen“ und „telefonier“ schon. | Umsetzung WP119 | (1) bestätigt 2026-10-21 (Maintainer: „gemischt lassen“); (2)–(4) offen |
| K115 | 2026-10-24 | Sprache (Wake Word, zu K23, K24, K107, K110) | **Aktivierungswort nur noch „Hey Wendelin“ (Entscheidung Maintainer):** Aufwecken und Unterbrechen während einer Antwort nur mit „Hey Wendelin“. „Wendelin“ allein löst nicht mehr aus (ersetzt K107: dort „nur ‚Wendelin‘ unterbricht“). Stufe 1 wertet nur den Kopf „Hey Wendelin“. Prüfer und Rückfall-Erkenner verlangen „hey“ vor „Wendelin“ (mit Erkennungsvarianten). Eingelernt wird nur „Hey Wendelin“, alte „Wendelin“-Vorlagen werden ignoriert, mit Hinweis zum Neueinlernen. Texte in de/en/fr entsprechend. Modell zum Start: v8a (Stimmenset clean) mit Prüfer B (zentrierter Vorlagen-Vergleich), Parakeet als Rückfall. | Messungen WP137 | zurückgestellt (2026-10-24): Stufe 1 (v8a, ein Ausgang) und Prüfer B trennen „Wendelin“ nicht von „Hey Wendelin“ (WP137, W-allein-Messung). Vorerst wecken beide Wörter, mit v8a (clean) + Prüfer B und Direktannahme ab 0,999. K107 gilt bis dahin weiter. Wieder aufgreifen, wenn ein Stufe-1-Modell mit eigenem HW-Kopf existiert (Training erst nach dem App-Test). Nachtrag 2026-10-26 (Maintainer): Texte, Hinweise, Benachrichtigung und Doku nennen ab sofort konsequent „Hey Wendelin“ (WP156); die Hey-Pflicht in der Erkennung folgt erst nach Auswertung des Weckwort-Archivs (WP155). Texte umgesetzt mit WP156 (2026-10-27); Hinweise zur Prüfung sagen „das Aktivierungswort“, die Benachrichtigung „Aktivierungswort“ statt „Wake Word“. |
| K127 | 2026-10-27 | Einrichtung, Berechtigungen (Android) | Bei Installation aus einer Datei (Android 13+ „Eingeschränkte Einstellungen“) zeigt die App einen bedingt formulierten Hinweis mit Knopf zu den App-Infos, wenn die Integration an ist und SMS-Berechtigung bzw. Benachrichtigungszugriff fehlt; er verschwindet nach der Erteilung. Erkennung über die Installationsquelle, nicht über den AppOp (für Apps nicht lesbar). Neuer Kanal `restricted_settings`, keine neue Berechtigung. | WP159, Meldung Maintainer 2026-10-23; Entscheidung Maintainer in der Paket-Sitzung | offen |
| K128 | 2026-10-27 | Anbieter, Attestierung (GPU) | Die Auswahl „GPU-Prüfung über NVIDIA“ erscheint nur, wenn der Anbieter für das Modell einen GPU-Nachweis liefert (oder schon ein Modus ≠ aus gespeichert ist); sonst ist sie ausgeblendet und „aus“ wird gespeichert. Unbekannter Nachweis zählt wie kein Nachweis; bei einem echten Prüffehler erscheint ein Hinweis „GPU-Nachweis konnte nicht geprüft werden“. | WP159, Meldung Maintainer 2026-10-23 | offen |
| K129 | 2026-10-27 | Integrationen (Spotify) | Zielgerät von Spotify: ein ausdrücklich genanntes Gerät (Parameter `device`); sonst das Gerät, auf dem auf dem Konto gerade tatsächlich etwas spielt (Fortschritt wächst; pausiert zählt nicht); sonst das Handy, auf dem Wendelin läuft, dessen Spotify-App geweckt wird. Auf Fremdgeräten prüft Wendelin bis etwa 10 s; ohne Bestätigung bleibt die Wiedergabe dort und Wendelin sagt, dass es sie geschickt, aber nicht bestätigen konnte. Aufs Handy weicht es nur aus, wenn der Befehl mit einem Fehler für ein totes Gerät scheitert (WP166/WP167, Korrektur Maintainer 2026-10-28: „immer aufs Handy“ war ein Missverständnis; Chromecast startet verzögert). Erfolg meldet Wendelin nur bei bestätigter Wiedergabe (Android-Mediensitzung der Spotify-App, sonst Web-API `is_playing`, Gerät und Fortschritt); sonst ehrliche Meldung. Erfolglose Playlist-Suche wird gesagt statt still Ersatz zu spielen. | WP161, Gerätetest Maintainer 2026-10-27 (Befehl ging an totes Fremdgerät); Entscheidung Maintainer | offen |
| K130 | 2026-10-27 | Sicherheitsstufen (Home Assistant, MCP/HTTP), Sprechererkennung | (1) HA-Aufrufe haben eine Stufe A–D je Geräteart (Licht, Medien, Szenen, Schalter, Klima, Rollos); Schloss, Alarm, Garage/Tor/Tür und Szenen mit kritischem Mitglied nur je Gerät; Szenen mit unbekannten Mitgliedern höchstens C. (2) Eine gespeicherte Tool-Stufe auf `ha__call` wirkt zusätzlich (wurde entgegen ADR 0022 ignoriert); `ha__call_secure` fest D. (3) MCP/HTTP-Werkzeuge mit Stufe A–D neben dem Risiko; „alles bestätigen“ gewinnt. (4) Obergrenze der Sprecher-Schwelle 0,60 → 0,50 (auch gespeicherte Profile), ungültige Schwelle gilt als 0,50 statt als erkannt. (5) Gesperrt wird der Name weiterhin nicht genannt. ADR 0022 nachgetragen. | WP160, Meldung Maintainer 2026-10-27 (Licht gesperrt nicht steuerbar); Gerätetest 5/5 statt 2/5 | offen |
| K131 | 2026-10-28 | Overlay gesperrt, Sicherheitsstufen (ADR 0022) | (1) Gesperrt zeigt das Overlay die aktuelle Anfrage und die gesprochene Antwort (ungekürzter gesprochener Teil), oben ein Entsperren-Knopf; kein Verlauf, im Fehlerfall der gesprochene Fehlersatz (bisher: nichts aus den eigenen Daten). (2) Neues Merkmal „wirkt nur entsperrt“ (maps__navigate, maps__search_place, location__navigate_to, media__open_audible, obsidian__open_note, phone__call, station__start; bewusst nicht sms__compose, spotify__*): gesperrt mit erlaubter Stufe wird der Aufruf nicht ausgeführt, ein fester Satz kommt, die Entsperr-Abfrage öffnet sich, nach echtem Entsperren läuft er genau einmal ohne neuen Modelllauf; Abbruch, Schließen oder 60 s verwerfen ihn. Der WP153-Merkeintrag trägt Text (30 s) oder Werkzeugaufruf (60 s). (3) Werkzeuge können den Lauf beenden, bevor das Modell erneut aufgerufen wird. (4) Die Sperrsätze kommen in der Sprache der Äußerung. | WP163, Wunsch Maintainer 2026-10-27 (Text gesperrt sichtbar; Navigation gesperrt kam nicht an, Lösung: nach Entsperren ausführen) | offen |
| K132 | 2026-10-28 | Sprachausgabe, Barge-in (nimmt K88/K93 zurück) | Der Schalter „Antwort als Gesprächston“ und der Kommunikationsmodus der Ausgabe (`MODE_IN_COMMUNICATION`, `USAGE_VOICE_COMMUNICATION`, Lautsprecher-Route) entfallen samt Code; ein gespeicherter Wert wird beim Start gelöscht. Es bleibt der frühere Stand: Wiedergabe normal, Echo-Unterdrückung nur über die Aufnahme (`VOICE_COMMUNICATION` + AEC). Prüfer B und Echo-Filter beim Unterbrechen (K124) sowie `MODIFY_AUDIO_SETTINGS` bleiben. | WP165, Meldung Maintainer 2026-10-27 (Antwort wurde im Anruf-Stream leiser); Entscheidung Maintainer 2026-10-27/28 | offen |
| K133 | 2026-10-28 | Integrationen (Kontakte, Navigation) | (1) `contacts__find` liefert nur angefragte Felder (`fields`: phone, email, address, birthday, organization; kein Notizfeld), Zusatzfelder werden nur für Treffer geladen; Kontakte bleiben vertrauenswürdige Quelle (Entscheidung Maintainer). (2) Neues Werkzeug `contacts__navigate` (Name, App, Adress-Bezeichnung, Auswahl): holt die Adresse auf dem Gerät und startet die Navigation; das Modell erfährt die Adresse nie, nur einen Status; fester Satz „Navigation zu <Name> gestartet.“; wirkt nur entsperrt (Ergänzung zu K131); nur angeboten mit Kontakten und Navigations-App. (3) `maps__navigate` bekommt `app` (Google Maps oder Waze); Waze ist eine eigene Integration ohne eigene Werkzeuge, Einstellung „Navigations-App“, ohne stillen Rückfall auf die andere App, Waze nur Auto. (4) Das Dev-Log zeigt bei `contacts__find` nur die Trefferanzahl. | WP164, Wunsch Maintainer 2026-10-27 | offen |
| K138 | 2026-10-29 | Wake Word (Stufe 2) | Die zweite Prüfung macht in beiden Erkennungswegen (Vorlagen und Modell) immer Prüfer B; kann er nicht entscheiden, prüft das installierte Erkennungsmodell (Parakeet vor Whisper, Whisper nur mit Silero VAD), nie fest Whisper. Fehlt ein Modell oder eine eingelernte Folge, zeigt die App einen Hinweis in den Einstellungen und der Dienst-Benachrichtigung statt Treffer still zu verwerfen. Im Entwicklermodus laufen beide Stufe-1-Erkenner parallel (der zweite löst nie aus) und jede Äußerung wird mit beiden Höchstwerten archiviert. | WP171, Gerätetest Maintainer 2026-10-28 (Zweitgerät ohne Whisper verwarf jeden Treffer) | offen |
| K139 | 2026-10-29 | Stationsmodus, Wake Word | Solange der Stationsmodus offen ist (auch bei dunklem Bildschirm), ist das Weckwort an, unabhängig von „aus“ bzw. „nur beim Laden“; Assistenten-Rolle, Mikrofon-Berechtigung und eine Pause durch den Nutzer gelten weiter. | WP171, Entscheidung Maintainer in der Paket-Sitzung | offen |
| K140 | 2026-10-29 | Overlay, Gesprächsmodus | Endet das Zuhören ohne Äußerung (auch direkt nach dem Weckwort), schließt sich das Overlay immer, egal wie es geöffnet wurde; danach hört das Weckwort wieder zu. Offen bleibt es bei Rückfrage/Bestätigung, Entsperr-Abfrage, laufendem Agenten und getipptem Austausch; fällt ein solcher Grund später weg, schließt es nicht nachträglich. Mikrofon-Tipp während der Antwort bricht ab („Abgebrochen.“); nach einem Erkennungsfehler bleibt die Meldung kurz sichtbar, dann zu; nach Rückgängig schließt es, sobald „Zurückgenommen.“ gesprochen ist. | WP172, Wunsch Maintainer 2026-10-28 (Fenster blieb stehen, Weckwort ging danach nicht) | offen |
