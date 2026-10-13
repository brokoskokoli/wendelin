# WP43 – Spike Attestierung und Rust-Build (Klärung, Messung, Entscheidung)

Abhängig von: – (sofort startbar). Ergebnis: Notiz `docs/notes/attestation-spike-<datum>.md`, eingecheckte Fixtures unter `packages/wendelin_providers/test/fixtures/tee/` (nach `tool/check_secrets.dart`) und die Entscheidung Weg A/B (`M4.md`, Recherche 4). Grundlage: `docs/notes/phala-aci-probe-2026-10-13.md`.

## Fragen

1. **Format (sparsame Live-Probe, Keys aus `~/.wendelin-live.env`, nie ausgeben):** Aktuelles `/v1/aci/attestation` und eine Quittung zu einer Mini-Anfrage (kleinstes TEE-Modell, ≤ 20 Tokens). Liefert die API inzwischen `workload_id`, `freshness.stale_after` und `keyset_endorsement`? Gibt es einen Header oder eine Option, die `upstream.verified.required: true` erzwingt? Wie sieht `/v1/aci/sessions/{id}` aus?
2. **`report_data`-Ableitung** beim ACI-Endpunkt aus dem Quellcode von `github.com/Dstack-TEE/private-ai-gateway`: Welche Bytes (Nonce, Keyset-Digest, Kanonisierung des Keysets) gehen in die 64 Byte? Wie wird der Keyset-Digest kanonisch berechnet, und wie wird `keyset_endorsement` geprüft? Gegenprobe mit den Fixtures.
3. **Event-Log:** Lässt sich RTMR3 aus `event_log` nachrechnen und der Compose-Hash (`app_compose`) belegen? Reicht das, um `source_provenance.repo_commit` an die Messung zu binden?
4. **Kollateral:** Intel PCS (`api.trustedservices.intel.com`, TDX v4) direkt gegen den PCCS von Phala. Größe, Gültigkeit (`nextUpdate`), Abrufzeit. Offline-Prüfung mit gecachtem Kollateral.
5. **Rust-Weg A:** Crate `native/attest` mit `dcap-qvl` (MIT), `ed25519-dalek`, `sha2`; `flutter_rust_bridge` 2.12. Build für `aarch64-linux-android` (Pflicht), dazu `x86_64-linux-android` und `armv7-linux-androideabi`, falls die App sie ausliefert. Gemessen werden die Prüfzeit eines echten Quotes auf dem Emulator, der APK-Zuwachs je ABI und die Build-Zeit. Benötigt werden `rustup` (Homebrew-Rust hat nur `aarch64-apple-darwin`) und NDK, Frage 1 an den Maintainer.
6. **Weg B:** `com.phala:dcap-qvl-android` (Maven Central, JNA) in einem Test-Build. Gemessen werden Prüfzeit, APK-Zuwachs und ob `tool/check_apk.sh` (K7) grün bleibt. Ed25519 dann in Dart (Paketwahl, Lizenz).
7. **Gate/CI:** Welche Schritte braucht `tool/gate.dart` (z. B. `cargo test`, `cargo clippy -D warnings`, `cargo deny check`, Prüfung „generierter frb-Code aktuell“), und was braucht der `apk`-Job in `.github/workflows/gate.yml` (rustup-Targets, `cargo-ndk`, Cache)? Läuft das Gate weiter ohne Rust (Paket überspringen mit Hinweis), damit reine Dart-Arbeit nicht blockiert?
8. **TLS-Pinning in Dart:** Lässt sich die SPKI des Serverzertifikats bei einer gültigen Kette prüfen (eigene `connectionFactory` mit `SecureSocket`, `peerCertificate.der` → SPKI-SHA256)? Wo läuft das Parsen, in Rust oder in Dart?

## Entscheidungen
- Weg A oder B, mit Messwerten (Vorschlag aus `M4.md`: A, wenn Build in Gate und CI ≤ 1 Tag stabil).
- Genaue Prüfschritte und Feldnamen für WP46, Kanonisierung, `report_data`-Layout.
- Kollateral-Quelle und Cache-Regeln.
- TCB-Status-Abbildung (UpToDate, SWHardeningNeeded, ConfigurationNeeded, OutOfDate, Revoked → grün/gelb/rot), Vorschlag für die Frage an den Maintainer.

## Abnahmekriterien
- [ ] Notiz mit Antworten auf 1–8. Unklares ist als offen markiert, mit Quelle (Datei/Zeile im Gateway-Quellcode, Doku-Link).
- [ ] Fixtures: Gateway-Attestierung, Quittung, ggf. Modell-Report, je mit Probedatum, ohne Header und Keys; `tool/check_secrets.dart` grün. Zusätzlich je eine manipulierte Variante (Quote-Byte, Quittungsfeld, Nonce).
- [ ] Prototyp (Spike-Branch) verifiziert die Fixture-Quote offline mit gecachtem Kollateral und meldet TCB-Status. Prüfzeit auf dem Emulator ist gemessen.
- [ ] APK-Zuwachs für A und B gemessen (`tool/check_apk.sh` bleibt grün).
- [ ] Liste der Gate-/CI-Änderungen für WP47.
- [ ] Kosten der Live-Probe im Bericht (Ziel < 0,01 USD).
