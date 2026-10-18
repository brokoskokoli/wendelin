# WP83 – NRAS-Token-Signatur prüfen, GPU-Quelle im Log (`native/attest` oder `wendelin_providers`, `app/`)

Bezug: Nachtest APK 11193bb (2026-10-16, `ergebnisse.md` 12.9): Das TEE-Prüfprotokoll zeigt „GPU-Evidenz: Ergebnis geprüft (NRAS), Signatur ungeprüft“. Die GPU-Aussage hängt dann nur an der TLS-Verbindung zu nras.attestation.nvidia.com und ist nicht nachträglich belegbar. Außerdem sagt die Logzeile `gpu gpu=pass` nicht, ob über NRAS oder nur lokal (Nonce-Bindung) geprüft wurde.

## Inhalt
1. **Signatur:** Das von NRAS gelieferte Ergebnis (JWT, ES384) gegen die öffentlichen NVIDIA-Schlüssel (JWKS von NVIDIA, `kid`) prüfen; Ablauf (`exp`/`iat`), Aussteller, Nonce und die relevanten Claims (`x-nvidia-overall-att-result` bzw. je GPU) aus dem **geprüften** Token lesen. JWKS mit Cache (Ablauf, Neuladen bei unbekanntem `kid`), Abruf über eine TLS-Verbindung zu NVIDIA, fail-closed (Signatur falsch → rot; JWKS nicht abrufbar → wie „nras nicht erreichbar“ behandeln, bestehende Logik). Kryptografie bevorzugt in Rust (`native/attest`, eigenes Modul) oder mit vorhandenen Dart-Abhängigkeiten; keine neuen schweren Abhängigkeiten ohne Begründung.
2. Gilt für Phala und NEAR (beide nutzen NRAS). Anzeige „Signatur geprüft“.
3. **Log/Anzeige:** `gpu gpu=pass via=nras|local` (bzw. `fail reason=…`) in der `Wendelin/attest`-Zeile; Prüfprotokoll-Stufe nennt die Quelle.
4. Testvektoren: echtes NRAS-Token (öffentlich, ohne Geheimnisse) aufzeichnen; manipulierte Signatur/Claims/abgelaufenes Token als Negativtests.

## Abnahmekriterien
- [ ] Rust-/Unit-Tests mit echten und manipulierten Tokens; Live-Test (`@Tags(['live'])`, sparsam) grün.
- [ ] ADR-Ergänzung (0018/0019 oder neu) und Konzept-Eintrag (Orchestrator). Gate grün.
