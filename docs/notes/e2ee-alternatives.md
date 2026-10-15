# E2EE-Alternativen zu Phala: Tinfoil und NEAR AI Cloud (Recherche, Stand 2026-10-15)

Recherche ohne Codeänderung im Repo. Quellcode liegt (nicht ausgeführt) unter
`/private/tmp/claude-501/-Users-stefanrichter-ai-james/f56969ca-5b83-41fc-888c-87fe9795f5d4/scratchpad/e2ee-alt/`
(`tinfoil/{ehbp,tinfoil-rs,go,tfshim,router}`, `near/{docs,inference-proxy,cloud-api}`). Pfade unten relativ dazu.
Markierung: **[?]** = nicht belegt/unsicher. Es wurden nur öffentliche GETs gemacht (Tinfoil-Attestierung/Schlüssel, NEAR `/v1/model/list`); kein Konto, kein Key.

## 0. Kurzfassung

| | Phala v2 (heute) | Tinfoil | NEAR AI Cloud |
|---|---|---|---|
| Was verschlüsselt | einzelne Nachrichtenfelder | **ganzer HTTP-Body** (inkl. `tools`, `tool_calls`, Tool-Ergebnisse, SSE-Antwort) | einzelne Felder; mit Header `X-Encrypt-All-Fields: true` auch `tools[]`, `tool_calls`, Tool-Ergebnisse |
| Entschlüsselung endet | Gateway-CVM | **Router-CVM** (attestiert, Open Source), dann TLS (gepinnt) zum Modell-CVM | **Modell-TEE** (`inference-proxy` neben vLLM); Gateway reicht nur Header/Chiffre durch |
| CPU-TEE (Produktion) | Intel TDX | **AMD SEV-SNP** (Live-Router; TDX-Liste leer) | Intel TDX (dstack, wie Phala) |
| Neu für uns | - | HPKE/EHBP, **SEV-SNP**, **Sigstore/Rekor** | XChaCha20 + Ed25519->X25519, RTMR3-Replay |
| Quittung je Antwort | ja | nicht gefunden | ja (Ed25519/ECDSA, `provider_tee` oder `gateway`) |
| Aufwand | WP62 ≈ 1 Tag | ≈ 3-5 Tage | ≈ 1,5-2 Tage |

**Empfehlung:** NEAR AI zuerst (als Ergänzung, nicht als Ersatz von Phala); Tinfoil danach als zweiter Anbieter, wenn die SEV-SNP-/Sigstore-Arbeit vertretbar ist. Details in Abschnitt 8.

---

## 1. Tinfoil

### 1.1 Was wird verschlüsselt, wo endet es
- EHBP verschlüsselt **den gesamten HTTP-Nachrichtenkörper** in beide Richtungen, Header bleiben im Klartext (`ehbp/SPEC.md` §1, §7.2). Damit liegen `tools`, `tool_choice`, `messages[].tool_calls`, Tool-Ergebnisse und die komplette SSE-Antwort (inkl. `tool_calls`-Deltas) im Chiffretext. Streaming: Antwort ist ein Strom längenpräfixierter AEAD-Chunks, jeder Chunk einzeln authentisiert, Auslieferung ab dem ersten authentisierten Chunk erlaubt (`SPEC.md` §4.3, §5.2). Ein SSE-Ende ist nicht Teil des Protokolls; Vollständigkeit prüft die Anwendung (`SPEC.md` §6.2.1).
- Nur Anfragen **mit Body** werden geschützt (`SPEC.md` §7.4); `GET /v1/models` o. ä. bleibt Klartext (für uns unkritisch).
- Entschlüsselung: Jede Tinfoil-CVM führt den Sidecar `tfshim` aus, der EHBP terminiert (`tfshim/api.go:127-175`, `tfshim/main.go:76-110`) und danach an den lokalen Upstream (`127.0.0.1`) weiterreicht. Der Einstiegspunkt `inference.tinfoil.sh` ist der **Router-Enclave**; er liest den Modellnamen aus dem Klartext-Body, verifiziert Modell-Enclaves (SEV-SNP oder TDX-Quote, Sigstore inkl. Rekor) und leitet über **gepinntes TLS** weiter (Doku `https://docs.tinfoil.sh/verification/attestation-architecture`; `router/README.md:3-12`). **Der Klartext liegt also im Router-CVM und im Modell-CVM**, nicht auf Host oder Betreiber-Infrastruktur. Das ist strukturell ähnlich wie beim Phala-Gateway (Ende im Gateway-CVM, nicht im Modell-TEE), mit dem Unterschied, dass `tools`/`tool_calls` geschützt sind und der Router-Code samt Modell-Repo-Zuordnung in der Router-Messung steht (Doku, gleiche Seite).
- Der SDK erlaubt auch, einen bestimmten Enclave direkt zu adressieren (`tinfoil-rs/README.md`, „Advanced Functionality“); ob Modell-Enclaves dauerhaft öffentlich direkt erreichbar sind **[?]**.

