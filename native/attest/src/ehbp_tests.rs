//! Tests für `ehbp`: Konformanzvektoren der Referenz (v0.4.1), Anfrage-Rundlauf, Negativfälle.
use super::*;
use hpke::{OpModeR, Serializable};
use rand_core09::RngCore;
use serde_json::Value;

fn vectors() -> Vec<Value> {
    serde_json::from_str(include_str!("../tests/ehbp/crypto.json")).unwrap()
}

fn h(v: &Value, k: &str) -> Vec<u8> {
    hex::decode(v["inputs"][k].as_str().unwrap()).unwrap()
}

/// Füttert den Decoder mit Fragmenten; liefert (Klartext vor Fehler, Fehler?).
fn run(v: &Value, frag: usize) -> (Vec<u8>, Option<String>) {
    let mut d = match EhbpResponseDecoder::derive(
        &h(v, "exportedSecret"),
        &h(v, "requestEnc"),
        &h(v, "responseNonce"),
    ) {
        Ok(d) => d,
        Err(e) => return (vec![], Some(e)),
    };
    let mut out = Vec::new();
    for c in h(v, "encryptedResponse").chunks(frag) {
        match d.push(c) {
            Ok(p) => out.extend(p),
            Err(e) => {
                assert!(
                    d.push(&[0]).is_err() && d.finish().is_err(),
                    "Decoder nach Fehler nutzbar"
                );
                return (out, Some(e));
            }
        }
    }
    match d.finish() {
        Ok(()) => (out, None),
        Err(e) => (out, Some(e)),
    }
}

#[test]
fn conformance_vectors_25() {
    let mut n = 0;
    for v in vectors() {
        let op = v["operation"].as_str().unwrap();
        let id = v["id"].as_str().unwrap();
        let exp = &v["expect"];
        match op {
            "token_roundtrip" => continue,
            "compute_nonce" => {
                let base: [u8; 12] = h(&v, "nonceBase").try_into().unwrap();
                let seq = u64::from_be_bytes(h(&v, "seqHex").try_into().unwrap());
                assert_eq!(
                    hex::encode(compute_nonce(&base, seq)),
                    exp["body_hex"],
                    "{id}"
                );
            }
            "derive_keys" => match EhbpResponseDecoder::derive(
                &h(&v, "exportedSecret"),
                &h(&v, "requestEnc"),
                &h(&v, "responseNonce"),
            ) {
                Ok(d) => assert_eq!(hex::encode(d.material()), exp["body_hex"], "{id}"),
                Err(e) => assert!(
                    exp["outcome"] == "error" && e.starts_with("INVALID_INPUT"),
                    "{id}"
                ),
            },
            _ => {
                // Einzelpush, 1-Byte- und 3-Byte-Fragmente: gleiches Ergebnis.
                for frag in [usize::MAX, 1, 3] {
                    let (out, e) = run(&v, frag.min(1 << 20));
                    if exp["outcome"] == "ok" {
                        assert!(e.is_none(), "{id} frag {frag}: {e:?}");
                        assert_eq!(hex::encode(&out), exp["body_hex"], "{id}");
                    } else {
                        let e = e.unwrap_or_else(|| panic!("{id} frag {frag}: kein Fehler"));
                        assert!(
                            e.starts_with(exp["error_code"].as_str().unwrap()),
                            "{id}: {e}"
                        );
                        if frag == 1 {
                            // Byteweise: genau der beglaubigte Präfix kommt heraus.
                            assert_eq!(out.len() as u64, exp["bytes_emitted_before_error"], "{id}");
                        } else {
                            assert!(
                                out.len() as u64
                                    <= exp["bytes_emitted_before_error"].as_u64().unwrap(),
                                "{id}"
                            );
                        }
                    }
                }
            }
        }
        n += 1;
    }
    assert_eq!(n, 25);
}

struct Server {
    sk: <X25519HkdfSha256 as hpke::Kem>::PrivateKey,
    cfg: Vec<u8>,
}

fn server(seed: u64) -> Server {
    let mut rng = rand_chacha_free::rng(seed);
    let (sk, pk) = <X25519HkdfSha256 as hpke::Kem>::gen_keypair(&mut rng);
    let mut cfg = vec![0u8, 0x00, 0x20];
    cfg.extend_from_slice(&pk.to_bytes());
    cfg.extend_from_slice(&[0, 4, 0, 1, 0, 2]);
    Server { sk, cfg }
}

/// Minimaler deterministischer Zufall nur für Tests (rand_core 0.9, kein Zusatz-Crate).
mod rand_chacha_free {
    use rand_core09::{CryptoRng, RngCore};
    pub struct Ctr(u64);
    pub fn rng(seed: u64) -> Ctr {
        Ctr(seed)
    }
    impl RngCore for Ctr {
        fn next_u32(&mut self) -> u32 {
            self.next_u64() as u32
        }
        fn next_u64(&mut self) -> u64 {
            self.0 = self
                .0
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            self.0
        }
        fn fill_bytes(&mut self, dst: &mut [u8]) {
            for c in dst.chunks_mut(8) {
                let b = self.next_u64().to_le_bytes();
                c.copy_from_slice(&b[..c.len()]);
            }
        }
    }
    impl CryptoRng for Ctr {}
}

