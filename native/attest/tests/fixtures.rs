//! Tests gegen die echten Probe-Daten (WP43) mit Negativfällen je Prüfstufe.
//! Jede Manipulation muss genau die erwartete Stufe rot färben, alle anderen bleiben grün.
use serde_json::{json, Value};
use std::{fs, time::Instant};
use wendelin_attest::api;
use wendelin_attest::collateral::{
    build_collateral, collateral_request, next_update, root_crl_url, CollateralParts,
};
use wendelin_attest::report::{verify_receipt, verify_report, Verdict};

/// Prüfzeitpunkt der Fixtures (Kollateral gültig bis 2026-11-12, Keyset bis 1794413028).
const NOW: u64 = 1_791_934_700;
const NOT_AFTER: u64 = 1_794_413_028;
const NONCE: &str = "abababababababababababababababababababababababababababababababab";

fn fx(n: &str) -> String {
    let d = std::env::var("FIXTURE_DIR")
        .unwrap_or("../../packages/wendelin_providers/test/fixtures/tee".into());
    fs::read_to_string(format!("{d}/{n}")).unwrap_or_else(|e| panic!("Fixture {n}: {e}"))
}

fn report() -> Value {
    serde_json::from_str(&fx("gateway_attestation.json")).unwrap()
}

fn check(report: &Value, now: u64) -> Verdict {
    verify_report(&report.to_string(), NONCE, &fx("collateral_pcs.json"), now)
}

fn evidence(r: &mut Value) -> &mut Value {
    &mut r["attestation"]["evidence"]
}

fn event_log(r: &Value) -> Vec<Value> {
    let t = r["attestation"]["evidence"]["event_log"]
        .as_str()
        .expect("event_log als String");
    serde_json::from_str(t).unwrap()
}

fn set_event_log(r: &mut Value, log: Vec<Value>) {
    evidence(r)["event_log"] = Value::String(serde_json::to_string(&log).unwrap());
}

/// Alle Stufen außer den genannten müssen grün sein (Mutationsschutz gegen "Ergebnis fest true/false").
fn only_red(v: &Verdict, red: &[&str]) {
    let stages = [
        ("keyset_digest", v.keyset_digest_ok),
        ("report_data", v.report_data_ok),
        ("quote_report_data", v.quote_report_data_ok),
        ("quote", v.quote_ok),
        ("rtmr3", v.rtmr3_replay_ok),
        ("compose", v.compose_hash_ok),
        ("not_expired", v.keyset_not_expired),
        ("tls_binding", v.tls_binding_listed),
    ];
    for (name, ok) in stages {
        assert_eq!(ok, !red.contains(&name), "Stufe {name}: {v:#?}");
    }
    assert_eq!(v.all_ok(), red.is_empty(), "{v:#?}");
}

#[test]
fn fixture_is_green_on_all_stages() {
    let t = Instant::now();
    let v = check(&report(), NOW);
    eprintln!("Prüfzeit Host: {:?}", t.elapsed());
    assert!(v.errors.is_empty(), "{:?}", v.errors);
    only_red(&v, &[]);
    assert_eq!(v.tcb_status, "UpToDate");
    assert_eq!(
        v.repo_commit.as_deref(),
        Some("24a31ff1b33cb45cd2ad0ddac02749eb4ea424e2")
    );
    assert_eq!(v.compose_hash.as_deref().map(str::len), Some(64));
}

#[test]
fn wrong_nonce_breaks_report_data_only() {
    let v = verify_report(
        &report().to_string(),
        &"cd".repeat(32),
        &fx("collateral_pcs.json"),
        NOW,
    );
    only_red(&v, &["report_data", "quote_report_data"]);
}