### 1.2 Protokoll
- HPKE (RFC 9180): KEM X25519-HKDF-SHA256, KDF HKDF-SHA256, AEAD AES-256-GCM, `info = "ehbp request"`; genau diese eine Suite, alles andere wird abgelehnt (`ehbp/SPEC.md` §3.2, §4.4.1).
- Schlüssel: `GET /.well-known/hpke-keys` (OHTTP-KeyConfig, RFC 9458) (`SPEC.md` §3.1). **Wichtig:** Der Schlüssel wird nicht von dort vertraut, sondern aus der Attestierung entnommen (siehe 1.3).
- Request: Header `Ehbp-Encapsulated-Key` (hex, 32 Byte `enc`), Body = Folge von `LEN(4 Byte BE) || AEAD-Chunk`, AAD leer, ein HPKE-Kontext, Sequenznummer zählt nur nichtleere Chunks (`SPEC.md` §4.1, §4.3).
- Response: Header `Ehbp-Response-Nonce` (32 Byte hex). Schlüssel: `secret = Export("ehbp response", 32)`, `salt = enc || nonce`, HKDF-Extract/Expand mit „key“/„nonce“, AES-256-GCM, Nonce pro Chunk = `nonce_base XOR i` (`SPEC.md` §4.4.1). Antwort ist damit an die Anfrage gebunden (Replay/Austausch nicht möglich, `SPEC.md` §7.1).
- Fail-closed ist normativ: fehlender Nonce bei 2xx = Abbruch, kein Klartext-Fallback (`SPEC.md` §5.3).
- Komplexität: klein. Rust-Referenz `ehbp/rust/src/derive.rs` (359 Z.) + HPKE über Crate `hpke 0.13` (X25519); wir haben `x25519-dalek`/`hkdf`/`aes-gcm` bereits, brauchen aber eine RFC-9180-Schlüsselplanung (Crate `hpke` oder ~100 Zeilen selbst). Streaming-Chunk-Parser ist ebenfalls klein. Dart: nur Port-Anbindung wie bei `AttestationCrypto`.
- **Testvektoren: ja.** `ehbp/test-vectors/derive.json`, `response-decryption.json`, `session-recovery-token.json`, dazu ein Konformanzpaket `ehbp/test-vectors/conformance/{crypto,e2e,shape,server-security}.json` (~200 KB) und `ehbp/conformance/`. Request-seitig gelten die HPKE-Vektoren aus RFC 9180 Anhang A.
- Referenzen zum Portieren: Go (Original, `ehbp/client`, `ehbp/identity`), JS, Python, Swift, **Rust** (`ehbp/rust`, Crate `tinfoil-ehbp` 0.4.1, MIT). Lizenz MIT bzw. Apache-2.0 (SDKs).

