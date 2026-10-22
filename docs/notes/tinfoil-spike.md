# Tinfoil-Spike: E2EE mit Tools (EHBP/HPKE), Stand 2026-10-15

Skripte und Rohdaten (nicht im Repo): `<lokales Scratchpad>/tinfoil-spike/` (`ehbp-check/`, `verify-live/`, `live/`, `att.bin`, `proxy.json`, `models.json`, `docs/`). Quellen: `.../scratchpad/e2ee-alt/tinfoil/`. Ergänzt `e2ee-alternatives.md` (dort Abschnitt 1). **[?]** = unsicher/nicht belegt.

## Empfehlung

**Machbar ohne große Schwierigkeiten: ja, mit Einschränkung.** Die Technik funktioniert heute durchgängig (live belegt: Attestierung, Sigstore, EHBP-Rundlauf mit Tools, Streaming, Deutsch). Der Aufwand liegt fast nur im neuen Sicherheitscode (SEV-SNP und Sigstore), nicht in der Krypto. Realistisch ca. 3-5 Agenten-Tage (siehe 6). Der Router sieht den Klartext (attestiert) – das ist die einzige echte Vertrauensabweichung gegenüber „bis ins Modell-TEE“, aber besser als Phala heute (dort Tools im Klartext). Gegen NEAR als ersten Anbieter spricht nur, dass Tinfoil mehr Neues braucht. Inhaltlich ist Tinfoil der stärkere Kandidat (Ganzkörper-Verschlüsselung, an die Anfrage gebundene Antwort, formale Spezifikation mit Konformanz-Suite).

## 1. Attestierung offline prüfbar? Ja (am Router, SEV-SNP)

