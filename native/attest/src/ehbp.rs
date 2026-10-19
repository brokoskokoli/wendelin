//! Encrypted HTTP Body Protocol (EHBP) für Tinfoil, Sender-Seite (WP76c).
//!
//! Quelle: `tinfoilsh/encrypted-http-body-protocol` v0.4.1 (SPEC §3, §4, §4.4). Anfrage: HPKE
//! (RFC 9180) `X25519-HKDF-SHA256 / HKDF-SHA256 / AES-256-GCM`, `info = "ehbp request"`, leere AAD,
//! Body = Folge `LEN(4, BE) ‖ Chunk` mit Klartext-Frames zu höchstens 64 KiB. Antwort: Schlüssel und
//! Nonce kommen aus `HKDF(salt = enc ‖ response_nonce, ikm = export("ehbp response", 32))` mit den
//! Labels `key`/`nonce`; Nonce je Chunk = Basis XOR Zähler (u64, nur nichtleere Frames zählen).
//!
//! Der HPKE-Schlüssel des Servers gilt nur, wenn er aus der KeyConfig (`/.well-known/hpke-keys`)
//! stammt und `report_data[32..64]` des attestierten SNP-Reports gleicht ([`bind_key_config`]).
//! Der Antwort-Decoder ist zustandsbehaftet (Dart schiebt nur Bytes) und fail-closed: nach dem
//! ersten Fehler liefert er nie wieder Klartext. Schlüssel und Klartexte landen in keinem Fehlertext.
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use hkdf::Hkdf;
use hpke::aead::AesGcm256;
use hpke::kdf::HkdfSha256;
use hpke::kem::X25519HkdfSha256;
use hpke::{Deserializable, OpModeS, Serializable};
use rand_core09::{CryptoRng, OsRng, RngCore, UnwrapErr};
use sha2::Sha256;
use zeroize::{Zeroize, Zeroizing};

const REQUEST_INFO: &[u8] = b"ehbp request";
const EXPORT_LABEL: &[u8] = b"ehbp response";
const KEY_LEN: usize = 32;
const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;
const RESPONSE_NONCE_LEN: usize = 32;
/// Obergrenze eines Chunks (SPEC §4.3): 64 MiB Chiffretext.
const MAX_CHUNK: usize = 64 * 1024 * 1024;
/// Klartext je Anfrage-Frame.
const FRAME_PLAIN: usize = 64 * 1024;
const KEY_CONFIG_LEN: usize = 41;

/// Ergebnis der Schlüsselbindung: der TLS-SPKI-Hash, auf den die Verbindung zu pinnen ist.
pub struct EhbpBinding {
    /// `report_data[0..32]` (SHA-256 des TLS-SPKI).
    pub tls_spki_sha256: Vec<u8>,
}

/// Eine verschlüsselte Anfrage; die Sitzung für die Antwort kommt getrennt dazu.
pub struct EhbpSealed {
    /// Wert für `Ehbp-Encapsulated-Key` (32 Byte, Dart kodiert hex).
    pub encapsulated_key: Vec<u8>,
    /// Gerahmter Body.
    pub body: Vec<u8>,
}

/// Anfrage und Sitzung (Opaque kann nicht Feld eines Strukturtyps nach Dart sein).
pub type EhbpRequest = (EhbpSealed, EhbpSession);

/// Geheimnis der Anfrage für die Antwortableitung (`export`); Opaque in Dart.
#[flutter_rust_bridge::frb(opaque)]
pub struct EhbpSession {
    enc: [u8; KEY_LEN],
    secret: Zeroizing<[u8; KEY_LEN]>,
}

/// Zustandsbehafteter Antwort-Decoder; Opaque in Dart.
#[flutter_rust_bridge::frb(opaque)]
pub struct EhbpResponseDecoder {
    key: Zeroizing<[u8; KEY_LEN]>,
    nonce_base: [u8; NONCE_LEN],
    seq: u64,
    buf: Vec<u8>,
    state: State,
}

#[derive(PartialEq)]
enum State {
    Open,
    Failed,
    Finished,
}

fn err(code: &str, text: &str) -> String {
    format!("{code}: {text}")
}

/// Liest die KeyConfig (RFC 9458 §3, genau eine Suite) und liefert den KEM-Schlüssel.
/// `key_id` 0, KEM 0x0020, KDF 0x0001, AEAD 0x0002; alles andere wird abgelehnt.
pub fn parse_key_config(cfg: &[u8]) -> Result<[u8; KEY_LEN], String> {
    if cfg.len() != KEY_CONFIG_LEN {
        return Err(err("UNSUPPORTED_SUITE", "KeyConfig hat unerwartete Länge"));
    }
    let be = |i: usize| u16::from_be_bytes([cfg[i], cfg[i + 1]]);
    if cfg[0] != 0 || be(1) != 0x0020 || be(35) != 4 || be(37) != 0x0001 || be(39) != 0x0002 {
        return Err(err(
            "UNSUPPORTED_SUITE",
            "KeyConfig weicht von X25519/HKDF-SHA256/AES-256-GCM ab",
        ));
    }
    let mut pk = [0u8; KEY_LEN];
    pk.copy_from_slice(&cfg[3..35]);
    Ok(pk)
}

fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

/// Prüft, dass der Schlüssel der KeyConfig `report_data[32..64]` gleicht, und liefert den TLS-Pin.
pub fn bind_key_config(key_config: &[u8], report_data: &[u8]) -> Result<EhbpBinding, String> {
    let pk = parse_key_config(key_config)?;
    if report_data.len() != 64 {
        return Err(err("INVALID_INPUT", "report_data muss 64 Byte haben"));
    }
    if !ct_eq(&pk, &report_data[32..]) {
        return Err(err(
            "KEY_NOT_BOUND",
            "HPKE-Schlüssel gehört nicht zum attestierten Report",
        ));
    }
    Ok(EhbpBinding {
        tls_spki_sha256: report_data[..32].to_vec(),
    })
}

/// Verschlüsselt `plaintext` an den attestierten Schlüssel (nur nach erfolgreicher Bindung).
pub fn begin_request(
    key_config: &[u8],
    report_data: &[u8],
    plaintext: &[u8],
) -> Result<EhbpRequest, String> {
    begin_request_with(key_config, report_data, plaintext, &mut UnwrapErr(OsRng))
}

pub(crate) fn begin_request_with<R: CryptoRng + RngCore>(
    key_config: &[u8],
    report_data: &[u8],
    plaintext: &[u8],
    rng: &mut R,
) -> Result<EhbpRequest, String> {
    bind_key_config(key_config, report_data)?;
    let pk = parse_key_config(key_config)?;
    if plaintext.is_empty() {
        return Err(err("INVALID_INPUT", "leerer Body wird nicht verschlüsselt"));
    }
    let pk = <X25519HkdfSha256 as hpke::Kem>::PublicKey::from_bytes(&pk)
        .map_err(|_| err("HPKE_SETUP_FAILED", "Serverschlüssel ungültig"))?;
    let (enc, mut ctx) = hpke::setup_sender::<AesGcm256, HkdfSha256, X25519HkdfSha256, _>(
        &OpModeS::Base,
        &pk,
        REQUEST_INFO,
        rng,
    )
    .map_err(|_| err("HPKE_SETUP_FAILED", "HPKE-Aufbau fehlgeschlagen"))?;
    let mut secret = Zeroizing::new([0u8; KEY_LEN]);
    ctx.export(EXPORT_LABEL, &mut secret[..])
        .map_err(|_| err("HPKE_SETUP_FAILED", "Export fehlgeschlagen"))?;
    let mut body = Vec::with_capacity(plaintext.len() + plaintext.len() / FRAME_PLAIN * 20 + 20);
    for chunk in plaintext.chunks(FRAME_PLAIN) {
        let ct = ctx
            .seal(chunk, &[])
            .map_err(|_| err("AEAD_ENCRYPT_FAILED", "Verschlüsseln fehlgeschlagen"))?;
        body.extend_from_slice(&(ct.len() as u32).to_be_bytes());
        body.extend_from_slice(&ct);
    }
    let enc_bytes: [u8; KEY_LEN] = enc.to_bytes().into();
    Ok((
        EhbpSealed {
            encapsulated_key: enc_bytes.to_vec(),
            body,
        },
        EhbpSession {
            enc: enc_bytes,
            secret,
        },
    ))
}

impl EhbpSession {
    /// Antwort-Decoder aus dem Header `Ehbp-Response-Nonce` (genau 32 Byte).
    pub fn response_decoder(&self, response_nonce: &[u8]) -> Result<EhbpResponseDecoder, String> {
        EhbpResponseDecoder::derive(&self.secret[..], &self.enc, response_nonce)
    }
}

