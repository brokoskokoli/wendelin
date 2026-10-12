# Phala/RedPill ACI – Probe vom 2026-10-13

Kurzer Live-Test der Attestierungs- und Quittungs-Endpunkte als Grundlage für M4 (`AttestedProvider`, `PhalaVerifier`). Base-URL `https://api.redpill.ai/v1`, Auth `Authorization: Bearer <key>` (Key-Präfix `sk-rp-`). Kosten des Tests: ca. 0,00001 USD.

## Endpunkte

| Zweck | Aufruf | Ergebnis |
| --- | --- | --- |
| Modelle | `GET /v1/models` | 200, 66 Modelle, Feld `is_tee` (18 × true, z. B. `z-ai/glm-5.3-flash`, `z-ai/glm-5.3`, `qwen/qwen3.6-27b`, `openai/gpt-oss-120b`, `meta-llama/llama-3.3-70b-instruct`) |
| Gateway-Attestierung | `GET /v1/aci/attestation?nonce=<64 hex>` | 200, ~50 KB, `api_version: aci/1` |
| Attestierung inkl. Modell/GPU | `GET /v1/attestation/report?model=<id>&nonce=<64 hex>` | 200, ~320 KB; zusätzlich `signing_address`/`signing_public_key` (ECDSA), `intel_quote`, `nvidia_payload`, `all_attestations` |
| Chat | `POST /v1/chat/completions` (OpenAI-kompatibel) | 200; Header `x-receipt-id`, `x-aci-version`, `x-aci-keyset-digest`, `x-e2ee-applied` |
| Quittung | `GET /v1/aci/receipts/{x-receipt-id}` | 200, signierte Quittung (Ed25519) |
| Signatur (Legacy) | `GET /v1/signature/{chat_id}?model=<id>&signing_algo=ecdsa` | 200, Quittung + `text = sha256(req):sha256(resp)` + ECDSA-Signatur der Signing-Address |

## Inhalt der Attestierung (`/v1/aci/attestation`)

- `workload_keyset_digest` (sha256), `attestation.tee_type = tdx`
- `workload_keyset`: `receipt_signing_keys` (Ed25519, `key_id: dstack-kms-receipt-ed25519-v1`), `e2ee_public_keys` (secp256k1 und x25519, AES-256-GCM/HKDF), `tls_public_keys` (SPKI-SHA256 für `api.redpill.ai`, `tee.redpill.ai`, `inference.phala.com`), `not_after` (Keyset läuft ab, aktuell 2026-11-11)
- `report_data` (32 Byte) und `evidence.quote` (TDX-Quote, ~5 KB), `event_log`, `vm_config`, `app_compose`, `key_custody` (dstack-kms)
- `evidence.downstream_tls_binding`: Domain `api.redpill.ai` + SPKI-SHA256 → **TLS terminiert in der Enklave**, TLS-Pinning ist möglich
- `source_provenance`: `repo_url` `github.com/Dstack-TEE/private-ai-gateway`, `repo_commit`; `image_digest` aktuell `null`

## Geprüft

- Nonce-Bindung `/v1/attestation/report`: Nonce steht in `report_data` (nach der Signing-Address) und im `nvidia_payload` ✓
- Nonce-Bindung `/v1/aci/attestation`: `report_data` ist **nicht** `sha256(nonce)` oder `sha256(nonce‖keyset_digest)` – Ableitung steht im Quellcode des private-ai-gateway, für M4 klären.
- **GPU-Attestierung vorhanden** (offene Frage aus dem Konzept): mit `model=` kommt NVIDIA-Evidenz für 8 × Hopper, nonce-gebunden.
- Quittung: `event_log` mit `request.received` → `route.selected` → `upstream.verified` → `response.returned`; `body_hash` von `request.received` = SHA-256 der exakt gesendeten Bytes ✓, `response.returned` = SHA-256 der exakt empfangenen Bytes ✓. (`response.received` ≠ `response.returned`: Gateway ergänzt die Antwort, z. B. Kosten.)
- Quittungssignatur: Ed25519 über die Quittung ohne `signature`, als JSON mit sortierten Schlüsseln und kompakten Trennern → **gültig** mit dem `receipt_signing_keys`-Schlüssel aus der Attestierung; manipulierte Quittung → ungültig ✓.

## Abweichungen vom Konzept / für M4 beachten

- Kein `workload_id` und kein `freshness.stale_after` in der Antwort. Pinning daher auf `workload_keyset_digest` (+ `repo_commit`), Frische über `not_after` und die eigene Nonce.
- `upstream.verified` hatte `required: false` bei `result: verified`. Das Konzept erwartet `required: true`; vermutlich nur bei angeforderter Pflichtprüfung (Header/Option klären). Prüfung in der App: mindestens `result == verified`.
- Upstream im Beispiel: `near-ai:z-ai/glm-5.3-flash` – der Gateway leitet an einen weiteren TEE-Anbieter weiter; die Kette steht im `route.selected`-Eintrag.
- `glm-5.3-flash` ist ein Reasoning-Modell: bei `max_tokens: 20` war `content` leer (alle Tokens Reasoning). Für den „klein, ohne Reasoning“-Default Reasoning abschalten oder anderes Modell wählen.
- E2EE wird angeboten (`supported_e2ee_versions: ["2"]`, `x-e2ee-applied`), war im Test aus.
