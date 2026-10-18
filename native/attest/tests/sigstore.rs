//! Sigstore-Prüfung des Tinfoil-Releases (WP76b) gegen aufgezeichnete öffentliche Bundles des
//! Router-Repos (`tests/sigstore/bundle_<tag>.json`, über die GitHub-Attestierungs-API geholt).
//! v0.0.158 gehört zum aufgezeichneten SNP-Report (`tests/snp/tinfoil_report.bin`).
use serde_json::Value;
use std::fs;
use wendelin_attest::sigstore::{verify_release, SigstoreVerdict, TRUSTED_ROOT_JSON};
use wendelin_attest::snp;

const REPO: &str = "tinfoilsh/confidential-model-router";
const TAG: &str = "v0.0.158";
const DIGEST: &str = "8daaecd40cd29b45d508d7250feadf5e3eff555cb6fadd58131c996598007e97";
const MEAS_158: &str = "9b5493714af482656d43d963774da1185a611dac14a46a03cfbde5a2984201a9d41fc2b6a5f81b806e58acae104226a6";

fn bundle(tag: &str) -> Value {
    let s = fs::read_to_string(format!("tests/sigstore/bundle_{tag}.json")).unwrap();
    serde_json::from_str(&s).unwrap()
}

fn run(b: &Value) -> SigstoreVerdict {
    verify_release(&b.to_string(), REPO, TAG, DIGEST, MEAS_158, None)
}

fn only_failed(v: &SigstoreVerdict) -> Vec<&'static str> {
    let mut f = vec![];
    for (ok, n) in [
        (v.dsse_ok, "dsse"),
        (v.chain_ok, "chain"),
        (v.identity_ok, "identity"),
        (v.rekor_ok, "rekor"),
        (v.measurement_ok, "measurement"),
    ] {
        if !ok {
            f.push(n);
        }
    }
    f
}

fn flip_b64(s: &str) -> String {
    flip_at(s, 4)
}

fn flip_at(s: &str, i: usize) -> String {
    let mut c: Vec<char> = s.chars().collect();
    c[i] = if c[i] == 'A' { 'B' } else { 'A' };
    c.into_iter().collect()
}

#[test]
fn report_measurement_matches_signed_release() {
    let report = fs::read("tests/snp/tinfoil_report.bin").unwrap();
    let info = snp::report_info(&report).unwrap();
    let v = verify_release(
        &bundle(TAG).to_string(),
        REPO,
        TAG,
        DIGEST,
        &info.measurement_hex,
        None,
    );
    assert!(v.all_ok(), "{:?}", v.errors);
    assert_eq!(v.snp_measurement_hex, MEAS_158);
    assert_eq!(v.release_tag, TAG);
    assert!(v.integrated_time > 1_700_000_000);
}

#[test]
fn newer_release_is_valid_but_measurement_differs_from_old_report() {
    let v = verify_release(
        &bundle("v0.0.159").to_string(),
        REPO,
        "v0.0.159",
        "1ffc1cde7acd5134367cb9f430024203ed4455a51ee4473f7b3e75bd556d0a6b",
        MEAS_158,
        None,
    );
    assert_eq!(only_failed(&v), ["measurement"], "{:?}", v.errors);
}

#[test]
fn uppercase_report_measurement_is_accepted() {
    let v = verify_release(
        &bundle(TAG).to_string(),
        REPO,
        TAG,
        &DIGEST.to_uppercase(),
        &MEAS_158.to_uppercase(),
        None,
    );
    assert!(v.all_ok(), "{:?}", v.errors);
}

#[test]
fn wrong_measurement_fails_only_that_stage() {
    let other = format!("00{}", &MEAS_158[2..]);
    let v = verify_release(&bundle(TAG).to_string(), REPO, TAG, DIGEST, &other, None);
    assert_eq!(only_failed(&v), ["measurement"]);
    assert!(!v.all_ok());
}