Belegt gegen `inference.tinfoil.sh` (alles nur öffentliche GETs):
- `GET /.well-known/tinfoil-attestation` liefert `{format: sev-snp-guest/v2, body: base64(gzip(Report))}`; Report = 1184 Byte, SNP-Report Version 3. Der Client prüft nur den Router. Die Modell-Enklaven prüft der Router (Abbildung Modell→Repo ist in der Router-Messung einkompiliert, Doku `verification/attestation-architecture`). Das Manifest `GET /.well-known/tinfoil-proxy` (aus dem Router, 45 KB) listet alle Modell-Enklaven mit Repo, Tag, Messwerten, HPKE-/TLS-Schlüsseln und Frische. **Modell-Enklaven laufen gemischt auf TDX und SNP** (z. B. gpt-oss-120b, Llama, Kimi, Voxtral: TDX; GLM, websearch: SNP; Gemma 4: beides). Für den Client zählt nur der Router (SNP), TDX/DCAP wird also nicht gebraucht.
- Bindung **live nachgerechnet**: `report_data[0..32] = SHA-256(TLS-SPKI)` stimmt mit dem per `openssl s_client` gemessenen Hash des Serverzertifikats überein; `report_data[32..64]` = HPKE-Schlüssel aus `/.well-known/hpke-keys` (OHTTP-KeyConfig, 41 Byte: id 0, KEM 0x0020, X25519, KDF 1, AEAD 2). Policy-Bits: Debug 0, SMT 1, VMPL 0, `reported_tcb` = `0a00000000001754`.
- Kette **mit openssl nachgeprüft**: VCEK von `kdsintf.amd.com/vcek/v1/Genoa/<chip_id>?blSPL&teeSPL&snpSPL&ucodeSPL` (Produkt per Probieren: Milan/Turin 404, Genoa 200; Report v3 trägt den Produktnamen nicht), `cert_chain` (ASK+ARK, 4,6 KB, ARK selbstsigniert, RSA-PSS), `openssl verify` VCEK→ASK→ARK OK; ECDSA-P-384-SHA-384-Signatur über die ersten 0x2A0 Byte (r,s je 72 Byte little-endian) mit dem VCEK-Schlüssel: „Verified OK“, bei einem geflippten Bit in `report_data`: Fehler. Die ARK-Fingerabdrücke wären in der App zu pinnen (Genoa; ggf. Turin/Milan [?] je nach künftiger Hardware).
- Sigstore: Messwert des Routers muss zum **neuesten GitHub-Release** passen (`tinfoil.hash` → Attestations-Bundle: DSSE, Fulcio-Kette, Rekor-Inklusion mit Checkpoint/Merkle, SCT; Identität `github.com/tinfoilsh/confidential-model-router/.github/workflows/…@refs/tags/<tag>`). Das ist **nötig**, sonst gäbe es keine Aussage über den Code (die SNP-Messung allein ist nur ein Hash). Der Rust-Client `tinfoil` 0.2.1 hat das vollständig: **`verify_complete` lief live erfolgreich in 2,2 s** (Release v0.0.158, Messwert Enklave = Messwert Code `9b5493…01a9`, TLS- und HPKE-Fingerprint = die oben gemessenen). Die Trust-Root-Datei (`trusted_root.json`, 6,8 KB) und die Genoa-Kette (4,6 KB) sind eingebettet; KDS und GitHub laufen über Tinfoil-Proxys (`kds-proxy.tinfoil.sh`, `github-proxy.tinfoil.sh`): Verfügbarkeitsabhängigkeit, kein Vertrauensproblem (alles wird signaturgeprüft), aber die Chip-ID geht an den Proxy (Datenschutz klein).
- Rust-Crates: `sev` 8 (`snp`, `crypto_nossl`, kein OpenSSL) plus `rsa`, `p384`, `p256`, `ecdsa`, `x509-cert`, `ed25519-dalek` 3 in `tinfoil-rs`. `sigstore-rs` 0.13 ist **nicht** nutzbar (laut Cargo.toml-Kommentar braucht es `oauth`); Tinfoil hat die DSSE-/Rekor-/Fulcio-Prüfung selbst geschrieben (`src/verifier/sigstore/*`, ca. 4,4 kLOC; `attestation/sev/*` ca. 2,4 kLOC; Merkle-Beweis 1 kLOC).
- Größe/Android: `verify-live` (tinfoil-rs komplett inkl. tokio, reqwest, rustls/ring, async-openai, Verifier, `opt-level=z`, LTO, strip) baut mit dem NDK 28 für `aarch64-linux-android` (Toolchain aus rustup, nicht Homebrew) und ist **3,4 MB**. Nur Verifier (sev + sigstore ohne HTTP, Netz bleibt in Dart wie heute) schätze ich auf 0,5-1 MB zusätzlich je ABI **[?, nicht gemessen]**; HPKE-Teil <100 KB. Gesamt realistisch +0,6-1,2 MB je ABI.
- TDX/NRAS/DCAP aus `native/attest` helfen für Tinfoil nicht. Wiederverwendbar: SHA-256/384, SPKI-Hash (`spki.rs`), Pin- und Fail-closed-Gerüst des `PhalaVerifier`. GPU: nur indirekt (Enklave startet nicht ohne CC-Modus), im Client-Pfad keine NRAS-Prüfung gefunden **[?]**.

## 2. EHBP/HPKE: Testvektoren offline nachgerechnet