#[test]
fn flipped_quote_byte_fails_quote_stage() {
    let mut r = report();
    let q = r["attestation"]["evidence"]["quote"]
        .as_str()
        .unwrap()
        .to_string();
    let mut b = q.into_bytes();
    b[1200] = if b[1200] == b'0' { b'1' } else { b'0' };
    evidence(&mut r)["quote"] = Value::String(String::from_utf8(b).unwrap());
    let v = check(&r, NOW);
    assert!(!v.quote_ok && !v.all_ok(), "{v:#?}");
    assert!(
        v.errors.iter().any(|e| e.starts_with("Quote")),
        "{:?}",
        v.errors
    );
}

#[test]
fn tampered_keyset_breaks_digest_and_report_data() {
    let mut r = report();
    r["attestation"]["workload_keyset"]["not_after"] = json!(NOT_AFTER + 1);
    let v = check(&r, NOW);
    only_red(&v, &["keyset_digest", "report_data", "quote_report_data"]);
}

#[test]
fn expired_keyset_only_breaks_freshness() {
    let v = check(&report(), NOT_AFTER + 1);
    only_red(&v, &["not_expired"]);
}

#[test]
fn expired_collateral_fails_quote_stage() {
    // nach nextUpdate (2026-11-12T22:38:12Z)
    let v = check(&report(), 1_794_523_093);
    assert!(!v.quote_ok && !v.all_ok(), "{v:#?}");
}

#[test]
fn rtmr3_replay_detects_dropped_event() {
    let mut r = report();
    let mut log = event_log(&r);
    let i = log
        .iter()
        .rposition(|e| e["imr"] == 3 && e["event"] != "compose-hash")
        .expect("imr-3-Ereignis");
    log.remove(i);
    set_event_log(&mut r, log);
    only_red(&check(&r, NOW), &["rtmr3"]);
}

#[test]
fn rtmr3_replay_detects_reordered_events() {
    let mut r = report();
    let mut log = event_log(&r);
    let idx: Vec<usize> = (0..log.len()).filter(|&i| log[i]["imr"] == 3).collect();
    assert!(idx.len() >= 2);
    log.swap(idx[0], idx[1]);
    set_event_log(&mut r, log);
    only_red(&check(&r, NOW), &["rtmr3"]);
}

#[test]
fn event_with_wrong_digest_is_a_hard_error() {
    let mut r = report();
    let mut log = event_log(&r);
    let i = log.iter().position(|e| e["imr"] == 3).unwrap();
    log[i]["event_payload"] = json!("00");
    set_event_log(&mut r, log);
    let v = check(&r, NOW);
    assert!(
        v.errors.iter().any(|e| e.contains("Digest")),
        "{:?}",
        v.errors
    );
    assert!(!v.all_ok());
}

#[test]
fn compose_hash_detects_changed_app_compose() {
    let mut r = report();
    let ac = r["attestation"]["evidence"]["app_compose"]
        .as_str()
        .unwrap()
        .to_string();
    evidence(&mut r)["app_compose"] = Value::String(format!("{ac} "));
    only_red(&check(&r, NOW), &["compose"]);
}

#[test]
fn compose_hash_requires_the_event() {
    let mut r = report();
    let log: Vec<Value> = event_log(&r)
        .into_iter()
        .filter(|e| e["event"] != "compose-hash")
        .collect();
    set_event_log(&mut r, log);
    let v = check(&r, NOW);
    assert!(!v.compose_hash_ok && !v.all_ok(), "{v:#?}");
}

#[test]
fn tls_binding_must_be_listed_in_keyset() {
    let mut r = report();
    evidence(&mut r)["downstream_tls_binding"]["spki_sha256"] = json!("00".repeat(32));
    only_red(&check(&r, NOW), &["tls_binding"]);
}

#[test]
fn tls_binding_missing_is_not_listed() {
    let mut r = report();
    evidence(&mut r)
        .as_object_mut()
        .unwrap()
        .remove("downstream_tls_binding");
    only_red(&check(&r, NOW), &["tls_binding"]);
}

#[test]
fn nonce_must_be_64_lowercase_hex() {
    for bad in [
        "",
        "ab",
        &"AB".repeat(32),
        &format!("{}\"", "a".repeat(63)),
        &"g".repeat(64),
    ] {
        let v = verify_report(&report().to_string(), bad, &fx("collateral_pcs.json"), NOW);
        assert!(
            v.errors.iter().any(|e| e.contains("Nonce")),
            "{bad}: {:?}",
            v.errors
        );
        assert!(!v.all_ok());
    }
}