#[test]
fn wrong_tag_or_repo_fails_identity() {
    let b = bundle(TAG).to_string();
    let v = verify_release(&b, REPO, "v0.0.159", DIGEST, MEAS_158, None);
    assert_eq!(only_failed(&v), ["identity"], "{:?}", v.errors);
    let v = verify_release(&b, REPO, "v0.0.15", DIGEST, MEAS_158, None);
    assert_eq!(only_failed(&v), ["identity"]);
    let v = verify_release(
        &b,
        "tinfoilsh/confidential-model-routex",
        TAG,
        DIGEST,
        MEAS_158,
        None,
    );
    assert_eq!(only_failed(&v), ["identity"]);
    let v = verify_release(
        &b,
        "evil/confidential-model-router",
        TAG,
        DIGEST,
        MEAS_158,
        None,
    );
    assert_eq!(only_failed(&v), ["identity"]);
}

#[test]
fn wrong_digest_fails_dsse_and_measurement() {
    let other = DIGEST.replace('8', "9");
    let v = verify_release(&bundle(TAG).to_string(), REPO, TAG, &other, MEAS_158, None);
    assert_eq!(only_failed(&v), ["dsse", "measurement"], "{:?}", v.errors);
}

#[test]
fn tampered_payload_is_rejected() {
    let mut b = bundle(TAG);
    let p = b["dsseEnvelope"]["payload"].as_str().unwrap().to_string();
    b["dsseEnvelope"]["payload"] = Value::String(flip_b64(&p));
    let v = run(&b);
    assert!(!v.dsse_ok && !v.rekor_ok && !v.all_ok(), "{:?}", v.errors);
}

#[test]
fn tampered_dsse_signature_is_rejected() {
    let mut b = bundle(TAG);
    let s = b["dsseEnvelope"]["signatures"][0]["sig"]
        .as_str()
        .unwrap()
        .to_string();
    b["dsseEnvelope"]["signatures"][0]["sig"] = Value::String(flip_b64(&s));
    let v = run(&b);
    assert!(!v.dsse_ok && !v.all_ok());
}

#[test]
fn substituted_certificate_is_rejected() {
    // Zertifikat des anderen Releases: DSSE-Signatur passt nicht, Rekor-Eintrag nennt anderes Zertifikat.
    let mut b = bundle(TAG);
    b["verificationMaterial"]["certificate"] =
        bundle("v0.0.159")["verificationMaterial"]["certificate"].clone();
    let v = run(&b);
    assert!(!v.dsse_ok && !v.rekor_ok && !v.all_ok(), "{:?}", v.errors);
}

#[test]
fn tampered_set_is_rejected() {
    let mut b = bundle(TAG);
    let e = &mut b["verificationMaterial"]["tlogEntries"][0];
    let s = e["inclusionPromise"]["signedEntryTimestamp"]
        .as_str()
        .unwrap()
        .to_string();
    e["inclusionPromise"]["signedEntryTimestamp"] = Value::String(flip_b64(&s));
    assert!(!run(&b).rekor_ok);
}

#[test]
fn missing_set_is_rejected() {
    let mut b = bundle(TAG);
    b["verificationMaterial"]["tlogEntries"][0]["inclusionPromise"] = Value::Null;
    assert!(!run(&b).rekor_ok);
}

#[test]
fn shifted_integrated_time_is_rejected() {
    // Die Zeit steckt im SET; eine Änderung (z. B. um ein abgelaufenes Zertifikat zu retten) fällt auf.
    let mut b = bundle(TAG);
    let e = &mut b["verificationMaterial"]["tlogEntries"][0];
    let t: u64 = e["integratedTime"].as_str().unwrap().parse().unwrap();
    e["integratedTime"] = Value::String((t + 1).to_string());
    assert!(!run(&b).rekor_ok);
}