fn report_data(cfg: &[u8]) -> Vec<u8> {
    let mut rd = vec![7u8; 32];
    rd.extend_from_slice(&cfg[3..35]);
    rd
}

fn deframe(body: &[u8]) -> Vec<Vec<u8>> {
    let mut v = vec![];
    let mut p = 0;
    while p < body.len() {
        let l = u32::from_be_bytes(body[p..p + 4].try_into().unwrap()) as usize;
        v.push(body[p + 4..p + 4 + l].to_vec());
        p += 4 + l;
    }
    v
}

#[test]
fn request_roundtrip_with_recipient_and_response() {
    let s = server(1);
    let rd = report_data(&s.cfg);
    let b = bind_key_config(&s.cfg, &rd).unwrap();
    assert_eq!(b.tls_spki_sha256, vec![7u8; 32]);
    let mut plain = vec![0u8; FRAME_PLAIN * 2 + 5];
    rand_chacha_free::rng(9).fill_bytes(&mut plain);
    let (req, session) = begin_request(&s.cfg, &rd, &plain).unwrap();
    // Empfängerseite
    let frames = deframe(&req.body);
    assert_eq!(frames.len(), 3);
    assert_eq!(frames[0].len(), FRAME_PLAIN + TAG_LEN);
    let enc =
        <X25519HkdfSha256 as hpke::Kem>::EncappedKey::from_bytes(&req.encapsulated_key).unwrap();
    let mut ctx = hpke::setup_receiver::<AesGcm256, HkdfSha256, X25519HkdfSha256>(
        &OpModeR::Base,
        &s.sk,
        &enc,
        REQUEST_INFO,
    )
    .unwrap();
    let got: Vec<u8> = frames
        .iter()
        .flat_map(|f| ctx.open(f, &[]).unwrap())
        .collect();
    assert_eq!(got, plain);
    let mut secret = [0u8; 32];
    ctx.export(EXPORT_LABEL, &mut secret).unwrap();
    assert_eq!(&secret[..], &session.secret[..]);
    // Antwort: Server verschlüsselt mit abgeleiteten Schlüsseln (zwei Frames), Client entschlüsselt.
    let nonce = [5u8; 32];
    let mut dec = session.response_decoder(&nonce).unwrap();
    let srv = EhbpResponseDecoder::derive(&secret, &req.encapsulated_key, &nonce).unwrap();
    let c = Aes256Gcm::new_from_slice(&srv.key[..]).unwrap();
    let mut wire = vec![];
    for (i, m) in [&b"data: hallo\n\n"[..], &b"data: [DONE]\n\n"[..]]
        .iter()
        .enumerate()
    {
        let ct = c
            .encrypt(
                Nonce::from_slice(&compute_nonce(&srv.nonce_base, i as u64)),
                Payload { msg: m, aad: &[] },
            )
            .unwrap();
        wire.extend_from_slice(&(ct.len() as u32).to_be_bytes());
        wire.extend(ct);
    }
    let mut out = vec![];
    for ch in wire.chunks(5) {
        out.extend(dec.push(ch).unwrap());
    }
    dec.finish().unwrap();
    assert_eq!(out, b"data: hallo\n\ndata: [DONE]\n\n");
}

#[test]
fn requests_use_fresh_ephemeral_keys() {
    let s = server(2);
    let rd = report_data(&s.cfg);
    let (a, _) = begin_request(&s.cfg, &rd, b"x").unwrap();
    let (b, _) = begin_request(&s.cfg, &rd, b"x").unwrap();
    assert_ne!(a.encapsulated_key, b.encapsulated_key);
    assert_ne!(a.body, b.body);
}

#[test]
fn key_config_must_be_exact() {
    let s = server(3);
    let rd = report_data(&s.cfg);
    for (i, val) in [(0usize, 1u8), (1, 1), (2, 0x21), (36, 5), (38, 2), (40, 3)] {
        let mut c = s.cfg.clone();
        c[i] = val;
        assert!(
            parse_key_config(&c)
                .unwrap_err()
                .starts_with("UNSUPPORTED_SUITE"),
            "Byte {i}"
        );
        assert!(begin_request(&c, &rd, b"x").is_err());
    }
    assert!(parse_key_config(&s.cfg[..40]).is_err());
    let mut long = s.cfg.clone();
    long.extend_from_slice(&[0, 0]);
    assert!(parse_key_config(&long).is_err());
}