### 1.3 Attestierung und Schlüsselbindung
- Format: `GET /.well-known/tinfoil-attestation` liefert `{format, body}` (Live bestätigt: `inference.tinfoil.sh` → `https://tinfoil.sh/predicate/sev-snp-guest/v2`, gzip+base64). `GET https://atc.tinfoil.sh/routers?platform=snp` → `["router-0.tinfoil.sh","inference.tinfoil.sh"]`, `platform=tdx` → `[]` (Live, 2026-10-15). **Produktion läuft also auf AMD SEV-SNP.** Der Go-Verifier kann auch Intel TDX (`go/verify/README.md`), der Rust-Client **nicht** (`tinfoil-rs/src/verifier/attestation/mod.rs:101-104`: „Intel TDX attestation not yet implemented“).
- Bindung: Der Enclave erzeugt TLS-Schlüssel und HPKE-Schlüssel und legt `report_data = SHA256(TLS-SPKI)(32 Byte) || HPKE-Pubkey(32 Byte)` (64 Byte) in die Hardware-Quote (`tfshim/attestation.go:17-27`, `tfshim/main.go:92-110`). Der Client nimmt den HPKE-Schlüssel nur aus der geprüften Quote (`tinfoil-rs/src/client.rs:257-262, 380-386`) und vergleicht ihn zusätzlich mit den kodierten SANs des TLS-Zertifikats (`client.rs:479-485`).
- Code-Herkunft: Sigstore-Bundle (GitHub Actions `measure-image-action`), DSSE, Fulcio, Rekor-Inklusion, SCT; Messung der Quote wird gegen die signierten Messwerte verglichen (`tinfoil-rs/src/verifier/sigstore/*`, ~2500 Z.; Doku `attestation-architecture`). Neuere Go-Versionen nutzen ein „V3“-Dokument (ein Abruf mit Nonce, eingebettete Kollateralien, offline prüfbar, Frische-Zeugen max. 7 Tage) (`go/verify/README.md`, Abschnitt „V3 verification flow“).
- GPU: Beim Start prüft der Enclave per `nvattest` den CC-Modus der GPUs und startet sonst nicht; der Client prüft nur die CPU-Quote, GPU indirekt (Doku `attestation-architecture`). Das Go-SDK kennt ein Format `nvidia-gpu-evidence/v1` im neuen Dokument (`go/verify/document/document.go:53`), ob Clients es prüfen **[?]**. Kein NRAS im Client-Pfad, den ich gefunden habe.
- Wiederverwendbar aus `native/attest`: SHA-256/384, Ed25519-Verify, SPKI-Hash (`spki.rs`), Pin-Logik und Fail-closed-Gerüst (`PhalaVerifier`-Stufenmodell, ADR 0014). **Neu:** SEV-SNP-Report-Parsing und -Prüfung (VCEK/ASK/ARK-Kette von AMD KDS, TCB/Policy; Referenz: Crate `sev` mit `crypto_nossl`, in `tinfoil-rs/Cargo.toml`), komplette Sigstore-/Rekor-/Fulcio-Prüfung samt Merkle-Beweisen, Messwert-Abgleich, HPKE/EHBP. TDX-Quote/DCAP/NRAS helfen hier **nicht**, solange Tinfoil auf SNP läuft.

### 1.4 OpenAI-Kompatibilität, Modelle, Konto
- Chat Completions OpenAI-kompatibel; Function Calling: „Most chat models support function calling“, Kimi K3 empfohlen (`https://docs.tinfoil.sh/guides/tool-calling`). Streaming mit Tools: Doku schweigt, EHBP-Stream ist aber protokollseitig vorgesehen **[?] nicht praktisch getestet**.
- Modelle laut `https://docs.tinfoil.sh/models/chat`: Kimi K3 (2,8 T / 104 B aktiv, 256K), GLM-5.3 (743 B / 39 B aktiv), DeepSeek V4.1 Flash (552 B, experimentell), Gemma 4 31B (nativ Tools, 35+ Sprachen), GPT-OSS 120B (131K), Llama 3.3 70B (128K, mehrsprachig). Deutsch-Qualität nicht belegt **[?]**; Gemma 4 31B oder GPT-OSS 120B wären sinnvolle Kandidaten zum Testen.
- Preise: offizielle Seite nennt keine Zahlen (`https://tinfoil.sh/pricing`: „pay-as-you-go, per-model“). Drittquellen (unsicher): GPT-OSS 120B 0,15/0,60 USD, Gemma 4 31B 0,40/1,00, Llama 3.3 70B 1,75/2,75 je Mio. Token (typingmind-Aggregator). Tiers/Limits steigen mit bezahlter Nutzung, im Dashboard sichtbar; Konto + Stripe nötig (pricing-Seite).

