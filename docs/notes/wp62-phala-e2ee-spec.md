# WP62 – Spezifikation Phala/RedPill E2EE v2 (x25519)

Stand 2026-10-14. Recherche, kein Repo-Code geändert.

Quellenkürzel:
- **SPEC** = `Dstack-TEE/private-ai-gateway` @ `57477f5d9caced1f95ffd2562e7ba421849a0d7e` (https://github.com/Dstack-TEE/private-ai-gateway), Datei `spec/...`. Lokaler Klon: `<lokales Scratchpad>/phala-ref/private-ai-gateway/`
- **REF** = derselbe Repo, Server-Referenzcode (Rust, `src/...`). Es gibt dort keinen Client-Encrypt-Code; `clients/verifier-ts/src/index.ts:10` sagt ausdrücklich, E2EE-Feldverschlüsselung werde nicht konstruiert. Der Client muss also nach SPEC plus Server-Gegenstück (REF) gebaut werden.
- **PHALA-DOC** = https://docs.phala.com/phala-cloud/confidential-ai/confidential-model/e2ee-encryption
- **RP-DOC** = https://docs.redpill.ai/confidential-ai/e2e-encryption und https://docs.redpill.ai/guides/e2ee-encryption
- **LIVE** = ungeschützter GET `https://tee.redpill.ai/v1/aci/attestation?nonce=<64hex>` am 2026-10-14 (kein Key nötig, keine Inferenz). Dateien: `scratchpad/phala-ref/att-tee.redpill.ai.json` (identisch für api.redpill.ai und inference.phala.com).

## 0. Wichtigste Befunde / Abweichungen vom WP

1. **Die Doku nennt nur secp256k1, der Server bietet aber x25519 an.** PHALA-DOC und RP-DOC beschreiben ausschließlich `secp256k1-aes-256-gcm-hkdf-sha256` (Schlüssel `dstack-kms-e2ee-v1`). Die SPEC (`spec/e2ee-v2.md:88-96`) definiert zwei Suiten und empfiehlt X25519. LIVE-Keyset enthält beide: `dstack-kms-e2ee-x25519-v1` (algo `x25519-aes-256-gcm-hkdf-sha256`, Public Key `408e82d159832cfae15007781bcade0badee7d50e9f76d50eaa1777464006537`) und `dstack-kms-e2ee-v1` (secp256k1). Der Coder wählt per `algo` und nicht per `key_id` (SPEC §4, §7); `key_id` ist nur ein Label. Der x25519-Schlüssel kann rotieren; nie hartkodieren.
2. **Alle Strings in `messages[].content` müssen verschlüsselt sein**, nicht nur "mindestens einer" (REF `e2ee_crypto.rs:263-296`, siehe 3.2). Ein unverschlüsselter String-Content wird als Hex-Ciphertext interpretiert und führt zu `e2ee_decryption_failed`.
3. **Tool-Definitionen und `tool_calls` sind unverschlüsselt** (siehe 6).
4. **Verschlüsselung endet im Gateway-CVM** (`serving: "aggregator"`, LIVE), nicht im Modell-TEE (PHALA-DOC: "does not hide plaintext from that gateway").
5. Schlüssel gilt gateway-weit, nicht pro Modell (`spec/aci.md:349-352`: "service-scoped: one report describes the whole workload, not one model"). Das Modell geht nur als Klartext-`model` in die AAD ein.
6. Kein veröffentlichter Ciphertext-Testvektor; nur AAD-Vektoren (siehe 8).

## 1. Header

### Request (alle fünf Pflicht; SPEC `e2ee-v2.md:56-67`)
| Header | Wert |
|---|---|
| `X-E2EE-Version` | exakt `2` |
| `X-Client-Pub-Key` | Public Key des Clients, hex, Kurve der gewählten Suite. x25519: 32 Byte roh = 64 Hex-Zeichen. Optionales `0x`-Präfix wird akzeptiert (REF `aci/e2ee.rs:119-129`). |
| `X-Model-Pub-Key` | Hex des Service-Keys aus dem attestierten Keyset (Eintrag mit `algo == x25519-aes-256-gcm-hkdf-sha256`). Muss byte-gleich (nach Normalisierung) einem Keyset-Eintrag entsprechen, sonst `e2ee_model_key_mismatch` (REF `aggregator/service/e2ee.rs:270-284`). |
| `X-E2EE-Nonce` | 32 Zufallsbytes als genau 64 Hex-Zeichen, **Kleinbuchstaben verwenden**, kein `0x` (REF `e2ee_crypto.rs:23`, Test `:767`). Pro Request frisch. |
| `X-E2EE-Timestamp` | Unix-Sekunden, Ganzzahl. Erlaubt `|now - ts| <= 300` (REF `aggregator/service/e2ee.rs:265`). Uhr des Geräts vorher prüfen; bei Abweichung Fehler `e2ee_invalid_timestamp`. |

- **`X-Signing-Algo` nicht senden** (Legacy-Pfad, SPEC `e2ee-v2.md:66`; REF `e2ee.rs:~229`: wenn vorhanden, wird v1-Legacy ohne AAD genommen).
- Replay: Tupel (Client-Pubkey, Service-Pubkey, Nonce lowercase) wird 300 s gesperrt (REF `e2ee.rs` `claim_e2ee_replay`, Ende der Datei). Wiederholung = `e2ee_replay_detected`. Konsequenz: Retry nach Netzfehler braucht neue Nonce, neuen Timestamp, neue Verschlüsselung.
- Die Nonce wird in der AAD **so verwendet wie im Header gesendet** (REF `e2ee.rs`: `nonce: Some(nonce)` ohne Lowercasing). Daher immer Lowercase senden.
- `Authorization: Bearer <key>` wie gewohnt (SPEC `aci.md:437-441`).

### Response (SPEC `e2ee-v2.md:69-79`; REF `middleware/completion.rs:1702-1730`)
| Header | Bedeutung |
|---|---|
| `X-E2EE-Applied` | `true` wenn verschlüsselt, sonst `false` (bei normalen Inferenzantworten, `docs/api-reference.md:48`). |
| `X-E2EE-Version` | `2` |
| `X-E2EE-Algo` | `algo` des gewählten Service-Keys |
| `X-Receipt-Id` | Quittungs-ID (nicht E2EE-spezifisch) |
| `X-ACI-Keyset-Digest` | digest des bedienenden Keysets (`aci.md:443-451`); bei Änderung gegenüber dem geprüften Report neu attestieren |

SPEC: Das sind unauthentifizierte Hinweise (`e2ee-v2.md:77`). Der Client darf sich nicht darauf verlassen; maßgeblich ist, dass die Felder per AEAD entschlüsselbar sind (siehe 7).

## 2. Kryptoschema (SPEC `e2ee-v2.md:81-116`, REF `aci/e2ee.rs`)

Suite `x25519-aes-256-gcm-hkdf-sha256`:
- Pro Feld frisches ephemeres X25519-Schlüsselpaar (REF `e2ee.rs:151`) und frische 12-Byte-AES-GCM-Nonce (`:155`). Pflicht pro Feld (SPEC `:113`).
- `shared = X25519(eph_secret, recipient_public)` (32 Byte roh, RFC 7748).
- `key = HKDF-SHA256(salt = keine (leer/None), ikm = shared, info = ASCII "aci.e2ee.v2.x25519", L = 32)` (REF `e2ee.rs:43, 424-430`). Salt: `Hkdf::new(None, ..)` = RFC-5869-Default (HashLen Nullbytes). Das ist bei Rust-`hkdf` automatisch so; bei eigener Implementierung "kein Salt" meinen.
- AES-256-GCM, Nonce 12 Byte, Tag 16 Byte, **AAD = JCS-JSON** (Abschnitt 4).
- Wire-Format pro Feld: **Lowercase-Hex** von `eph_public(32) || gcm_nonce(12) || ciphertext || tag(16)` (REF `e2ee.rs:166-170`; Tag hängt am Ciphertext, aes-gcm-Crate-Standard). Mindestlänge 60 Byte (`:180`). Beim Entschlüsseln akzeptiert die Referenz optionales `0x`.
- Plaintext: UTF-8 des Feldwerts.
- Anfrage: Empfänger = Service-X25519-Key (`X-Model-Pub-Key`). Antwort: Empfänger = `X-Client-Pub-Key`; der Server verschlüsselt jedes Antwortfeld mit eigenem ephemeren Key an den Client-Key (REF `e2ee_crypto.rs:704-723`).
- **Client-Schlüssel für die Antwort**: Der Client erzeugt ein X25519-Schlüsselpaar (Empfehlung: pro Request frisch, privat nur im Speicher), sendet den Public Key in `X-Client-Pub-Key`, hält den Private Key bis Antwortende zum Entschlüsseln. Es gibt keinen weiteren Austausch. Der Client-Key muss zur Suite des Service-Keys passen (REF `e2ee.rs:~277-281`: Normalisierung nach `selected_key.algo`; sonst `e2ee_invalid_public_key`).
- X25519-Clamping macht die Bibliothek (x25519-dalek `StaticSecret`/`EphemeralSecret`). Nulltest des Shared Secret (Low-Order-Point): von der Referenz nicht geprüft; Rust-Crate `x25519-dalek` 2.x bietet `was_contributory()`; Empfehlung, bei Fehlschlag abzubrechen (**eigene Empfehlung, nicht Quelle**).
- secp256k1 nur zur Abgrenzung: Ephemeral 65 Byte unkomprimiert SEC1, Shared = x-Koordinate, info `aci.e2ee.v2.secp256k1` (SPEC `:91`). Nicht implementieren.

## 3. Verschlüsselte Felder

Feldpfad (`field`): Member-Namen und Array-Indizes ab Body-Wurzel mit `.` verbunden, z. B. `messages.3.content` (SPEC `e2ee-v2.md:120-127`). Bei `choices`/`data` zählt der `index`-Member, falls vorhanden, sonst die Position (REF `e2ee_crypto.rs:426-430, 563-566`).

### 3.1 Chat-Request (`POST /v1/chat/completions`)
Das JSON bleibt OpenAI-kompatibel, nur Werte werden ersetzt (Hex-String statt Klartext). Die Referenz iteriert `messages[]` und behandelt `content` (REF `e2ee_crypto.rs:148-178, 263-360`):

| Fall | Feldpfad | Verhalten Server |
|---|---|---|
| `content` ist String (jede Rolle: system, user, assistant, tool) | `messages.{m}.content` | wird **immer** als Ciphertext entschlüsselt; Klartext → Fehler. Das Ergebnis, wenn es als JSON-Array parst, wird als strukturierter Content wiederhergestellt, sonst String (`:400-405`). |
| `content` ist Array, Part `type:"text"` mit String `text` | `messages.{m}.content.{c}.text` | wird entschlüsselt |
| Part `type:"image_url"` mit String `image_url.url` | `messages.{m}.content.{c}.image_url.url` | wird entschlüsselt (Data-URL oder URL als Plaintext) |
| Part `type:"input_audio"` mit String `input_audio.data` | `messages.{m}.content.{c}.input_audio.data` | wird entschlüsselt |
| anderer Part-Typ | – | unverändert durchgereicht |
| `content` null/fehlend (z. B. assistant mit `tool_calls`) | – | übersprungen |
| Nachricht ohne verschlüsselbaren Teil in allen Messages | – | `decrypted_count == 0` → `e2ee_decryption_failed` (`:171-173`) |

Folgerungen für den Coder:
- Regel: **Jeden String-Content und jeden `text`/`image_url.url`/`input_audio.data`-Part verschlüsseln.** Leere Strings (`""`) ebenfalls verschlüsseln (leerer Plaintext ist gültig; GCM mit 0 Byte Daten). Sonst schlägt die Entschlüsselung dieses Felds fehl (**Schlussfolgerung aus dem Code, nicht live getestet**).
- Einfachste robuste Variante: Für jede Nachricht mit String-Content den ganzen `content` als `messages.{m}.content` verschlüsseln. Für Array-Content entweder jeden Part einzeln (text/image_url/input_audio, siehe Tabelle) oder den gesamten Array "compact serialisiert" als JSON-String in `messages.{m}.content` (SPEC `:133, 142-146`: "structured content array serialized to JSON"). Letzteres braucht nur einen Pfad; der Server stellt den Array wieder her (`decrypted_chat_content_value`).
- Nicht verschlüsselt (und nicht vom Server erwartet): `model`, `stream`, `stream_options`, `temperature`, `max_tokens`, `tools`, `tool_choice`, `response_format`, `messages[].role`, `messages[].name`, `messages[].tool_call_id`, `messages[].tool_calls`, usw. `model` muss ein String im Top-Level sein (`e2ee_invalid_payload_model`).
- Es gibt keinen Sonderpfad für ein `system`-Feld; System-Prompts laufen als `messages[]` mit `role:"system"` und werden wie jede Nachricht verschlüsselt. (Kein separates top-level `system` im OpenAI-Chat-Format.)
- Andere Endpunkte (`/v1/responses`, `/v1/messages`, `/v1/systemone`) → `400 e2ee_unsupported_endpoint` (`docs/api-reference.md:32-34`). Wendelin nutzt nur `/v1/chat/completions`.
- `POST /v1/completions` (`prompt`, `prompt.{i}`) und `/v1/embeddings` (`input`, `input.{i}`) sind in der SPEC definiert (`:136-139`), für WP62 irrelevant.

### 3.2 Chat-Antwort (nicht streamend; REF `e2ee_crypto.rs:407-475`; SPEC `:154-156`)
Für jedes `choices[i]` (Index = `index`-Member, sonst Position) werden, falls vorhanden und String (null = übersprungen; Nicht-String → Serverfehler), verschlüsselt:
- `choices.{i}.message.content`
- `choices.{i}.message.reasoning`
- `choices.{i}.message.reasoning_content`
- `choices.{i}.message.audio.data`

**Nicht** verschlüsselt: `message.tool_calls`, `message.role`, `finish_reason`, `usage`, `id`, `model`, `created`, `refusal` (nicht in der Liste; **`refusal` aus Code abgeleitet: wird nicht angefasst**).

### 3.3 Chat-Antwort streamend (SSE; REF `e2ee_crypto.rs:553-620`, `aggregator/service/streaming.rs:572-667`)
- Pro SSE-Event mit `data:`-Zeile (kein `[DONE]`) wird das JSON geparst, dann in `choices[i].delta` verschlüsselt: `delta.content`, `delta.reasoning`, `delta.reasoning_content`. Feldpfade `choices.{i}.delta.content` usw.
- Ist `delta.content == ""`, wird das Feld **entfernt** statt verschlüsselt (`:597-599`). `null` bleibt null.
- **`delta.tool_calls` bleibt Klartext** (kein Code dafür).
- `id` im AAD ist die `id` des jeweiligen Chunks (`:563-566`, `unwrap_or("")`). Der Client nimmt die `id` des Chunks, in dem das Ciphertext-Feld steht. Annahme: alle Chunks einer Antwort haben dieselbe `id` (OpenAI-Verhalten); wenn nicht, trotzdem die `id` des jeweiligen Chunks verwenden. Fehlt `id`: `""`.
- `[DONE]`, Kommentarzeilen (`:`) und Events ohne `data` werden unverändert durchgereicht; `usage`-Chunks mit leeren `choices` sind Klartext.
- Jede Delta-Chiffre ist ein eigenes Feld mit eigener ephemeren Key/Nonce. Der Client entschlüsselt jeden Delta einzeln und verkettet dann den Klartext. Die Deltas sind nicht geordnet/gebunden außer über die Quittung (siehe 7).
- Framing: Zeilen `data: <json>` getrennt durch Leerzeile. Eigene SSE-Zeilenpufferung: Zeilen mit `\n` oder `\r\n` splitten, Events bei Leerzeile (`streaming.rs:582-619`).

### 3.4 Fehlerantworten
Fehler (z. B. 400 `e2ee_*`) sind Klartext-JSON im OpenAI-Fehlerformat: `{"error":{"type":"e2ee_...","message":...}}` (SPEC `:254-258`; REF `error_responses.rs`). `X-ACI-*` Header sind auch dort gesetzt. Wendelin: Fehlertext anzeigen, kein Retry mit Klartext.

## 4. AAD (SPEC `e2ee-v2.md:164-204`, REF `e2ee_crypto.rs:89-130`)

JCS (RFC 8785): Member alphabetisch (UTF-16-Codeunit-Reihenfolge), kompakt ohne Leerraum, Strings minimal escaped, `ts` als JSON-Ganzzahl.

Request-Feld:
```
{"algo":"<algo>","field":"<pfad>","model":"<model>","nonce":"<nonce>","purpose":"aci.e2ee.request.v2","ts":<int>}
```
Antwort-Feld:
```
{"algo":"<algo>","field":"<pfad>","id":"<response id oder ''>","model":"<model>","nonce":"<nonce>","purpose":"aci.e2ee.response.v2","ts":<int>}
```
- `algo` = `algo` des gewählten Service-Keys (`x25519-aes-256-gcm-hkdf-sha256`).
- `model` = Top-Level-`model` des Requests, **byte-genau** (kein Trimmen/Alias). In der Antwort-AAD ebenfalls das **Request**-Modell, nicht das `model` der Antwort (SPEC `:195-198`; REF `ctx.request_model`, `:683-693`). Bei RedPill-Modellnamen wie `google/gemma-...` also genau den gesendeten String.
- `nonce`, `ts` = Header-Werte des Requests (gleiche Werte für alle Felder und für die Antwort).
- Alle Beispiel-Strings enthalten nur ASCII, JCS-Escaping nur bei Sonderzeichen im Modellnamen relevant.

## 5. Schlüsselbeschaffung und Bindung (SPEC `aci.md:173-335`, `:336-418`)

1. `GET https://<host>/v1/aci/attestation?nonce=<64 Hex-Zeichen, Lowercase, frisch>` (Hosts live: `tee.redpill.ai`, `api.redpill.ai`, `inference.phala.com`; alle drei lieferten denselben Keyset-Digest `sha256:f41362b5…5e00`). Der Endpunkt antwortete 2026-10-14 ohne Authorization-Header mit HTTP 200; die Docs senden einen Bearer-Key mit. Ob ein Key künftig Pflicht wird, ist unklar.
2. Antwortform (LIVE bestätigt): `{api_version:"aci/1", workload_keyset_digest, attestation:{tee_type:"tdx", workload_keyset:{subject, not_after, receipt_signing_keys[], e2ee_public_keys[{key_id,algo,public_key}], tls_public_keys[{spki_sha256,domain}]}, report_data, source_provenance, evidence:{quote, quote_report_data, event_log, vm_config, app_compose, key_custody, downstream_tls_binding}}, service_capabilities:{supported_e2ee_versions:["2"], serving:"aggregator"}}`.
3. Bindungskette (SPEC `aci.md:268-302`):
   - `workload_keyset_digest = "sha256:" + hex(sha256(JCS(workload_keyset)))`.
   - Statement-Bytes exakt: `{"keyset_digest":"sha256:<hex>","nonce":"<nonce>","purpose":"aci.report_data.v1"}`.
   - `report_data = sha256(statement)` (32 Byte); im 64-Byte-TDX-Report-Data-Feld Bytes 0–31, Rest Nullen.
   - Der TDX-Quote muss dieses `report_data` enthalten (Evidence `quote_report_data`).
   - **Ich habe diese Kette für die LIVE-Antwort lokal nachgerechnet: Digest und `report_data` stimmen (mit meinem Nonce), `quote_report_data` = `report_data || 32×00`.** Die Quote-Signaturprüfung (Intel-Kette, Compose-Hash, RTMR3) habe ich nicht ausgeführt; sie gehört zu WP61/`native/attest`.
4. Der E2EE-Key wird verwendet, wenn (a) Quote verifiziert und `report_data` mit eigener Nonce übereinstimmt, (b) Digest über das eingebettete Keyset stimmt, (c) `now < not_after`, (d) Provenance/Compose akzeptabel (Policy, WP61), (e) der Key in `e2ee_public_keys` mit `algo == x25519-aes-256-gcm-hkdf-sha256` steht. "Keys neben einem Quote, die nicht über diese Rechnung gebunden sind, darf der Verifier nicht akzeptieren" (`aci.md:300-301`).
5. Verifier-Policy (SPEC `aci.md:815-818`): E2EE-Key muss in `e2ee_public_keys` stehen = Kanal-Bindung (Check 6). Custody (Check 5, KMS-Signaturkette) ist Policy; im Referenz-Verifier "SKIP, wenn nicht konfiguriert" (`docs/quickstart.md:37-38`).
6. Keyset ändern → neuer Digest und neuer Report. Antwort-Header `X-ACI-Keyset-Digest` mit dem geprüften Digest vergleichen; bei Abweichung neu attestieren, bevor weiter Daten gesendet werden (SPEC `aci.md:456-459`).
7. Der Server hat noch weitere nicht-E2EE-Schutzschichten (TLS-SPKI-Pinning aus `tls_public_keys`, WP61). E2EE ersetzt das nicht.
8. Ein Schlüssel für alle Modelle (Gateway-Key). Kein Modell-Key. Ob der x25519-Key im Betrieb stabil bleibt: unbekannt, `not_after` im LIVE-Keyset = 1794417333 = 2026-11-11 17:15 UTC, also nur ca. 4 Wochen Lebensdauer: Client muss Ablauf prüfen und regelmäßig neu attestieren, Keyset/Key kann sich ändern.

## 6. Tool-Definitionen und `tool_calls`

**Bestätigt unverschlüsselt (aus Code, nicht live getestet):**
- Request: `tools`, `tool_choice` werden von `decrypt_request_payload` nicht angefasst (REF `e2ee_crypto.rs:148-178`); `messages[].tool_calls` und `tool_call_id` ebenso. Nur `content` der tool-Rolle (String) wird verlangt verschlüsselt.
- Antwort: `tool_calls` (Argumente, Namen) bleiben im Klartext, buffered und streaming (`:407-475, 553-620`: nur content/reasoning/reasoning_content/audio.data).
- SPEC-Tabelle `e2ee-v2.md:152-158` listet ebenfalls nur diese Felder. Eine ausdrückliche Doku-Aussage "tool_calls sind unverschlüsselt" gibt es nicht; es ist die Konsequenz aus der "Feldliste" ("An endpoint whose response fields are not defined here MUST reject v2", betrifft aber Endpunkte, nicht Felder).
- Risiko, das Wendelin sichtbar machen sollte: ein Modell, das statt Text nur einen `tool_calls`-Aufruf liefert, gibt dessen Argumente (z. B. Kalendereinträge) nur per TLS/Attestierung geschützt zurück.

## 7. Fehlerverhalten, Quittung, Verifikation

**Fehler** (SPEC `e2ee-v2.md:254-271`; alle HTTP 400, Klartext-JSON, OpenAI-Fehlerform): `e2ee_header_missing`, `e2ee_invalid_version`, `e2ee_invalid_public_key`, `e2ee_model_key_mismatch`, `e2ee_invalid_nonce`, `e2ee_replay_detected`, `e2ee_invalid_timestamp`, `e2ee_invalid_payload_model`, `e2ee_decryption_failed`, `e2ee_unsupported_endpoint`.

**Server ohne E2EE:** Wenn die Version nicht in `supported_e2ee_versions` steht → `400 e2ee_invalid_version` "E2EE v2 is not supported by this service" (REF `http/app/handlers.rs:678-688`, `error_responses.rs:13-19`). Wenn das Gateway gar kein E2EE-Report liefert (`supported_e2ee_versions` ohne `"2"` oder kein passender Key): Client bricht vor dem Senden ab. Ein Server, der E2EE-Header ignoriert, würde mit `X-E2EE-Applied: false` (oder ohne den Header) und Klartext-Feldern antworten. Das Referenz-Gateway tut das nicht (REF ist strikt), aber ein fremder/kompromittierter Server könnte. Die SPEC sagt: "MUST NOT return plaintext content marked as E2EE-applied" (`:161`). Client-Regel für WP62: 200-Antwort nur akzeptieren, wenn `X-E2EE-Applied: true`, `X-E2EE-Version: 2`, `X-E2EE-Algo` == gewählte Suite **und** jedes Content-/Reasoning-Feld, das nicht null/fehlend ist, ein gültiger Hex-Ciphertext ist, der mit korrekter AAD entschlüsselt. Ein String, der nicht als Ciphertext entschlüsselt (auch plausibler Klartext) → Abbruch. (Diese Regel ist Empfehlung des Berichts; die SPEC fordert sie nicht explizit vom Client.)
- Offene Frage: Ein Modell-Antwort ohne `content` und ohne `reasoning` (nur `tool_calls`) hat gar kein Ciphertext-Feld; der Client kann hier nur über `X-E2EE-Applied` prüfen. Das ist ein Prüflücke; **unsicher, wie das Gateway sich bei Antwort ohne verschlüsselbare Felder verhält** (Code `:540-563`: keine Fehlermeldung, Header bleibt gesetzt).

**Falscher Key:** `X-Model-Pub-Key` nicht im Keyset → `e2ee_model_key_mismatch` (400). Falscher Client-Key-Typ/-Länge → `e2ee_invalid_public_key`. Falsche AAD oder falscher Key beim Entschlüsseln → `e2ee_decryption_failed` (REF `e2ee_crypto.rs:380-398`).

**Quittung/Signatur (SPEC `e2ee-v2.md:238-252`, `aci.md:511-595`):**
- Abruf: `GET /v1/aci/receipts/{id}`, id = `X-Receipt-Id` (oder die Response-`id`). Receipts sind nur begrenzt (TTL, im Speicher) vorhanden (`aci.md:525-531`, `trust-boundary` Doku). Dokument: `event_log` mit `request.received`, `request.forwarded`, `upstream.verified`, `response.returned`, `key_id`, `signature` (Ed25519 über JCS ohne `signature`, hex, `aci.md:533-543`). Signing-Key: `receipt_signing_keys` des attestierten Keysets (LIVE: `dstack-kms-receipt-ed25519-v1`).
- `request.received.body_hash` = SHA-256 (`sha256:<hex>`) über den **entschlüsselten**, kompakt serialisierten Request-Body (nicht die Chiffre-Wire-Bytes) (SPEC `:243-245`; PHALA-DOC "Receipts with E2EE"). Die Referenz serialisiert den `serde_json::Value` neu (`serde_json::to_vec`, Feature `preserve_order` an, `Cargo.toml:26`), d. h. Member-Reihenfolge wie vom Client gesendet, kompakt, ohne Whitespace. Ob exakt dieselben Bytes wie beim Client entstehen (Zahlenformat, Unicode-Escapes, doppelte Keys), ist **nicht verifiziert**; für Hash-Gleichheit Client-Body kompakt in gleicher Member-Reihenfolge serialisieren.
- `response.returned.body_hash` = Hash über die **exakten Wire-Bytes der Antwort inkl. Chiffretexten** und, bei SSE, über den kompletten Stream inkl. Framing (`data:`-Zeilen, Leerzeilen, `[DONE]`) (SPEC `:246-247`; `aci.md:586-588`). Der Client muss dafür die rohen Antwortbytes aufbewahren.
- Verifikation also: Request-Hash gegen Klartext-Body, Response-Hash gegen Chiffre-Wire-Bytes, und die AEAD-Tags prüfen separat die Felder. Reihenfolge/Vollständigkeit der Stream-Deltas wird nur durch den Response-Hash der Quittung abgesichert, nicht durch die Tags (SPEC `:230-233`). Wer die Quittung nicht prüft, erkennt gelöschte oder umgeordnete Deltas nicht.
- Hinweis: Das Phala-Doc "Signature"-Legacy-Wrapper (`X-Signing-Algo`) ist für Legacy-Clients und hier irrelevant.

## 8. Testvektoren

**Veröffentlicht (nur AAD, exakt kopiert aus `spec/e2ee-v2-test-vectors.md:10-37`, gleich in `src/aggregator/service/e2ee_crypto.rs:731-732` und `clients/verifier-ts/test/vectors.test.ts:55-58`):**

| Eingabe | Wert |
|---|---|
| Suite | `x25519-aes-256-gcm-hkdf-sha256` |
| Service-Seed | 32 × `0x03` |
| Service-Public-Key | `5dfedd3b6bd47f6fa28ee15d969d5bb0ea53774d488bdaf9df1c6e0124b3ef22` |
| Model | `demo-model` |
| Nonce | `000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f` |
| ts | `1750000000` |
| Response-id | `chatcmpl-123` |

Request-AAD für `messages.0.content` (Bytes exakt):
```
{"algo":"x25519-aes-256-gcm-hkdf-sha256","field":"messages.0.content","model":"demo-model","nonce":"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f","purpose":"aci.e2ee.request.v2","ts":1750000000}
```
Response-AAD für `choices.0.message.content`:
```
{"algo":"x25519-aes-256-gcm-hkdf-sha256","field":"choices.0.message.content","id":"chatcmpl-123","model":"demo-model","nonce":"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f","purpose":"aci.e2ee.response.v2","ts":1750000000}
```
Zusätzlich ACI-Bindung (`spec/test-vectors.md:37-63`), gleiches Keyset: JCS-Keyset (Zeile 43), `workload_keyset_digest = sha256:53a5cd44b30dcc51999754c719f2628a041f174ecbf9662a6f8e898a10cd9371`; mit Nonce `000102…1f` ist `report_data = df2174d28130852b413646a3786927b93e94c11d770268b65def8bdba45cb49e`; ohne Nonce `0633919ca3f00e97bafaa3304278eb22420cc3ff0d19f87dfca2d3f7508150bc`. Keyset-JCS siehe `spec/test-vectors.md:43` (nicht kopiert, da lang).

**Keine veröffentlichten Ciphertext-Vektoren** (Ephemeral-Key und GCM-Nonce sind zufällig, die Referenztests prüfen nur AAD; `spec/e2ee-v2-test-vectors.md:20-21`). Die Tests der Gegenstelle prüfen Rundläufe nur intern (`src/aggregator/service/e2ee_crypto.rs` Tests).

**Rundlauf-Test (Empfehlung):**
1. Rust-Unit: Key aus Seed 32×`0x03` → Public Key muss `5dfedd3b…ef22` sein (bestätigt RFC-7748-Ableitung). AAD-Builder gegen die zwei Strings oben vergleichen (Byte-genau).
2. Krypto-Rundlauf: `encrypt(pub, pt, aad)` → `decrypt(secret, ct, aad)` identisch; falsche AAD, falscher Feldpfad, geänderte Nonce/ts, kippen eines Bits → Fehler. Länge: `64 + 24 + 2*len(pt) + 32` Hex-Zeichen.
3. Deterministischer Eigentest: Mit festem Ephemeral-Seed und fester GCM-Nonce einen Vektor aus Python-`cryptography` (oder OpenSSL: `pkeyutl -derive` X25519, `hkdf`, `aes-256-gcm`) erzeugen und im Test einfrieren. Gegenprüfung unabhängig von der Rust-Bibliothek. (Habe ich nicht ausgeführt; `cryptography` ist hier nicht installiert.)
4. Interop mit der Referenz: Referenzserver `Dstack-TEE/private-ai-gateway` lokal bauen und `X-Model-Pub-Key` mit dem Test-Key betreiben (aufwendig; nicht ausgeführt), oder `@tags(['live'])` gegen `tee.redpill.ai` (ein kleiner Request, ein Stream). Antwort wird erst durch den Server verschlüsselt; hier zeigt ein Live-Test die Gegenstelle.
5. Dart-Fake-Server: akzeptiert nur Hex in `messages[].content`; antwortet mit korrekt AAD-verschlüsselten Feldern (Rust-Helfer im Test), plus negative Fälle (`X-E2EE-Applied: false`, Klartext-content, falscher `id` in AAD, entferntes Delta).

## 9. v3 (kurz)

Es gibt noch keine v3-Spezifikation. Bekannt ist nur: v2 ist "frozen compatibility protocol", wird von v3 ersetzt, das Referenz-Gateway unterstützt v2 mindestens bis **2027-02-10** (sechs Monate ab Richtlinie vom 2026-08-10); Protokoll und Migrationspfad werden "separately specified" (SPEC `e2ee-v2.md:13-27`; `aci.md:496-509`; `docs/attested-confidential-inference.md:236`). Ein Retirement-Hinweis nennt später die Schritte. Empfehlung: Protokollversion (Header, Suite, AAD-Aufbau, Feldliste) in einem Baustein kapseln; Version aus `service_capabilities.supported_e2ee_versions` lesen und bei fehlender `"2"` abbrechen.

## 10. Unsicherheiten (gesammelt)

1. Phala-/RedPill-Doku nennt nur secp256k1; x25519 ist nur über SPEC + LIVE-Keyset belegt. Kein Live-Rundlauf mit x25519 gegen den Server gemacht (kein Key, keine Inferenz).
2. Verhalten bei String-`content` im Klartext und bei leerem String ist aus dem Code gelesen (`Value::String → decrypt`), nicht getestet.
3. Antworten ohne verschlüsselbare Felder (nur `tool_calls`, nur `refusal`): kein Ciphertext zum Prüfen; Schutz nur über Header/Quittung.
4. `body_hash`-Gleichheit für `request.received` (Serialisierungsdetails) nicht verifiziert.
5. Der Attestierungs-Endpunkt ging 2026-10-14 ohne Key; Docs zeigen Bearer. Verhalten bei Key-Pflicht unklar.
6. Custody/KMS-Bindung des E2EE-Keys (`key_custody` in der Evidence) wurde nicht geprüft; Referenz-Verifier überspringt sie ohne Policy.
7. Verhalten bei Chunks mit wechselnder `id` im Stream nicht geprüft.
8. Rotation/Lebensdauer des x25519-Keys (`not_after` LIVE `1794417333`) und ob RedPill den x25519-Eintrag dauerhaft führt, ist nicht zugesagt.
9. Zeilenangaben mit `~` sind ungefähr (aus Ausschnitten gelesen); exakte Zeilen im lokalen Klon nachschlagen.
