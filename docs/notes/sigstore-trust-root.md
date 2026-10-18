# Sigstore-Trust-Root und Release-Prüfung (WP76b)

Stand 2026-10-18. Modul: `native/attest/src/sigstore.rs`, Vektoren `native/attest/tests/sigstore.rs` mit `tests/sigstore/bundle_v0.0.158.json` und `bundle_v0.0.159.json` (öffentliche Bundles des Router-Repos `tinfoilsh/confidential-model-router`, ohne Geheimnisse).

## Was geprüft wird
Der SNP-Messwert des Routers (`SnpReportInfo.measurementHex`, WP76a) wird gegen das signierte GitHub-Release verglichen. Eingaben des Aufrufers (WP76d, holt sie über HTTP und Cache):
1. `tag` = `releases/latest` des Repos, `digestHex` = `releases/download/<tag>/tinfoil.hash` (64 Hex).
2. `bundleJson` = `attestations[0].bundle` aus `GET /repos/<repo>/attestations/sha256:<digest>` (Sigstore-Bundle v0.3).
   Quellen: `api.github.com` (60 Anfragen/h ohne Token) oder die Proxys von Tinfoil (`api-github-proxy.tinfoil.sh`; `github-proxy.tinfoil.sh` für `tinfoil.hash`). Alles wird signaturgeprüft, die Proxys sind kein Vertrauensanker.

`verifyRelease` (Dart) bzw. `verify_tinfoil_release` (Rust) liefert je Stufe ein Ergebnis: `dsseOk`, `chainOk`, `identityOk`, `rekorOk`, `measurementOk`. Nur alle zusammen (`allOk`) sagen: Der Messwert des Reports gehört zum signierten Release `repo@tag`. Der Aufrufer prüft zusätzlich, dass `tag` wirklich das neueste Release ist; nach einem Tinfoil-Update kann der Router kurz noch den alten Messwert melden (fail-closed, nach Pause erneut versuchen).

## Offline und Cache
Die Prüfung braucht kein Netz. Zertifikatsgültigkeit und Schlüsselfenster werden zur von Rekor signierten Eintragszeit beurteilt (SET), nicht zu „jetzt“. Ein gecachtes Bundle (samt `tag`/`digest`) bleibt deshalb dauerhaft prüfbar. Die Trust-Root liegt eingebettet im Binary (`native/attest/assets/sigstore_trusted_root.json`, 6,8 KB). Es gibt bewusst keinen Laufzeit-Download der Trust-Root: Ohne TUF-Client (Signaturketten, Rotation) wäre ein ungeprüftes Nachladen ein Vertrauensloch. Der Parameter `trusted_root_json` der Rust-API dient Tests und einem späteren TUF-Pfad.

## Pflege (Update-Pfad)
Sigstore rotiert die Schlüssel selten (Fulcio-CA seit 2022-04, Rekor v1 seit 2021, Rekor v2 `log2025-1` seit 2025-09). Prüfen und ggf. aktualisieren:

    dart run tool/update_sigstore_root.dart          # nur prüfen
    dart run tool/update_sigstore_root.dart --write  # Asset überschreiben

Das Skript folgt der TUF-Kette von `tuf-repo-cdn.sigstore.dev` (timestamp, snapshot, targets; Hashes und Längen) und vergleicht die Datei byte-genau mit `sigstore/root-signing` (GitHub, signierte Commits); bei Abweichung bricht es ab. Danach den SHA-256 in `native/attest/tests/sigstore.rs` (`embedded_trust_root_is_the_documented_one`) und hier nachziehen, Rust-Tests laufen lassen, Review. Ein neues Release der App liefert die neue Root aus; eine Aktualisierung ist nötig, wenn Tinfoils Bundles gegen neue Schlüssel signiert werden (Symptom: `chain`/`rekor` rot bei sonst gültigem Bundle). Die TUF-Signaturen selbst prüft das Skript nicht; das ist der Grund für den zweiten, unabhängigen Quellenvergleich.

Aktueller Stand: SHA-256 `6494e21ea73fa7ee769f85f57d5a3e6a08725eae1e38c755fc3517c9e6bc0b66`. Gleich in drei Quellen (TUF-CDN, `sigstore/root-signing`, eingebettete Datei von `tinfoil-rs`), TUF-Zeitstempel gültig bis 2026-10-25 (wird laufend erneuert, ohne die Root-Datei zu ändern).

## Größe
`libwendelin_attest.so` (arm64-v8a, Release, `opt-level=z`, LTO) wächst von 1 780 648 auf 1 846 176 Byte, also +65 528 Byte (+64 KiB) für Sigstore samt Trust-Root, `p256` und `base64` (Messung 2026-10-18 mit `cargo ndk`, Basis = Stand vor WP76b). Das Ziel (≤ ~1,2 MB je ABI für ganz Tinfoil) ist damit für diesen Teil weit unterschritten; der Grund ist der Verzicht auf `tinfoil-rs` (tokio/reqwest) und auf SCT.

## Grenzen (Abweichungen vom Tinfoil-Client `tinfoil-rs`)
- **Keine SCT-Prüfung** (Certificate Transparency des Fulcio-Zertifikats). Das Blattzertifikat ist stattdessen durch den Rekor-Eintrag (Inklusionsbeweis, SET, Bindung an Zertifikat/Signatur/Payload-Hash) und die Kette zur Fulcio-CA im Zeitfenster gebunden. Nachrüstbar, falls das Review es verlangt (zusätzlich ca. 100 Zeilen und der CT-Logschlüssel aus der Trust-Root).
- **Nur Rekor v1** (ECDSA P-256, Eintragsart `dsse` 0.0.1, mit SET). Bundles gegen Rekor v2 / TSA-Zeitstempel (Ed25519-Schlüssel `log2025-1`) lehnt die Prüfung fail-closed ab. GitHub signiert Attestierungen heute noch gegen Rekor v1; sollte sich das ändern, ist das eine Folgeaufgabe.
- Kein Widerruf (Fulcio-Zertifikate leben 10 Minuten).
- Identität: Aussteller `https://token.actions.githubusercontent.com`, Repository-Erweiterung = `repo`, Workflow-URI `https://github.com/<repo>/.github/workflows/<datei>@refs/tags/<tag>` (jeder Workflow des Repos, wie `tinfoil-rs`).