### 1.5 Quittungen
- Keine signierte Antwortquittung gefunden (Suche nach receipt/signature im Router, SDKs, EHBP ohne Treffer in diesem Sinn). Integrität pro Antwort kommt aus EHBP (AEAD, an Anfrage gebunden) statt aus einer Signatur. Es gibt also **keinen „Receipts“-Ersatz** für `ExchangeRecord`/Prüfprotokoll **[?] nicht endgültig ausgeschlossen**.

### 1.6 Reife
- EHBP v0.4.1 vom 2026-10-14, 219 Commits, Konformanz-Suite seit 2026-10-05, aktive Sicherheitsfixes (z. B. „never trust Content-Length: 0 to skip encryption“, „clear GetBody on encrypted requests“); SDK-Rust `tinfoil` 0.2.1, Go-SDK schon bei V3-Verifikation und `v0.17.0-rc.2` im Router. Aktiv, aber schnelle Änderungen (Verifikationsformat V2 → V3) = Breaking-Change-Risiko. Es gibt ein Sicherheitsaudit-Dokument (`ehbp/conformance/SECURITY-AUDIT.md`, nicht gelesen).

---

## 2. NEAR AI Cloud

### 2.1 Was wird verschlüsselt, wo endet es
- Standard: nur `content`, `reasoning_content`, `reasoning`, `audio.data` (Doku `near/docs/cloud/guides/e2ee-chat-completions.mdx:623`). Mit Request-Header **`X-Encrypt-All-Fields: true`** zusätzlich: `tools[].function.{name,description,parameters}` (Schema als String), `tool_choice.function.name`, Nachrichten-`name`/`refusal`, `tool_calls[].function.{name,arguments}` in Anfrage und Antwort, Logprobs-Token (`e2ee-chat-completions.mdx:512, 621-640`; Implementierung `inference-proxy/src/encryption.rs:447-500, 603-640, 704-765`). **Damit schließt NEAR genau die Lücke, die bei Phala v2 offen ist.** Tool-Ergebnisse (Rolle `tool`, `content`) sind normaler `content` und damit verschlüsselt.
- Nicht verschlüsselt bleiben `model`, `stream`, Parameter, Rollen, Header (Gateway muss routen). Gilt für Chat Completions, Completions, Embeddings, Images; **nicht für die Responses API** (`e2ee-chat-completions.mdx:684`).
- Streaming: jeder SSE-Chunk wird einzeln verschlüsselt (`e2ee-chat-completions.mdx:690`; `encryption.rs:574-590`).
- Entschlüsselung: im **Modell-TEE**. Das Gateway kopiert nur die Header `X-Signing-Algo`, `X-Client-Pub-Key`, `X-Model-Pub-Key`, `X-Encryption-Version`, `X-Encrypt-All-Fields` durch (`cloud-api/crates/api/src/routes/completions.rs:57-90`) und entschlüsselt nicht (kein Entschlüsselungscode dort gefunden). Der `inference-proxy` (Rust, vor vLLM/sglang in der GPU-TEE-CVM; `inference-proxy/README.md:1-5`) entschlüsselt die Anfrage mit dem im TEE erzeugten Schlüssel und verschlüsselt die Antwort an den Client-Schlüssel. Die Doku-Sequenz zeigt dasselbe (`e2ee-chat-completions.mdx:24-47`). **Einschränkung:** Ob Anfrage-Klartext zwischen `inference-proxy` und vLLM innerhalb derselben CVM bleibt, ist per Architektur so gedacht, wurde aber nicht an der Deployment-Konfiguration geprüft **[?]**.
- Geltungsbereich: nur Modelle mit Anbieter `near` (eigene GPU-Flotte). „3P Confidential TEE“ (Chutes) und „Incognito“ (OpenAI/Anthropic/…) sind nicht Ende-zu-Ende zum Modell (`near/docs/cloud/models.mdx`; `e2ee-chat-completions.mdx:11`).

