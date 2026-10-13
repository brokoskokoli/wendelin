# TEE-Fixtures (WP43, Probe 2026-10-14)

Echte Antworten von `api.redpill.ai` (Phala/RedPill), ohne Header und ohne API-Key.

- `gateway_attestation.json`: `GET /v1/aci/attestation?nonce=abab…ab` (32 Byte `ab`, 64 Hex).
- `receipt.json`: Quittung `rcpt-6120…` zu einer Mini-Anfrage (`z-ai/glm-5.3-flash`, 20 Tokens). Signaturschlüssel steht im Keyset der Attestierung.
- `session.json`: `GET /v1/aci/sessions/{session_id}` aus der Quittung (Upstream near-ai, TCB-Status `OutOfDate`).
- `collateral_pcs.json`: TDX-Kollateral von Intel PCS (`api.trustedservices.intel.com`), `nextUpdate` 2026-11-12.
- `model_report_trimmed.json`: `GET /v1/attestation/report?model=…&nonce=cdcd…cd`, gekürzt (ohne `all_attestations`, ohne `intel_quote`, nur GPU-0 in `nvidia_payload`).
- `nras_response.json`: Antwort von `POST https://nras.attestation.nvidia.com/v3/attest/gpu` auf alle 8 GPU-Evidenzen (Nonce `cdcd…cd`), signierte JWTs.

Prüfzeitpunkt für die Offline-Prüfung: Unix `1791934700` (Kollateral ist ein Monat gültig). Manipulierte Varianten entstehen in den Rust-Tests (`native/attest/tests/`).
