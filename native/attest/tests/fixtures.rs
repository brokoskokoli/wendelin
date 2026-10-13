use std::{fs, time::Instant};
use wendelin_attest::{verify_receipt, verify_report};

const NOW: u64 = 1_791_934_700;
const NONCE: &str = "abababababababababababababababababababababababababababababababab";

fn fx(n: &str) -> String {
    let d = std::env::var("FIXTURE_DIR").unwrap_or("../../packages/wendelin_providers/test/fixtures/tee".into());
    fs::read_to_string(format!("{d}/{n}")).unwrap()
}

#[test]
fn fixture_verifies_offline_and_reports_tcb() {
    let t = Instant::now();
    let v = verify_report(&fx("gateway_attestation.json"), NONCE, &fx("collateral_pcs.json"), NOW);
    eprintln!("Prüfzeit host: {:?}\n{v:#?}", t.elapsed());
    assert!(v.errors.is_empty(), "{:?}", v.errors);
    assert!(v.keyset_digest_ok && v.report_data_ok && v.quote_ok);
    assert!(v.quote_report_data_ok && v.rtmr3_replay_ok && v.compose_hash_ok);
    assert!(v.keyset_not_expired && v.tls_binding_listed);
    assert!(!v.tcb_status.is_empty());
}

#[test]
fn wrong_nonce_is_detected() {
    let v = verify_report(&fx("gateway_attestation.json"), &"cd".repeat(32), &fx("collateral_pcs.json"), NOW);
    assert!(!v.report_data_ok && !v.quote_report_data_ok);
}

#[test]
fn flipped_quote_byte_fails() {
    let rep = fx("gateway_attestation.json");
    let q = rep.split("\"quote\":\"").nth(1).unwrap().split('"').next().unwrap();
    // Byte im Signaturbereich ändern (nach Header + TD-Report)
    let mut b = q.as_bytes().to_vec();
    let i = 1200;
    b[i] = if b[i] == b'0' { b'1' } else { b'0' };
    let bad = rep.replacen(q, std::str::from_utf8(&b).unwrap(), 1);
    let v = verify_report(&bad, NONCE, &fx("collateral_pcs.json"), NOW);
    assert!(!v.quote_ok, "{v:?}");
}

#[test]
fn tampered_keyset_changes_digest() {
    let bad = fx("gateway_attestation.json").replacen("\"not_after\":1794413028", "\"not_after\":1794413029", 1);
    let v = verify_report(&bad, NONCE, &fx("collateral_pcs.json"), NOW);
    assert!(!v.keyset_digest_ok && !v.report_data_ok);
}

#[test]
fn expired_keyset_is_flagged() {
    let v = verify_report(&fx("gateway_attestation.json"), NONCE, &fx("collateral_pcs.json"), NOW);
    assert!(v.keyset_not_expired);
    let v = verify_report(&fx("gateway_attestation.json"), NONCE, &fx("collateral_pcs.json"), 1_794_413_100);
    assert!(!v.keyset_not_expired || !v.quote_ok);
}

#[test]
fn receipt_signature_ok_and_tamper_detected() {
    let rep = fx("gateway_attestation.json");
    let rc = fx("receipt.json");
    assert_eq!(verify_receipt(&rc, &rep), Ok(true));
    let bad = rc.replacen("\"model\":\"z-ai/glm-5.3-flash\"", "\"model\":\"z-ai/glm-5.3-flasH\"", 1);
    assert_ne!(bad, rc);
    assert_eq!(verify_receipt(&bad, &rep), Ok(false));
}
