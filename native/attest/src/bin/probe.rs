//! Kollateral holen (Intel PCS / Phala PCCS), Größe und Zeit messen, JSON ablegen.
use dcap_qvl::collateral::CollateralClient;
use std::time::Instant;
#[tokio::main]
async fn main() {
    let a: Vec<String> = std::env::args().collect();
    let rep: serde_json::Value = serde_json::from_slice(&std::fs::read(&a[1]).unwrap()).unwrap();
    let q = hex::decode(rep["attestation"]["evidence"]["quote"].as_str().unwrap()).unwrap();
    for (name, url) in [("pcs", "https://api.trustedservices.intel.com"), ("phala", dcap_qvl::PHALA_PCCS_URL)] {
        let t = Instant::now();
        match CollateralClient::with_default_http(url).unwrap().fetch(&q).await {
            Ok(c) => {
                let j = serde_json::to_string(&c).unwrap();
                println!("{name}: {} Byte, {:?}", j.len(), t.elapsed());
                std::fs::write(format!("{}/collateral_{name}.json", a[2]), j).unwrap();
            }
            Err(e) => println!("{name}: FEHLER {e}"),
        }
    }
}
