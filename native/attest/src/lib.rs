//! Spike WP43: Prüfung von ACI-Attestierung (TDX) und Quittungen, offline.
//! Reine Funktionen, keine Netzaufrufe (Kollateral kommt als JSON von außen).
use dcap_qvl::{verify::QuoteVerifier, QuoteCollateralV3};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde_json::Value;
use sha2::{Digest, Sha256, Sha384};

/// JCS für ACI: kompaktes JSON, Schlüssel lexikografisch, nur ganze Zahlen.
pub fn canon(v: &Value) -> Vec<u8> {
    let mut out = Vec::new();
    write(v, &mut out);
    out
}
fn write(v: &Value, o: &mut Vec<u8>) {
    match v {
        Value::Object(m) => {
            let mut keys: Vec<&String> = m.keys().collect();
            keys.sort();
            o.push(b'{');
            for (i, k) in keys.iter().enumerate() {
                if i > 0 {
                    o.push(b',');
                }
                o.extend(serde_json::to_vec(k).unwrap());
                o.push(b':');
                write(&m[*k], o);
            }
            o.push(b'}');
        }
        Value::Array(a) => {
            o.push(b'[');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    o.push(b',');
                }
                write(x, o);
            }
            o.push(b']');
        }
        other => o.extend(serde_json::to_vec(other).unwrap()),
    }
}

#[derive(Debug, Default, serde::Serialize)]
pub struct Verdict {
    pub keyset_digest_ok: bool,
    pub report_data_ok: bool,
    pub quote_report_data_ok: bool,
    pub quote_ok: bool,
    pub tcb_status: String,
    pub advisory_ids: Vec<String>,
    pub rtmr3_replay_ok: bool,
    pub compose_hash_ok: bool,
    pub keyset_not_expired: bool,
    pub tls_binding_listed: bool,
    pub repo_commit: Option<String>,
    pub errors: Vec<String>,
}

fn s<'a>(v: &'a Value, p: &[&str]) -> Option<&'a str> {
    let mut c = v;
    for k in p {
        c = c.get(*k)?;
    }
    c.as_str()
}

/// Prüft einen `/v1/aci/attestation`-Bericht gegen `nonce_hex` und das Kollateral.
pub fn verify_report(report_json: &str, nonce_hex: &str, collateral_json: &str, now: u64) -> Verdict {
    let mut r = Verdict::default();
    if let Err(e) = verify_inner(report_json, nonce_hex, collateral_json, now, &mut r) {
        r.errors.push(e);
    }
    r
}

fn verify_inner(rep: &str, nonce: &str, coll: &str, now: u64, r: &mut Verdict) -> Result<(), String> {
    let d: Value = serde_json::from_str(rep).map_err(|e| e.to_string())?;
    let a = d.get("attestation").ok_or("attestation fehlt")?;
    let ks = a.get("workload_keyset").ok_or("keyset fehlt")?;
    let digest = format!("sha256:{}", hex::encode(Sha256::digest(canon(ks))));
    r.keyset_digest_ok = Some(digest.as_str()) == s(&d, &["workload_keyset_digest"]);
    let stmt = format!(
        r#"{{"keyset_digest":"{digest}","nonce":"{nonce}","purpose":"aci.report_data.v1"}}"#
    );
    let rd = hex::encode(Sha256::digest(stmt.as_bytes()));
    r.report_data_ok = Some(rd.as_str()) == s(a, &["report_data"]);
    r.repo_commit = s(a, &["source_provenance", "repo_commit"]).map(String::from);
    r.keyset_not_expired = ks.get("not_after").and_then(Value::as_u64).is_some_and(|t| now < t);
    let ev = a.get("evidence").ok_or("evidence fehlt")?;
    if let Some(spki) = s(ev, &["downstream_tls_binding", "spki_sha256"]) {
        r.tls_binding_listed = ks["tls_public_keys"]
            .as_array()
            .is_some_and(|l| l.iter().any(|k| k["spki_sha256"] == spki));
    }
    let quote = hex::decode(s(ev, &["quote"]).ok_or("quote fehlt")?).map_err(|e| e.to_string())?;
    let collateral: QuoteCollateralV3 = serde_json::from_str(coll).map_err(|e| format!("collateral: {e}"))?;
    let vr = QuoteVerifier::new_prod()
        .verify(&quote, &collateral, now)
        .map_err(|e| format!("quote: {e}"))?;
    r.quote_ok = true;
    r.tcb_status = vr.status.clone();
    r.advisory_ids = vr.advisory_ids.clone();
    let td = vr.report.as_td10().ok_or("kein TD10-Report")?;
    // report_data im Quote: 32 Byte Digest + 32 Null
    let mut want = hex::decode(&rd).unwrap();
    want.extend([0u8; 32]);
    r.quote_report_data_ok = td.report_data.as_slice() == want.as_slice();
    // RTMR3 aus dem Ereignisprotokoll nachrechnen
    let log: Value = match ev.get("event_log") {
        Some(Value::String(t)) => serde_json::from_str(t).map_err(|e| e.to_string())?,
        Some(v) => v.clone(),
        None => return Err("event_log fehlt".into()),
    };
    let mut m = [0u8; 48];
    let mut compose_ev = None;
    for e in log.as_array().ok_or("event_log kein Array")? {
        if e["imr"] != 3 {
            continue;
        }
        let name = e["event"].as_str().unwrap_or("");
        let payload = hex::decode(e["event_payload"].as_str().unwrap_or("")).map_err(|x| x.to_string())?;
        let ty = e["event_type"].as_u64().unwrap_or(0) as u32;
        let mut h = Sha384::new();
        h.update(ty.to_le_bytes());
        h.update(b":");
        h.update(name.as_bytes());
        h.update(b":");
        h.update(&payload);
        let dg = h.finalize();
        if hex::encode(dg) != e["digest"].as_str().unwrap_or("") {
            return Err(format!("Ereignis {name}: Digest passt nicht zur Nutzlast"));
        }
        let mut f = Sha384::new();
        f.update(m);
        f.update(dg);
        m.copy_from_slice(&f.finalize());
        if name == "compose-hash" {
            compose_ev = Some(hex::encode(&payload));
        }
    }
    r.rtmr3_replay_ok = m == td.rt_mr3;
    let ac = s(ev, &["app_compose"]).ok_or("app_compose fehlt")?;
    r.compose_hash_ok = compose_ev == Some(hex::encode(Sha256::digest(ac.as_bytes())));
    Ok(())
}

