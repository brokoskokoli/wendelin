//! SPKI-Hash eines X.509-Zertifikats (DER) für das TLS-Pinning.
use der::{Decode, Encode};
use sha2::{Digest, Sha256};
use x509_cert::Certificate;

/// SHA-256 über die DER-Kodierung von `SubjectPublicKeyInfo`.
pub fn spki_sha256(cert_der: &[u8]) -> Result<[u8; 32], String> {
    let cert = Certificate::from_der(cert_der).map_err(|e| format!("Zertifikat: {e}"))?;
    let spki = cert
        .tbs_certificate()
        .subject_public_key_info()
        .to_der()
        .map_err(|e| format!("SPKI: {e}"))?;
    Ok(Sha256::digest(spki).into())
}

/// CRL-Verteilpunkt (erste URL) eines Zertifikats, falls vorhanden.
pub fn crl_url(cert_der: &[u8]) -> Result<Option<String>, String> {
    use x509_cert::ext::pkix::{
        name::DistributionPointName, name::GeneralName, CrlDistributionPoints,
    };
    let cert = Certificate::from_der(cert_der).map_err(|e| format!("Zertifikat: {e}"))?;
    let Some(exts) = cert.tbs_certificate().extensions() else {
        return Ok(None);
    };
    for ext in exts {
        if ext.extn_id.to_string() != "2.5.29.31" {
            continue;
        }
        let pts = CrlDistributionPoints::from_der(ext.extn_value.as_bytes())
            .map_err(|e| format!("CRL-Punkte: {e}"))?;
        for p in pts.0.iter() {
            if let Some(DistributionPointName::FullName(names)) = &p.distribution_point {
                for n in names {
                    if let GeneralName::UniformResourceIdentifier(u) = n {
                        return Ok(Some(u.to_string()));
                    }
                }
            }
        }
    }
    Ok(None)
}
