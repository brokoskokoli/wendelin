//! Synthetisches Sigstore-Bundle (WP76b, Nachbesserung): eigene Fulcio-CA (Wurzel + Zwischenzertifikat,
//! P-384), eigener Rekor-Schlüssel (P-256), eigener Checkpoint, SET und Inklusionsbeweis, alles zur
//! Laufzeit mit festen Schlüsseln erzeugt und über `trusted_root_json` vertraut. Jede Abweichung
//! (`Spec`) verletzt genau eine Regel; erwartet wird, dass genau die zugehörige Stufe rot wird.
use base64::{engine::general_purpose::STANDARD as B64, Engine};
use p256::ecdsa::{signature::Signer, SigningKey as K256};
use p384::ecdsa::SigningKey as K384;
use sha2::{Digest, Sha256};
use wendelin_attest::sigstore::{verify_release, SigstoreVerdict};

const REPO: &str = "acme/router";
const TAG: &str = "v1.2.3";
const DIGEST: &str = "8daaecd40cd29b45d508d7250feadf5e3eff555cb6fadd58131c996598007e97";
const MEAS: &str = "9b5493714af482656d43d963774da1185a611dac14a46a03cfbde5a2984201a9d41fc2b6a5f81b806e58acae104226a6";
const PREDICATE: &str = "https://tinfoil.sh/predicate/snp-tdx-multiplatform/v1";
const T: u64 = 1_717_200_000; // 2024-06-01T00:00:00Z
const GH: &str = "https://token.actions.githubusercontent.com";
const OID_CS: &str = "1.3.6.1.5.5.7.3.3";

// --- DER ------------------------------------------------------------------------------------

fn tlv(tag: u8, c: &[u8]) -> Vec<u8> {
    let mut v = vec![tag];
    if c.len() < 128 {
        v.push(c.len() as u8);
    } else if c.len() < 256 {
        v.extend([0x81, c.len() as u8]);
    } else {
        v.extend([0x82, (c.len() >> 8) as u8, c.len() as u8]);
    }
    v.extend_from_slice(c);
    v
}
fn seq(parts: &[Vec<u8>]) -> Vec<u8> {
    tlv(0x30, &parts.concat())
}
fn oid(s: &str) -> Vec<u8> {
    let a: Vec<u64> = s.split('.').map(|x| x.parse().unwrap()).collect();
    let mut c = vec![(a[0] * 40 + a[1]) as u8];
    for &n in &a[2..] {
        let mut b = vec![(n & 0x7f) as u8];
        let mut n = n >> 7;
        while n > 0 {
            b.push((n & 0x7f) as u8 | 0x80);
            n >>= 7;
        }
        b.reverse();
        c.extend(b);
    }
    tlv(0x06, &c)
}
fn utf8(s: &str) -> Vec<u8> {
    tlv(0x0c, s.as_bytes())
}
fn name(cn: &str) -> Vec<u8> {
    seq(&[tlv(0x31, &seq(&[oid("2.5.4.3"), utf8(cn)]))])
}
fn ext(o: &str, val: &[u8]) -> Vec<u8> {
    seq(&[oid(o), tlv(0x04, val)])
}
fn spki(curve: &str, point: &[u8]) -> Vec<u8> {
    let mut bits = vec![0];
    bits.extend_from_slice(point);
    seq(&[
        seq(&[oid("1.2.840.10045.2.1"), oid(curve)]),
        tlv(0x03, &bits),
    ])
}

#[derive(Clone)]
enum Key {
    P256(K256),
    P384(K384),
}
impl Key {
    fn p256(seed: u8) -> Self {
        Key::P256(K256::from_slice(&[seed; 32]).unwrap())
    }
    fn p384(seed: u8) -> Self {
        Key::P384(K384::from_slice(&[seed; 48]).unwrap())
    }
    fn spki(&self) -> Vec<u8> {
        match self {
            Key::P256(k) => spki(
                "1.2.840.10045.3.1.7",
                k.verifying_key().to_sec1_point(false).as_bytes(),
            ),
            Key::P384(k) => spki(
                "1.3.132.0.34",
                k.verifying_key().to_sec1_point(false).as_bytes(),
            ),
        }
    }
    fn sign(&self, msg: &[u8]) -> Vec<u8> {
        match self {
            Key::P256(k) => {
                let s: p256::ecdsa::Signature = k.sign(msg);
                s.to_der().as_bytes().to_vec()
            }
            Key::P384(k) => {
                let s: p384::ecdsa::Signature = k.sign(msg);
                s.to_der().as_bytes().to_vec()
            }
        }
    }
    fn alg(&self) -> Vec<u8> {
        seq(&[oid(match self {
            Key::P256(_) => "1.2.840.10045.4.3.2",
            Key::P384(_) => "1.2.840.10045.4.3.3",
        })])
    }
}

