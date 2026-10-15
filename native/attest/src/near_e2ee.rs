//! Feldverschlüsselung der NEAR-AI-Cloud-E2EE-Schnittstelle (WP75, ADR 0019).
//!
//! Quelle: `nearai/cloud-api`/`inference-proxy` (`src/encryption.rs`, Modul `nacl_v2`) und die Doku
//! `e2ee-chat-completions`. Pro Feld: frisches ephemeres X25519-Paar und frische 24-Byte-Nonce,
//! `shared = X25519(eph, empfänger)`, `key = HKDF-SHA256(salt = keiner, ikm = shared,
//! info = "ed25519_encryption", L = 32)`, XChaCha20-Poly1305 **ohne AAD**. Wire-Format:
//! Kleinbuchstaben-Hex von `eph_public(32) || nonce(24) || ciphertext || tag(16)`.
//!
//! Die Schlüssel sind Ed25519-Identitäten: Der Empfänger (Modell-TEE) ist der attestierte
//! `signing_public_key`, der Client sendet seinen Ed25519-Schlüssel in `X-Client-Pub-Key`. Beide
//! werden wie in libsodium (`crypto_sign_ed25519_*_to_curve25519`) nach X25519 umgerechnet. Die
//! Feldliste und die Header gehören zum Protokollbaustein in Dart.
//!
//! Geheimnisse (Seeds, Klartext) werden nie geloggt oder in Fehlertexte übernommen.
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use ed25519_dalek::{SigningKey, VerifyingKey};
use hkdf::Hkdf;
use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha256, Sha512};
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::Zeroizing;

const INFO: &[u8] = b"ed25519_encryption";
const NONCE_LEN: usize = 24;
const KEY_LEN: usize = 32;
const TAG_LEN: usize = 16;
const MIN_LEN: usize = KEY_LEN + NONCE_LEN + TAG_LEN;

/// Client-Identität: Ed25519-Schlüssel (öffentlich: `X-Client-Pub-Key`) und der daraus
/// abgeleitete X25519-Geheimschlüssel zum Entschlüsseln der Antwort.
pub struct NearIdentity {
    /// X25519-Geheimschlüssel (32 Byte, libsodium `crypto_sign_ed25519_sk_to_curve25519`).
    pub secret: Vec<u8>,
    /// Ed25519-Public-Key (32 Byte).
    pub public: Vec<u8>,
}

/// Erzeugt eine frische Identität aus dem Betriebssystem-Zufall.
pub fn generate_identity() -> NearIdentity {
    let mut seed = Zeroizing::new([0u8; KEY_LEN]);
    OsRng.fill_bytes(&mut seed[..]);
    identity_from_seed(&seed)
}

/// Identität aus einem Ed25519-Seed (Tests, Testvektoren).
pub fn identity_from_seed(seed: &[u8; KEY_LEN]) -> NearIdentity {
    let signing = SigningKey::from_bytes(seed);
    let mut hash = Sha512::digest(seed);
    let mut secret = [0u8; KEY_LEN];
    secret.copy_from_slice(&hash[..KEY_LEN]);
    hash.iter_mut().for_each(|b| *b = 0);
    secret[0] &= 248;
    secret[31] &= 127;
    secret[31] |= 64;
    NearIdentity {
        secret: secret.to_vec(),
        public: signing.verifying_key().to_bytes().to_vec(),
    }
}

fn array32(b: &[u8], what: &str) -> Result<[u8; KEY_LEN], String> {
    <[u8; KEY_LEN]>::try_from(b).map_err(|_| format!("{what}: 32 Byte erwartet"))
}

fn cipher(secret: &StaticSecret, peer: &PublicKey) -> Result<XChaCha20Poly1305, String> {
    let shared = Zeroizing::new(secret.diffie_hellman(peer).to_bytes());
    // Low-Order-Punkt: gemeinsames Geheimnis wäre konstant null, nicht vertrauenswürdig.
    if shared.iter().all(|b| *b == 0) {
        return Err("Schlüsselvereinbarung ungültig".into());
    }
    let mut key = Zeroizing::new([0u8; KEY_LEN]);
    Hkdf::<Sha256>::new(None, &shared[..])
        .expand(INFO, &mut key[..])
        .map_err(|_| "Schlüsselableitung fehlgeschlagen".to_string())?;
    XChaCha20Poly1305::new_from_slice(&key[..]).map_err(|_| "Schlüssel ungültig".to_string())
}

