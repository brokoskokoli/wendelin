//! Feldverschlüsselung der Phala/RedPill-E2EE-Schnittstelle, Protokoll v2, Suite
//! `x25519-aes-256-gcm-hkdf-sha256` (WP62).
//!
//! Quelle: `Dstack-TEE/private-ai-gateway` @ 57477f5d (`spec/e2ee-v2.md` §Crypto, Referenzcode
//! `src/aci/e2ee.rs`). Pro Feld: frisches ephemeres X25519-Paar und frische 12-Byte-GCM-Nonce,
//! `shared = X25519(eph, empfänger)`, `key = HKDF-SHA256(salt = keiner, ikm = shared,
//! info = "aci.e2ee.v2.x25519", L = 32)`, AES-256-GCM mit der AAD (JCS-JSON, baut Dart).
//! Wire-Format: Kleinbuchstaben-Hex von `eph_public(32) || nonce(12) || ciphertext || tag(16)`.
//! Die AAD, die Feldliste und die Header gehören zum Protokollbaustein in Dart.
//!
//! Geheimnisse (ephemere Schlüssel, Klartext) werden nie geloggt oder in Fehlertexte übernommen.
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use hkdf::Hkdf;
use rand_core::{OsRng, RngCore};
use sha2::Sha256;
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::Zeroizing;

const INFO: &[u8] = b"aci.e2ee.v2.x25519";
const NONCE_LEN: usize = 12;
const KEY_LEN: usize = 32;
const TAG_LEN: usize = 16;
/// Kleinste gültige Chiffre: Ephemeral + Nonce + Tag (leerer Klartext).
const MIN_LEN: usize = KEY_LEN + NONCE_LEN + TAG_LEN;

/// Ein X25519-Schlüsselpaar (roh, je 32 Byte).
pub struct E2eeKeypair {
    pub secret: Vec<u8>,
    pub public: Vec<u8>,
}

/// Erzeugt ein frisches X25519-Paar aus dem Betriebssystem-Zufall.
pub fn generate_keypair() -> E2eeKeypair {
    let mut seed = [0u8; KEY_LEN];
    OsRng.fill_bytes(&mut seed);
    keypair_from_seed(seed)
}

/// Paar aus einem Seed (Tests, Testvektoren).
pub fn keypair_from_seed(seed: [u8; KEY_LEN]) -> E2eeKeypair {
    let secret = StaticSecret::from(seed);
    let public = PublicKey::from(&secret);
    E2eeKeypair {
        secret: secret.to_bytes().to_vec(),
        public: public.as_bytes().to_vec(),
    }
}

fn array32(b: &[u8], what: &str) -> Result<[u8; KEY_LEN], String> {
    <[u8; KEY_LEN]>::try_from(b).map_err(|_| format!("{what}: 32 Byte erwartet"))
}

fn cipher(secret: &StaticSecret, peer: &PublicKey) -> Result<Aes256Gcm, String> {
    let shared = Zeroizing::new(secret.diffie_hellman(peer).to_bytes());
    let contributory = !shared.iter().all(|b| *b == 0);
    // Low-Order-Punkt: gemeinsames Geheimnis wäre konstant null, nicht vertrauenswürdig.
    if !contributory {
        return Err("Schlüsselvereinbarung ungültig".into());
    }
    let mut key = Zeroizing::new([0u8; KEY_LEN]);
    Hkdf::<Sha256>::new(None, &shared[..])
        .expand(INFO, &mut key[..])
        .map_err(|_| "Schlüsselableitung fehlgeschlagen".to_string())?;
    Aes256Gcm::new_from_slice(&key[..]).map_err(|_| "Schlüssel ungültig".to_string())
}

/// Verschlüsselt mit festem Ephemeral-Seed und fester Nonce. Nur für Tests und Testvektoren.
pub fn encrypt_with(
    recipient_public: &[u8],
    eph_seed: [u8; KEY_LEN],
    nonce: [u8; NONCE_LEN],
    plaintext: &[u8],
    aad: &[u8],
) -> Result<String, String> {
    let peer = PublicKey::from(array32(recipient_public, "Empfängerschlüssel")?);
    let eph = StaticSecret::from(eph_seed);
    let eph_pub = PublicKey::from(&eph);
    let sealed = cipher(&eph, &peer)?
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| "Verschlüsselung fehlgeschlagen".to_string())?;
    let mut wire = Vec::with_capacity(MIN_LEN + plaintext.len());
    wire.extend_from_slice(eph_pub.as_bytes());
    wire.extend_from_slice(&nonce);
    wire.extend_from_slice(&sealed);
    Ok(hex::encode(wire))
}

/// Verschlüsselt [plaintext] an [recipient_public] mit frischem Ephemeralpaar und frischer Nonce.
pub fn encrypt(recipient_public: &[u8], plaintext: &[u8], aad: &[u8]) -> Result<String, String> {
    let mut seed = [0u8; KEY_LEN];
    let mut nonce = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut seed);
    OsRng.fill_bytes(&mut nonce);
    encrypt_with(recipient_public, seed, nonce, plaintext, aad)
}