#[test]
fn tampered_inclusion_proof_is_rejected() {
    let mut b = bundle(TAG);
    let ip = &mut b["verificationMaterial"]["tlogEntries"][0]["inclusionProof"];
    let h = ip["hashes"][0].as_str().unwrap().to_string();
    ip["hashes"][0] = Value::String(flip_b64(&h));
    let v = run(&b);
    assert!(!v.rekor_ok && !v.all_ok());
    assert!(
        v.errors.iter().any(|e| e.contains("Merkle")),
        "{:?}",
        v.errors
    );
}

#[test]
fn truncated_or_extended_proof_is_rejected() {
    let mut b = bundle(TAG);
    let hashes = b["verificationMaterial"]["tlogEntries"][0]["inclusionProof"]["hashes"]
        .as_array_mut()
        .unwrap();
    let first = hashes.remove(0);
    assert!(!run(&b).rekor_ok);
    let hashes = b["verificationMaterial"]["tlogEntries"][0]["inclusionProof"]["hashes"]
        .as_array_mut()
        .unwrap();
    hashes.insert(0, first.clone());
    hashes.insert(0, first);
    assert!(!run(&b).rekor_ok);
}

#[test]
fn root_hash_not_matching_checkpoint_is_rejected() {
    let mut b = bundle(TAG);
    let ip = &mut b["verificationMaterial"]["tlogEntries"][0]["inclusionProof"];
    let r = ip["rootHash"].as_str().unwrap().to_string();
    ip["rootHash"] = Value::String(flip_b64(&r));
    assert!(!run(&b).rekor_ok);
}

#[test]
fn tampered_checkpoint_signature_is_rejected() {
    let mut b = bundle(TAG);
    let ip = &mut b["verificationMaterial"]["tlogEntries"][0]["inclusionProof"];
    let env = ip["checkpoint"]["envelope"].as_str().unwrap().to_string();
    let (head, sig) = env.rsplit_once(' ').unwrap();
    ip["checkpoint"]["envelope"] = Value::String(format!("{head} {}", flip_at(sig, 30)));
    assert!(!run(&b).rekor_ok);
}

#[test]
fn checkpoint_signature_with_wrong_key_hint_is_rejected() {
    let mut b = bundle(TAG);
    let ip = &mut b["verificationMaterial"]["tlogEntries"][0]["inclusionProof"];
    let env = ip["checkpoint"]["envelope"].as_str().unwrap().to_string();
    let (head, sig) = env.rsplit_once(' ').unwrap();
    ip["checkpoint"]["envelope"] = Value::String(format!("{head} {}", flip_at(sig, 1)));
    assert!(!run(&b).rekor_ok);
}

#[test]
fn tree_size_not_matching_checkpoint_is_rejected() {
    let mut b = bundle(TAG);
    let ip = &mut b["verificationMaterial"]["tlogEntries"][0]["inclusionProof"];
    let n: u64 = ip["treeSize"].as_str().unwrap().parse().unwrap();
    ip["treeSize"] = Value::String((n + 1).to_string());
    assert!(!run(&b).rekor_ok);
}

#[test]
fn tampered_body_is_rejected() {
    let mut b = bundle(TAG);
    let e = &mut b["verificationMaterial"]["tlogEntries"][0];
    let s = e["canonicalizedBody"].as_str().unwrap().to_string();
    e["canonicalizedBody"] = Value::String(flip_b64(&s));
    assert!(!run(&b).rekor_ok);
}

#[test]
fn zero_or_two_log_entries_are_rejected() {
    let mut b = bundle(TAG);
    let e = b["verificationMaterial"]["tlogEntries"][0].clone();
    b["verificationMaterial"]["tlogEntries"] = Value::Array(vec![e.clone(), e]);
    assert!(!run(&b).rekor_ok);
    b["verificationMaterial"]["tlogEntries"] = Value::Array(vec![]);
    assert!(!run(&b).rekor_ok);
}

#[test]
fn unknown_log_key_is_rejected() {
    let mut b = bundle(TAG);
    b["verificationMaterial"]["tlogEntries"][0]["logId"]["keyId"] =
        Value::String("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=".into());
    assert!(!run(&b).rekor_ok);
}

