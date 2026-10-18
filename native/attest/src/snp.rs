//! AMD SEV-SNP-Attestierung (WP76a, Tinfoil): Report parsen, VCEK/ASK/ARK-Kette prüfen,
//! Report-Signatur, Richtlinie und Bindung von `report_data` (TLS-SPKI ‖ HPKE-Schlüssel).
//!
//! Reine, netzfreie Funktionen: VCEK und Zertifikatskette holt Dart vom AMD-KDS
//! (`kdsintf.amd.com`) und reicht sie hinein. Die ARK-Schlüssel sind per SPKI-SHA-256 gepinnt
//! (Milan, Genoa, Turin); alles andere wird per Signatur geprüft.
//!
//! Layout des Reports: SEV-SNP ABI Spec 56860, Tabelle "ATTESTATION_REPORT" (Version 2/3, 1184 Byte).
//! VCEK-Erweiterungen: AMD "VCEK Certificate and KDS Interface Spec" 57230, Tabelle 8.
use der::{Decode, Encode};
use rsa::pkcs8::DecodePublicKey;
use rsa::pss::{Signature as PssSignature, VerifyingKey as PssKey};
use rsa::sha2::{Digest, Sha256, Sha384};
use rsa::signature::Verifier;
use x509_cert::Certificate;

/// Größe eines SNP-Reports.
pub const REPORT_LEN: usize = 0x4A0;
/// Länge des signierten Bereichs (Offset der Signatur).
const SIGNED_LEN: usize = 0x2A0;

/// SHA-256 über das SPKI der AMD-Root-Schlüssel (ARK), aus `kdsintf.amd.com/vcek/v1/<Produkt>/cert_chain`.
const PINNED_ARKS: [(&str, &str); 3] = [
    (
        "Milan",
        "9f056bee44377e29308cb5ffa895bdfb62d18881fa6bed8d6f075b0204089cb9",
    ),
    (
        "Genoa",
        "429a69c9422aa258ee4d8db5fcda9c6470ef15f8cd5a9cebd6cbc7d90b863831",
    ),
    (
        "Turin",
        "4f125410563a2ab9a50356f9243f6fe0b6f73de98603f53f90339c70e9d7ad08",
    ),
];

/// DER der PSS-Parameter (SHA-384, MGF1-SHA-384, Salt 48), wie AMD sie in ARK/ASK/VCEK verwendet;
/// `trailerField` 1 ist der Standardwert und darf fehlen oder stehen.
fn pss_params_ok(der: &[u8]) -> bool {
    const CORE: [u8; 52] = [
        0xa0, 0x0f, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02,
        0x05, 0x00, 0xa1, 0x1c, 0x30, 0x1a, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01,
        0x01, 0x08, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02,
        0x05, 0x00, 0xa2, 0x03, 0x02, 0x01, 0x30,
    ];
    const TRAILER: [u8; 5] = [0xa3, 0x03, 0x02, 0x01, 0x01];
    let core = &CORE[..];
    let plain = [&[0x30, core.len() as u8][..], core].concat();
    let full = [&[0x30, (core.len() + 5) as u8][..], core, &TRAILER].concat();
    der == plain || der == full
}
const OID_RSASSA_PSS: &str = "1.2.840.113549.1.1.10";

const OID_SPL_BOOT: &str = "1.3.6.1.4.1.3704.1.3.1";
const OID_SPL_TEE: &str = "1.3.6.1.4.1.3704.1.3.2";
const OID_SPL_SNP: &str = "1.3.6.1.4.1.3704.1.3.3";
const OID_SPL_UCODE: &str = "1.3.6.1.4.1.3704.1.3.8";
const OID_HWID: &str = "1.3.6.1.4.1.3704.1.4";

/// TCB-Komponenten (je ein Byte) eines `reported_tcb`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct SnpTcb {
    pub bootloader: u8,
    pub tee: u8,
    pub snp: u8,
    pub microcode: u8,
}

impl SnpTcb {
    fn from_u64(v: u64) -> Self {
        let b = v.to_le_bytes();
        Self {
            bootloader: b[0],
            tee: b[1],
            snp: b[6],
            microcode: b[7],
        }
    }
}

/// Geparste Felder des Reports, soweit Wendelin sie braucht.
#[derive(Debug, Clone, Default)]
pub struct SnpReportInfo {
    pub version: u32,
    pub policy: u64,
    pub vmpl: u32,
    pub reported_tcb: SnpTcb,
    /// `true` bei Signatur mit dem VLEK statt dem VCEK (nicht unterstützt).
    pub signed_with_vlek: bool,
    /// Messwert (SHA-384, Hex) der Gast-Messung.
    pub measurement_hex: String,
    /// `report_data` (64 Byte, Hex).
    pub report_data_hex: String,
    /// Chip-ID (64 Byte, Hex) für die KDS-Anfrage.
    pub chip_id_hex: String,
}