#[test]
fn float_in_keyset_is_rejected_not_hashed_differently() {
    let mut r = report();
    r["attestation"]["workload_keyset"]["not_after"] = json!(1794413028.5);
    let v = check(&r, NOW);
    assert!(
        v.errors.iter().any(|e| e.contains("Nicht-ganze Zahl")),
        "{:?}",
        v.errors
    );
    assert!(!v.keyset_digest_ok && !v.all_ok());
}

#[test]
fn observed_tls_spki_must_be_listed_for_the_host() {
    let rep = fx("gateway_attestation.json");
    let api_spki = "c68585e7dc00a55d3082a9c860cb916e1788c5daec51505e413d27ab94f7d4c7";
    assert!(api::tls_spki_listed(
        rep.clone(),
        api_spki.into(),
        "api.redpill.ai".into()
    ));
    assert!(api::tls_spki_listed(
        rep.clone(),
        api_spki.to_uppercase(),
        "API.redpill.ai".into()
    ));
    // Eintrag gehört zu einer anderen Domain
    assert!(!api::tls_spki_listed(
        rep.clone(),
        api_spki.into(),
        "tee.redpill.ai".into()
    ));
    // beobachteter Schlüssel steht nicht im Keyset (heutiger Befund der Probe: Let's-Encrypt-SPKI)
    let seen = "6ebb83be".repeat(8);
    assert!(!api::tls_spki_listed(
        rep.clone(),
        seen,
        "api.redpill.ai".into()
    ));
    assert!(!api::tls_spki_listed(
        "{".into(),
        api_spki.into(),
        "api.redpill.ai".into()
    ));
    // Eintrag ohne domain gilt für jeden Host
    let mut r: Value = serde_json::from_str(&rep).unwrap();
    r["attestation"]["workload_keyset"]["tls_public_keys"] =
        json!([{"spki_sha256": "ab".repeat(32)}]);
    assert!(api::tls_spki_listed(
        r.to_string(),
        "ab".repeat(32),
        "irgendwo.example".into()
    ));
}

#[test]
fn garbage_input_is_an_error_not_a_panic() {
    let v = verify_report("{", NONCE, "{}", NOW);
    assert!(!v.errors.is_empty() && !v.all_ok());
    let v = verify_report(&report().to_string(), NONCE, "{}", NOW);
    assert!(!v.errors.is_empty() && !v.quote_ok);
}

#[test]
fn receipt_signature_ok_and_tamper_detected() {
    let rep = fx("gateway_attestation.json");
    let rc = fx("receipt.json");
    let ok = verify_receipt(&rc, &rep);
    assert!(
        ok.signature_ok && ok.keyset_matches && ok.error.is_none(),
        "{ok:?}"
    );
    let bad = rc.replacen(
        "\"model\":\"z-ai/glm-5.3-flash\"",
        "\"model\":\"z-ai/glm-5.3-flasH\"",
        1,
    );
    assert_ne!(bad, rc);
    let v = verify_receipt(&bad, &rep);
    assert!(!v.signature_ok && v.keyset_matches, "{v:?}");
}

#[test]
fn receipt_with_foreign_keyset_digest_or_key_is_rejected() {
    let rep = fx("gateway_attestation.json");
    let mut rc: Value = serde_json::from_str(&fx("receipt.json")).unwrap();
    rc["workload_keyset_digest"] = json!("sha256:00");
    assert!(!verify_receipt(&rc.to_string(), &rep).keyset_matches);
    let mut rc: Value = serde_json::from_str(&fx("receipt.json")).unwrap();
    rc["key_id"] = json!("unbekannt");
    assert!(verify_receipt(&rc.to_string(), &rep).error.is_some());
    let mut rc: Value = serde_json::from_str(&fx("receipt.json")).unwrap();
    rc["signature"] = json!("abcd");
    assert!(!verify_receipt(&rc.to_string(), &rep).signature_ok);
}

