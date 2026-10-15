# WP76 – Tinfoil als weiterer TEE-Anbieter mit E2EE (EHBP/HPKE) (`native/attest`, `wendelin_providers`, `app/`)

Bezug: Entscheidung Maintainer 2026-10-15 (Tinfoil zusätzlich, umsetzen, sofern ohne große Schwierigkeiten – Spike: ja). Grundlage: `docs/notes/tinfoil-spike.md`, `docs/notes/e2ee-alternatives.md`. K28: kein automatischer Anbieterwechsel.

Aufteilung (Spike: ~27–38 Agenten-Stunden):
- **WP76a – SEV-SNP-Attestierung in Rust:** Report parsen, VCEK/ASK/ARK-Kette (AMD KDS, ARK gepinnt), TCB/Policy, `report_data` = TLS-SPKI ‖ HPKE-Schlüssel; Testvektoren aus aufgezeichneten öffentlichen Reports.
- **WP76b – Sigstore/Rekor:** Code-Hash des Routers gegen das signierte Release prüfen (Trust-Root gepflegt, offline-fähig mit Cache); APK-Zuwachs messen (Ziel ≤ ~1,2 MB je ABI).
- **WP76c – EHBP/HPKE:** Anfrage und Antwort (inkl. SSE-Strom) verschlüsseln/entschlüsseln, 25 Antwort-Vektoren aus der Referenz als Tests, TLS-Pin (SPKI aus dem Report) wie WP61, fail-closed.
- **WP76d – Anbieter-Profil „Tinfoil (TEE)“:** Einrichtung, Modelle (Standard gpt-oss-120b oder gemma4-31b nach Eval), Prüfprotokoll-Stufen (SNP, Sigstore, TLS, E2EE), Hinweis „keine Quittung je Antwort“, Live-Test (Tools, Streaming, zweiter Zug mit Tool-Ergebnis), Emulator-Fixture, ADR 0020.

## Abnahmekriterien
- [ ] je Teil Unit-/Rust-Tests mit Vektoren; Live-Test (`TINFOIL_API_KEY`, sparsam) grün; Emulator-Fixture (E2E-Agent); Gate grün.