- Unabhängige Implementierung (`ehbp-check`: `hpke` 0.13, `aes-gcm`, `hkdf`) gegen `test-vectors/conformance/crypto.json`: **25 von 25** Antwort-Vektoren bestanden (Schlüsselableitung, Nonce-XOR bis Sequenz > 2^32, Entschlüsseln, fragmentiertes Streaming, manipuliertes Tag, abgeschnittener Frame, überlanger Chunk, vertauschte Frames, falsche Nonce/enc/Secret, Leer-Frames inkl. 4096er Flut). Einziger Stolperstein: Null-Längen-Frames werden übersprungen und zählen nicht in die Sequenz (SPEC §4.3). Die Referenz `tinfoil-ehbp` 0.4.1 besteht ihre 51 Tests lokal.
- Anfrageseite mit `hpke` 0.13 (X25519-HKDF-SHA256 / HKDF-SHA256 / AES-256-GCM, `info="ehbp request"`, leere AAD): Sender↔Empfänger-Rundlauf mit zwei Frames, `export("ehbp response",32)` identisch auf beiden Seiten; synthetische Antwort mit 5-Byte-Fragmenten korrekt entschlüsselt. Ein fester Kreuz-Vektor für die Anfrageseite existiert nicht (RFC 9180 Anhang A deckt AES-256-GCM nicht ab; Rust-`hpke` hat eigene Tests) **[?]**.
- Format: Header `Ehbp-Encapsulated-Key` (hex, 32 Byte) bzw. `Ehbp-Response-Nonce`; Body = Folge `LEN(4 Byte BE) ‖ AEAD-Chunk`, Anfrage in 64-KiB-Frames; Antwortschlüssel `HKDF(salt = enc‖nonce, ikm = Export)` mit Labels „key“/„nonce“, Nonce je Chunk = base XOR Zähler. Antwort-Stream: ein Frame je Netzwerkschreibvorgang, erste authentisierte Bytes sofort nutzbar. Die SSE-Ereignisse stecken **innerhalb** des entschlüsselten Stroms, d. h. der bestehende SSE-Parser läuft nach der Entschlüsselung unverändert (live bestätigt, 11 bis 285 Chunks). EOF/`[DONE]` prüft die Anwendung (SPEC §6.2.1).

## 3. Was wird verschlüsselt, was sieht der Router?

- Ganzer Body in beide Richtungen: `messages`, `tools`, `tool_choice`, `tool_calls` (Anfrage und Antwort, auch als SSE-Deltas), Tool-Ergebnisse. Header bleiben Klartext (inkl. `Authorization: Bearer <API-Key>`, Modell steht aber im Body).
- **Router-CVM sieht den Klartext** (liest das Modell, führt serverseitige Tools wie Websuche/Code aus, setzt Rate-Limits). Es folgt Re-Verschlüsselung (gepinntes TLS) zur attestierten Modell-Enklave. Der Router meldet laut Doku nur Metadaten an das Tinfoil-Backend (API-Key, Modell, Token-Zahlen, Zeitstempel, Request-ID, Enklave; ohne Inhalte; Code offen und gemessen). Außerdem existiert im Router ein Paket `safeguards/` (asynchrone Acceptable-Use-Prüfung „für First-Party-Chat“): Gilt laut README nur für Tinfoils eigenen Chat **[?, nicht im Code verifiziert]**.
- **Direktzugriff auf Modell-Enklaven ohne Router: praktisch nein.** Hostnamen stehen im Manifest (`<modell>-infNN-M.tinfoil.containers.tinfoil.dev`), lösen auf, aber Port 443 war von hier **nicht erreichbar** (Timeout/geschlossen). Das SDK kennt „Enclave direkt adressieren“, das gilt nur für selbst gehostete Container. Vertrauen in den Router bleibt also nötig.

## 4. Modelle, Preise, Limits, Quittungen

- Öffentlicher Katalog `GET /v1/models` (ohne Key, mit Preisen). Chat-Modelle mit `tool_calling: true`: gpt-oss-120b (131K, 0,15/0,60 USD je Mio. Token in/out), gemma4-31b (262K, 0,40/1,00, multimodal), glm-5-3 (1M, 1,80/5,75), kimi-k3 (262K, 4,00/20,00), llama3-3-70b (131K, 1,75/2,75), deepseek-v4-1-flash (1M, 0,65/1,45, experimentell), gpt-oss-safeguard-120b. Außerdem relevant für Sprache: `whisper-large-v3-turbo` (STT), `voxtral-small-24b` (Audio→Chat), `voxtral-mini-4b-realtime`, TTS `qwen3-tts`/`voxtral-tts`, `websearch`, `pii-filter`, `doc-upload`; eigenes Thema, nicht getestet.
- Limits: Tiers im Dashboard, über das Konto sichtbar **[?]**; Konto + Zahlungsmittel nötig. Preisfrage für Wendelin: ~300 Prompt- + 80-300 Completion-Token je Tool-Fall (gpt-oss denkt verdeckt, 200+ Completion-Token) ≈ unter 0,0002 USD je Anfrage.
- **Quittungen: keine** (weder Signatur noch Beleg in Docs/Code gefunden). Ersatz: AEAD-Antwort, kryptografisch an die Anfrage gebunden (HPKE-Export); kein Nachweis „welches Modell/Enklave“ pro Antwort außer über das Manifest. Das Prüfprotokoll braucht eine Stufe „ohne Quittung“.

