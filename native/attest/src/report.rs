//! Prüfung eines ACI-Berichts (`/v1/aci/attestation`) und einer Quittung, offline.
//! Reine Funktionen: Kollateral und Zeit kommen von außen.
//!
//! Quellenbelege (Dstack-TEE/private-ai-gateway @ 24a31ff, Datei:Zeile):
//! - Keyset-Digest `"sha256:" || hex(sha256(JCS(keyset)))`: `crates/aci-protocol/src/identity.rs:27-29`
//! - Statement und `report_data`: `identity.rs:44-72` (Statement), `:76-79` (`sha256(statement)`),
//!   `:82-87` (32 Byte Digest + 32 Null-Byte im Slot); Nonce 64 Kleinbuchstaben-Hex (`identity.rs:32-39`)
//! - Quittungssignatur über JCS ohne `signature`: `crates/aci-protocol/src/receipt.rs:7-15`
//! - RTMR3-Nachrechnung: `crates/aci-verify/src/dstack.rs:145-158` (Faltung), `:160-173` (Ereignis-Digest);
//!   Compose-Hash gleich sha256(`app_compose`): `dstack.rs:98-143`
//! - Prüfreihenfolge, Ablauf (`now < not_after`) und TLS-Kanalbindung: `spec/aci.md` §9.1 (Zeilen 778-800, Nr. 1 Hardware, 3 Ablauf, 6 Kanal)
use ed25519_dalek::{Signature, VerifyingKey};
use serde_json::Value;
use sha2::{Digest, Sha256, Sha384};

use crate::jcs::canon;
use crate::quote::verify_quote;

/// Ergebnis je Prüfstufe. Ein Wert `false` ist nie "unbekannt": Jede Stufe wird immer ausgewertet,
/// soweit die Eingabe es zulässt. Harte Eingabefehler stehen in `errors`.
#[derive(Debug, Default, Clone)]
pub struct Verdict {
    /// `workload_keyset_digest` stimmt mit sha256(JCS(workload_keyset)) überein.
    pub keyset_digest_ok: bool,
    /// `report_data` im Bericht ist sha256 des Statements aus Keyset-Digest und Nonce.
    pub report_data_ok: bool,
    /// Die ersten 32 Byte `report_data` im Quote sind dieser Digest (Rest Null).
    pub quote_report_data_ok: bool,
    /// Quote-Signaturkette und Kollateral gültig.
    pub quote_ok: bool,
    pub tcb_status: String,
    pub advisory_ids: Vec<String>,
    /// RTMR3 aus dem Ereignisprotokoll nachgerechnet gleich RTMR3 im Quote.
    pub rtmr3_replay_ok: bool,
    /// sha256(`app_compose`) gleich Nutzlast des `compose-hash`-Ereignisses.
    pub compose_hash_ok: bool,
    /// `now < workload_keyset.not_after`.
    pub keyset_not_expired: bool,
    /// TLS-SPKI der Evidenz steht in `tls_public_keys` des Keysets.
    pub tls_binding_listed: bool,
    /// SPKI-Hash der Evidenz (Hex), für den Vergleich mit dem echten Zertifikat.
    pub tls_binding_spki: Option<String>,
    pub compose_hash: Option<String>,
    pub repo_commit: Option<String>,
    pub errors: Vec<String>,
}

impl Verdict {
    /// Alle Stufen grün und keine Fehler (TCB-Status bewertet die Richtlinie in Dart).
    pub fn all_ok(&self) -> bool {
        self.errors.is_empty()
            && self.keyset_digest_ok
            && self.report_data_ok
            && self.quote_report_data_ok
            && self.quote_ok
            && self.rtmr3_replay_ok
            && self.compose_hash_ok
            && self.keyset_not_expired
            && self.tls_binding_listed
    }
}

fn s<'a>(v: &'a Value, p: &[&str]) -> Option<&'a str> {
    let mut c = v;
    for k in p {
        c = c.get(*k)?;
    }
    c.as_str()
}

