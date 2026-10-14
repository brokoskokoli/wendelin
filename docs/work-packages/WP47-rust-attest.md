# WP47 – Rust-Prüfmodul und Anbindung (`native/attest` + App-Implementierung von `AttestationCrypto`)

Abhängig von: WP43 (Weg A oder B, Gate/CI-Liste), Port-Signatur aus WP46. Andockpunkte: Projektstruktur `native/attest` (Konzept), App-Ports unter `app/lib/platform/` (neuer Ordner `attest/`), `tool/gate.dart`, `.github/workflows/gate.yml`, `tool/check_apk.sh`, `app/android/app/build.gradle.kts`. Konzept „Plattform und Tech-Stack“ (TEE-Prüfung).

## Inhalt (Weg A, Konzept)
- Crate `native/attest`: dünne API über `dcap-qvl` (Quote prüfen mit übergebenem Kollateral, Report-Felder, TCB-Status, Advisory-IDs), `ed25519-dalek`, `sha2`, SPKI-Extraktion aus X.509-DER. Kein Netz im Crate: Das Kollateral holt Dart über den vorhandenen HTTP-Stack und reicht es hinein. Unit-Tests in Rust mit den Fixtures aus WP43.
- `flutter_rust_bridge`-Anbindung, generierter Code eingecheckt, Prüfung „aktuell“ im Gate.
- Build für die ABIs, die die App ausliefert (mindestens `arm64-v8a`), über cargokit/`cargo-ndk`. Die Release-Größe ist optimiert (`opt-level = "z"`, `lto`, `strip`).
- App: `RustAttestationCrypto implements AttestationCrypto`, Kollateral-Cache (Datei, bis `nextUpdate`), Riverpod-Provider in `app/lib/di/`.
- Gate: Schritt `native/attest` mit `cargo test`, `cargo clippy -D warnings`, `cargo deny check` (Lizenzen, MIT/Apache erlaubt). Ohne `cargo` wird der Schritt mit Hinweis übersprungen, CI erzwingt ihn. CI: rustup-Targets und Cache im `apk`-Job, Rust-Job für `cargo test`.

## Inhalt (Weg B, falls WP43 so entscheidet)
- `com.phala:dcap-qvl-android` über einen Kotlin-Kanal `app.wendelin/attest` (Tabelle in `docs/ARCHITECTURE.md` nachführen), Ed25519/SHA in Dart (Paket mit permissiver Lizenz). Gleicher Port, gleiche Tests.

## Abnahmekriterien
- [ ] Contract-Test des Ports (aus WP46 `testing.dart`) läuft gegen die echte Implementierung auf dem Emulator (`integration_test`, `Wendelin_AOSP_35`): Fixture-Quote grün, manipulierte Quote rot, Ed25519 gültig/ungültig, SPKI-Hash eines bekannten Zertifikats.
- [ ] Prüfzeit einer Quote auf dem Emulator gemessen und im Bericht (offene Frage im Konzept „Performance der DCAP-Prüfung auf dem Handy“).
- [ ] APK-Zuwachs je ABI im Bericht. `tool/check_apk.sh` grün (K7, keine neuen GMS-/Firebase-Klassen).
- [ ] Gate lokal und CI grün, auch auf einem Rechner ohne Rust (Schritt übersprungen, mit Hinweis).
- [ ] `cargo deny check` grün, Lizenzen im Bericht.
- [ ] `docs/ARCHITECTURE.md` (Ports-Tabelle, ggf. Kanäle) und `docs/ENGINEERING.md` (Rust-Regeln, Toolchain) nachgeführt.

## Prüfliste für den Maintainer (echtes Telefon)
- [ ] Prüfzeit der Attestierung beim ersten Start einer Phala-Sitzung (Logzeile `attest-done ms=…`) notieren.

## Nachtrag aus Spike WP43 (Review 2026-10-14)
- Ausgangspunkt: Prototyp `native/attest/` auf Branch `wp/43-spike-attestation` (nicht auf main), Ergebnisse in `docs/notes/attestation-spike-2026-10-14.md`, Fixtures in `packages/wendelin_providers/test/fixtures/tee/`.
- Offen aus WP43: vollständiger APK-Bau mit Rust-Bibliothek und `tool/check_apk.sh` (APK-Zuwachs messen); `cargo deny`-Liste braucht zusätzlich ISC, Zlib, Unicode-3.0, Unlicense-OR-MIT.
- Negativtests ergänzen, die im Prototyp fehlen: RTMR3-Replay, Compose-Hash, TLS-Bindung (Mutation „Ergebnis fest true“ muss rot werden); schwache `||`-Prüfung in `tests/fixtures.rs:55` und falscher Kommentar Z. 34 (Byte 600 liegt in report_data) korrigieren.
- Quellenbelege für report_data und Keyset-Digest im Gateway-Quellcode mit Datei:Zeile nachtragen.
- Fixture mit `provider.aci_verified: true` ergänzen.
