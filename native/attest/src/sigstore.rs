//! Sigstore-Prüfung des Tinfoil-Releases (WP76b): Der Messwert des Routers (SNP-Report) muss zum
//! signierten GitHub-Release passen. Reine, netzfreie Funktionen: Das Bundle (`tinfoil.hash` →
//! GitHub-Attestierung, Sigstore-Bundle v0.3) holt Dart, die Trust-Root liegt eingebettet im Repo
//! (`assets/sigstore_trusted_root.json`, Pflege siehe `docs/notes/sigstore-trust-root.md`).
//!
//! Geprüft wird, fail-closed, jede Stufe einzeln:
//! - `dsse_ok`: DSSE-Signatur (PAE) mit dem Blattzertifikat, in-toto-Statement (`predicateType`
//!   snp-tdx-multiplatform/v1), Subject-Digest = `tinfoil.hash`;
//! - `chain_ok`: Blattzertifikat → Fulcio-CA aus der Trust-Root (ECDSA P-384), Gültigkeit zum
//!   Rekor-Zeitpunkt, KeyUsage digitalSignature, EKU codeSigning;
//! - `identity_ok`: OIDC-Aussteller GitHub Actions, Repository und Workflow `…@refs/tags/<tag>`;
//! - `rekor_ok`: SET (signierter Eintragszeitpunkt), Checkpoint-Signatur, Merkle-Inklusionsbeweis
//!   (RFC 9162), Bindung von Zertifikat, Signatur und Payload-Hash an den Rekor-Eintrag;
//! - `measurement_ok`: `snp_measurement` des Releases = Messwert des Reports.
//!
//! Bewusst nicht enthalten: SCT-Prüfung (das Zertifikat ist durch Rekor-Eintrag und Zeitfenster
//! gebunden), Rekor-v2-/TSA-Bundles (nur der öffentliche Rekor v1 mit ECDSA-P-256-Schlüssel),
//! Widerruf. Der Aufbau folgt der Prüfung im Tinfoil-Client (`tinfoil-rs`, Apache-2.0), ist aber
//! eigenständig und deutlich kleiner.
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use der::{Decode, Encode};
use sha2::{Digest, Sha256};
use x509_cert::spki::SubjectPublicKeyInfoOwned;
use x509_cert::Certificate;

/// Eingebettete Sigstore-Trust-Root (TUF-Ziel `trusted_root.json`).
pub const TRUSTED_ROOT_JSON: &str = include_str!("../assets/sigstore_trusted_root.json");

const OIDC_ISSUER_GITHUB: &str = "https://token.actions.githubusercontent.com";
const PREDICATE_TYPE: &str = "https://tinfoil.sh/predicate/snp-tdx-multiplatform/v1";
const PAYLOAD_TYPE: &str = "application/vnd.in-toto+json";

const OID_OIDC_ISSUER_V1: &str = "1.3.6.1.4.1.57264.1.1";
const OID_OIDC_ISSUER_V2: &str = "1.3.6.1.4.1.57264.1.8";
const OID_GITHUB_REPOSITORY: &str = "1.3.6.1.4.1.57264.1.5";
const OID_GITHUB_REF: &str = "1.3.6.1.4.1.57264.1.6";
const OID_SOURCE_REPOSITORY_URI: &str = "1.3.6.1.4.1.57264.1.12";
const OID_SOURCE_REPOSITORY_REF: &str = "1.3.6.1.4.1.57264.1.14";
const OID_BUILD_SIGNER_URI: &str = "1.3.6.1.4.1.57264.1.9";
const OID_KEY_USAGE: &str = "2.5.29.15";
const OID_EXT_KEY_USAGE: &str = "2.5.29.37";
const OID_CODE_SIGNING: &str = "1.3.6.1.5.5.7.3.3";
const OID_ECDSA_SHA256: &str = "1.2.840.10045.4.3.2";
const OID_ECDSA_SHA384: &str = "1.2.840.10045.4.3.3";
const OID_P256: &str = "1.2.840.10045.3.1.7";
const OID_P384: &str = "1.3.132.0.34";

