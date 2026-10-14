# WP62 – Phala-E2EE v2 verpflichtend (`native/attest`, `wendelin_providers`)

Abhängig von: WP61. Bezug: Wunsch Maintainer 2026-10-14 („nur die End-to-End-Encrypted Endpoints verwenden“), K37 (offen), Doku https://docs.phala.com/phala-cloud/confidential-ai/confidential-model/e2ee-encryption

## Inhalt
- **Protokoll v2:** Header `X-E2EE-*`; je Feld ephemeres ECDH → HKDF-SHA256 → AES-256-GCM. Profil **x25519**. Verschlüsselt werden Nachrichteninhalte, entschlüsselt Antwort und Stream-Deltas. Exakte Feldliste, Header und Formate aus der Phala-Doku/Referenzimplementierung übernehmen und im Code mit Quelle belegen.
- **Krypto in Rust** (`native/attest`): `x25519-dalek`, `hkdf`, `aes-gcm`; Dart ruft über flutter_rust_bridge. Ephemere Schlüssel nie loggen.
- **Schlüssel nur aus geprüfter Attestierung:** `workload_keyset.e2ee_public_keys`, gebunden über `report_data`; ohne grüne Attestierung kein Schlüssel.
- **Keine Klartext-Variante:** Phala-Profile senden nur verschlüsselt. Server antwortet unverschlüsselt, Header fehlen oder Entschlüsselung scheitert → Abbruch mit Fehler (K28), nie Klartext anzeigen oder senden.
- **Streaming bleibt;** Deltas werden einzeln entschlüsselt.
- **Quittung:** `body_hash` wird gegen den entschlüsselten Body bzw. das, was Phala signiert, geprüft (laut Doku klären, im Bericht festhalten).
- **Grenzen ehrlich:** v2 verschlüsselt keine Tool-Definitionen und keine `tool_calls`-Argumente; diese laufen über gepinntes TLS (WP61). Die Verschlüsselung endet im Gateway-CVM, nicht im Modell-TEE. Beides geht an WP63 (Anzeige) und ins Konzept.
- **v3:** Phala hat v2 eingefroren, Umstellung bis 10.02.2027 → Protokollversion als eigener Baustein kapseln.

## Abnahmekriterien
- [x] Rust-Tests mit Testvektoren (Rundlauf und, falls Phala welche veröffentlicht, deren Vektoren).
- [x] Dart-Tests: Request enthält keinen Klartext der Nachrichten (Fake-Server prüft Body); fehlende/kaputte Verschlüsselung in der Antwort → Fehler, kein Klartext; Stream mit verschlüsselten Deltas.
- [~] Live-Test (`@Tags(['live'])`, ein kleiner Request, ein Streaming-Request) gegen RedPill mit Gemma 4 31B: Key ohne Guthaben (HTTP 402); stattdessen Beleg, dass der Dienst richtig und falsch verschlüsselte Anfragen unterscheidet (siehe ADR 0018). Antwortpfad live offen bis Guthaben da ist.
- [ ] Emulator-Lauf durch separaten E2E-Agenten.
- [ ] Gate grün (inkl. Rust/CI).