### 2.2 Protokoll (v2)
- Schlüssel: Modell-**Ed25519**-Pubkey (aus Attestierung) wird zu X25519 konvertiert (libsodium `crypto_sign_ed25519_pk_to_curve25519`); Client erzeugt ebenfalls Ed25519-Schlüssel und sendet ihn in `X-Client-Pub-Key`, Antwort geht an diesen Schlüssel. Pro Feld: ephemeres X25519 → ECDH → `HKDF-SHA256(salt=leer, info="ed25519_encryption")` → **XChaCha20-Poly1305**, 24-Byte-Nonce, **keine AAD**; Wire: `eph_pub(32) || nonce(24) || ct||tag`, Hex-kodiert in das JSON-Feld (`e2ee-chat-completions.mdx:50-59, 100-120`; `inference-proxy/src/encryption.rs:205-262`). Zweite Variante `ecdsa` (secp256k1-ECIES, AES-256-GCM) für Ethereum-Schlüssel (`encryption.rs:265-340`), brauchen wir nicht.
- Header: `X-Signing-Algo: ed25519`, `X-Client-Pub-Key`, `X-Model-Pub-Key`, `X-Encryption-Version: 2`, `X-Encrypt-All-Fields: true`, `x-no-aliasing: true` (`e2ee-chat-completions.mdx:130-142, 512`).
- Komplexität: sehr klein (Referenzcode in Python in der Doku; Rust in `inference-proxy/src/encryption.rs` ~100 Zeilen Krypto). Für `native/attest` fehlen nur `chacha20poly1305` (XChaCha) und die Ed25519→X25519-Konvertierung (`ed25519-dalek` `VerifyingKey::to_montgomery`; `x25519-dalek`/`hkdf` sind schon da). Feldlogik (JSON-Walk über `tools`, `tool_calls`, Nachrichten, SSE-Deltas) analog `E2eeProtocolV2`.
- **Testvektoren:** keine offiziellen, aber im Rust-Code ein festes libsodium/PyNaCl-Vektor-Paar (`encryption.rs:1069-1100`, Ed25519→X25519-Schlüssel und ein Chiffretext) und Rundlauf-Tests; E2E-Tests in `cloud-api/crates/api/tests/e2e_all/chat_encryption.rs`. Wir würden eigene Vektoren mit PyNaCl/Node erzeugen (wie bei WP62).
- **Kryptografische Schwächen (Bewertung von mir):** keine AAD, keine Bindung der Feldchiffre an Anfrage, Feldname oder Position, keine Antwort-an-Anfrage-Bindung (ein Gateway kann Felder vertauschen oder wiederholen, nur nicht lesen); dieselbe Ed25519-Identität dient Signatur und Verschlüsselung; Hex-Overhead. Sie mindern Vertraulichkeit gegen das Gateway nicht, Integrität nur über die (optionale) Signatur. Fehlender Replay-Schutz anders als Phala (300 s Zeitstempel).

### 2.3 Attestierung und Schlüsselbindung
- `GET /v1/attestation/report?model=…&provider=near&signing_algo=ed25519&nonce=<32 Byte hex>` (benötigt API-Key; Abruf kostenlos) liefert `gateway_attestation` und `model_attestations[]` (mehrere Kandidaten, alle prüfen, dann nach Policy wählen) (`e2ee-chat-completions.mdx:~200-300`; `near/docs/cloud/verification/reference/quote-nonce-signer.mdx`).
- Geprüft wird: Intel-**TDX**-Quote über `dcap-qvl` (identisch zu unserem Stack), TCB-Status, TD_ATTRIBUTES-Debug-Bit, `MRCONFIGID = 0x01 || SHA256(app_compose) || 0…`, **RTMR3-Replay** des dstack-Ereignislogs (SHA-384), GPU über **NVIDIA NRAS** (`nvidia_payload`, Nonce, `x-nvidia-overall-att-result`), optional TLS-SPKI-Bindung (`quote-nonce-signer.mdx:38-110`).
- Bindung: `report_data` (64 Byte) = Signier-Identität (Ed25519-Pubkey, 32 Byte; ohne TLS-Bindung) bzw. `SHA256(identity || tls_spki_sha256)` in den ersten 32 Byte; letzte 32 Byte = Client-Nonce (`quote-nonce-signer.mdx:38-46`). Der Verschlüsselungsschlüssel **ist** der attestierte Signaturschlüssel (`signing_public_key`).
- Code-Herkunft: Image-Digests aus `app_compose` extrahieren und per Provenance (Sigstore-ähnlich) prüfen; die Doku beschreibt das als **eigene, getrennte Policy** („Image Provenance“), kein fester Client-Schritt (`near/docs/cloud/verification/cloud-api/image-provenance.mdx`). Wir könnten es zunächst als „Compose-Hash gegen Allowlist“ lösen.
- Wiederverwendung: sehr hoch. Das ist die **dstack-Familie wie Phala** (Quote, `dcap-qvl`, Kollateral, NRAS, `report_data`, RTMR3/Compose-Hash, Ed25519-Verify). Neu: `report_data`-Layout, `signing_public_key`-Auswahl unter mehreren Kandidaten, RTMR3-Replay (falls bei Phala noch nicht vorhanden **[?]**), Compose-Allowlist, Policy-Objekt.
- Schwäche: Alle Instanzen eines Modells teilen einen Schlüssel; ein `provider_tee`-Signatur-Match beweist nicht dieselbe Instanz wie der geprüfte Bericht (`response-signatures.mdx`, Abschnitt „Instances…“).