/// Ergebnis je Prüfstufe; jede Stufe wird, soweit die Eingabe es zulässt, immer ausgewertet.
#[derive(Debug, Default, Clone)]
pub struct SigstoreVerdict {
    pub dsse_ok: bool,
    pub chain_ok: bool,
    pub identity_ok: bool,
    pub rekor_ok: bool,
    /// `snp_measurement` des signierten Releases = Messwert des Reports.
    pub measurement_ok: bool,
    /// Messwert laut signiertem Release (SHA-384, Hex); leer, wenn das Statement nicht lesbar war.
    pub snp_measurement_hex: String,
    /// Release-Tag aus der Workflow-Identität des Zertifikats.
    pub release_tag: String,
    /// Von Rekor signierter Eintragszeitpunkt (Unix-Sekunden).
    pub integrated_time: u64,
    pub errors: Vec<String>,
}

impl SigstoreVerdict {
    /// Alle Stufen grün: Der Messwert des Reports gehört zum signierten Release von `repo`@`tag`.
    pub fn all_ok(&self) -> bool {
        self.errors.is_empty()
            && self.dsse_ok
            && self.chain_ok
            && self.identity_ok
            && self.rekor_ok
            && self.measurement_ok
    }
}

type R<T> = Result<T, String>;

fn b64(s: &str) -> R<Vec<u8>> {
    B64.decode(s).map_err(|e| format!("Base64 ungültig: {e}"))
}

fn jstr<'a>(v: &'a serde_json::Value, path: &[&str]) -> R<&'a str> {
    let mut cur = v;
    for k in path {
        cur = cur
            .get(*k)
            .ok_or_else(|| format!("Feld fehlt: {}", path.join(".")))?;
    }
    cur.as_str()
        .ok_or_else(|| format!("Feld kein String: {}", path.join(".")))
}

/// `int64` im Protobuf-JSON ist ein String; Zahlen akzeptieren wir ebenfalls.
fn jnum(v: &serde_json::Value, path: &[&str]) -> R<u64> {
    let mut cur = v;
    for k in path {
        cur = cur
            .get(*k)
            .ok_or_else(|| format!("Feld fehlt: {}", path.join(".")))?;
    }
    cur.as_str()
        .and_then(|s| s.parse().ok())
        .or_else(|| cur.as_u64())
        .ok_or_else(|| format!("Feld keine Zahl: {}", path.join(".")))
}

/// RFC 3339 in UTC (`YYYY-MM-DDTHH:MM:SS[.f]Z`) → Unix-Sekunden.
fn parse_rfc3339(s: &str) -> R<u64> {
    let bad = || format!("Zeitstempel ungültig: {s}");
    let s = s.strip_suffix('Z').ok_or_else(bad)?;
    let (date, time) = s.split_once('T').ok_or_else(bad)?;
    let num = |p: &str| p.parse::<i64>().map_err(|_| bad());
    let d: Vec<&str> = date.split('-').collect();
    let t: Vec<&str> = time.split(':').collect();
    if d.len() != 3 || t.len() != 3 {
        return Err(bad());
    }
    let (y, m, day) = (num(d[0])?, num(d[1])?, num(d[2])?);
    let sec = num(t[2].split('.').next().unwrap_or(""))?;
    let (h, mi) = (num(t[0])?, num(t[1])?);
    if !(1..=12).contains(&m) || !(1..=31).contains(&day) {
        return Err(bad());
    }
    // days_from_civil (Howard Hinnant)
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    let ts = days * 86400 + h * 3600 + mi * 60 + sec;
    u64::try_from(ts).map_err(|_| bad())
}

// ---------------------------------------------------------------------------------------------
// Trust-Root

struct Window {
    from: Option<u64>,
    until: Option<u64>,
}

impl Window {
    fn parse(v: Option<&serde_json::Value>) -> R<Self> {
        let Some(v) = v else {
            return Ok(Self {
                from: None,
                until: None,
            });
        };
        let from = v
            .get("start")
            .and_then(|s| s.as_str())
            .map(parse_rfc3339)
            .transpose()?;
        let until = v
            .get("end")
            .and_then(|s| s.as_str())
            .map(parse_rfc3339)
            .transpose()?;
        Ok(Self { from, until })
    }
    fn contains(&self, t: u64) -> bool {
        self.from.is_none_or(|f| t >= f) && self.until.is_none_or(|u| t <= u)
    }
}

struct RekorKey {
    /// Host aus `baseUrl` (Checkpoint-Ursprung und Schlüsselname der Notiz).
    host: String,
    key_id: Vec<u8>,
    spki_der: Vec<u8>,
    key_details: String,
    valid: Window,
}

