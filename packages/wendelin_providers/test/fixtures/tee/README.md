# TEE-Fixtures (WP43, Probe 2026-10-14)

Echte Antworten von `api.redpill.ai` (Phala/RedPill), ohne Header und ohne API-Key.

- `gateway_attestation.json`: `GET /v1/aci/attestation?nonce=abab…ab` (32 Byte `ab`, 64 Hex).
- `receipt.json`: Quittung `rcpt-6120…` zu einer Mini-Anfrage (`z-ai/glm-5.3-flash`, 20 Tokens). Signaturschlüssel steht im Keyset der Attestierung.
- `session.json`: `GET /v1/aci/sessions/{session_id}` aus der Quittung (Upstream near-ai, TCB-Status `OutOfDate`).
- `collateral_pcs.json`: TDX-Kollateral von Intel PCS (`api.trustedservices.intel.com`), `nextUpdate` 2026-11-12.
- `model_report_trimmed.json`: `GET /v1/attestation/report?model=…&nonce=cdcd…cd`, gekürzt (ohne `all_attestations`, ohne `intel_quote`, nur GPU-0 in `nvidia_payload`).
- `nras_response.json`: Antwort von `POST https://nras.attestation.nvidia.com/v3/attest/gpu` auf alle 8 GPU-Evidenzen (Nonce `cdcd…cd`), signierte JWTs.

Prüfzeitpunkt für die Offline-Prüfung: Unix `1791934700` (Kollateral ist ein Monat gültig). Manipulierte Varianten entstehen in den Rust-Tests (`native/attest/tests/` (Branch `wp/43-spike-attestation`)).

## `aci_verified/` (WP47, Probe 2026-10-14 03:18 UTC)
Zweiter Satz mit einer Anfrage, die `"provider":{"aci_verified":true}` setzt (`upstream.verified.required: true`). Das Gateway hatte inzwischen ein neues Keyset (Digest `f41362b5…`, `not_after` 1794417333), deshalb gehören Bericht und Quittung zusammen, nicht zum Satz oben. Prüfzeitpunkt `1791947900`, Kollateral weiter `collateral_pcs.json`, Nonce `abab…ab`.

- `request_body.json`: die exakt gesendeten Bytes (ohne Zeilenumbruch am Ende). `sha256` davon steht als `body_hash` im Ereignis `request.received` der Quittung.
- `response_body.json`: die exakt empfangenen Bytes. `sha256` davon steht im Ereignis `response.returned`.
- `response_headers.txt`: `x-receipt-id`, `x-aci-version`, `x-aci-keyset-digest` der Antwort.
- `receipt.json`: `GET /v1/aci/receipts/{x-receipt-id}`; `attestation.json`: `GET /v1/aci/attestation?nonce=abab…ab`.

- `nras_signed.json`: echte NRAS-Antwort (2026-10-18, 1 GPU, Nonce `75b040ac…1eab`), Gesamt-JWT mit ES384-Signatur samt abgetrenntem GPU-Token. `nras_jwks_subset.json`: der zugehörige öffentliche NVIDIA-Schlüssel (Auszug aus `https://nras.attestation.nvidia.com/.well-known/jwks.json`, nur `kty/crv/kid/x/y`). Beides öffentlich, keine Geheimnisse. Das Token läuft ab (`exp` 1792322298), Tests setzen die Uhr.
