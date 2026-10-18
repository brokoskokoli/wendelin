//! SEV-SNP-Prüfung (WP76a) gegen einen aufgezeichneten öffentlichen Tinfoil-Router-Report (Genoa,
//! Stand 2026-10-15) mit Negativfällen je Prüfstufe.
use std::fs;
use wendelin_attest::snp::{self, SnpPolicy, SnpTcb, SnpVerdict};

/// Prüfzeitpunkt: 2026-10-16 12:00 UTC.
const NOW: u64 = 1_792_152_000;

fn fx(n: &str) -> Vec<u8> {
    fs::read(format!("tests/snp/{n}")).unwrap_or_else(|e| panic!("Fixture {n}: {e}"))
}

fn chain(product: &str) -> String {
    String::from_utf8(fx(&format!("amd_{product}_cert_chain.pem"))).unwrap()
}

fn report() -> Vec<u8> {
    fx("tinfoil_report.bin")
}

/// `report_data[0..32]` (SPKI-Hash, am 2026-10-15 per `openssl s_client` gegengeprüft).
fn tls() -> Vec<u8> {
    report()[0x50..0x70].to_vec()
}

/// HPKE-Schlüssel aus `/.well-known/hpke-keys` (KeyConfig: id, KEM, Schlüssel ab Byte 3).
fn hpke() -> Vec<u8> {
    fx("tinfoil_hpke_keys.bin")[3..35].to_vec()
}

fn policy() -> SnpPolicy {
    SnpPolicy {
        min_tcb: SnpTcb {
            bootloader: 9,
            tee: 0,
            snp: 22,
            microcode: 80,
        },
    }
}

fn run(rep: &[u8], vcek: &[u8], chain_pem: &str, now: u64) -> SnpVerdict {
    snp::verify(rep, vcek, chain_pem, now, &policy(), &tls(), &hpke())
}

fn good() -> SnpVerdict {
    run(
        &report(),
        &fx("tinfoil_vcek_genoa.der"),
        &chain("genoa"),
        NOW,
    )
}

/// Alle Stufen außer den genannten müssen grün sein.
fn only_red(v: &SnpVerdict, red: &[&str]) {
    let st = [
        ("report", v.report_ok),
        ("chain", v.chain_ok),
        ("vcek", v.vcek_matches_report),
        ("sig", v.signature_ok),
        ("policy", v.policy_ok),
        ("tls", v.tls_bound),
        ("hpke", v.hpke_bound),
    ];
    for (n, ok) in st {
        assert_eq!(!ok, red.contains(&n), "Stufe {n}: {:?}", v.errors);
    }
    assert!(!v.all_ok());
}

#[test]
fn echter_report_besteht_alle_stufen() {
    let v = good();
    assert!(v.all_ok(), "{:?}", v.errors);
    assert_eq!(v.product.as_deref(), Some("Genoa"));
    let i = v.info.unwrap();
    assert_eq!(i.version, 3);
    assert_eq!(i.vmpl, 0);
    assert_eq!(
        i.reported_tcb,
        SnpTcb {
            bootloader: 10,
            tee: 0,
            snp: 23,
            microcode: 84
        }
    );
    assert_eq!(i.measurement_hex.len(), 96);
    assert!(i.chip_id_hex.starts_with("1af1aa6c1f56037a"));
}

#[test]
fn report_info_liest_felder_ohne_pruefung() {
    let i = snp::report_info(&report()).unwrap();
    assert_eq!(i.chip_id_hex.len(), 128);
    assert!(i.report_data_hex.starts_with("1fb743c49aa79fff"));
    assert!(!i.signed_with_vlek);
    assert!(snp::report_info(&report()[..100]).is_err());
}

#[test]
fn manipulierte_report_data_bricht_signatur() {
    let mut r = report();
    r[0x50] ^= 1;
    let v = run(&r, &fx("tinfoil_vcek_genoa.der"), &chain("genoa"), NOW);
    only_red(&v, &["sig", "tls"]);
}