struct FulcioCa {
    chain: Vec<Certificate>,
    valid: Window,
}

struct TrustRoot {
    rekor: Vec<RekorKey>,
    fulcio: Vec<FulcioCa>,
}

fn load_root(json: &str) -> R<TrustRoot> {
    let v: serde_json::Value =
        serde_json::from_str(json).map_err(|e| format!("Trust-Root nicht lesbar: {e}"))?;
    let mut rekor = Vec::new();
    for t in v
        .get("tlogs")
        .and_then(|t| t.as_array())
        .ok_or("Trust-Root ohne tlogs")?
    {
        let base = jstr(t, &["baseUrl"])?;
        let host = base
            .strip_prefix("https://")
            .and_then(|h| h.split('/').next())
            .filter(|h| !h.is_empty())
            .ok_or("Rekor-baseUrl ohne https-Host")?
            .to_string();
        rekor.push(RekorKey {
            host,
            key_id: b64(jstr(t, &["logId", "keyId"])?)?,
            spki_der: b64(jstr(t, &["publicKey", "rawBytes"])?)?,
            key_details: jstr(t, &["publicKey", "keyDetails"])?.to_string(),
            valid: Window::parse(t.get("publicKey").and_then(|k| k.get("validFor")))?,
        });
    }
    let mut fulcio = Vec::new();
    let cas = v.get("certificateAuthorities").and_then(|t| t.as_array());
    for ca in cas.ok_or("Trust-Root ohne certificateAuthorities")? {
        let mut chain = Vec::new();
        let certs = ca.get("certChain").and_then(|c| c.get("certificates"));
        for c in certs
            .and_then(|c| c.as_array())
            .ok_or("CA ohne Zertifikate")?
        {
            let der = b64(jstr(c, &["rawBytes"])?)?;
            chain.push(Certificate::from_der(&der).map_err(|e| format!("CA-Zertifikat: {e}"))?);
        }
        if chain.is_empty() {
            continue;
        }
        fulcio.push(FulcioCa {
            chain,
            valid: Window::parse(ca.get("validFor"))?,
        });
    }
    Ok(TrustRoot { rekor, fulcio })
}

// ---------------------------------------------------------------------------------------------
// Krypto-Helfer

fn spki_point(spki: &SubjectPublicKeyInfoOwned) -> R<(String, Vec<u8>)> {
    let curve = spki
        .algorithm
        .parameters
        .as_ref()
        .and_then(|p| p.decode_as::<der::asn1::ObjectIdentifier>().ok())
        .map(|o| o.to_string())
        .unwrap_or_default();
    let key = spki
        .subject_public_key
        .as_bytes()
        .ok_or("Schlüssel nicht byte-ausgerichtet")?;
    Ok((curve, key.to_vec()))
}

fn ecdsa_p256(point: &[u8], msg: &[u8], sig_der: &[u8]) -> bool {
    use p256::ecdsa::{signature::Verifier, Signature, VerifyingKey};
    let (Ok(k), Ok(s)) = (
        VerifyingKey::from_sec1_bytes(point),
        Signature::from_der(sig_der),
    ) else {
        return false;
    };
    k.verify(msg, &s).is_ok()
}

fn ecdsa_p384(point: &[u8], msg: &[u8], sig_der: &[u8]) -> bool {
    use p384::ecdsa::{signature::Verifier, Signature, VerifyingKey};
    let (Ok(k), Ok(s)) = (
        VerifyingKey::from_sec1_bytes(point),
        Signature::from_der(sig_der),
    ) else {
        return false;
    };
    k.verify(msg, &s).is_ok()
}

/// `child` ist von `issuer` signiert (ECDSA P-256/SHA-256 oder P-384/SHA-384, passend gepaart).
fn issued_by(child: &Certificate, issuer: &Certificate) -> R<()> {
    if child.tbs_certificate().issuer() != issuer.tbs_certificate().subject() {
        return Err("Aussteller passt nicht zum Subject des Ausstellerzertifikats".into());
    }
    let tbs = child
        .tbs_certificate()
        .to_der()
        .map_err(|e| format!("TBS: {e}"))?;
    let sig = child
        .signature()
        .as_bytes()
        .ok_or("Signatur nicht byte-ausgerichtet")?;
    let (curve, point) = spki_point(issuer.tbs_certificate().subject_public_key_info())?;
    let alg = child.signature_algorithm().oid.to_string();
    let ok = match (curve.as_str(), alg.as_str()) {
        (OID_P256, OID_ECDSA_SHA256) => ecdsa_p256(&point, &tbs, sig),
        (OID_P384, OID_ECDSA_SHA384) => ecdsa_p384(&point, &tbs, sig),
        _ => {
            return Err(format!(
                "Kurve/Signaturverfahren nicht unterstützt: {curve} / {alg}"
            ))
        }
    };
    ok.then_some(())
        .ok_or_else(|| "Zertifikatssignatur ungültig".to_string())
}