/// Mindestanforderungen an das Ziel. Debug-Gäste und VMPL ≠ 0 lehnt die Prüfung immer ab.
#[derive(Debug, Clone, Default)]
pub struct SnpPolicy {
    pub min_tcb: SnpTcb,
}

/// Ergebnis je Prüfstufe; jede Stufe wird, soweit die Eingabe es zulässt, immer ausgewertet.
#[derive(Debug, Default, Clone)]
pub struct SnpVerdict {
    pub report_ok: bool,
    /// VCEK → ASK → ARK gültig, ARK gepinnt, Zertifikate zeitlich gültig.
    pub chain_ok: bool,
    /// VCEK passt zum Chip und zur `reported_tcb` des Reports.
    pub vcek_matches_report: bool,
    /// ECDSA-P-384-Signatur des Reports mit dem VCEK.
    pub signature_ok: bool,
    /// Kein Debug, VMPL 0, VCEK-signiert, TCB-Mindestwerte erreicht.
    pub policy_ok: bool,
    /// `report_data[0..32]` = erwarteter TLS-SPKI-Hash.
    pub tls_bound: bool,
    /// `report_data[32..64]` = erwarteter HPKE-Schlüssel.
    pub hpke_bound: bool,
    /// AMD-Produkt der gepinnten Wurzel (`Milan`, `Genoa`, `Turin`).
    pub product: Option<String>,
    pub info: Option<SnpReportInfo>,
    pub errors: Vec<String>,
}

impl SnpVerdict {
    pub fn all_ok(&self) -> bool {
        self.errors.is_empty()
            && self.report_ok
            && self.chain_ok
            && self.vcek_matches_report
            && self.signature_ok
            && self.policy_ok
            && self.tls_bound
            && self.hpke_bound
    }
}

struct Parsed<'a> {
    raw: &'a [u8],
    info: SnpReportInfo,
    reported_tcb_raw: u64,
    chip_id: &'a [u8],
    report_data: &'a [u8],
}

fn le32(r: &[u8], o: usize) -> u32 {
    u32::from_le_bytes(r[o..o + 4].try_into().unwrap())
}

fn le64(r: &[u8], o: usize) -> u64 {
    u64::from_le_bytes(r[o..o + 8].try_into().unwrap())
}

fn parse(report: &[u8]) -> Result<Parsed<'_>, String> {
    if report.len() != REPORT_LEN {
        return Err(format!("Report: {} Byte statt {REPORT_LEN}", report.len()));
    }
    let version = le32(report, 0);
    if !(2..=5).contains(&version) {
        return Err(format!("Report: Version {version} nicht unterstützt"));
    }
    if le32(report, 0x34) != 1 {
        return Err("Report: Signaturverfahren ist nicht ECDSA-P-384-SHA-384".into());
    }
    let reported = le64(report, 0x180);
    let info = SnpReportInfo {
        version,
        policy: le64(report, 0x08),
        vmpl: le32(report, 0x30),
        reported_tcb: SnpTcb::from_u64(reported),
        signed_with_vlek: (le32(report, 0x48) >> 2) & 7 != 0,
        measurement_hex: hex::encode(&report[0x90..0xC0]),
        report_data_hex: hex::encode(&report[0x50..0x90]),
        chip_id_hex: hex::encode(&report[0x1A0..0x1E0]),
    };
    Ok(Parsed {
        raw: report,
        info,
        reported_tcb_raw: reported,
        chip_id: &report[0x1A0..0x1E0],
        report_data: &report[0x50..0x90],
    })
}

/// Felder des Reports (für die KDS-Anfrage und die Anzeige); `Err` bei unlesbarem Report.
pub fn report_info(report: &[u8]) -> Result<SnpReportInfo, String> {
    parse(report).map(|p| p.info)
}

fn certs_from_pem(pem_text: &str) -> Result<Vec<Certificate>, String> {
    let blocks = pem::parse_many(pem_text).map_err(|e| format!("Kette: {e}"))?;
    let mut out = Vec::new();
    for b in blocks.iter().filter(|b| b.tag() == "CERTIFICATE") {
        out.push(Certificate::from_der(b.contents()).map_err(|e| format!("Zertifikat: {e}"))?);
    }
    Ok(out)
}

