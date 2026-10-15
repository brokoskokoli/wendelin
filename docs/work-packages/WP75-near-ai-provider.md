# WP75 – NEAR AI Cloud als weiterer TEE-Anbieter mit E2EE inkl. Tools (`native/attest`, `wendelin_providers`, `app/`)

Bezug: Entscheidung Maintainer 2026-10-15 (NEAR AI zusätzlich zu Phala, nach Spike direkt umsetzen). Grundlagen: `docs/notes/e2ee-alternatives.md`, `docs/notes/near-spike.md`, ADR 0014/0018. K28 gilt: kein automatischer Anbieterwechsel.

## Inhalt
- **Attestierung (`NearVerifier`):** TDX-Quote (dcap-qvl wie Phala), `report_data` = Ed25519-Schlüssel ‖ Nonce, Compose-Hash/MRCONFIGID/RTMR3, NVIDIA NRAS (GPU), Gateway- und Modell-Quote getrennt bewerten; TCB `OutOfDate` = rot mit Hinweis (Regel M4). Allowlist für Compose-Hashes: Quelle laut Spike klären, bis dahin wie Phala „Herkunft nur protokolliert“. Wiederverwendung von `native/attest` und `AttestationStages`; neue Stufen nur, wo NEAR sich unterscheidet.
- **E2EE (`X-Encrypt-All-Fields: true`):** X25519 + HKDF-SHA256 + XChaCha20-Poly1305 nach NEAR-Referenz, in Rust; alle Felder inkl. `tools`, `tool_calls`, Tool-Ergebnisse; Streaming je SSE-Chunk. Schlüssel nur aus geprüfter Attestierung. Keine Klartext-Variante, fail-closed (K28). Da das Protokoll keine AAD/Bindung der Antwort an die Anfrage hat: eigene Bindungsprüfung, soweit möglich (z. B. Chat-ID/Nonce), sonst im ADR als Restrisiko.
- **TLS-Pin** wie WP61, sofern NEAR einen attestierten TLS-Schlüssel liefert; sonst begründen.
- **Quittung/Signatur:** abrufen und prüfen, wo verfügbar. Bei Streaming signiert laut Doku das Gateway – in Anzeige und Prüfprotokoll ehrlich ausweisen.
- **Provider-Profil „NEAR AI (TEE)“** im Einrichtungsassistenten (wie Phala), Modelle nur aus der NEAR-eigenen E2EE-Liste (keine über Chutes geroutete Modelle); Standard `z-ai/glm-5.3-flash` (Annahme, nach Live-Test bestätigen). Prüfprotokoll-Stufen, Schild, Hinweis „Tools Ende-zu-Ende-verschlüsselt“.
- **ADR 0019** (NEAR E2EE), Konzept-Eintrag durch den Orchestrator.

## Abnahmekriterien
- [ ] Rust-Tests (Rundlauf, Manipulation, eigener eingefrorener Vektor), Dart-Tests (kein Klartext im Wire inkl. Tools, kaputte/unverschlüsselte Antwort → Fehler, Streaming).
- [ ] Attestierungs-Tests mit aufgezeichneten öffentlichen NEAR-Attestierungen (Fixtures ohne Secrets).
- [ ] Live-Test (`@Tags(['live'])`, `NEAR_AI_API_KEY`, sparsam): Attestierung grün, E2EE-Chat mit Tool-Aufruf nicht-streaming und streaming. **Merge erst, wenn der Live-Test grün ist** (Key braucht Credits/Limit auf cloud.near.ai).
- [ ] Emulator-Fixture analog Phala (separater E2E-Agent).
- [ ] Gate grün.