#[test]
fn manipulierter_messwert_bricht_nur_die_signatur() {
    let mut r = report();
    r[0x90] ^= 1;
    only_red(
        &run(&r, &fx("tinfoil_vcek_genoa.der"), &chain("genoa"), NOW),
        &["sig"],
    );
}

#[test]
fn manipulierte_signatur_ist_rot() {
    let mut r = report();
    r[0x2A0 + 3] ^= 1;
    only_red(
        &run(&r, &fx("tinfoil_vcek_genoa.der"), &chain("genoa"), NOW),
        &["sig"],
    );
    let mut r = report();
    r[0x2A0 + 60] = 1; // obere Bytes von r müssen Null sein
    only_red(
        &run(&r, &fx("tinfoil_vcek_genoa.der"), &chain("genoa"), NOW),
        &["sig"],
    );
}

#[test]
fn falscher_chip_oder_tcb_passt_nicht_zum_vcek() {
    let mut r = report();
    r[0x1A0] ^= 1;
    let v = run(&r, &fx("tinfoil_vcek_genoa.der"), &chain("genoa"), NOW);
    only_red(&v, &["vcek", "sig"]);
    let mut r = report();
    r[0x180 + 7] -= 1; // reported_tcb: Microcode 83
    let v = run(&r, &fx("tinfoil_vcek_genoa.der"), &chain("genoa"), NOW);
    only_red(&v, &["vcek", "sig"]);
}

#[test]
fn kette_anderer_produkte_wird_abgelehnt() {
    let v = run(
        &report(),
        &fx("tinfoil_vcek_genoa.der"),
        &chain("milan"),
        NOW,
    );
    only_red(&v, &["chain"]);
}

#[test]
fn ark_muss_gepinnt_sein() {
    // Selbstsigniertes ARK-Zertifikat anderer Herkunft (Fremdzertifikat) statt der AMD-Wurzel.
    let other = String::from_utf8(
        fs::read("../../packages/wendelin_providers/test/fixtures/tee/redpill_api_cert.pem")
            .unwrap(),
    )
    .unwrap();
    only_red(
        &run(&report(), &fx("tinfoil_vcek_genoa.der"), &other, NOW),
        &["chain"],
    );
    only_red(
        &run(&report(), &fx("tinfoil_vcek_genoa.der"), "", NOW),
        &["chain"],
    );
}

#[test]
fn fehlendes_ark_oder_ask_ist_rot() {
    let c = chain("genoa");
    let blocks: Vec<&str> = c.split_inclusive("-----END CERTIFICATE-----\n").collect();
    assert_eq!(blocks.len(), 2);
    for one in [blocks[0], blocks[1]] {
        only_red(
            &run(&report(), &fx("tinfoil_vcek_genoa.der"), one, NOW),
            &["chain"],
        );
    }
}

#[test]
fn manipuliertes_zertifikat_bricht_die_kette() {
    let mut vcek = fx("tinfoil_vcek_genoa.der");
    let n = vcek.len();
    vcek[n - 5] ^= 1; // Signaturbytes
    let v = run(&report(), &vcek, &chain("genoa"), NOW);
    assert!(!v.chain_ok && !v.all_ok());
    let v = run(&report(), b"kein DER", &chain("genoa"), NOW);
    assert!(!v.all_ok() && !v.errors.is_empty());
}

#[test]
fn zertifikate_muessen_zeitlich_gueltig_sein() {
    only_red(
        &run(
            &report(),
            &fx("tinfoil_vcek_genoa.der"),
            &chain("genoa"),
            1_500_000_000,
        ),
        &["chain"],
    );
    only_red(
        &run(
            &report(),
            &fx("tinfoil_vcek_genoa.der"),
            &chain("genoa"),
            2_700_000_000,
        ),
        &["chain"],
    );
}