## 5. Live-Test (12 Anfragen mit Key, Wert nie ausgegeben)

Ablauf: `verify_complete` (SNP + Sigstore) → HPKE-Schlüssel nur aus der geprüften Quote → `tinfoil-ehbp`-Client → `POST /v1/chat/completions` mit `tools`. Bei allen 12 Antworten war der Header `Ehbp-Response-Nonce` gesetzt und die Entschlüsselung hat bestanden. System-Prompt: Datum Mittwoch 18.11.2026. Fälle aus `evals/cases/de.yaml`: `de-cal-tauchen`, `de-cal-zahnarzt-freitag`, `de-cal-ganztag`, Timer „12 Minuten Nudeln“, Wecker „morgen halb sieben“ (Tool-Schemata nachgebaut, nicht die Eval-Originale).

| Modell | Modus | Ergebnis |
|---|---|---|
| gpt-oss-120b | ohne Streaming, alle 5 Fälle | 5/5 richtig: Tauchen 19.11. 10:00; Zahnarzt 20.11. 14:30; Familienfest ganztägig 21.11. (mit `end` 22.11.); Timer 720 s „Nudeln“; Wecker 19.11. 06:30. 1,0-2,9 s |
| gpt-oss-120b | Streaming, 3 Fälle (0, 1, 3) | 3/3 richtig; `tool_calls`-Deltas zerlegt ankommend und zusammensetzbar, `finish_reason=tool_calls`, `usage` im letzten Chunk, `[DONE]` da; erstes Byte 0,29-0,62 s |
| gemma4-31b | Streaming, Fälle 0 und 3 | 2/2 richtig; 0,6-1,0 s gesamt, sehr schnell |
| gemma4-31b | ohne Streaming, Fälle 1, 2 | 2/2 richtig (Zahnarzt 20.11. 14:30; Familienfest `all_day`, Start 21.11.T00:00) |

Nicht getestet (Budget/Umfang): zweiter Zug mit Tool-Ergebnis (`role: tool`) zurück, Abbruch während des Streams, Fehlerfälle (401, 429), Latenz im Mobilnetz, die vollständigen Eval-Prädikate (nur Sichtprüfung der Argumente). Qualität von Deutsch im Fließtext wurde nicht gemessen.

## 6. Implementierungsvorschlag