fn valid_at(c: &Certificate, t: u64) -> bool {
    let v = &c.tbs_certificate().validity();
    t >= v.not_before.to_unix_duration().as_secs() && t <= v.not_after.to_unix_duration().as_secs()
}

fn ext_value<'a>(c: &'a Certificate, oid: &str) -> Option<&'a [u8]> {
    c.tbs_certificate()
        .extensions()
        .as_ref()?
        .iter()
        .find(|e| e.extn_id.to_string() == oid)
        .map(|e| e.extn_value.as_bytes())
}

/// Fulcio-Erweiterungen sind in v1 rohe Strings, ab `.8` DER-UTF8String.
fn ext_string(c: &Certificate, oid: &str) -> Option<String> {
    let raw = ext_value(c, oid)?;
    if let Ok(s) = der::asn1::Utf8StringRef::from_der(raw) {
        return Some(s.to_string());
    }
    std::str::from_utf8(raw).ok().map(str::to_string)
}

// ---------------------------------------------------------------------------------------------
// Stufen

struct Parsed {
    cert: Certificate,
    cert_der: Vec<u8>,
    payload: Vec<u8>,
    payload_type: String,
    sig: Vec<u8>,
}

fn parse_bundle(bundle: &serde_json::Value) -> R<Parsed> {
    let cert_der = b64(jstr(
        bundle,
        &["verificationMaterial", "certificate", "rawBytes"],
    )?)?;
    let cert = Certificate::from_der(&cert_der).map_err(|e| format!("Zertifikat: {e}"))?;
    let env = bundle.get("dsseEnvelope").ok_or("dsseEnvelope fehlt")?;
    let sigs = env
        .get("signatures")
        .and_then(|s| s.as_array())
        .ok_or("DSSE ohne signatures")?;
    if sigs.len() != 1 {
        return Err(format!(
            "DSSE braucht genau eine Signatur, gefunden {}",
            sigs.len()
        ));
    }
    Ok(Parsed {
        cert,
        cert_der,
        payload: b64(jstr(env, &["payload"])?)?,
        payload_type: jstr(env, &["payloadType"])?.to_string(),
        sig: b64(jstr(&sigs[0], &["sig"])?)?,
    })
}

fn pae(payload_type: &str, payload: &[u8]) -> Vec<u8> {
    let mut v = format!(
        "DSSEv1 {} {} {} ",
        payload_type.len(),
        payload_type,
        payload.len()
    )
    .into_bytes();
    v.extend_from_slice(payload);
    v
}

/// DSSE-Signatur und in-toto-Statement; liefert den `snp_measurement`.
fn check_dsse(p: &Parsed, expected_digest_hex: &str) -> R<String> {
    if p.payload_type != PAYLOAD_TYPE {
        return Err(format!(
            "DSSE-payloadType nicht unterstützt: {}",
            p.payload_type
        ));
    }
    let (curve, point) = spki_point(p.cert.tbs_certificate().subject_public_key_info())?;
    if curve != OID_P256 || !ecdsa_p256(&point, &pae(&p.payload_type, &p.payload), &p.sig) {
        return Err("DSSE-Signatur ungültig".into());
    }
    let st: serde_json::Value =
        serde_json::from_slice(&p.payload).map_err(|e| format!("Statement: {e}"))?;
    let ty = jstr(&st, &["_type"])?;
    if ty != "https://in-toto.io/Statement/v1" && ty != "https://in-toto.io/Statement/v0.1" {
        return Err(format!("in-toto-Typ nicht unterstützt: {ty}"));
    }
    if jstr(&st, &["predicateType"])? != PREDICATE_TYPE {
        return Err("predicateType nicht unterstützt".into());
    }
    let subjects = st
        .get("subject")
        .and_then(|s| s.as_array())
        .ok_or("Statement ohne subject")?;
    let digest = subjects
        .first()
        .and_then(|s| s.get("digest"))
        .and_then(|d| d.get("sha256"))
        .and_then(|d| d.as_str())
        .ok_or("Statement ohne sha256-Subject")?;
    if !digest.eq_ignore_ascii_case(expected_digest_hex) {
        return Err("Subject-Digest passt nicht zu tinfoil.hash".into());
    }
    let m = jstr(&st, &["predicate", "snp_measurement"])?;
    if m.len() != 96 || hex::decode(m).is_err() {
        return Err("snp_measurement ist kein SHA-384-Hex".into());
    }
    Ok(m.to_ascii_lowercase())
}