### 2.4 OpenAI-Kompatibilität, Modelle, Konto
- OpenAI-kompatibel (`https://cloud-api.near.ai/v1/chat/completions`), `tools`, Streaming, `reasoning`. Live-Liste (`GET https://cloud-api.near.ai/v1/model/list`, 58 Modelle, 2026-10-15). Eigene Flotte (`providerType=vllm`, E2EE-fähig) mit Tools:

| Modell | USD/Mio. Token (ein/aus) | Kontext | Features |
|---|---|---|---|
| `Qwen/Qwen3.6-35B-A3B-FP8` | 0,17 / 1,10 | 262K | tools, structured_outputs, reasoning, logprobs |
| `Qwen/Qwen3.8-27B` | 0,04 / 1,35 | 262K | tools, structured_outputs, reasoning |
| `z-ai/glm-5.3-flash` | 0,08 / 0,50 | 1M | tools, structured_outputs, reasoning |

  Größere „attested“ Modelle (Kimi K3 3,30/16,50, Kimi K2.6, Qwen3.5-397B, DeepSeek V3.2) laufen über Chutes (3P-TEE) und sind laut Doku nicht Teil des NEAR-E2EE-Pfads (`e2ee-chat-completions.mdx:11`, `models.mdx`). Deutsch-Qualität der Qwen-/GLM-Modelle **[?]** nicht geprüft (Qwen3 und GLM sind mehrsprachig, aber ohne Messung).
- Konto/Key: Registrierung auf `cloud.near.ai`, Credits kaufen, API-Key erzeugen (`near/docs/cloud/quickstart.mdx:9-13`). Zahlungswege, Rate Limits **[?]** nicht in der Doku gefunden. Reasoning-Modelle: `reasoning`/`reasoning_content` sind verschlüsselt (müssen wir wie bei Phala behandeln).

### 2.5 Quittungen
- Ja. `GET /v1/signature/<chat_id>?signing_algo=ed25519` liefert `text` + `signature`; `text = <MODEL_ID>:SHA256(Request-Bytes):SHA256(Response-Bytes)` (`signature_kind=provider_tee`) oder `<req_hash>:<resp_hash>` (`gateway`) (`near/docs/cloud/verification/cloud-api/response-signatures.mdx`). Der Schlüssel muss zum vorab geprüften Modellbericht passen.
- **Achtung für Wendelin:** Bei **gestreamten** Antworten, Alias-Auflösung und Responses API signiert das **Gateway** statt des Modells (`response-signatures.mdx`, Absatz „The Gateway signs…“). Wendelin streamt immer; ob mit `x-no-aliasing` und passenden Stream-Optionen eine `provider_tee`-Signatur erreichbar ist, ist **[?]** offen und der wichtigste Testpunkt. Die Doku sagt selbst, die Kette Modell → Gateway → Endantwort sei noch nicht vollständig gebunden (`response-signatures.mdx`, Hinweis am Ende).
- Mit E2EE hashen Request/Response-Bytes vermutlich die verschlüsselte Form **[?]**; entspricht unserem Phala-Vorgehen für die Antwort.