/// Nonce wie im Gateway: genau 64 Zeichen aus `0-9a-f`.
fn is_valid_nonce(n: &str) -> bool {
    n.len() == 64
        && n.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// Prüft einen Bericht gegen `nonce_hex` (die gesendete Nonce) und das Kollateral zum Zeitpunkt `now`.
pub fn verify_report(
    report_json: &str,
    nonce_hex: &str,
    collateral_json: &str,
    now: u64,
) -> Verdict {
    let mut r = Verdict::default();
    if let Err(e) = verify_inner(report_json, nonce_hex, collateral_json, now, &mut r) {
        r.errors.push(e);
    }
    r
}

fn verify_inner(
    rep: &str,
    nonce: &str,
    coll: &str,
    now: u64,
    r: &mut Verdict,
) -> Result<(), String> {
    let d: Value = serde_json::from_str(rep).map_err(|e| e.to_string())?;
    let a = d.get("attestation").ok_or("attestation fehlt")?;
    let ks = a.get("workload_keyset").ok_or("keyset fehlt")?;
    if !is_valid_nonce(nonce) {
        return Err("Nonce muss aus 64 Kleinbuchstaben-Hexzeichen bestehen".into());
    }
    let digest = format!("sha256:{}", hex::encode(Sha256::digest(canon(ks)?)));
    r.keyset_digest_ok = Some(digest.as_str()) == s(&d, &["workload_keyset_digest"]);
    // Statement exakt wie in spec/aci.md §3.2 (Schlüssel alphabetisch).
    let stmt = format!(
        r#"{{"keyset_digest":"{digest}","nonce":"{nonce}","purpose":"aci.report_data.v1"}}"#
    );
    let rd = Sha256::digest(stmt.as_bytes());
    r.report_data_ok = Some(hex::encode(rd).as_str()) == s(a, &["report_data"]);
    r.repo_commit = s(a, &["source_provenance", "repo_commit"]).map(String::from);
    r.keyset_not_expired = ks
        .get("not_after")
        .and_then(Value::as_u64)
        .is_some_and(|t| now < t);
    let ev = a.get("evidence").ok_or("evidence fehlt")?;
    r.tls_binding_spki = s(ev, &["downstream_tls_binding", "spki_sha256"]).map(String::from);
    if let Some(spki) = &r.tls_binding_spki {
        r.tls_binding_listed = ks["tls_public_keys"].as_array().is_some_and(|l| {
            l.iter()
                .any(|k| k["spki_sha256"].as_str() == Some(spki.as_str()))
        });
    }
    let quote = hex::decode(s(ev, &["quote"]).ok_or("quote fehlt")?).map_err(|e| e.to_string())?;
    let q = verify_quote(&quote, coll, now);
    r.tcb_status = q.tcb_status.clone();
    r.advisory_ids = q.advisory_ids.clone();
    if let Some(e) = &q.error {
        return Err(e.clone());
    }
    r.quote_ok = q.ok;
    let mut want = rd.to_vec();
    want.extend([0u8; 32]);
    r.quote_report_data_ok = q.report_data == want;
    let (replayed, compose_ev) = replay_rtmr3(ev)?;
    r.rtmr3_replay_ok = replayed.as_slice() == q.rt_mr3.as_slice();
    let ac = s(ev, &["app_compose"]).ok_or("app_compose fehlt")?;
    r.compose_hash_ok =
        compose_ev.is_some() && compose_ev == Some(hex::encode(Sha256::digest(ac.as_bytes())));
    r.compose_hash = compose_ev;
    Ok(())
}

/// RTMR3 aus dem Ereignisprotokoll: je Ereignis `sha384(typ_le32 ":" name ":" nutzlast)`,
/// dann `m = sha384(m || digest)` ab 48 Null-Byte. Liefert RTMR3 und die Nutzlast von `compose-hash` (Hex).
fn replay_rtmr3(ev: &Value) -> Result<([u8; 48], Option<String>), String> {
    let log: Value = match ev.get("event_log") {
        Some(Value::String(t)) => serde_json::from_str(t).map_err(|e| e.to_string())?,
        Some(v) => v.clone(),
        None => return Err("event_log fehlt".into()),
    };
    let mut m = [0u8; 48];
    let mut compose = None;
    for e in log.as_array().ok_or("event_log kein Array")? {
        if e["imr"] != 3 {
            continue;
        }
        let name = e["event"].as_str().unwrap_or("");
        let payload =
            hex::decode(e["event_payload"].as_str().unwrap_or("")).map_err(|x| x.to_string())?;
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
            compose = Some(hex::encode(&payload));
        }
    }
    Ok((m, compose))
}