/// Prüft die Ed25519-Signatur einer Quittung gegen das Keyset des Berichts.
pub fn verify_receipt(receipt_json: &str, report_json: &str) -> Result<bool, String> {
    let mut rc: Value = serde_json::from_str(receipt_json).map_err(|e| e.to_string())?;
    let rep: Value = serde_json::from_str(report_json).map_err(|e| e.to_string())?;
    let ks = &rep["attestation"]["workload_keyset"];
    if rc["workload_keyset_digest"] != rep["workload_keyset_digest"] {
        return Ok(false);
    }
    let kid = rc["key_id"].as_str().ok_or("key_id")?.to_string();
    let pk = ks["receipt_signing_keys"]
        .as_array()
        .and_then(|l| l.iter().find(|k| k["key_id"] == kid.as_str()))
        .and_then(|k| k["public_key"].as_str())
        .ok_or("Schlüssel nicht im Keyset")?;
    let sig = rc.as_object_mut().ok_or("kein Objekt")?.remove("signature");
    let sig = hex::decode(sig.and_then(|v| v.as_str().map(String::from)).ok_or("signature")?).map_err(|e| e.to_string())?;
    let vk = VerifyingKey::from_bytes(&hex::decode(pk).map_err(|e| e.to_string())?.try_into().map_err(|_| "pk-Länge")?)
        .map_err(|e| e.to_string())?;
    let sig = Signature::from_slice(&sig).map_err(|e| e.to_string())?;
    Ok(vk.verify(&canon(&rc), &sig).is_ok())
}

/// C-Einstieg für die Messung (Weg A/B-Spike); WP46 ersetzt ihn durch frb.
/// Alle Zeiger zeigen auf NUL-terminierte UTF-8-Strings, Rückgabe per `wendelin_free`.
///
/// # Safety
/// Die Zeiger müssen gültig und NUL-terminiert sein.
#[no_mangle]
pub unsafe extern "C" fn wendelin_verify_report(
    report: *const std::ffi::c_char,
    nonce: *const std::ffi::c_char,
    collateral: *const std::ffi::c_char,
    now: u64,
) -> *mut std::ffi::c_char {
    let c = |p| std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned();
    let v = verify_report(&c(report), &c(nonce), &c(collateral), now);
    std::ffi::CString::new(serde_json::to_string(&v).unwrap_or_default()).unwrap().into_raw()
}

/// Gibt eine von `wendelin_verify_report` gelieferte Zeichenkette frei.
///
/// # Safety
/// `p` muss von `wendelin_verify_report` stammen.
#[no_mangle]
pub unsafe extern "C" fn wendelin_free(p: *mut std::ffi::c_char) {
    drop(std::ffi::CString::from_raw(p));
}