/// Blattzertifikat → Fulcio-CA aus der Trust-Root, zeitlich zum Rekor-Zeitpunkt gültig.
fn check_chain(root: &TrustRoot, cert: &Certificate, at: u64) -> R<()> {
    let ku = ext_value(cert, OID_KEY_USAGE).ok_or("KeyUsage fehlt")?;
    // BIT STRING: Tag 03, Länge, unused-Bits, Byte; digitalSignature = Bit 0 (0x80).
    if ku.len() < 4 || ku[0] != 0x03 || ku[3] & 0x80 == 0 {
        return Err("KeyUsage ohne digitalSignature".into());
    }
    let eku = ext_value(cert, OID_EXT_KEY_USAGE).ok_or("ExtendedKeyUsage fehlt")?;
    let eku = x509_cert::ext::pkix::ExtendedKeyUsage::from_der(eku)
        .map_err(|e| format!("ExtendedKeyUsage: {e}"))?;
    if !eku.0.iter().any(|o| o.to_string() == OID_CODE_SIGNING) {
        return Err("ExtendedKeyUsage ohne codeSigning".into());
    }
    if !valid_at(cert, at) {
        return Err("Zertifikat zum Rekor-Zeitpunkt nicht gültig".into());
    }
    let mut last = "keine passende Fulcio-CA in der Trust-Root".to_string();
    for ca in root.fulcio.iter().filter(|c| c.valid.contains(at)) {
        let r = (|| -> R<()> {
            issued_by(cert, &ca.chain[0])?;
            for w in ca.chain.windows(2) {
                issued_by(&w[0], &w[1])?;
            }
            let top = ca.chain.last().ok_or("leere Kette")?;
            if top.tbs_certificate().subject() != top.tbs_certificate().issuer() {
                return Err("Kette endet nicht in einer Wurzel".into());
            }
            issued_by(top, top)?;
            if !ca.chain.iter().all(|c| valid_at(c, at)) {
                return Err("CA-Zertifikat zum Rekor-Zeitpunkt nicht gültig".into());
            }
            Ok(())
        })();
        match r {
            Ok(()) => return Ok(()),
            Err(e) => last = e,
        }
    }
    Err(last)
}

/// Aussteller GitHub Actions, Repository und Workflow-Referenz `refs/tags/<tag>`; liefert den Tag.
fn check_identity(cert: &Certificate, repo: &str, tag: &str) -> R<()> {
    let issuer = ext_string(cert, OID_OIDC_ISSUER_V2)
        .or_else(|| ext_string(cert, OID_OIDC_ISSUER_V1))
        .ok_or("OIDC-Aussteller fehlt")?;
    if issuer != OIDC_ISSUER_GITHUB {
        return Err(format!("OIDC-Aussteller nicht GitHub Actions: {issuer}"));
    }
    // Repository: v2-Erweiterung (.12, volle URL) und/oder die veraltete .5 (`owner/repo`);
    // mindestens eine muss da sein, jede vorhandene muss passen.
    let uri = ext_string(cert, OID_SOURCE_REPOSITORY_URI);
    let legacy = ext_string(cert, OID_GITHUB_REPOSITORY);
    if uri.is_none() && legacy.is_none() {
        return Err("Repository fehlt".into());
    }
    if let Some(u) = &uri {
        if *u != format!("https://github.com/{repo}") {
            return Err(format!("Repository {u} statt {repo}"));
        }
    }
    if let Some(l) = &legacy {
        if l != repo {
            return Err(format!("Repository {l} statt {repo}"));
        }
    }
    let git_ref = format!("refs/tags/{tag}");
    for oid in [OID_SOURCE_REPOSITORY_REF, OID_GITHUB_REF] {
        if let Some(r) = ext_string(cert, oid) {
            if r != git_ref {
                return Err(format!("Referenz {r} statt {git_ref}"));
            }
        }
    }
    let wf = ext_string(cert, OID_BUILD_SIGNER_URI).ok_or("Workflow-Identität fehlt")?;
    let prefix = format!("https://github.com/{repo}/.github/workflows/");
    let suffix = format!("@refs/tags/{tag}");
    let name = wf
        .strip_prefix(&prefix)
        .and_then(|r| r.strip_suffix(&suffix));
    match name {
        Some(n) if !n.is_empty() && !n.contains('@') && !n.contains('/') => Ok(()),
        _ => Err(format!(
            "Workflow-Identität {wf} passt nicht zu {repo}@{tag}"
        )),
    }
}

