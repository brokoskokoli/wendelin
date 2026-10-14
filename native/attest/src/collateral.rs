//! Kollateral beschaffen ohne Netz im Crate: Dart holt die Antworten von Intel PCS,
//! dieses Modul sagt, was zu holen ist, und setzt die Teile zusammen.
use dcap_qvl::{intel, quote::Quote, QuoteCollateralV3};
use serde_json::Value;

use crate::spki;

/// Was bei Intel PCS für einen Quote abzurufen ist.
#[derive(Debug, Clone)]
pub struct CollateralRequest {
    /// `tdx` oder `sgx`.
    pub tee: String,
    /// FMSPC als Großbuchstaben-Hex.
    pub fmspc: String,
    /// `processor` oder `platform`.
    pub ca: String,
}

/// Die rohen PCS-Antworten (Header-Werte bereits URL-dekodiert).
#[derive(Debug, Clone)]
pub struct CollateralParts {
    pub pck_crl: Vec<u8>,
    pub pck_crl_issuer_chain: String,
    pub root_ca_crl: Vec<u8>,
    /// Antwortkörper von `tcb` (JSON mit `tcbInfo` und `signature`).
    pub tcb_info_body: String,
    pub tcb_info_issuer_chain: String,
    /// Antwortkörper von `qe/identity` (JSON mit `enclaveIdentity` und `signature`).
    pub qe_identity_body: String,
    pub qe_identity_issuer_chain: String,
}

/// FMSPC, CA und TEE-Art aus der im Quote eingebetteten PCK-Kette.
pub fn collateral_request(quote: &[u8]) -> Result<CollateralRequest, String> {
    let q = Quote::parse(quote).map_err(|e| format!("Quote: {e}"))?;
    let fmspc = intel::quote_fmspc(&q).map_err(|e| format!("FMSPC: {e}"))?;
    let ca = intel::quote_ca(&q).map_err(|e| format!("CA: {e}"))?;
    Ok(CollateralRequest {
        tee: if q.header.is_sgx() { "sgx" } else { "tdx" }.into(),
        fmspc: hex::encode_upper(fmspc),
        ca: ca.as_id_str().into(),
    })
}

/// URL der Root-CA-CRL aus der Ausstellerkette der QE-Identität (letztes Zertifikat der Kette).
pub fn root_crl_url(qe_identity_issuer_chain: &str) -> Result<String, String> {
    let certs = pem::parse_many(qe_identity_issuer_chain.as_bytes()).map_err(|e| e.to_string())?;
    let root = certs.last().ok_or("leere Ausstellerkette")?;
    spki::crl_url(root.contents())?.ok_or_else(|| "kein CRL-Verteilpunkt im Root-Zertifikat".into())
}

fn field(body: &str, key: &str) -> Result<(Value, Vec<u8>), String> {
    let v: Value = serde_json::from_str(body).map_err(|e| format!("{key}: {e}"))?;
    let inner = v.get(key).cloned().ok_or(format!("{key} fehlt"))?;
    let sig = v
        .get("signature")
        .and_then(Value::as_str)
        .ok_or("signature fehlt")?;
    Ok((
        inner,
        hex::decode(sig).map_err(|e| format!("signature: {e}"))?,
    ))
}

/// Fügt die PCS-Antworten zu `QuoteCollateralV3` (als JSON) zusammen.
pub fn build_collateral(p: &CollateralParts) -> Result<String, String> {
    let (tcb, tcb_sig) = field(&p.tcb_info_body, "tcbInfo")?;
    let (qe, qe_sig) = field(&p.qe_identity_body, "enclaveIdentity")?;
    let c = QuoteCollateralV3 {
        pck_crl_issuer_chain: p.pck_crl_issuer_chain.clone(),
        root_ca_crl: p.root_ca_crl.clone(),
        pck_crl: p.pck_crl.clone(),
        tcb_info_issuer_chain: p.tcb_info_issuer_chain.clone(),
        tcb_info: tcb.to_string(),
        tcb_info_signature: tcb_sig,
        qe_identity_issuer_chain: p.qe_identity_issuer_chain.clone(),
        qe_identity: qe.to_string(),
        qe_identity_signature: qe_sig,
        pck_certificate_chain: None,
    };
    serde_json::to_string(&c).map_err(|e| e.to_string())
}

/// Frühestes `nextUpdate` (ISO-8601, UTC) von TCB-Info und QE-Identität: bis dahin ist das Kollateral nutzbar.
pub fn next_update(collateral_json: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(collateral_json).map_err(|e| e.to_string())?;
    let mut best: Option<String> = None;
    for k in ["tcb_info", "qe_identity"] {
        let inner: Value = serde_json::from_str(v[k].as_str().ok_or(format!("{k} fehlt"))?)
            .map_err(|e| e.to_string())?;
        let n = inner["nextUpdate"]
            .as_str()
            .ok_or(format!("{k}.nextUpdate fehlt"))?
            .to_string();
        // ISO-8601 in UTC mit gleicher Schreibweise: lexikografischer Vergleich genügt.
        if best.as_ref().is_none_or(|b| n < *b) {
            best = Some(n);
        }
    }
    best.ok_or_else(|| "kein nextUpdate".into())
}