/// X25519-Schlüssel des Ed25519-Public-Keys (Montgomery-Form).
pub fn ed25519_to_x25519(ed_public: &[u8]) -> Result<[u8; KEY_LEN], String> {
    let vk = VerifyingKey::from_bytes(&array32(ed_public, "Empfängerschlüssel")?)
        .map_err(|_| "Empfängerschlüssel ungültig".to_string())?;
    Ok(vk.to_montgomery().to_bytes())
}

/// Verschlüsselt mit festem Ephemeral-Seed und fester Nonce. Nur für Tests und Testvektoren.
pub fn encrypt_with(
    recipient_ed_public: &[u8],
    eph_seed: [u8; KEY_LEN],
    nonce: [u8; NONCE_LEN],
    plaintext: &[u8],
) -> Result<String, String> {
    let peer = PublicKey::from(ed25519_to_x25519(recipient_ed_public)?);
    let eph = StaticSecret::from(eph_seed);
    let eph_pub = PublicKey::from(&eph);
    let sealed = cipher(&eph, &peer)?
        .encrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad: &[],
            },
        )
        .map_err(|_| "Verschlüsselung fehlgeschlagen".to_string())?;
    let mut wire = Vec::with_capacity(MIN_LEN + plaintext.len());
    wire.extend_from_slice(eph_pub.as_bytes());
    wire.extend_from_slice(&nonce);
    wire.extend_from_slice(&sealed);
    Ok(hex::encode(wire))
}

/// Verschlüsselt [plaintext] an den Ed25519-Schlüssel [recipient_ed_public].
pub fn encrypt(recipient_ed_public: &[u8], plaintext: &[u8]) -> Result<String, String> {
    let mut seed = Zeroizing::new([0u8; KEY_LEN]);
    let mut nonce = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut seed[..]);
    OsRng.fill_bytes(&mut nonce);
    encrypt_with(recipient_ed_public, *seed, nonce, plaintext)
}