fn cert(
    subject: &str,
    issuer: &str,
    nb: &str,
    na: &str,
    key: &Key,
    signer: &Key,
    exts: Vec<Vec<u8>>,
) -> Vec<u8> {
    let validity = seq(&[tlv(0x17, nb.as_bytes()), tlv(0x17, na.as_bytes())]);
    let mut parts = vec![
        tlv(0xa0, &tlv(0x02, &[2])),
        tlv(0x02, &[1]),
        signer.alg(),
        name(issuer),
        validity,
        name(subject),
        key.spki(),
    ];
    if !exts.is_empty() {
        parts.push(tlv(0xa3, &seq(&exts)));
    }
    let tbs = seq(&parts);
    let mut sig = vec![0];
    sig.extend(signer.sign(&tbs));
    seq(&[tbs, signer.alg(), tlv(0x03, &sig)])
}

// --- Bundle ---------------------------------------------------------------------------------

#[derive(Clone)]
struct Spec {
    issuer: String,
    eku: &'static str,
    /// KeyUsage-Byte (0x80 = digitalSignature); `None` = Erweiterung fehlt.
    key_usage: Option<u8>,
    leaf_nb: &'static str,
    leaf_na: &'static str,
    root_na: &'static str,
    inter_na: &'static str,
    root_selfsig_bad: bool,
    predicate: &'static str,
    ext12: Option<String>,
    ext5: Option<String>,
    ext14: Option<String>,
    ext6: Option<String>,
    bad_entry_sig: bool,
    kind_version: (&'static str, &'static str),
    body_kind: &'static str,
    body_api: &'static str,
    // Baum
    tree_size: u64,
    proof_index: u64,
    cp_root_wrong: bool,
    cp_origin: String,
    cp_name: String,
}

impl Spec {
    fn ok() -> Self {
        Spec {
            issuer: GH.into(),
            eku: OID_CS,
            key_usage: Some(0x80),
            leaf_nb: "240531000000Z",
            leaf_na: "240602000000Z",
            root_na: "340101000000Z",
            inter_na: "340101000000Z",
            root_selfsig_bad: false,
            predicate: PREDICATE,
            ext12: Some(format!("https://github.com/{REPO}")),
            ext5: Some(REPO.into()),
            ext14: Some(format!("refs/tags/{TAG}")),
            ext6: Some(format!("refs/tags/{TAG}")),
            bad_entry_sig: false,
            kind_version: ("dsse", "0.0.1"),
            body_kind: "dsse",
            body_api: "0.0.1",
            tree_size: 2,
            proof_index: 0,
            cp_root_wrong: false,
            cp_origin: "rekor.sigstore.dev - 1193050959916656506".into(),
            cp_name: "rekor.sigstore.dev".into(),
        }
    }
}

fn sha(b: &[u8]) -> [u8; 32] {
    Sha256::digest(b).into()
}
fn leaf_hash(body: &[u8]) -> [u8; 32] {
    sha(&[&[0u8][..], body].concat())
}
fn node(l: &[u8], r: &[u8]) -> [u8; 32] {
    sha(&[&[1u8][..], l, r].concat())
}