### 2.6 Reife
- `inference-proxy`: Rust-Rewrite, E2EE-Cipher im März 2026 von XSalsa20 auf XChaCha20-Poly1305 geändert (Breaking, `encryption.rs` Commit 2026-03-12), Tool-/Feld-Verschlüsselung erst April 2026 (`X-Encrypt-All-Fields`, Commits 2026-04-10/13), Verifikationsdoku im Aug-Sep 2026 mehrfach umgebaut (`docs`-Log); „direct“-Endpunkte als experimentell markiert. Git-Tags des Proxys: nur `prod-2026…`-Releases. Stabilität mittel; die Protokollversionsnummer (`X-Encryption-Version: 2`) erlaubt aber saubere Trennung.

---

## 3. Vergleich der Kernfragen für Wendelin

| Frage | Tinfoil | NEAR |
|---|---|---|
| Tools/`tool_calls` verschlüsselt | ja (Ganzkörper) | ja, nur mit `X-Encrypt-All-Fields` (Pflicht für uns) |
| Ende der Entschlüsselung | Router-CVM + Modell-CVM (zwei Hops, beide attestiert) | Modell-TEE |
| Metadaten (Modell, Parameter) | Klartext-Header; Body komplett verschlüsselt, Router liest aber Modellname im Router-CVM | `model`, `stream`, Parameter im Klartext im Gateway-TEE |
| Antwort an Anfrage gebunden | ja (HPKE-Export) | nein (nur Client-Schlüssel) |
| Quittung | nein | ja (aber Streaming-Frage) |
| CPU-TEE | SEV-SNP (neu) | TDX (vorhanden) |
| Code-Herkunft | Sigstore/Rekor fest eingebaut | Compose-Hash, Provenance getrennt |
| Referenzcode | Rust, Go, JS, Swift, Python | Python (Doku), Rust (Server-Seite) |
| Reife des Protokolls | formale Spezifikation + Konformanz-Suite | Doku + Serverimplementierung, keine Spezifikation |

## 4. Aufwand für Wendelin (grobe Agenten-Stunden, WP62 ≈ 8 h inkl. Review)

**NEAR (≈ 12-16 h, 1,5-2 Tage):**
1. Rust `native/attest`: XChaCha20-Poly1305 + Ed25519→X25519 + Vektoren (≈ 2 h).
2. Dart: `NearE2eeCodec` (Felder in `messages`, `tools`, `tool_choice`, `tool_calls`, Response und SSE-Deltas, Hex-Format) analog `E2eeProtocolV2` (≈ 3 h).
3. `NearVerifier`-Stufen: Gateway- und Modellquote, `report_data`, Nonce, Debug-Bit, Compose-Hash/RTMR3, NRAS, Kandidatenwahl, Policy/Allowlist (≈ 4 h, viel Wiederverwendung aus `PhalaVerifier`).
4. Quittung (Ed25519-Signatur über `<Modell>:<req>:<resp>`) in `ExchangeRecord` einhängen (≈ 2 h).
5. Provider-Profil, Konto/Key-Eintrag, Live-Test (klein), Review (≈ 3 h).

**Tinfoil (≈ 24-40 h, 3-5 Tage):**
1. EHBP/HPKE in Rust + Chunk-Streaming in `ChatWireCodec` (Byte-Strom statt JSON-Felder, ≈ 4-5 h).
2. SEV-SNP-Prüfung (VCEK-Abruf bei AMD KDS, Kette ARK/ASK/VCEK, Policy/TCB, `report_data`) (≈ 8-12 h).
3. Sigstore/Rekor/Fulcio/DSSE/Merkle + Messwert-Abgleich; Crate-Reuse (`tinfoil-rs`, Rust ≥ 1.88, tokio/reqwest, Android-Cross-Build ungetestet) oder Port (≈ 10-16 h).
4. Router-Vertrauensmodell abbilden (Modell→Repo-Zuordnung, Router-Messung), Pinning, Tests, Review (≈ 4-6 h).
5. Keine Quittung: UI/Prüfprotokoll müssen ohne `receipt`-Stufe auskommen (zusätzliche Arbeit am Statusmodell).

