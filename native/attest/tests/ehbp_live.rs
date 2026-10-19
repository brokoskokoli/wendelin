//! Live-Test gegen den Tinfoil-Router (EHBP, WP76c). `#[ignore]`: braucht `TINFOIL_API_KEY`.
//!
//! ```text
//! set -a; . ~/.wendelin-live.env; set +a
//! cargo test -p wendelin_attest --test ehbp_live -- --ignored
//! ```
//!
//! Höchstens zwei Anfragen (Streaming und ohne), kleines Modell, 16 Token. `curl` ist der HTTP-Client
//! (das Crate hat keinen); der Key geht über stdin an curl, nie in Argumente, Ausgabe oder Fehlertexte.
//! Die Attestierung des Reports gehört zu WP76d: hier wird `report_data` aus dem Schlüssel der
//! KeyConfig selbst gebildet, geprüft wird das EHBP-Protokoll gegen den echten Dienst.
use std::io::Write;
use std::process::{Command, Stdio};
use wendelin_attest::ehbp::{begin_request, bind_key_config};

const HOST: &str = "https://inference.tinfoil.sh";
const MODEL: &str = "gemma4-31b";

fn curl(args: &[&str], stdin: &str) -> Vec<u8> {
    let mut c = Command::new("curl")
        .args(["-sS", "--max-time", "60", "-K", "-"])
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("curl");
    c.stdin.take().unwrap().write_all(stdin.as_bytes()).unwrap();
    let out = c.wait_with_output().unwrap();
    assert!(out.status.success(), "curl fehlgeschlagen");
    out.stdout
}

fn tmp(name: &str) -> String {
    std::env::temp_dir()
        .join(format!("wendelin-ehbp-live-{name}"))
        .to_string_lossy()
        .into()
}

fn exchange(stream: bool) -> String {
    let key = std::env::var("TINFOIL_API_KEY").expect("TINFOIL_API_KEY (~/.wendelin-live.env)");
    let cfg = curl(
        &[
            "-H",
            "accept: application/ohttp-keys",
            &format!("{HOST}/.well-known/hpke-keys"),
        ],
        "",
    );
    let mut rd = vec![0u8; 32];
    rd.extend_from_slice(&cfg[3..35]);
    bind_key_config(&cfg, &rd).expect("KeyConfig des Dienstes");
    let body = format!(
        r#"{{"model":"{MODEL}","messages":[{{"role":"user","content":"Sag nur: Hallo"}}],"max_tokens":16,"stream":{stream}}}"#
    );
    let (sealed, session) = begin_request(&cfg, &rd, body.as_bytes()).unwrap();
    let (reqf, hdrf) = (tmp(&format!("req-{stream}")), tmp(&format!("hdr-{stream}")));
    std::fs::write(&reqf, &sealed.body).unwrap();
    let config = format!(
        "header = \"Authorization: Bearer {key}\"\nheader = \"Content-Type: application/json\"\nheader = \"Ehbp-Encapsulated-Key: {}\"\n",
        hex::encode(&sealed.encapsulated_key)
    );
    let resp = curl(
        &[
            "-X",
            "POST",
            "--data-binary",
            &format!("@{reqf}"),
            "-D",
            &hdrf,
            &format!("{HOST}/v1/chat/completions"),
        ],
        &config,
    );
    let headers = std::fs::read_to_string(&hdrf).unwrap().to_lowercase();
    let nonce = headers
        .lines()
        .find_map(|l| l.strip_prefix("ehbp-response-nonce:"))
        .expect("Ehbp-Response-Nonce fehlt (Antwort nicht verschlüsselt)")
        .trim()
        .to_string();
    let mut dec = session
        .response_decoder(&hex::decode(nonce).unwrap())
        .unwrap();
    let mut plain = Vec::new();
    for c in resp.chunks(1024) {
        plain.extend(dec.push(c).expect("Antwort authentisch"));
    }
    dec.finish().expect("Antwort vollständig");
    String::from_utf8(plain).unwrap()
}

#[test]
#[ignore = "live: braucht TINFOIL_API_KEY und Netz"]
fn live_non_streaming() {
    let text = exchange(false);
    let v: serde_json::Value = serde_json::from_str(&text).expect("JSON");
    assert!(v["choices"][0]["message"].is_object());
}

#[test]
#[ignore = "live: braucht TINFOIL_API_KEY und Netz"]
fn live_streaming() {
    let text = exchange(true);
    assert!(text.contains("data: {") && text.contains("data: [DONE]"));
}