#[test]
fn trust_root_without_fulcio_ca_fails_chain() {
    let mut r: Value = serde_json::from_str(TRUSTED_ROOT_JSON).unwrap();
    r["certificateAuthorities"] = Value::Array(vec![]);
    let v = verify_release(
        &bundle(TAG).to_string(),
        REPO,
        TAG,
        DIGEST,
        MEAS_158,
        Some(&r.to_string()),
    );
    assert_eq!(only_failed(&v), ["chain"], "{:?}", v.errors);
}

#[test]
fn trust_root_with_expired_ca_window_fails_chain() {
    let mut r: Value = serde_json::from_str(TRUSTED_ROOT_JSON).unwrap();
    for ca in r["certificateAuthorities"].as_array_mut().unwrap() {
        ca["validFor"]["end"] = Value::String("2023-01-01T00:00:00Z".into());
    }
    let v = verify_release(
        &bundle(TAG).to_string(),
        REPO,
        TAG,
        DIGEST,
        MEAS_158,
        Some(&r.to_string()),
    );
    assert_eq!(only_failed(&v), ["chain"]);
}

#[test]
fn trust_root_with_foreign_fulcio_ca_fails_chain() {
    // Eine fremde (Rekor-)Wurzel als Fulcio-CA: Kette kann nicht gelten.
    let mut r: Value = serde_json::from_str(TRUSTED_ROOT_JSON).unwrap();
    let foreign = r["certificateAuthorities"][0].clone();
    r["certificateAuthorities"] = Value::Array(vec![foreign]);
    let v = verify_release(
        &bundle(TAG).to_string(),
        REPO,
        TAG,
        DIGEST,
        MEAS_158,
        Some(&r.to_string()),
    );
    assert_eq!(only_failed(&v), ["chain"]);
}

#[test]
fn trust_root_without_rekor_key_fails_rekor() {
    let mut r: Value = serde_json::from_str(TRUSTED_ROOT_JSON).unwrap();
    r["tlogs"] = Value::Array(vec![]);
    let v = verify_release(
        &bundle(TAG).to_string(),
        REPO,
        TAG,
        DIGEST,
        MEAS_158,
        Some(&r.to_string()),
    );
    assert!(!v.rekor_ok && !v.all_ok());
}

#[test]
fn rekor_key_not_yet_valid_at_integrated_time_is_rejected() {
    let mut r: Value = serde_json::from_str(TRUSTED_ROOT_JSON).unwrap();
    r["tlogs"][0]["publicKey"]["validFor"]["start"] = Value::String("2030-01-01T00:00:00Z".into());
    let v = verify_release(
        &bundle(TAG).to_string(),
        REPO,
        TAG,
        DIGEST,
        MEAS_158,
        Some(&r.to_string()),
    );
    assert!(!v.rekor_ok);
}

#[test]
fn garbage_inputs_never_panic() {
    for b in ["", "{}", "[]", "null", "{\"dsseEnvelope\":1}", "\u{0}"] {
        let v = verify_release(b, REPO, TAG, DIGEST, MEAS_158, None);
        assert!(!v.all_ok() && !v.errors.is_empty(), "{b}");
    }
    let v = verify_release(
        &bundle(TAG).to_string(),
        REPO,
        TAG,
        DIGEST,
        MEAS_158,
        Some("kaputt"),
    );
    assert!(!v.all_ok() && !v.errors.is_empty());
    let v = verify_release(&bundle(TAG).to_string(), REPO, TAG, "", "", None);
    assert!(!v.all_ok());
}

#[test]
fn embedded_trust_root_is_the_documented_one() {
    // Eine Änderung muss bewusst erfolgen und `docs/notes/sigstore-trust-root.md` mitziehen.
    use sha2::{Digest, Sha256};
    assert_eq!(
        hex::encode(Sha256::digest(TRUSTED_ROOT_JSON.as_bytes())),
        "6494e21ea73fa7ee769f85f57d5a3e6a08725eae1e38c755fc3517c9e6bc0b66"
    );
}