#[test]
fn ed25519_rfc8032_vector_and_negatives() {
    // RFC 8032 Abschnitt 7.1, Test 2 (Nachricht 0x72).
    let pk =
        hex::decode("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c").unwrap();
    let sig = hex::decode("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00").unwrap();
    assert!(api::verify_ed25519(pk.clone(), vec![0x72], sig.clone()));
    assert!(!api::verify_ed25519(pk.clone(), vec![0x73], sig.clone()));
    let mut bad = sig.clone();
    bad[0] ^= 1;
    assert!(!api::verify_ed25519(pk.clone(), vec![0x72], bad));
    assert!(!api::verify_ed25519(
        pk.clone(),
        vec![0x72],
        sig[..63].to_vec()
    ));
    assert!(!api::verify_ed25519(pk[..31].to_vec(), vec![0x72], sig));
}

#[test]
fn sha_known_answers() {
    assert_eq!(
        hex::encode(api::sha256(b"abc".to_vec())),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
    assert_eq!(
        hex::encode(api::sha384(b"abc".to_vec())),
        "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"
    );
}

fn intel_root_der() -> Vec<u8> {
    let c: Value = serde_json::from_str(&fx("collateral_pcs.json")).unwrap();
    let certs = pem::parse_many(c["tcb_info_issuer_chain"].as_str().unwrap()).unwrap();
    certs.last().unwrap().contents().to_vec()
}

#[test]
fn spki_hash_of_intel_root_matches_openssl() {
    // openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | sha256
    let h = api::spki_sha256(intel_root_der()).unwrap();
    assert_eq!(
        hex::encode(h),
        "a0af031289f5d5d4132f9186068a7fc13628633ba235777472e29b6b6c67a49e"
    );
    assert!(api::spki_sha256(vec![1, 2, 3]).is_err());
}

fn quote_bytes() -> Vec<u8> {
    hex::decode(
        report()["attestation"]["evidence"]["quote"]
            .as_str()
            .unwrap(),
    )
    .unwrap()
}

#[test]
fn collateral_request_reads_fmspc_and_ca_from_quote() {
    let r = collateral_request(&quote_bytes()).unwrap();
    assert_eq!(r.tee, "tdx");
    assert_eq!(r.ca.len().min(1), 1);
    assert!(r.ca == "processor" || r.ca == "platform");
    assert_eq!(r.fmspc.len(), 12);
    assert!(collateral_request(&[0u8; 10]).is_err());
}

#[test]
fn collateral_roundtrip_through_parts_verifies() {
    let c: Value = serde_json::from_str(&fx("collateral_pcs.json")).unwrap();
    let s = |k: &str| c[k].as_str().unwrap().to_string();
    let tcb: Value = serde_json::from_str(&s("tcb_info")).unwrap();
    let qe: Value = serde_json::from_str(&s("qe_identity")).unwrap();
    let parts = CollateralParts {
        pck_crl: hex::decode(s("pck_crl")).unwrap(),
        pck_crl_issuer_chain: s("pck_crl_issuer_chain"),
        root_ca_crl: hex::decode(s("root_ca_crl")).unwrap(),
        tcb_info_body: json!({"tcbInfo": tcb, "signature": s("tcb_info_signature")}).to_string(),
        tcb_info_issuer_chain: s("tcb_info_issuer_chain"),
        qe_identity_body: json!({"enclaveIdentity": qe, "signature": s("qe_identity_signature")})
            .to_string(),
        qe_identity_issuer_chain: s("qe_identity_issuer_chain"),
    };
    let built = build_collateral(&parts).unwrap();
    let info = api::verify_quote(quote_bytes(), built.clone(), NOW);
    assert!(info.ok, "{:?}", info.error);
    assert_eq!(info.tcb_status, "UpToDate");
    assert_eq!(next_update(&built).unwrap(), "2026-11-12T22:38:12Z");
    assert_eq!(
        next_update(&fx("collateral_pcs.json")).unwrap(),
        "2026-11-12T22:38:12Z"
    );
    let mut broken = parts.clone();
    broken.tcb_info_body = broken.tcb_info_body.replace("\"signature\"", "\"sig\"");
    assert!(build_collateral(&broken).is_err());
    // geänderte TCB-Info bricht die Signatur: das Kollateral ist unbrauchbar
    let mut forged = parts;
    forged.tcb_info_body = forged.tcb_info_body.replacen("UpToDate", "OutOfDate", 1);
    let f = build_collateral(&forged).unwrap();
    assert!(!api::verify_quote(quote_bytes(), f, NOW).ok);
}

#[test]
fn root_crl_url_comes_from_root_certificate() {
    let c: Value = serde_json::from_str(&fx("collateral_pcs.json")).unwrap();
    let u = root_crl_url(c["qe_identity_issuer_chain"].as_str().unwrap()).unwrap();
    assert_eq!(
        u,
        "https://certificates.trustedservices.intel.com/IntelSGXRootCA.der"
    );
    assert!(root_crl_url("kein PEM").is_err());
}

#[test]
fn verify_quote_rejects_garbage_without_panicking() {
    let i = api::verify_quote(vec![1, 2, 3], fx("collateral_pcs.json"), NOW);
    assert!(!i.ok && i.error.is_some());
    let i = api::verify_quote(quote_bytes(), "{".into(), NOW);
    assert!(!i.ok && i.error.is_some());
}

// Zweiter Fixture-Satz (WP47, Probe 2026-10-14 03:18 UTC): Anfrage mit `provider.aci_verified: true`,
// dazu Bericht (neues Keyset nach Neustart des Gateways), Quittung, gesendete und empfangene Bytes.
const NOW_VERIFIED: u64 = 1_791_947_900;

fn av(n: &str) -> String {
    fx(&format!("aci_verified/{n}"))
}

#[test]
fn aci_verified_set_is_green_end_to_end() {
    let v = verify_report(
        &av("attestation.json"),
        NONCE,
        &fx("collateral_pcs.json"),
        NOW_VERIFIED,
    );
    assert!(v.errors.is_empty(), "{:?}", v.errors);
    only_red(&v, &[]);
    let r = verify_receipt(&av("receipt.json"), &av("attestation.json"));
    assert!(r.signature_ok && r.keyset_matches, "{r:?}");
    // Die Quittung gehört zum Keyset dieses Berichts, nicht zu dem aus dem ersten Fixture-Satz.
    let other = verify_receipt(&av("receipt.json"), &fx("gateway_attestation.json"));
    assert!(!other.keyset_matches);
}

#[test]
fn aci_verified_receipt_binds_sent_and_received_bytes() {
    let rc: Value = serde_json::from_str(&av("receipt.json")).unwrap();
    let ev = rc["event_log"].as_array().unwrap();
    let hash = |bytes: String| format!("sha256:{}", hex::encode(api::sha256(bytes.into_bytes())));
    let first = |t: &str| {
        ev.iter()
            .find(|e| e["type"] == t)
            .unwrap_or_else(|| panic!("{t} fehlt"))
    };
    // `request.received` trägt den Hash der gesendeten Bytes, `response.returned` den der empfangenen.
    assert_eq!(
        first("request.received")["body_hash"],
        hash(av("request_body.json"))
    );
    assert_eq!(
        first("response.returned")["body_hash"],
        hash(av("response_body.json"))
    );
    let up = first("upstream.verified");
    assert_eq!(
        (up["required"].clone(), up["result"].clone()),
        (json!(true), json!("verified"))
    );
    assert!(av("request_body.json").contains("\"aci_verified\":true"));
    // Manipulierte Antwort passt nicht mehr zum signierten Hash.
    assert_ne!(
        first("response.returned")["body_hash"],
        hash(av("response_body.json").replace("ok", "OK"))
    );
}