fn spki_der(c: &Certificate) -> Result<Vec<u8>, String> {
    c.tbs_certificate()
        .subject_public_key_info()
        .to_der()
        .map_err(|e| format!("SPKI: {e}"))
}

/// Prüft die Signatur von `child` mit dem RSA-Schlüssel von `issuer` (nur RSASSA-PSS-SHA-384).
fn verify_cert_sig(child: &Certificate, issuer: &Certificate) -> Result<(), String> {
    let alg = child.signature_algorithm();
    if alg.oid.to_string() != OID_RSASSA_PSS {
        return Err(format!("Signaturverfahren {} nicht erlaubt", alg.oid));
    }
    let params = alg
        .parameters
        .as_ref()
        .ok_or("PSS-Parameter fehlen")?
        .to_der()
        .map_err(|e| format!("PSS-Parameter: {e}"))?;
    if !pss_params_ok(&params) {
        return Err("PSS-Parameter weichen von SHA-384/MGF1-SHA-384/Salt 48 ab".into());
    }
    let key = PssKey::<Sha384>::from_public_key_der(&spki_der(issuer)?)
        .map_err(|e| format!("RSA-Schlüssel: {e}"))?;
    let tbs = child
        .tbs_certificate()
        .to_der()
        .map_err(|e| format!("TBS: {e}"))?;
    let sig = PssSignature::try_from(child.signature().raw_bytes())
        .map_err(|e| format!("Signatur: {e}"))?;
    key.verify(&tbs, &sig)
        .map_err(|_| "Signatur ungültig".into())
}

fn valid_at(c: &Certificate, now: u64) -> bool {
    let v = c.tbs_certificate().validity();
    let nb = v.not_before.to_unix_duration().as_secs();
    let na = v.not_after.to_unix_duration().as_secs();
    nb <= now && now < na
}

/// ARK (selbstsigniert, gepinnt) → ASK → VCEK; liefert das Produkt der Wurzel.
fn verify_chain(
    vcek: &Certificate,
    chain: &[Certificate],
    now: u64,
) -> Result<&'static str, String> {
    let ark = chain
        .iter()
        .find(|c| c.tbs_certificate().subject() == c.tbs_certificate().issuer())
        .ok_or("ARK fehlt in der Kette")?;
    let ask = chain
        .iter()
        .find(|c| c.tbs_certificate().issuer() == ark.tbs_certificate().subject() && *c != ark)
        .ok_or("ASK fehlt in der Kette")?;
    let ark_hash = hex::encode(Sha256::digest(spki_der(ark)?));
    let product = PINNED_ARKS
        .iter()
        .find(|(_, h)| *h == ark_hash)
        .map(|(p, _)| *p)
        .ok_or("ARK ist nicht gepinnt")?;
    verify_cert_sig(ark, ark).map_err(|e| format!("ARK: {e}"))?;
    verify_cert_sig(ask, ark).map_err(|e| format!("ASK: {e}"))?;
    verify_cert_sig(vcek, ask).map_err(|e| format!("VCEK: {e}"))?;
    for (n, c) in [("ARK", ark), ("ASK", ask), ("VCEK", vcek)] {
        if !valid_at(c, now) {
            return Err(format!("{n}: Zertifikat zum Prüfzeitpunkt nicht gültig"));
        }
    }
    Ok(product)
}

fn ext<'a>(c: &'a Certificate, oid: &str) -> Option<&'a [u8]> {
    c.tbs_certificate()
        .extensions()?
        .iter()
        .find(|e| e.extn_id.to_string() == oid)
        .map(|e| e.extn_value.as_bytes())
}

fn spl(c: &Certificate, oid: &str) -> Option<u8> {
    u8::from_der(ext(c, oid)?).ok()
}

/// Chip-ID und TCB des VCEK müssen zu `reported_tcb` und `chip_id` des Reports passen.
fn vcek_matches(vcek: &Certificate, p: &Parsed) -> Result<(), String> {
    let hw = ext(vcek, OID_HWID).ok_or("VCEK: hwID fehlt")?;
    if hw != p.chip_id {
        return Err("VCEK gehört zu einem anderen Chip".into());
    }
    let t = SnpTcb::from_u64(p.reported_tcb_raw);
    let v = SnpTcb {
        bootloader: spl(vcek, OID_SPL_BOOT).ok_or("VCEK: blSPL fehlt")?,
        tee: spl(vcek, OID_SPL_TEE).ok_or("VCEK: teeSPL fehlt")?,
        snp: spl(vcek, OID_SPL_SNP).ok_or("VCEK: snpSPL fehlt")?,
        microcode: spl(vcek, OID_SPL_UCODE).ok_or("VCEK: ucodeSPL fehlt")?,
    };
    if v != t {
        return Err("VCEK-TCB weicht von reported_tcb ab".into());
    }
    Ok(())
}