#[test]
fn tcb_unter_minimum_verletzt_die_richtlinie() {
    for m in [
        SnpTcb {
            bootloader: 11,
            ..policy().min_tcb
        },
        SnpTcb {
            tee: 1,
            ..policy().min_tcb
        },
        SnpTcb {
            snp: 24,
            ..policy().min_tcb
        },
        SnpTcb {
            microcode: 85,
            ..policy().min_tcb
        },
    ] {
        let p = SnpPolicy { min_tcb: m };
        let v = snp::verify(
            &report(),
            &fx("tinfoil_vcek_genoa.der"),
            &chain("genoa"),
            NOW,
            &p,
            &tls(),
            &hpke(),
        );
        only_red(&v, &["policy"]);
    }
    // genau das Minimum ist erlaubt
    let p = SnpPolicy {
        min_tcb: SnpTcb {
            bootloader: 10,
            tee: 0,
            snp: 23,
            microcode: 84,
        },
    };
    assert!(snp::verify(
        &report(),
        &fx("tinfoil_vcek_genoa.der"),
        &chain("genoa"),
        NOW,
        &p,
        &tls(),
        &hpke()
    )
    .all_ok());
}

#[test]
fn debug_vmpl_und_vlek_verletzen_die_richtlinie() {
    let mut r = report();
    r[0x08 + 2] |= 1 << 3; // Policy-Bit 19: Debug
    let v = run(&r, &fx("tinfoil_vcek_genoa.der"), &chain("genoa"), NOW);
    assert!(!v.policy_ok && !v.all_ok());
    let mut r = report();
    r[0x30] = 1;
    assert!(!run(&r, &fx("tinfoil_vcek_genoa.der"), &chain("genoa"), NOW).policy_ok);
    let mut r = report();
    r[0x48] |= 1 << 2; // signing_key = VLEK
    assert!(!run(&r, &fx("tinfoil_vcek_genoa.der"), &chain("genoa"), NOW).policy_ok);
}

#[test]
fn bindung_an_tls_und_hpke_ist_getrennt() {
    let mut t = tls();
    t[31] ^= 1;
    let v = snp::verify(
        &report(),
        &fx("tinfoil_vcek_genoa.der"),
        &chain("genoa"),
        NOW,
        &policy(),
        &t,
        &hpke(),
    );
    only_red(&v, &["tls"]);
    let mut h = hpke();
    h[0] ^= 1;
    let v = snp::verify(
        &report(),
        &fx("tinfoil_vcek_genoa.der"),
        &chain("genoa"),
        NOW,
        &policy(),
        &tls(),
        &h,
    );
    only_red(&v, &["hpke"]);
    for bad in [vec![], vec![0u8; 31], vec![0u8; 33]] {
        let v = snp::verify(
            &report(),
            &fx("tinfoil_vcek_genoa.der"),
            &chain("genoa"),
            NOW,
            &policy(),
            &bad,
            &bad,
        );
        only_red(&v, &["tls", "hpke"]);
    }
}

#[test]
fn unlesbare_reports_werden_abgelehnt() {
    let ok = fx("tinfoil_vcek_genoa.der");
    for r in [
        vec![],
        report()[..1183].to_vec(),
        [report(), vec![0]].concat(),
    ] {
        let v = run(&r, &ok, &chain("genoa"), NOW);
        assert!(!v.report_ok && !v.all_ok() && v.errors.len() == 1);
    }
    let mut r = report();
    r[0] = 9; // Version
    assert!(!run(&r, &ok, &chain("genoa"), NOW).report_ok);
    let mut r = report();
    r[0x34] = 2; // Signaturverfahren
    assert!(!run(&r, &ok, &chain("genoa"), NOW).report_ok);
}