/// (Bundle-JSON, Trust-Root-JSON)
fn build(s: &Spec) -> (String, String) {
    let root_k = Key::p384(1);
    let inter_k = Key::p384(2);
    let attacker = Key::p384(9);
    let leaf_k = Key::p256(3);
    let rekor_k = Key::p256(4);
    let Key::P256(rk) = &rekor_k else {
        unreachable!()
    };
    let rekor_spki = rekor_k.spki();
    let key_id = sha(&rekor_spki).to_vec();

    let root = cert(
        "Synth Root",
        "Synth Root",
        "200101000000Z",
        s.root_na,
        &root_k,
        if s.root_selfsig_bad {
            &attacker
        } else {
            &root_k
        },
        vec![],
    );
    let inter = cert(
        "Synth Inter",
        "Synth Root",
        "200101000000Z",
        s.inter_na,
        &inter_k,
        &root_k,
        vec![],
    );
    let mut exts = vec![];
    if let Some(ku) = s.key_usage {
        exts.push(seq(&[
            oid("2.5.29.15"),
            tlv(0x01, &[0xff]),
            tlv(0x04, &[0x03, 0x02, 0x01, ku]),
        ]));
    }
    exts.push(ext("2.5.29.37", &seq(&[oid(s.eku)])));
    exts.push(ext("1.3.6.1.4.1.57264.1.8", &utf8(&s.issuer)));
    exts.push(ext(
        "1.3.6.1.4.1.57264.1.9",
        &utf8(&format!(
            "https://github.com/{REPO}/.github/workflows/release.yml@refs/tags/{TAG}"
        )),
    ));
    for (o, v) in [
        ("1.3.6.1.4.1.57264.1.12", &s.ext12),
        ("1.3.6.1.4.1.57264.1.5", &s.ext5),
        ("1.3.6.1.4.1.57264.1.14", &s.ext14),
        ("1.3.6.1.4.1.57264.1.6", &s.ext6),
    ] {
        if let Some(v) = v {
            exts.push(ext(o, &utf8(v)));
        }
    }
    let leaf = cert(
        "Synth Leaf",
        "Synth Inter",
        s.leaf_nb,
        s.leaf_na,
        &leaf_k,
        &inter_k,
        exts,
    );

    // DSSE
    let payload = serde_json::json!({
        "_type": "https://in-toto.io/Statement/v1",
        "subject": [{"name": "x", "digest": {"sha256": DIGEST}}],
        "predicateType": s.predicate,
        "predicate": {"snp_measurement": MEAS},
    })
    .to_string()
    .into_bytes();
    let ptype = "application/vnd.in-toto+json";
    let mut pae = format!("DSSEv1 {} {} {} ", ptype.len(), ptype, payload.len()).into_bytes();
    pae.extend_from_slice(&payload);
    let sig = leaf_k.sign(&pae);

    // Rekor-Eintrag
    let logged_sig = if s.bad_entry_sig {
        let mut x = sig.clone();
        *x.last_mut().unwrap() ^= 1;
        x
    } else {
        sig.clone()
    };
    let pem_s = pem::encode(&pem::Pem::new("CERTIFICATE", leaf.clone()));
    let body = serde_json::json!({
        "apiVersion": s.body_api,
        "kind": s.body_kind,
        "spec": {
            "payloadHash": {"algorithm": "sha256", "value": hex::encode(sha(&payload))},
            "signatures": [{"signature": B64.encode(&logged_sig), "verifier": B64.encode(pem_s)}],
        },
    })
    .to_string()
    .into_bytes();
    let body_b64 = B64.encode(&body);
    let log_index = 7u64;
    let set_msg = format!(
        "{{\"body\":\"{}\",\"integratedTime\":{},\"logID\":\"{}\",\"logIndex\":{}}}",
        body_b64,
        T,
        hex::encode(&key_id),
        log_index
    );
    let set: p256::ecdsa::Signature = rk.sign(set_msg.as_bytes());

    // Baum: Größe 1 (Blatt = Wurzel) oder 2 (Blatt links, beliebiger Nachbar rechts)
    let leaf_h = leaf_hash(&body);
    let sibling = [0x5au8; 32];
    let (root_h, hashes): ([u8; 32], Vec<String>) = if s.tree_size == 1 {
        (leaf_h, vec![])
    } else {
        (node(&leaf_h, &sibling), vec![B64.encode(sibling)])
    };
    let cp_root = if s.cp_root_wrong {
        [0xeeu8; 32]
    } else {
        root_h
    };
    let note = format!(
        "{}\n{}\n{}\n",
        s.cp_origin,
        s.tree_size,
        B64.encode(cp_root)
    );
    let cp_sig: p256::ecdsa::Signature = rk.sign(note.as_bytes());
    let mut raw = key_id[..4].to_vec();
    raw.extend_from_slice(cp_sig.to_der().as_bytes());
    let envelope = format!("{note}\n\u{2014} {} {}\n", s.cp_name, B64.encode(raw));

    let bundle = serde_json::json!({
        "mediaType": "application/vnd.dev.sigstore.bundle.v0.3+json",
        "verificationMaterial": {
            "certificate": {"rawBytes": B64.encode(&leaf)},
            "tlogEntries": [{
                "logIndex": log_index.to_string(),
                "logId": {"keyId": B64.encode(&key_id)},
                "kindVersion": {"kind": s.kind_version.0, "version": s.kind_version.1},
                "integratedTime": T.to_string(),
                "inclusionPromise": {"signedEntryTimestamp": B64.encode(set.to_der().as_bytes())},
                "inclusionProof": {
                    "logIndex": s.proof_index.to_string(),
                    "rootHash": B64.encode(root_h),
                    "treeSize": s.tree_size.to_string(),
                    "hashes": hashes,
                    "checkpoint": {"envelope": envelope},
                },
                "canonicalizedBody": body_b64,
            }],
        },
        "dsseEnvelope": {
            "payload": B64.encode(&payload),
            "payloadType": ptype,
            "signatures": [{"sig": B64.encode(&sig)}],
        },
    })
    .to_string();
    let trust = serde_json::json!({
        "tlogs": [{
            "baseUrl": "https://rekor.sigstore.dev",
            "logId": {"keyId": B64.encode(&key_id)},
            "publicKey": {
                "rawBytes": B64.encode(&rekor_spki),
                "keyDetails": "PKIX_ECDSA_P256_SHA_256",
                "validFor": {"start": "2021-01-01T00:00:00Z"},
            },
        }],
        "certificateAuthorities": [{
            "certChain": {"certificates": [
                {"rawBytes": B64.encode(&inter)},
                {"rawBytes": B64.encode(&root)},
            ]},
            "validFor": {"start": "2021-01-01T00:00:00Z"},
        }],
    })
    .to_string();
    (bundle, trust)
}

