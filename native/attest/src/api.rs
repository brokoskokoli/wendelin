//! Schnittstelle nach Dart (`flutter_rust_bridge`). Prüfungen melden Fehlschläge im Ergebnis,
//! nur unlesbare Eingaben (`Err`) werden zu Ausnahmen.
use sha2::{Digest, Sha256, Sha384};

pub use crate::collateral::{CollateralParts, CollateralRequest};
pub use crate::quote::QuoteInfo;
pub use crate::report::{ReceiptVerdict, Verdict};

/// Prüft einen TDX-Quote gegen `collateral_json` zum Zeitpunkt `now_unix`.
pub fn verify_quote(quote: Vec<u8>, collateral_json: String, now_unix: u64) -> QuoteInfo {
    crate::quote::verify_quote(&quote, &collateral_json, now_unix)
}

/// Prüft einen ACI-Bericht vollständig (Keyset, `report_data`, Quote, RTMR3, Compose-Hash, TLS-Bindung).
pub fn verify_aci_report(
    report_json: String,
    nonce_hex: String,
    collateral_json: String,
    now_unix: u64,
) -> Verdict {
    crate::report::verify_report(&report_json, &nonce_hex, &collateral_json, now_unix)
}

/// Prüft die Signatur einer Quittung gegen das Keyset des Berichts.
pub fn verify_aci_receipt(receipt_json: String, report_json: String) -> ReceiptVerdict {
    crate::report::verify_receipt(&receipt_json, &report_json)
}

/// Welches Kollateral der Quote braucht (FMSPC, CA, TEE-Art).
pub fn collateral_request(quote: Vec<u8>) -> Result<CollateralRequest, String> {
    crate::collateral::collateral_request(&quote)
}

/// URL der Root-CA-CRL aus der Ausstellerkette der QE-Identität.
pub fn root_crl_url(qe_identity_issuer_chain: String) -> Result<String, String> {
    crate::collateral::root_crl_url(&qe_identity_issuer_chain)
}

/// Setzt die PCS-Antworten zu Kollateral-JSON zusammen.
pub fn build_collateral(parts: CollateralParts) -> Result<String, String> {
    crate::collateral::build_collateral(&parts)
}

/// Frühestes `nextUpdate` (ISO-8601) des Kollaterals.
pub fn collateral_next_update(collateral_json: String) -> Result<String, String> {
    crate::collateral::next_update(&collateral_json)
}

/// Steht der beobachtete TLS-SPKI (Hex) für `host` im Keyset des Berichts?
#[flutter_rust_bridge::frb(sync)]
pub fn tls_spki_listed(report_json: String, observed_spki_hex: String, host: String) -> bool {
    crate::report::tls_spki_listed(&report_json, &observed_spki_hex, &host)
}

#[flutter_rust_bridge::frb(sync)]
pub fn verify_ed25519(public_key: Vec<u8>, message: Vec<u8>, signature: Vec<u8>) -> bool {
    crate::report::ed25519_ok(&public_key, &message, &signature)
}

#[flutter_rust_bridge::frb(sync)]
pub fn sha256(data: Vec<u8>) -> Vec<u8> {
    Sha256::digest(data).to_vec()
}

#[flutter_rust_bridge::frb(sync)]
pub fn sha384(data: Vec<u8>) -> Vec<u8> {
    Sha384::digest(data).to_vec()
}

/// SHA-256 über das `SubjectPublicKeyInfo` eines X.509-Zertifikats (DER).
#[flutter_rust_bridge::frb(sync)]
pub fn spki_sha256(certificate_der: Vec<u8>) -> Result<Vec<u8>, String> {
    crate::spki::spki_sha256(&certificate_der).map(|h| h.to_vec())
}

pub use crate::e2ee::E2eeKeypair;

/// Frisches X25519-Schlüsselpaar für eine E2EE-Anfrage (Phala, Protokoll v2); der private Teil
/// bleibt im Speicher des Aufrufers und dient nur dem Entschlüsseln der Antwort.
#[flutter_rust_bridge::frb(sync)]
pub fn e2ee_generate_keypair() -> E2eeKeypair {
    crate::e2ee::generate_keypair()
}

/// Verschlüsselt ein Feld (Suite `x25519-aes-256-gcm-hkdf-sha256`); liefert das Hex-Wire-Format.
#[flutter_rust_bridge::frb(sync)]
pub fn e2ee_encrypt(
    recipient_public: Vec<u8>,
    plaintext: Vec<u8>,
    aad: Vec<u8>,
) -> Result<String, String> {
    crate::e2ee::encrypt(&recipient_public, &plaintext, &aad)
}

/// Entschlüsselt ein Feld im Hex-Wire-Format; jeder Fehler (Hex, Länge, Tag, AAD) ist ein `Err`.
#[flutter_rust_bridge::frb(sync)]
pub fn e2ee_decrypt(secret: Vec<u8>, wire_hex: String, aad: Vec<u8>) -> Result<Vec<u8>, String> {
    crate::e2ee::decrypt(&secret, &wire_hex, &aad)
}
