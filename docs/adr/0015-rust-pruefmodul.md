# ADR 0015 – Rust-Prüfmodul für die TEE-Attestierung (`native/attest`)

Status: vorgeschlagen · 2026-10-14

## Kontext
Die Prüfung von TEE-Antworten (Konzept K23 h, WP46/WP47) braucht Quote-Prüfung (Intel DCAP: Zertifikatsketten, CRLs, TCB-Info, QE-Identität), Ed25519, SHA-384, JCS-Kanonisierung, das Nachrechnen von RTMR3 und den SPKI-Hash. Die Spike WP43 hat zwei Wege gemessen: Rust (`dcap-qvl` über `flutter_rust_bridge`) und die Android-Bibliothek `com.phala:dcap-qvl-android` mit Kotlin-Kanal.

## Entscheidung
Weg A: Crate `native/attest` (Rust, `dcap-qvl` mit `rustcrypto`-Backend, `ed25519-dalek`, `sha2`, `x509-cert`), angebunden über `flutter_rust_bridge` 2.12. Gründe laut Spike: alle Prüfschritte in einem getesteten Crate mit einem Fixture-Satz, Prüfzeit im einstelligen Millisekundenbereich, kleine Bibliothek, kein Kotlin/JNA, reiner Rust-Build ohne C-Abhängigkeit.

- **Kein Netz im Crate** (N3, ein HTTP-Stack): Der Crate sagt, welches Kollateral zu holen ist (`collateral_request`: FMSPC, CA, TEE-Art; `root_crl_url`), Dart holt es von Intel PCS und reicht die Antworten zurück (`build_collateral`). Zeit und Kollateral sind Parameter, die Funktionen sind rein.
- **Fehler im Ergebnis:** Prüfungen liefern Stufenfelder (`Verdict`, `QuoteInfo`, `ReceiptVerdict`); die Richtlinie (grün/gelb/rot, TCB-Abbildung) liegt in Dart (WP46).
- **Erzeugter Code eingecheckt**, das Gate prüft, dass er aktuell ist. Rust-Schritte im Gate; ohne Toolchain lokal übersprungen, in CI Pflicht.
- **Gradle** baut die `.so` mit `cargo-ndk` für die ABIs des Flutter-Builds.
- Weg B (AAR) bleibt als Rückfall möglich, weil der Port `AttestationCrypto` implementierungsunabhängig ist.

## Folgen
Das Repo braucht eine Rust-Toolchain für APK-Builds (Hinweise in `docs/ENGINEERING.md`). Der APK wächst um die `.so` (Messwerte im WP47-Bericht).

## Quellenbelege (Gateway `Dstack-TEE/private-ai-gateway` @ 24a31ff)
- Keyset-Digest `sha256:` + sha256(JCS(Keyset)): `crates/aci-protocol/src/identity.rs:27-29`; JCS mit ASCII-Schlüsseln und ganzen Zahlen, sonst Ablehnung: `crates/aci-protocol/src/digest.rs:33-64`.
- `report_data` = sha256 des Statements `{"keyset_digest":…,"nonce":…,"purpose":"aci.report_data.v1"}`, 32 Byte plus 32 Null-Byte im Quote: `identity.rs:44-87`; Nonce 64 Kleinbuchstaben-Hex: `identity.rs:32-39`.
- Quittung: Ed25519 über JCS ohne `signature`: `crates/aci-protocol/src/receipt.rs:7-15`.
- RTMR3-Nachrechnung und Compose-Hash: `crates/aci-verify/src/dstack.rs:145-173` und `:98-143`.
- Prüfreihenfolge, Ablauf und TLS-Kanalbindung (`tls_public_keys`, domaingebunden): `spec/aci.md` §9.1 (Zeilen 778-800).