fn run(s: &Spec) -> SigstoreVerdict {
    let (b, t) = build(s);
    verify_release(&b, REPO, TAG, DIGEST, MEAS, Some(&t))
}

fn failed(v: &SigstoreVerdict) -> Vec<&'static str> {
    [
        (v.dsse_ok, "dsse"),
        (v.chain_ok, "chain"),
        (v.identity_ok, "identity"),
        (v.rekor_ok, "rekor"),
        (v.measurement_ok, "measurement"),
    ]
    .into_iter()
    .filter(|(ok, _)| !ok)
    .map(|(_, n)| n)
    .collect()
}

/// Genau `stage` ist rot, und die Fehlermeldung nennt `hint` (damit nicht ein anderer Grund trifft).
fn red(s: &Spec, stage: &str, hint: &str) {
    let v = run(s);
    // Ohne geprüften Rekor-Zeitpunkt entfällt die Kettenprüfung ("übersprungen") und ist ebenfalls rot.
    let want: Vec<&str> = if stage == "rekor" {
        vec!["chain", "rekor"]
    } else {
        vec![stage]
    };
    assert_eq!(failed(&v), want, "{:?}", v.errors);
    assert!(
        v.errors.iter().any(|e| e.contains(hint)),
        "'{hint}' nicht in {:?}",
        v.errors
    );
}

// --- Tests ----------------------------------------------------------------------------------

#[test]
fn baseline_is_fully_valid() {
    let v = run(&Spec::ok());
    assert!(v.all_ok(), "{:?}", v.errors);
    assert_eq!(v.release_tag, TAG);
    assert_eq!(v.integrated_time, T);
}

#[test]
fn baseline_with_single_leaf_tree_is_valid() {
    let mut s = Spec::ok();
    s.tree_size = 1;
    let v = run(&s);
    assert!(v.all_ok(), "{:?}", v.errors);
}

#[test]
fn foreign_oidc_issuer_fails_identity() {
    let mut s = Spec::ok();
    s.issuer = "https://accounts.google.com".into();
    red(&s, "identity", "OIDC-Aussteller");
}

#[test]
fn missing_code_signing_eku_fails_chain() {
    let mut s = Spec::ok();
    s.eku = "1.3.6.1.5.5.7.3.4"; // emailProtection
    red(&s, "chain", "codeSigning");
}

#[test]
fn missing_key_usage_fails_chain() {
    let mut s = Spec::ok();
    s.key_usage = None;
    red(&s, "chain", "KeyUsage fehlt");
}

#[test]
fn key_usage_without_digital_signature_fails_chain() {
    let mut s = Spec::ok();
    s.key_usage = Some(0x06); // keyCertSign | cRLSign
    red(&s, "chain", "digitalSignature");
}

#[test]
fn leaf_expired_at_integrated_time_fails_chain() {
    let mut s = Spec::ok();
    s.leaf_na = "240531120000Z";
    red(&s, "chain", "Zertifikat zum Rekor-Zeitpunkt");
}

#[test]
fn leaf_not_yet_valid_at_integrated_time_fails_chain() {
    let mut s = Spec::ok();
    s.leaf_nb = "240601000001Z";
    s.leaf_na = "240602000000Z";
    red(&s, "chain", "Zertifikat zum Rekor-Zeitpunkt");
}

#[test]
fn expired_root_fails_chain() {
    let mut s = Spec::ok();
    s.root_na = "240101000000Z";
    red(&s, "chain", "CA-Zertifikat");
}

#[test]
fn expired_intermediate_fails_chain() {
    let mut s = Spec::ok();
    s.inter_na = "240101000000Z";
    red(&s, "chain", "CA-Zertifikat");
}