/// Entschlüsselt das Wire-Format [wire_hex] (optionales `0x`) mit dem privaten Schlüssel
/// [secret]; falsche AAD, falscher Schlüssel oder veränderte Bytes ergeben denselben Fehler.
pub fn decrypt(secret: &[u8], wire_hex: &str, aad: &[u8]) -> Result<Vec<u8>, String> {
    let hex_part = wire_hex.strip_prefix("0x").unwrap_or(wire_hex);
    let wire = hex::decode(hex_part).map_err(|_| "Chiffre ist kein Hex".to_string())?;
    if wire.len() < MIN_LEN {
        return Err("Chiffre zu kurz".into());
    }
    let secret = StaticSecret::from(array32(secret, "Privatschlüssel")?);
    let peer = PublicKey::from(array32(&wire[..KEY_LEN], "Ephemeralschlüssel")?);
    let (nonce, sealed) = wire[KEY_LEN..].split_at(NONCE_LEN);
    cipher(&secret, &peer)?
        .decrypt(Nonce::from_slice(nonce), Payload { msg: sealed, aad })
        .map_err(|_| "Entschlüsselung fehlgeschlagen".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const AAD: &[u8] = br#"{"algo":"x25519-aes-256-gcm-hkdf-sha256","field":"messages.0.content","model":"demo-model","nonce":"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f","purpose":"aci.e2ee.request.v2","ts":1750000000}"#;

    fn service() -> E2eeKeypair {
        keypair_from_seed([3u8; 32])
    }

    #[test]
    fn service_seed_gives_published_public_key() {
        // spec/e2ee-v2-test-vectors.md: Seed 32 x 0x03.
        assert_eq!(
            hex::encode(service().public),
            "5dfedd3b6bd47f6fa28ee15d969d5bb0ea53774d488bdaf9df1c6e0124b3ef22"
        );
    }

    #[test]
    fn roundtrip_and_length() {
        let s = service();
        for pt in ["", "Hallo Wörld", &"x".repeat(5000)] {
            let wire = encrypt(&s.public, pt.as_bytes(), AAD).unwrap();
            assert_eq!(wire.len(), 2 * (MIN_LEN + pt.len()));
            assert_eq!(wire, wire.to_lowercase());
            assert_eq!(decrypt(&s.secret, &wire, AAD).unwrap(), pt.as_bytes());
        }
    }

    #[test]
    fn each_encryption_is_fresh() {
        let s = service();
        let a = encrypt(&s.public, b"x", AAD).unwrap();
        let b = encrypt(&s.public, b"x", AAD).unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn prefix_0x_is_accepted() {
        let s = service();
        let wire = encrypt(&s.public, b"x", AAD).unwrap();
        assert_eq!(decrypt(&s.secret, &format!("0x{wire}"), AAD).unwrap(), b"x");
    }

    #[test]
    fn wrong_aad_key_or_bit_flip_fails() {
        let s = service();
        let wire = encrypt(&s.public, b"geheim", AAD).unwrap();
        let other_aad = AAD
            .iter()
            .map(|b| if *b == b'0' { b'1' } else { *b })
            .collect::<Vec<_>>();
        assert!(decrypt(&s.secret, &wire, &other_aad).is_err());
        assert!(decrypt(&keypair_from_seed([4u8; 32]).secret, &wire, AAD).is_err());
        let mut bytes = hex::decode(&wire).unwrap();
        let last = bytes.len() - 1;
        bytes[last] ^= 1;
        assert!(decrypt(&s.secret, &hex::encode(&bytes), AAD).is_err());
        bytes[last] ^= 1;
        bytes[40] ^= 1; // GCM-Nonce
        assert!(decrypt(&s.secret, &hex::encode(&bytes), AAD).is_err());
    }

    #[test]
    fn malformed_input_is_an_error_without_leaking() {
        let s = service();
        assert!(decrypt(&s.secret, "zz", AAD).is_err());
        assert!(decrypt(&s.secret, "abcd", AAD).is_err());
        assert!(decrypt(&s.secret[..5], &"00".repeat(80), AAD).is_err());
        assert!(encrypt(&s.public[..5], b"x", AAD).is_err());
        let err = decrypt(&s.secret, &"00".repeat(80), AAD).unwrap_err();
        assert!(!err.contains("00"));
    }

    #[test]
    fn low_order_point_is_rejected() {
        let zero = [0u8; 32];
        assert!(encrypt(&zero, b"x", AAD).is_err());
    }

    /// Eingefrorener Vektor, unabhängig mit Node.js `crypto` (X25519, HKDF-SHA256 ohne Salt,
    /// AES-256-GCM) erzeugt: Ephemeral-Seed 32 x 0x07, GCM-Nonce 12 x 0x09, Klartext "Hallo Wendelin".
    #[test]
    fn frozen_vector_matches_independent_implementation() {
        let wire = encrypt_with(
            &service().public,
            [7u8; 32],
            [9u8; 12],
            b"Hallo Wendelin",
            AAD,
        )
        .unwrap();
        assert_eq!(wire, include_str!("../tests/e2ee_vector.txt").trim());
        assert_eq!(
            decrypt(&service().secret, &wire, AAD).unwrap(),
            b"Hallo Wendelin"
        );
    }
}