impl EhbpResponseDecoder {
    /// Ableitung nach SPEC §4.4.1 (auch für die Konformanzvektoren).
    pub fn derive(secret: &[u8], enc: &[u8], response_nonce: &[u8]) -> Result<Self, String> {
        if secret.len() != KEY_LEN
            || enc.len() != KEY_LEN
            || response_nonce.len() != RESPONSE_NONCE_LEN
        {
            return Err(err(
                "INVALID_INPUT",
                "Längen von Secret, enc oder Nonce falsch",
            ));
        }
        let mut salt = Vec::with_capacity(enc.len() + response_nonce.len());
        salt.extend_from_slice(enc);
        salt.extend_from_slice(response_nonce);
        let hk = Hkdf::<Sha256>::new(Some(&salt), secret);
        let mut key = Zeroizing::new([0u8; KEY_LEN]);
        let mut nonce_base = [0u8; NONCE_LEN];
        hk.expand(b"key", &mut key[..])
            .and_then(|_| hk.expand(b"nonce", &mut nonce_base))
            .map_err(|_| err("HPKE_SETUP_FAILED", "Ableitung fehlgeschlagen"))?;
        Ok(Self {
            key,
            nonce_base,
            seq: 0,
            buf: Vec::new(),
            state: State::Open,
        })
    }

    /// Schlüsselmaterial `key ‖ nonce` (nur für Tests der Ableitung).
    #[cfg(test)]
    pub(crate) fn material(&self) -> Vec<u8> {
        [&self.key[..], &self.nonce_base[..]].concat()
    }

    fn fail<T>(&mut self, code: &str, text: &str) -> Result<T, String> {
        self.state = State::Failed;
        self.buf.zeroize();
        self.buf = Vec::new();
        Err(err(code, text))
    }

    /// Schiebt Netzwerkbytes hinein und liefert den Klartext aller dadurch vollständig
    /// authentisierten Frames. Jeder Fehler ist endgültig; der Klartext des fehlerhaften Aufrufs
    /// (auch schon entschlüsselte Frames davor) wird verworfen.
    pub fn push(&mut self, data: &[u8]) -> Result<Vec<u8>, String> {
        match self.state {
            State::Failed => {
                return Err(err(
                    "DECODER_FAILED",
                    "Decoder ist nach einem Fehler unbrauchbar",
                ))
            }
            State::Finished => return Err(err("DECODER_FINISHED", "Antwort ist bereits beendet")),
            State::Open => {}
        }
        self.buf.extend_from_slice(data);
        let mut out = Vec::new();
        let mut pos = 0usize;
        loop {
            let rest = &self.buf[pos..];
            if rest.len() < 4 {
                break;
            }
            let len = u32::from_be_bytes([rest[0], rest[1], rest[2], rest[3]]) as usize;
            if len > MAX_CHUNK {
                out.zeroize();
                return self.fail("CHUNK_TOO_LARGE", "Chunk überschreitet 64 MiB");
            }
            if len == 0 {
                pos += 4;
                continue;
            }
            if rest.len() < 4 + len {
                break;
            }
            let nonce = compute_nonce(&self.nonce_base, self.seq);
            let plain = Aes256Gcm::new_from_slice(&self.key[..]).ok().and_then(|c| {
                c.decrypt(
                    Nonce::from_slice(&nonce),
                    Payload {
                        msg: &rest[4..4 + len],
                        aad: &[],
                    },
                )
                .ok()
            });
            let Some(plain) = plain else {
                out.zeroize();
                return self.fail("AEAD_DECRYPT_FAILED", "Chunk nicht authentisch");
            };
            let Some(next) = self.seq.checked_add(1) else {
                out.zeroize();
                return self.fail("SEQUENCE_OVERFLOW", "Zähler erschöpft");
            };
            self.seq = next;
            out.extend_from_slice(&plain);
            pos += 4 + len;
        }
        self.buf.drain(..pos);
        Ok(out)
    }

    /// Ende des Bodys: ein angebrochener Frame oder Längenpräfix ist ein Abbruch (Abschneiden).
    pub fn finish(&mut self) -> Result<(), String> {
        match self.state {
            State::Failed => Err(err(
                "DECODER_FAILED",
                "Decoder ist nach einem Fehler unbrauchbar",
            )),
            State::Finished => Ok(()),
            State::Open if !self.buf.is_empty() => {
                self.fail("FRAMING_TRUNCATED", "Body endet mitten im Frame")
            }
            State::Open => {
                self.state = State::Finished;
                Ok(())
            }
        }
    }

    /// Zustand für Tests: wurde der Decoder nach Fehler gesperrt?
    #[cfg(test)]
    pub(crate) fn is_failed(&self) -> bool {
        self.state == State::Failed
    }
}

/// Nonce = Basis XOR Zähler (big-endian in die letzten 8 Byte).
pub fn compute_nonce(base: &[u8; NONCE_LEN], seq: u64) -> [u8; NONCE_LEN] {
    let mut n = *base;
    for (i, b) in seq.to_be_bytes().iter().enumerate() {
        n[NONCE_LEN - 8 + i] ^= b;
    }
    n
}

const _: () = assert!(TAG_LEN == 16);

#[cfg(test)]
#[path = "ehbp_tests.rs"]
mod tests;