## 5. Risiken
- **NEAR:** (a) Streaming-Quittung kommt vom Gateway statt vom Modell [?]; (b) kein AAD/keine Anfragebindung, Gateway kann Felder umsortieren, nicht lesen; (c) gemeinsamer Modellschlüssel über Instanzen; (d) Responses-API und Chutes-Modelle nicht E2EE; (e) Protokoll jung und nur durch Doku/Code spezifiziert; (f) Zahlung/Limits unklar; (g) kleine Qwen/GLM-Modelle statt 120B+; Tool-Treue und Deutsch zuerst messen.
- **Tinfoil:** (a) SEV-SNP und Sigstore sind viel neuer Sicherheitscode, der in Dart/Rust sauber geprüft werden muss; (b) Router sieht Klartext (attestiert, aber ein zusätzlicher Vertrauensanker, Modell-Routing im Router); (c) V2→V3-Verifikationswechsel läuft, Rust-SDK hinkt (TDX fehlt, Version 0.2.1); (d) keine Quittung; (e) Preise/Limits nur über Konto sichtbar; (f) Tool-Streaming nicht belegt.
- Beide: Anbieter-Wechsel ist eine Konzeptänderung (K28 „kein stiller Wechsel zu anderem Anbieter“) und braucht Eintrag im Änderungsprotokoll samt Bestätigung durch Stefan.

## 6. Empfehlung
1. **NEAR zuerst, als zusätzlicher Anbieter neben Phala** (nicht als Ersatz). Gründe: Tools/`tool_calls` verschlüsselt, Ende im Modell-TEE (Hauptproblem gelöst), gleiche TDX/dstack/`dcap-qvl`/NRAS-Familie wie Phala (höchste Wiederverwendung, geringster neuer Sicherheitscode), kleine Krypto, Quittungen vorhanden, Aufwand ≈ WP62.
   Vor dem Start einen **Spike (2-3 h, ein Konto, kleines Budget)**: (i) `X-Encrypt-All-Fields` mit Streaming und Tools gegen `Qwen3.6-35B-A3B` und `glm-5.3-flash` ausprobieren, (ii) prüfen, ob die Streaming-Signatur `provider_tee` oder `gateway` ist, (iii) Deutsch/Tool-Qualität anhand Wendelin-Prompts messen, (iv) Limits/Preise/Zahlweg klären.
2. **Phala behalten**, weil dort große Modelle (Konzeptgrundlage) und die Quittungen existieren; Phala bekommt keine Tool-Verschlüsselung, daher Tool-Anfragen nach Profil routen oder Tools bei Phala bewusst nur mit Hinweis zulassen (UI-Thema WP63).
3. **Tinfoil später** (eigenes WP), wenn (a) NEAR-Modelle für Deutsch/Tools nicht reichen oder (b) Ganzkörper-Verschlüsselung samt Antwortbindung gewünscht ist. Dann zuerst das SEV-SNP-Teilpaket als eigenes WP schneiden und prüfen, ob `tinfoil-rs`-Verifier als Abhängigkeit statt Port taugt.

## 7. Offene Fragen
- NEAR: Wer signiert gestreamte Antworten bei gesetztem `x-no-aliasing`? Wie sehen Rate Limits, Zahlungswege und Datenschutzfragen (Konto-Pflicht, Credits) aus? Hashen Quittungen bei E2EE die verschlüsselten Bytes?
- NEAR: Wird `app_compose` mit Image-Digests veröffentlicht und gibt es offizielle erwartete Compose-Hashes (Allowlist-Quelle)?
- Tinfoil: Preise offiziell, Streaming mit Tools praktisch, GPU-Evidence im Client-Pfad (V3), direkter Zugriff auf Modell-Enclaves ohne Router.
- Beide: Deutsch-Qualität und Tool-Treue der kleineren Modelle.
- Konzept: Anbieterwechsel/zweiter E2EE-Anbieter gegen K28/K37 prüfen, Eintrag im Änderungsprotokoll (Status `offen`).