/// Entschlüsselt das Wire-Format [wire_hex] (optionales `0x`) mit dem X25519-Geheimschlüssel
/// [secret]; falscher Schlüssel oder veränderte Bytes ergeben denselben Fehler.
pub fn decrypt(secret: &[u8], wire_hex: &str) -> Result<Vec<u8>, String> {
    let hex_part = wire_hex.strip_prefix("0x").unwrap_or(wire_hex);
    let wire = hex::decode(hex_part).map_err(|_| "Chiffre ist kein Hex".to_string())?;
    if wire.len() < MIN_LEN {
        return Err("Chiffre zu kurz".into());
    }
    let secret = StaticSecret::from(array32(secret, "Privatschlüssel")?);
    let peer = PublicKey::from(array32(&wire[..KEY_LEN], "Ephemeralschlüssel")?);
    let (nonce, sealed) = wire[KEY_LEN..].split_at(NONCE_LEN);
    cipher(&secret, &peer)?
        .decrypt(
            XNonce::from_slice(nonce),
            Payload {
                msg: sealed,
                aad: &[],
            },
        )
        .map_err(|_| "Entschlüsselung fehlgeschlagen".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn server() -> NearIdentity {
        identity_from_seed(&[3u8; 32])
    }

    // Referenzwerte unabhängig mit PyNaCl/libsodium erzeugt (Seeds 32 x 0x03 Server, 32 x 0x05 Client).
    const SERVER_ED_PUB: &str = "ed4928c628d1c2c6eae90338905995612959273a5c63f93636c14614ac8737d1";
    const SERVER_X_PUB: &str = "75e270df2952c57ba8367ba8618c178f9fe50db2799d304e74e918d985686146";
    const SERVER_X_SEC: &str = "98aebbb178a551876bfaf8e1e530dac6aaf6c2ea1c8f8406a3ab37dfb40fbc65";
    const CLIENT_ED_PUB: &str = "6e7a1cdd29b0b78fd13af4c5598feff4ef2a97166e3ca6f2e4fbfccd80505bf1";
    const CLIENT_X_SEC: &str = "48370d6146de919cc1ce472897775d9a6c2834c509e08e14efcb2b52188f946e";

    #[test]
    fn keys_match_libsodium_conversion() {
        let s = server();
        assert_eq!(hex::encode(&s.public), SERVER_ED_PUB);
        assert_eq!(hex::encode(&s.secret), SERVER_X_SEC);
        assert_eq!(
            hex::encode(ed25519_to_x25519(&s.public).unwrap()),
            SERVER_X_PUB
        );
        let c = identity_from_seed(&[5u8; 32]);
        assert_eq!(hex::encode(&c.public), CLIENT_ED_PUB);
        assert_eq!(hex::encode(&c.secret), CLIENT_X_SEC);
    }

    #[test]
    fn secret_and_public_belong_together() {
        let id = generate_identity();
        let derived = PublicKey::from(&StaticSecret::from(array32(&id.secret, "s").unwrap()));
        assert_eq!(derived.as_bytes(), &ed25519_to_x25519(&id.public).unwrap());
    }

    #[test]
    fn roundtrip_and_length() {
        let s = server();
        for pt in ["", "Hallo Wörld", &"x".repeat(5000)] {
            let wire = encrypt(&s.public, pt.as_bytes()).unwrap();
            assert_eq!(wire.len(), 2 * (MIN_LEN + pt.len()));
            assert_eq!(wire, wire.to_lowercase());
            assert_eq!(decrypt(&s.secret, &wire).unwrap(), pt.as_bytes());
        }
    }

    #[test]
    fn each_encryption_is_fresh() {
        let s = server();
        assert_ne!(
            encrypt(&s.public, b"x").unwrap(),
            encrypt(&s.public, b"x").unwrap()
        );
    }

    #[test]
    fn prefix_0x_is_accepted() {
        let s = server();
        let wire = encrypt(&s.public, b"x").unwrap();
        assert_eq!(decrypt(&s.secret, &format!("0x{wire}")).unwrap(), b"x");
    }

    #[test]
    fn manipulation_fails() {
        let s = server();
        let wire = encrypt(&s.public, b"geheim").unwrap();
        assert!(decrypt(&identity_from_seed(&[4u8; 32]).secret, &wire).is_err());
        let mut bytes = hex::decode(&wire).unwrap();
        for pos in [0usize, 40, bytes.len() - 1] {
            bytes[pos] ^= 1;
            assert!(
                decrypt(&s.secret, &hex::encode(&bytes)).is_err(),
                "pos {pos}"
            );
            bytes[pos] ^= 1;
        }
        assert_eq!(decrypt(&s.secret, &hex::encode(&bytes)).unwrap(), b"geheim");
        let cut = &bytes[..bytes.len() - 1];
        assert!(decrypt(&s.secret, &hex::encode(cut)).is_err());
    }

    #[test]
    fn malformed_input_is_an_error_without_leaking() {
        let s = server();
        assert!(decrypt(&s.secret, "zz").is_err());
        assert!(decrypt(&s.secret, "abcd").is_err());
        assert!(decrypt(&s.secret[..5], &"00".repeat(80)).is_err());
        assert!(encrypt(&s.public[..5], b"x").is_err());
        let err = decrypt(&s.secret, &"00".repeat(80)).unwrap_err();
        assert!(!err.contains("00"));
    }

    #[test]
    fn low_order_recipient_is_rejected() {
        // Ed25519-Identitätspunkt (y = 1) hat Ordnung 1, sein Montgomery-Bild ist der Nullpunkt.
        let mut identity = [0u8; 32];
        identity[0] = 1;
        assert!(encrypt(&identity, b"x").is_err());
    }

    /// Eingefrorener Vektor, unabhängig mit PyNaCl/libsodium und `cryptography` (X25519,
    /// HKDF-SHA256 ohne Salt, info `ed25519_encryption`, XChaCha20-Poly1305 IETF) erzeugt:
    /// Ephemeral-Seed 32 x 0x07, Nonce 24 x 0x09, Klartext "Hallo Wendelin".
    #[test]
    fn frozen_vector_matches_independent_implementation() {
        let wire = encrypt_with(&server().public, [7u8; 32], [9u8; 24], b"Hallo Wendelin").unwrap();
        assert_eq!(wire, include_str!("../tests/near_e2ee_vector.txt").trim());
        assert_eq!(decrypt(&server().secret, &wire).unwrap(), b"Hallo Wendelin");
    }
}
