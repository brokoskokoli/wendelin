//! TDX-Quote gegen übergebenes Kollateral prüfen (kein Netz, `now` kommt von außen).
use dcap_qvl::{quote::Quote, verify::QuoteVerifier, QuoteCollateralV3};

/// Ergebnis der Quote-Prüfung mit den Feldern des TD-Reports.
#[derive(Debug, Default, Clone)]
pub struct QuoteInfo {
    /// Signaturkette, CRLs, TCB-Info und QE-Identität sind gültig.
    pub ok: bool,
    /// Grund, wenn `ok` false ist.
    pub error: Option<String>,
    /// TCB-Status, z. B. `UpToDate`, `OutOfDate`, `Revoked`.
    pub tcb_status: String,
    pub advisory_ids: Vec<String>,
    pub mr_td: Vec<u8>,
    pub rt_mr0: Vec<u8>,
    pub rt_mr1: Vec<u8>,
    pub rt_mr2: Vec<u8>,
    pub rt_mr3: Vec<u8>,
    /// 64 Byte `report_data` aus dem Quote.
    pub report_data: Vec<u8>,
}

impl QuoteInfo {
    fn failed(e: impl ToString) -> Self {
        Self {
            error: Some(e.to_string()),
            ..Self::default()
        }
    }
}

/// Prüft `quote` mit `collateral_json` (`QuoteCollateralV3` als JSON) zum Zeitpunkt `now` (Unix-Sekunden).
pub fn verify_quote(quote: &[u8], collateral_json: &str, now: u64) -> QuoteInfo {
    let collateral: QuoteCollateralV3 = match serde_json::from_str(collateral_json) {
        Ok(c) => c,
        Err(e) => return QuoteInfo::failed(format!("Kollateral: {e}")),
    };
    let verified = match QuoteVerifier::new_prod().verify(quote, &collateral, now) {
        Ok(v) => v,
        Err(e) => return QuoteInfo::failed(format!("Quote: {e}")),
    };
    let Some(td) = verified.report.as_td10() else {
        return QuoteInfo::failed("kein TD10-Report");
    };
    QuoteInfo {
        ok: true,
        error: None,
        tcb_status: verified.status.clone(),
        advisory_ids: verified.advisory_ids.clone(),
        mr_td: td.mr_td.to_vec(),
        rt_mr0: td.rt_mr0.to_vec(),
        rt_mr1: td.rt_mr1.to_vec(),
        rt_mr2: td.rt_mr2.to_vec(),
        rt_mr3: td.rt_mr3.to_vec(),
        report_data: td.report_data.to_vec(),
    }
}

/// Ob der Quote lesbar ist (Kopf und Zertifizierungsdaten), ohne Signaturprüfung.
pub fn parse_ok(quote: &[u8]) -> bool {
    Quote::parse(quote).is_ok()
}