#[test]
fn key_must_equal_report_data() {
    let s = server(4);
    let other = server(5);
    let e = begin_request(&s.cfg, &report_data(&other.cfg), b"x")
        .err()
        .unwrap();
    assert!(e.starts_with("KEY_NOT_BOUND"), "{e}");
    let mut rd = report_data(&s.cfg);
    rd[63] ^= 1;
    assert!(bind_key_config(&s.cfg, &rd).is_err());
    assert!(bind_key_config(&s.cfg, &rd[..63]).is_err());
    // Nur der Schlüsselteil zählt; der TLS-Teil wird als Pin geliefert, nicht verglichen.
    let mut rd2 = report_data(&s.cfg);
    rd2[0] ^= 1;
    assert_eq!(
        bind_key_config(&s.cfg, &rd2).unwrap().tls_spki_sha256[0],
        7 ^ 1
    );
}

#[test]
fn empty_body_and_bad_nonce_rejected() {
    let s = server(6);
    let rd = report_data(&s.cfg);
    assert!(begin_request(&s.cfg, &rd, b"").is_err());
    let (_, r) = begin_request(&s.cfg, &rd, b"x").unwrap();
    for n in [0usize, 31, 33] {
        assert!(r.response_decoder(&vec![1u8; n]).is_err());
    }
}

#[test]
fn decoder_failure_is_final_and_finish_detects_truncation() {
    let s = server(7);
    let (_, r) = begin_request(&s.cfg, &report_data(&s.cfg), b"x").unwrap();
    let mut d = r.response_decoder(&[1u8; 32]).unwrap();
    assert!(d.push(&[0, 0, 0, 20, 1, 2, 3]).unwrap().is_empty());
    assert!(d.finish().unwrap_err().starts_with("FRAMING_TRUNCATED"));
    assert!(d.is_failed());
    assert!(d.push(&[]).is_err());
    let mut d2 = r.response_decoder(&[1u8; 32]).unwrap();
    d2.finish().unwrap();
    assert!(d2.push(&[0]).is_err());
}

#[test]
fn sequence_overflow_is_hard_error() {
    let mut d = EhbpResponseDecoder::derive(&[0u8; 32], &[0u8; 32], &[0u8; 32]).unwrap();
    d.seq = u64::MAX;
    let c = Aes256Gcm::new_from_slice(&d.key[..]).unwrap();
    let ct = c
        .encrypt(
            Nonce::from_slice(&compute_nonce(&d.nonce_base, u64::MAX)),
            Payload {
                msg: b"a",
                aad: &[],
            },
        )
        .unwrap();
    let mut w = (ct.len() as u32).to_be_bytes().to_vec();
    w.extend(ct);
    assert!(d.push(&w).unwrap_err().starts_with("SEQUENCE_OVERFLOW"));
    assert!(d.is_failed());
}

/// Zufall, der genau `ikm` liefert (HPKE zieht den ephemeren Schlüssel daraus, RFC 9180 DeriveKeyPair).
struct Fixed([u8; 32]);
impl rand_core09::RngCore for Fixed {
    fn next_u32(&mut self) -> u32 {
        0
    }
    fn next_u64(&mut self) -> u64 {
        0
    }
    fn fill_bytes(&mut self, dst: &mut [u8]) {
        dst.copy_from_slice(&self.0[..dst.len()]);
    }
}
impl rand_core09::CryptoRng for Fixed {}

/// Kreuzvektor der Anfrageseite: Empfänger- und ephemerer Schlüssel des CFRG-Vektors
/// (X25519/AES-256-GCM), `info = "ehbp request"`; erzeugt mit der unabhängigen Dart-Referenz
/// (`packages/wendelin_providers/test/tee/ehbp_request_vector_test.dart` prüft dieselben Werte).
#[test]
fn request_matches_dart_reference_vector() {
    let pk =
        hex::decode("430f4b9859665145a6b1ba274024487bd66f03a2dd577d7753c68d7d7d00c00c").unwrap();
    let ikm: [u8; 32] =
        hex::decode("2cd7c601cefb3d42a62b04b7a9041494c06c7843818e0ce28a8f704ae7ab20f9")
            .unwrap()
            .try_into()
            .unwrap();
    let mut cfg = vec![0u8, 0, 0x20];
    cfg.extend_from_slice(&pk);
    cfg.extend_from_slice(&[0, 4, 0, 1, 0, 2]);
    let mut rd = vec![1u8; 32];
    rd.extend_from_slice(&pk);
    let (sealed, session) =
        begin_request_with(&cfg, &rd, b"Hallo Tinfoil", &mut Fixed(ikm)).unwrap();
    assert_eq!(
        hex::encode(&sealed.encapsulated_key),
        "6c93e09869df3402d7bf231bf540fadd35cd56be14f97178f0954db94b7fc256"
    );
    assert_eq!(
        hex::encode(&session.secret[..]),
        "d8f1ee6100814d15c48553fd0d9907039e55c1f0282922c02c81ed973d63d2d3"
    );
    assert_eq!(
        hex::encode(&sealed.body),
        format!(
            "0000001d{}",
            "90c985f1adc6bd60f3dc00e769da0cc379db1a8b83cfb60376ac13481f"
        )
    );
}