fn node_hash(l: &[u8], r: &[u8]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update([1]);
    h.update(l);
    h.update(r);
    h.finalize().into()
}

/// Inklusionsbeweis nach RFC 9162, 2.1.3.2.
fn verify_inclusion(index: u64, size: u64, leaf: [u8; 32], path: &[Vec<u8>], root: &[u8]) -> bool {
    if index >= size {
        return false;
    }
    let (mut f, mut s, mut r) = (index, size - 1, leaf);
    for p in path {
        if s == 0 {
            return false;
        }
        if f & 1 == 1 || f == s {
            r = node_hash(p, &r);
            if f & 1 == 0 {
                while f & 1 == 0 && f != 0 {
                    f >>= 1;
                    s >>= 1;
                }
            }
        } else {
            r = node_hash(&r, p);
        }
        f >>= 1;
        s >>= 1;
    }
    s == 0 && r.as_slice() == root
}

/// Signierte Notiz (Checkpoint): Text bis zur Leerzeile, danach `— <name> <b64(4-Byte-Hinweis ‖ Sig)>`.
fn check_checkpoint(env: &str, key: &RekorKey, root_hash: &[u8], size: u64) -> R<()> {
    let (note, sigs) = env
        .split_once("\n\n")
        .ok_or("Checkpoint ohne Signaturteil")?;
    let note = format!("{note}\n");
    let lines: Vec<&str> = note.split('\n').collect();
    if lines.len() < 4 || lines[0].is_empty() {
        return Err("Checkpoint-Format ungültig".into());
    }
    // Ursprung `<host> - <Baum-ID>` (Rekor v1), Host = baseUrl der vertrauten Log-Instanz.
    let tree_id = lines[0]
        .strip_prefix(key.host.as_str())
        .and_then(|r| r.strip_prefix(" - "));
    if !tree_id.is_some_and(|t| !t.is_empty() && t.bytes().all(|c| c.is_ascii_digit())) {
        return Err("Checkpoint-Ursprung gehört nicht zum Rekor-Log".into());
    }
    if lines[1].parse::<u64>().ok() != Some(size) {
        return Err("Checkpoint-Größe ≠ treeSize".into());
    }
    if b64(lines[2])? != root_hash {
        return Err("Checkpoint-Wurzel ≠ rootHash des Beweises".into());
    }
    let (curve, point) = spki_point(
        &SubjectPublicKeyInfoOwned::from_der(&key.spki_der)
            .map_err(|e| format!("Rekor-Schlüssel: {e}"))?,
    )?;
    if curve != OID_P256 {
        return Err("Rekor-Schlüssel nicht ECDSA P-256".into());
    }
    for line in sigs.lines().filter(|l| !l.trim().is_empty()) {
        let mut parts = line.splitn(3, ' ');
        if parts.next() != Some("\u{2014}") || parts.next() != Some(key.host.as_str()) {
            continue;
        }
        let Some(raw) = parts.next().and_then(|s| b64(s.trim()).ok()) else {
            continue;
        };
        if raw.len() > 4
            && raw[..4] == key.key_id[..4.min(key.key_id.len())]
            && ecdsa_p256(&point, note.as_bytes(), &raw[4..])
        {
            return Ok(());
        }
    }
    Err("keine gültige Checkpoint-Signatur".into())
}

