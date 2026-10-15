//! Echte NEAR-AI-Quotes (aufgezeichnet 2026-10-15, `include_tls_fingerprint=true`) gegen das echte
//! Intel-Kollateral derselben Zeit: Signaturkette, TCB-Status und `report_data`-Bindung (WP75).
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::fs;
use wendelin_attest::quote::verify_quote;

/// Zeitpunkt des Abrufs; das Kollateral gilt bis 2026-11-14.
const NOW: u64 = 1_792_100_512;
const NONCE: &str = "f3b426ddde16000e004951b8f083930703e5570e487eca22bf83cb84e7f338e0";

fn fx(n: &str) -> String {
    let d = std::env::var("NEAR_FIXTURE_DIR")
        .unwrap_or("../../packages/wendelin_providers/test/fixtures/near".into());
    fs::read_to_string(format!("{d}/{n}")).unwrap_or_else(|e| panic!("Fixture {n}: {e}"))
}

fn report() -> Value {
    serde_json::from_str(&fx("report.json")).unwrap()
}

fn s(v: &Value, k: &str) -> String {
    v[k].as_str().unwrap().to_string()
}

fn expected_report_data(entry: &Value, key_field: &str) -> Vec<u8> {
    let mut bound = hex::decode(s(entry, key_field)).unwrap();
    bound.extend(hex::decode(s(entry, "tls_cert_fingerprint")).unwrap());
    let mut rd = Sha256::digest(&bound).to_vec();
    rd.extend(hex::decode(NONCE).unwrap());
    rd
}

#[test]
fn model_quote_is_genuine_current_and_binds_key_tls_and_nonce() {
    let r = report();
    let model = &r["model_attestations"][0];
    let quote = hex::decode(s(model, "intel_quote")).unwrap();
    let info = verify_quote(&quote, &fx("collateral_model.json"), NOW);
    assert!(info.ok, "{:?}", info.error);
    assert_eq!(info.tcb_status, "UpToDate");
    assert_eq!(
        info.report_data,
        expected_report_data(model, "signing_public_key")
    );
    // Debug-Bit (Bit 0 der TD_ATTRIBUTES) ist nicht gesetzt.
    assert_eq!(quote[48 + 120] & 1, 0);
}

#[test]
fn gateway_quote_is_genuine_but_its_platform_is_outdated() {
    let r = report();
    let gw = &r["gateway_attestation"];
    let quote = hex::decode(s(gw, "intel_quote")).unwrap();
    let info = verify_quote(&quote, &fx("collateral_gateway.json"), NOW);
    assert!(info.ok, "{:?}", info.error);
    assert!(
        info.tcb_status.starts_with("OutOfDate"),
        "{}",
        info.tcb_status
    );
    assert_eq!(
        info.report_data,
        expected_report_data(gw, "signing_address")
    );
}

#[test]
fn manipulated_quote_or_expired_collateral_is_rejected() {
    let r = report();
    let model = &r["model_attestations"][0];
    let mut quote = hex::decode(s(model, "intel_quote")).unwrap();
    quote[48 + 520 + 3] ^= 1; // report_data im signierten Teil
    assert!(!verify_quote(&quote, &fx("collateral_model.json"), NOW).ok);
    let genuine = hex::decode(s(model, "intel_quote")).unwrap();
    assert!(!verify_quote(&genuine, &fx("collateral_model.json"), NOW + 90 * 86_400).ok);
}