/// Ergebnis der Quittungsprüfung.
#[derive(Debug, Default, Clone)]
pub struct ReceiptVerdict {
    /// Ed25519-Signatur über JCS der Quittung ohne `signature` stimmt.
    pub signature_ok: bool,
    /// `workload_keyset_digest` der Quittung gleich dem des Berichts.
    pub keyset_matches: bool,
    pub error: Option<String>,
}

/// Prüft die Signatur einer Quittung gegen das Keyset des Berichts.
pub fn verify_receipt(receipt_json: &str, report_json: &str) -> ReceiptVerdict {
    let mut out = ReceiptVerdict::default();
    match receipt_inner(receipt_json, report_json, &mut out) {
        Ok(()) => {}
        Err(e) => out.error = Some(e),
    }
    out
}

fn receipt_inner(receipt: &str, report: &str, out: &mut ReceiptVerdict) -> Result<(), String> {
    let mut rc: Value = serde_json::from_str(receipt).map_err(|e| e.to_string())?;
    let rep: Value = serde_json::from_str(report).map_err(|e| e.to_string())?;
    let ks = &rep["attestation"]["workload_keyset"];
    out.keyset_matches = !rc["workload_keyset_digest"].is_null()
        && rc["workload_keyset_digest"] == rep["workload_keyset_digest"];
    let kid = rc["key_id"].as_str().ok_or("key_id fehlt")?.to_string();
    let pk = ks["receipt_signing_keys"]
        .as_array()
        .and_then(|l| l.iter().find(|k| k["key_id"] == kid.as_str()))
        .and_then(|k| k["public_key"].as_str())
        .ok_or("Schlüssel nicht im Keyset")?;
    let sig = rc
        .as_object_mut()
        .ok_or("Quittung kein Objekt")?
        .remove("signature");
    let sig = hex::decode(
        sig.as_ref()
            .and_then(Value::as_str)
            .ok_or("signature fehlt")?,
    )
    .map_err(|e| e.to_string())?;
    out.signature_ok = ed25519_ok(
        &hex::decode(pk).map_err(|e| e.to_string())?,
        &canon(&rc)?,
        &sig,
    );
    Ok(())
}

/// Ed25519-Prüfung; falsche Längen ergeben `false`.
pub fn ed25519_ok(public_key: &[u8], message: &[u8], signature: &[u8]) -> bool {
    let Ok(pk) = <[u8; 32]>::try_from(public_key) else {
        return false;
    };
    let Ok(vk) = VerifyingKey::from_bytes(&pk) else {
        return false;
    };
    let Ok(sig) = Signature::from_slice(signature) else {
        return false;
    };
    vk.verify_strict(message, &sig).is_ok()
}

/// Steht der beobachtete TLS-SPKI (Hex) für `host` im Keyset des Berichts? Einträge mit `domain`
/// gelten nur für diesen Host, Einträge ohne `domain` für jeden (`spec/aci.md` §9.1 Nr. 6).
pub fn tls_spki_listed(report_json: &str, observed_spki_hex: &str, host: &str) -> bool {
    let Ok(rep) = serde_json::from_str::<Value>(report_json) else {
        return false;
    };
    let observed = observed_spki_hex.to_ascii_lowercase();
    rep["attestation"]["workload_keyset"]["tls_public_keys"]
        .as_array()
        .is_some_and(|l| {
            l.iter().any(|k| {
                k["spki_sha256"]
                    .as_str()
                    .is_some_and(|s| s.eq_ignore_ascii_case(&observed))
                    && k["domain"]
                        .as_str()
                        .is_none_or(|d| d.eq_ignore_ascii_case(host))
            })
        })
}