/// Rekor: SET, Checkpoint, Inklusionsbeweis und Bindung des Eintrags an Zertifikat/Signatur/Payload.
fn check_rekor(root: &TrustRoot, bundle: &serde_json::Value, p: &Parsed) -> R<u64> {
    let entries = bundle
        .get("verificationMaterial")
        .and_then(|v| v.get("tlogEntries"))
        .and_then(|t| t.as_array())
        .ok_or("tlogEntries fehlen")?;
    if entries.len() != 1 {
        return Err(format!(
            "genau ein Rekor-Eintrag erwartet, gefunden {}",
            entries.len()
        ));
    }
    let e = &entries[0];
    let time = jnum(e, &["integratedTime"])?;
    let key_id = b64(jstr(e, &["logId", "keyId"])?)?;
    let key = root
        .rekor
        .iter()
        .find(|k| k.key_id == key_id && k.valid.contains(time))
        .ok_or("kein vertrauter Rekor-Schlüssel für Log-ID und Zeitpunkt")?;
    if key.key_details != "PKIX_ECDSA_P256_SHA_256" {
        return Err(format!(
            "Rekor-Schlüsseltyp nicht unterstützt: {}",
            key.key_details
        ));
    }
    let (_, point) = spki_point(
        &SubjectPublicKeyInfoOwned::from_der(&key.spki_der)
            .map_err(|e| format!("Schlüssel: {e}"))?,
    )?;

    let body_b64 = jstr(e, &["canonicalizedBody"])?;
    let body = b64(body_b64)?;

    // SET: signiert {body, integratedTime, logID, logIndex} (kanonisches JSON, Schlüssel sortiert).
    let set = b64(jstr(e, &["inclusionPromise", "signedEntryTimestamp"])?)?;
    let signed = format!(
        "{{\"body\":\"{}\",\"integratedTime\":{},\"logID\":\"{}\",\"logIndex\":{}}}",
        body_b64,
        time,
        hex::encode(&key_id),
        jnum(e, &["logIndex"])?
    );
    if !ecdsa_p256(&point, signed.as_bytes(), &set) {
        return Err("SET (signierter Eintragszeitpunkt) ungültig".into());
    }

    let ip = e.get("inclusionProof").ok_or("Inklusionsbeweis fehlt")?;
    let root_hash = b64(jstr(ip, &["rootHash"])?)?;
    let size = jnum(ip, &["treeSize"])?;
    check_checkpoint(
        jstr(ip, &["checkpoint", "envelope"])?,
        key,
        &root_hash,
        size,
    )?;
    let path = ip
        .get("hashes")
        .and_then(|h| h.as_array())
        .ok_or("Beweis ohne hashes")?
        .iter()
        .map(|h| {
            h.as_str()
                .ok_or("hash kein String".to_string())
                .and_then(b64)
        })
        .collect::<R<Vec<_>>>()?;
    let mut leaf = Sha256::new();
    leaf.update([0]);
    leaf.update(&body);
    if !verify_inclusion(
        jnum(ip, &["logIndex"])?,
        size,
        leaf.finalize().into(),
        &path,
        &root_hash,
    ) {
        return Err("Merkle-Inklusionsbeweis ungültig".into());
    }

    // Bindung: Der geloggte Eintrag gehört zu genau diesem Zertifikat, dieser Signatur, diesem Payload.
    let b: serde_json::Value =
        serde_json::from_slice(&body).map_err(|e| format!("Eintrag: {e}"))?;
    let kv = e.get("kindVersion");
    let kind = kv.and_then(|k| k.get("kind")).and_then(|k| k.as_str());
    let ver = kv.and_then(|k| k.get("version")).and_then(|k| k.as_str());
    if kind != Some("dsse")
        || b.get("kind").and_then(|k| k.as_str()) != kind
        || b.get("apiVersion").and_then(|k| k.as_str()) != ver
    {
        return Err("Rekor-Eintrag ist kein passender dsse-Eintrag".into());
    }
    let sig0 = b
        .get("spec")
        .and_then(|s| s.get("signatures"))
        .and_then(|s| s.as_array())
        .and_then(|a| a.first())
        .ok_or("Eintrag ohne Signatur")?;
    let pem = String::from_utf8(b64(jstr(sig0, &["verifier"])?)?).map_err(|_| "PEM kein UTF-8")?;
    let logged_cert = pem::parse(pem).map_err(|e| format!("PEM: {e}"))?;
    if logged_cert.contents() != p.cert_der.as_slice() {
        return Err("Zertifikat im Eintrag ≠ Zertifikat im Bundle".into());
    }
    if b64(jstr(sig0, &["signature"])?)? != p.sig {
        return Err("Signatur im Eintrag ≠ Signatur im Bundle".into());
    }
    let ph = b
        .get("spec")
        .and_then(|s| s.get("payloadHash"))
        .ok_or("payloadHash fehlt")?;
    if jstr(ph, &["algorithm"])? != "sha256"
        || jstr(ph, &["value"])? != hex::encode(Sha256::digest(&p.payload))
    {
        return Err("payloadHash im Eintrag ≠ Payload im Bundle".into());
    }
    Ok(time)
}