1. **WP-A EHBP-Codec (Rust + Dart, 5-6 h):** `native/attest`: HPKE (`hpke` 0.13 mit `rand_core` 0.9 – Konflikt zu vorhandenem `rand_core` 0.6 prüfen), Response-Ableitung, Frame-Decoder (zustandsbehaftet, damit Dart nur Bytes schiebt), frozen Vektoren aus `crypto.json`. Dart: `ChatWire`-Variante „Byte-Strom“ (`OpenAiChatAdapter.wireCodec`): Body als Ganzes sealen, Antwort-Bytes entschlüsseln, dann der bestehende SSE-Parser. Kein Feld-Codec nötig, einfacher als Phala v2.
2. **WP-B SEV-SNP-Verifier (Rust, 8-12 h):** Report-Parser v3, VCEK-Erweiterungen (TCB, Chip-ID, Produkt), Kette ARK(gepinnt)→ASK→VCEK (RSA-PSS), ECDSA-P-384, Policy (Debug aus, VMPL 0, Mindest-TCB, kein Provisional), `report_data`-Bindung. Entweder Port aus `tinfoil-rs/src/verifier/attestation/sev` (Apache-2.0) oder Crate `sev` einbinden. KDS-Abruf macht Dart (wie Collateral bei TDX), Produktauswahl Genoa/Turin/Milan durch Probieren.
3. **WP-C Sigstore/Rekor (Rust, 10-14 h):** DSSE, Fulcio-Kette, SCT, Rekor-Eintrag + Checkpoint + Merkle, eingebettete Trust-Root (muss mit App-Updates aktualisiert werden; Ablauf der Sigstore-Schlüssel beachten), Identitätsprüfung auf Repo+Tag, Messwertabgleich mit „neuestem Release“ (Frage: Verhalten bei Release-Wechsel zwischen Abruf und Prüfung → kurzer Retry). Alternative: `tinfoil-rs` als Abhängigkeit mit Dart-Anbindung; zieht aber tokio/reqwest/async-openai und doppelte HTTP-Schicht (3,4 MB Testbinary), deshalb eher Port der reinen Funktionen.
4. **WP-D Provider-Profil (Dart, 4-6 h):** `TinfoilVerifier` mit Stufen (`snp.report`, `snp.chain`, `snp.policy`, `bind.tls`, `bind.hpke`, `sigstore.*`, `measurement.match`), Pinning des TLS-SPKI (vorhandenes Muster), Schlüssel/Key-Eintrag, Modellliste aus `/v1/models` (öffentlich), Status ohne Quittung, Eval-Profil `tinfoil-*.json`, Live-Test klein, Review.
5. Gesamt **ca. 27-38 Agenten-Stunden** (3-5 Tage, entspricht der Schätzung in `e2ee-alternatives.md`, 24-40 h); Streaming/Tools-Risiko ist durch den Live-Test gesunken, Rest ist Sicherheitsreview von WP-B/C.
6. **APK-Zuwachs:** ca. +0,6-1,2 MB je ABI (siehe 1) **[geschätzt]**; Alternative Crate-Reuse ~+3 MB.

## 7. Risiken

- Viel neuer Sicherheitscode (SNP, Sigstore, Merkle): strenge Negativtests nötig (Vektoren: manipulierter Report, falsche Kette, abgelaufene/falsche Rekor-Prüfung, falsches Repo/Tag).
- Vertrauensanker: AMD ARK (Genoa) gepinnt; neue AMD-Hardware (Turin) verlangt neue Wurzel; Sigstore-Trust-Root wandert (Wartung per App-Update).
- Router sieht Klartext (attestiert, aber ein Anker mehr); Metadaten (API-Key, Modell, Token) gehen an das Tinfoil-Backend. Modell-Enklaven werden vom Router, nicht vom Client geprüft.
- „Neuestes Release“ als Soll-Messwert: nach Tinfoil-Updates kurzzeitig Abweichung möglich (Fail-closed führt zu Ausfall, dann Retry); Hängt von `github-proxy`/`kds-proxy` ab, Fallback auf direkte Quellen **[?]**.
- Formate bewegen sich (V2 → V3-Dokument, Rust-SDK 0.2.1, EHBP 0.4.1): Breaking-Change-Risiko; Version pinnen.
- Keine Quittung; Preis-/Limit-Details und Zahlweg nur im Konto; Router-Tools (Websuche) im Klartext im Router – Wendelins Tools laufen lokal, also nicht betroffen.
- Konzept: zweiter E2EE-Anbieter berührt K28/K37 (Änderungsprotokoll, Bestätigung durch Maintainer).

## 8. Offen

Zweiter Zug mit Tool-Ergebnis; Abbruchverhalten und Fehlercodes; Limits; Mobilnetz-Latenz; GPU-Evidenz im Client-Pfad (V3-Dokument); Verhalten bei TDX-Router (heute leere Liste `platform=tdx`); Turin/Milan-Router; Sicherheitsaudit `ehbp/conformance/SECURITY-AUDIT.md` nicht gelesen; Gesamtgröße nach Strip des reinen Verifiers messen.