/// Wandelt eine 72-Byte-Little-Endian-Zahl in 48 Byte Big-Endian (obere 24 Byte müssen 0 sein).
fn scalar_be(le: &[u8]) -> Result<[u8; 48], String> {
    if le[48..].iter().any(|b| *b != 0) {
        return Err("Signaturwert zu groß".into());
    }
    let mut out = [0u8; 48];
    for (i, b) in le[..48].iter().enumerate() {
        out[47 - i] = *b;
    }
    Ok(out)
}

fn verify_report_sig(vcek: &Certificate, report: &[u8]) -> Result<(), String> {
    use p384::ecdsa::{Signature, VerifyingKey};
    let point = vcek
        .tbs_certificate()
        .subject_public_key_info()
        .subject_public_key
        .raw_bytes();
    let key = VerifyingKey::from_sec1_bytes(point).map_err(|e| format!("VCEK-Schlüssel: {e}"))?;
    let r = scalar_be(&report[SIGNED_LEN..SIGNED_LEN + 72])?;
    let s = scalar_be(&report[SIGNED_LEN + 72..SIGNED_LEN + 144])?;
    let mut rs = [0u8; 96];
    rs[..48].copy_from_slice(&r);
    rs[48..].copy_from_slice(&s);
    let sig = Signature::from_slice(&rs).map_err(|e| format!("Signatur: {e}"))?;
    key.verify(&report[..SIGNED_LEN], &sig)
        .map_err(|_| "Report-Signatur ungültig".into())
}

fn check_policy(p: &Parsed, pol: &SnpPolicy) -> Result<(), String> {
    if p.info.policy & (1 << 19) != 0 {
        return Err("Debug-Gast".into());
    }
    if p.info.vmpl != 0 {
        return Err(format!("VMPL {} statt 0", p.info.vmpl));
    }
    if p.info.signed_with_vlek {
        return Err("Report nicht mit dem VCEK signiert".into());
    }
    let (t, m) = (p.info.reported_tcb, pol.min_tcb);
    if t.bootloader < m.bootloader || t.tee < m.tee || t.snp < m.snp || t.microcode < m.microcode {
        return Err(format!(
            "TCB {}.{}.{}.{} unter Minimum {}.{}.{}.{}",
            t.bootloader, t.tee, t.snp, t.microcode, m.bootloader, m.tee, m.snp, m.microcode
        ));
    }
    Ok(())
}

/// Prüft einen SNP-Report vollständig. `vcek_der` und `chain_pem` (ASK + ARK) kommen vom KDS.
pub fn verify(
    report: &[u8],
    vcek_der: &[u8],
    chain_pem: &str,
    now_unix: u64,
    policy: &SnpPolicy,
    expected_tls_spki_sha256: &[u8],
    expected_hpke_key: &[u8],
) -> SnpVerdict {
    let mut v = SnpVerdict::default();
    let p = match parse(report) {
        Ok(p) => p,
        Err(e) => {
            v.errors.push(e);
            return v;
        }
    };
    v.report_ok = true;
    v.info = Some(p.info.clone());
    v.tls_bound = expected_tls_spki_sha256.len() == 32
        && ct_eq(&p.report_data[..32], expected_tls_spki_sha256);
    v.hpke_bound = expected_hpke_key.len() == 32 && ct_eq(&p.report_data[32..], expected_hpke_key);
    match check_policy(&p, policy) {
        Ok(()) => v.policy_ok = true,
        Err(e) => v.errors.push(format!("Richtlinie: {e}")),
    }
    let vcek = match Certificate::from_der(vcek_der) {
        Ok(c) => c,
        Err(e) => {
            v.errors.push(format!("VCEK: {e}"));
            return v;
        }
    };
    match certs_from_pem(chain_pem).and_then(|c| verify_chain(&vcek, &c, now_unix)) {
        Ok(prod) => {
            v.chain_ok = true;
            v.product = Some(prod.to_string());
        }
        Err(e) => v.errors.push(format!("Kette: {e}")),
    }
    match vcek_matches(&vcek, &p) {
        Ok(()) => v.vcek_matches_report = true,
        Err(e) => v.errors.push(e),
    }
    match verify_report_sig(&vcek, p.raw) {
        Ok(()) => v.signature_ok = true,
        Err(e) => v.errors.push(e),
    }
    v
}

fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}