/// Prüft das Sigstore-Bundle des Releases `repo`@`tag` (`digest_hex` = Inhalt von `tinfoil.hash`)
/// gegen die Trust-Root (`None` = eingebettete) und vergleicht den signierten SNP-Messwert mit dem
/// des Reports. Nie ein Panic, nie ein `Err`: Fehler stehen im Ergebnis.
pub fn verify_release(
    bundle_json: &str,
    repo: &str,
    tag: &str,
    digest_hex: &str,
    report_measurement_hex: &str,
    trusted_root_json: Option<&str>,
) -> SigstoreVerdict {
    let mut v = SigstoreVerdict::default();
    let root = match load_root(trusted_root_json.unwrap_or(TRUSTED_ROOT_JSON)) {
        Ok(r) => r,
        Err(e) => {
            v.errors.push(e);
            return v;
        }
    };
    let bundle: serde_json::Value = match serde_json::from_str(bundle_json) {
        Ok(b) => b,
        Err(e) => {
            v.errors.push(format!("Bundle nicht lesbar: {e}"));
            return v;
        }
    };
    let parsed = match parse_bundle(&bundle) {
        Ok(p) => p,
        Err(e) => {
            v.errors.push(e);
            return v;
        }
    };
    let note = |r: R<()>, flag: &mut bool, errs: &mut Vec<String>, what: &str| match r {
        Ok(()) => *flag = true,
        Err(e) => errs.push(format!("{what}: {e}")),
    };
    match check_dsse(&parsed, digest_hex) {
        Ok(m) => {
            v.dsse_ok = true;
            v.snp_measurement_hex = m;
        }
        Err(e) => v.errors.push(format!("dsse: {e}")),
    }
    match check_rekor(&root, &bundle, &parsed) {
        Ok(t) => {
            v.rekor_ok = true;
            v.integrated_time = t;
        }
        Err(e) => v.errors.push(format!("rekor: {e}")),
    }
    if v.rekor_ok {
        note(
            check_chain(&root, &parsed.cert, v.integrated_time),
            &mut v.chain_ok,
            &mut v.errors,
            "chain",
        );
    } else {
        v.errors
            .push("chain: übersprungen (kein geprüfter Rekor-Zeitpunkt)".into());
    }
    note(
        check_identity(&parsed.cert, repo, tag),
        &mut v.identity_ok,
        &mut v.errors,
        "identity",
    );
    if v.identity_ok {
        v.release_tag = tag.to_string();
    }
    if v.dsse_ok {
        if v.snp_measurement_hex
            .eq_ignore_ascii_case(report_measurement_hex)
        {
            v.measurement_ok = true;
        } else {
            v.errors
                .push("measurement: Messwert des Reports ≠ signiertes Release".into());
        }
    }
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    fn leaf(n: u8) -> [u8; 32] {
        Sha256::digest([0, n]).into()
    }

    #[test]
    fn inclusion_rejects_index_at_or_beyond_size() {
        // Ein Blatt: Wurzel = Blatthash, leerer Pfad. Index 0 gilt, Index 1 (= size) nicht.
        let l = leaf(1);
        assert!(verify_inclusion(0, 1, l, &[], &l));
        assert!(!verify_inclusion(1, 1, l, &[], &l));
        // Zwei Blätter, Index 2 (= size) mit dem Pfad von Index 0.
        let (a, b) = (leaf(1), leaf(2));
        let root = node_hash(&a, &b);
        assert!(verify_inclusion(0, 2, a, &[b.to_vec()], &root));
        assert!(verify_inclusion(1, 2, b, &[a.to_vec()], &root));
        assert!(!verify_inclusion(2, 2, a, &[b.to_vec()], &root));
        assert!(!verify_inclusion(u64::MAX, 2, a, &[b.to_vec()], &root));
    }
}