#[test]
fn root_with_invalid_self_signature_fails_chain() {
    let mut s = Spec::ok();
    s.root_selfsig_bad = true;
    red(&s, "chain", "Zertifikatssignatur");
}

#[test]
fn foreign_predicate_type_fails_dsse() {
    let mut s = Spec::ok();
    s.predicate = "https://example.com/predicate/v1";
    let v = run(&s);
    assert_eq!(failed(&v), ["dsse", "measurement"], "{:?}", v.errors);
    assert!(v.errors.iter().any(|e| e.contains("predicateType")));
}

#[test]
fn entry_signature_differing_from_bundle_fails_rekor() {
    let mut s = Spec::ok();
    s.bad_entry_sig = true;
    red(&s, "rekor", "Signatur im Eintrag");
}

#[test]
fn entry_kind_not_dsse_fails_rekor() {
    let mut s = Spec::ok();
    s.kind_version = ("hashedrekord", "0.0.1");
    s.body_kind = "hashedrekord";
    red(&s, "rekor", "dsse-Eintrag");
}

#[test]
fn body_kind_differing_from_kind_version_fails_rekor() {
    let mut s = Spec::ok();
    s.body_kind = "hashedrekord";
    red(&s, "rekor", "dsse-Eintrag");
}

#[test]
fn body_api_version_differing_from_kind_version_fails_rekor() {
    let mut s = Spec::ok();
    s.body_api = "0.0.2";
    red(&s, "rekor", "dsse-Eintrag");
}

#[test]
fn proof_index_equal_to_tree_size_fails_rekor() {
    // Baum mit einem Blatt, Beweis für "Index 1": ohne index<size-Prüfung wäre der leere Pfad gültig.
    let mut s = Spec::ok();
    s.tree_size = 1;
    s.proof_index = 1;
    red(&s, "rekor", "Merkle");
}

#[test]
fn proof_index_beyond_tree_size_fails_rekor() {
    let mut s = Spec::ok();
    s.proof_index = 2;
    red(&s, "rekor", "Merkle");
}

#[test]
fn checkpoint_root_differing_from_proof_root_fails_rekor() {
    // Beweis und rootHash passen zusammen, die (gültig signierte) Notiz nennt eine andere Wurzel:
    // nur der Abgleich Checkpoint-Wurzel ↔ rootHash kann das fangen.
    let mut s = Spec::ok();
    s.cp_root_wrong = true;
    red(&s, "rekor", "Checkpoint-Wurzel");
}

#[test]
fn checkpoint_origin_of_foreign_log_fails_rekor() {
    let mut s = Spec::ok();
    s.cp_origin = "evil.example - 1193050959916656506".into();
    red(&s, "rekor", "Checkpoint-Ursprung");
}

#[test]
fn checkpoint_origin_without_numeric_tree_id_fails_rekor() {
    let mut s = Spec::ok();
    s.cp_origin = "rekor.sigstore.dev - abc".into();
    red(&s, "rekor", "Checkpoint-Ursprung");
}

#[test]
fn checkpoint_signature_under_foreign_key_name_fails_rekor() {
    let mut s = Spec::ok();
    s.cp_name = "evil.example".into();
    red(&s, "rekor", "Checkpoint-Signatur");
}

#[test]
fn repository_extension_v2_for_other_repo_fails_identity() {
    // Nur .12 weicht ab (.5 stimmt): die veraltete Erweiterung allein genügt nicht.
    let mut s = Spec::ok();
    s.ext12 = Some("https://github.com/evil/router".into());
    red(&s, "identity", "Repository");
}

#[test]
fn repository_extension_legacy_for_other_repo_fails_identity() {
    let mut s = Spec::ok();
    s.ext5 = Some("evil/router".into());
    red(&s, "identity", "Repository");
}

#[test]
fn only_v2_repository_extension_is_accepted() {
    let mut s = Spec::ok();
    s.ext5 = None;
    let v = run(&s);
    assert!(v.all_ok(), "{:?}", v.errors);
}

#[test]
fn no_repository_extension_fails_identity() {
    let mut s = Spec::ok();
    s.ext5 = None;
    s.ext12 = None;
    red(&s, "identity", "Repository fehlt");
}

#[test]
fn source_ref_extension_for_other_tag_fails_identity() {
    let mut s = Spec::ok();
    s.ext14 = Some("refs/tags/v9.9.9".into());
    red(&s, "identity", "Referenz");
}

#[test]
fn legacy_ref_extension_for_other_tag_fails_identity() {
    let mut s = Spec::ok();
    s.ext6 = Some("refs/heads/main".into());
    red(&s, "identity", "Referenz");
}
