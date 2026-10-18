//! Wendelin-Prüfmodul für TEE-Attestierungen (WP47, Weg A, ADR 0014).
//!
//! Reine, netzfreie Funktionen: Quote-Prüfung (`dcap-qvl`), ACI-Bericht und Quittung, Ed25519,
//! SHA-2, SPKI-Hash. Das Kollateral holt Dart mit dem vorhandenen HTTP-Stack und reicht es hinein.
//! `api` ist die Schnittstelle für `flutter_rust_bridge`; `frb_generated.rs` ist erzeugt und eingecheckt.
pub mod api;
pub mod collateral;
pub mod e2ee;
mod frb_generated;
pub mod jcs;
pub mod near_e2ee;
pub mod quote;
pub mod report;
pub mod snp;
pub mod spki;