#[test]
fn gepinnte_arks_und_asks_aller_produkte_verifizieren() {
    // Fremder VCEK: Pin, ARK-Selbstsignatur und ASK-Signatur der Kette sind in Ordnung,
    // erst die VCEK-Signatur scheitert.
    for p in ["genoa", "milan"] {
        let v = run(&report(), &fx("tinfoil_vcek_genoa.der"), &chain(p), NOW);
        let e = v.errors.join(";");
        assert_eq!(
            e.contains("VCEK: Signatur ungültig"),
            p != "genoa",
            "{p}: {e}"
        );
        assert!(
            !e.contains("nicht gepinnt") && !e.contains("ARK:") && !e.contains("ASK:"),
            "{p}: {e}"
        );
    }
}

// --- Synthetische Kette (ARK/ASK/VCEK mit AMD-artigen Erweiterungen, Schlüssel verworfen) ---
// Erzeugung: tests/snp/synth/README.md. Die Kette ist nicht gepinnt; die Tests übergeben ihren
// eigenen Pin (`verify_with_pins`) oder den echten (dann muss "nicht gepinnt" rot werden).

const SYN_PIN: [(&str, &str); 1] = [(
    "Synth",
    "27c9568c3519f9c15bc8e3628b6de4d878f8f897c00eb84654e42f0bcab020fa",
)];

fn syn(rep: &str, vcek: &str) -> SnpVerdict {
    syn_pins(rep, vcek, &SYN_PIN)
}

fn syn_pins(rep: &str, vcek: &str, pins: &[(&'static str, &'static str)]) -> SnpVerdict {
    let r = fx(&format!("synth_report_{rep}.bin"));
    let tls = r[0x50..0x70].to_vec();
    let hpke = r[0x70..0x90].to_vec();
    let chain = String::from_utf8(fx("synth_chain.pem")).unwrap();
    snp::verify_with_pins(&r, &fx(vcek), &chain, NOW, &policy(), &tls, &hpke, pins)
}

#[test]
fn synthetische_kette_besteht_mit_eigenem_pin() {
    let v = syn("ok", "synth_vcek.der");
    assert!(v.all_ok(), "{:?}", v.errors);
    assert_eq!(v.product.as_deref(), Some("Synth"));
}

#[test]
fn ark_pin_ist_die_einzige_huerde_der_kette() {
    // Gleiche, sonst gültige Kette mit den echten AMD-Pins: nur "nicht gepinnt".
    let v = syn_pins("ok", "synth_vcek.der", &snp::PINNED_ARKS);
    only_red(&v, &["chain"]);
    assert!(
        v.errors.iter().any(|e| e.contains("nicht gepinnt")),
        "{:?}",
        v.errors
    );
    assert!(v.product.is_none());
}

#[test]
fn abweichende_pss_parameter_werden_abgelehnt() {
    // VCEK mit Salt 32 statt 48 vom (echten) ASK signiert: Signatur wäre gültig, Parameter nicht.
    let v = syn("ok", "synth_vcek_salt32.der");
    only_red(&v, &["chain"]);
    assert!(
        v.errors.iter().any(|e| e.contains("PSS-Parameter")),
        "{:?}",
        v.errors
    );
}

#[test]
fn richtlinie_einzeln_bei_gueltiger_signatur() {
    for (name, msg) in [
        ("debug", "Debug"),
        ("migrate", "MIGRATE_MA"),
        ("vlek", "VCEK"),
        ("vmpl1", "VMPL"),
        ("provisional", "vorläufig"),
    ] {
        let v = syn(name, "synth_vcek.der");
        assert!(v.signature_ok && v.chain_ok, "{name}: {:?}", v.errors);
        only_red(&v, &["policy"]);
        assert!(
            v.errors.iter().any(|e| e.contains(msg)),
            "{name}: {:?}",
            v.errors
        );
    }
}

#[test]
fn tee_byte_abweichend_vom_vcek_ist_nur_vcek_rot() {
    let v = syn("tee1", "synth_vcek.der");
    only_red(&v, &["vcek"]);
    assert!(v.signature_ok && v.chain_ok);
}
