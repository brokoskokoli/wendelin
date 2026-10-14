//! Kanonisierung für ACI: JCS unter den Einschränkungen des Protokolls (ASCII-Schlüssel, nur ganze
//! Zahlen), dann ist JCS gleich kompaktes JSON mit sortierten Schlüsseln. Wie im Gateway wird ein
//! Wert, der unter vollem RFC 8785 anders kanonisiert würde, abgewiesen statt abweichend gehasht.
//! Quelle: Dstack-TEE/private-ai-gateway @ 24a31ff, `crates/aci-protocol/src/digest.rs:33-64`
//! (`jcs_bytes`, `JcsError`), `spec/aci.md` Anhang A.
use serde_json::Value;

/// Kanonische Bytes eines JSON-Werts; Fehler bei Fließkommazahlen und Nicht-ASCII-Schlüsseln.
pub fn canon(v: &Value) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    write(v, &mut out)?;
    Ok(out)
}

fn write(v: &Value, o: &mut Vec<u8>) -> Result<(), String> {
    match v {
        Value::Object(m) => {
            let mut keys: Vec<&String> = m.keys().collect();
            keys.sort();
            o.push(b'{');
            for (i, k) in keys.iter().enumerate() {
                if !k.is_ascii() {
                    return Err(format!("Nicht-ASCII-Feldname {k:?} in einem ACI-Dokument"));
                }
                if i > 0 {
                    o.push(b',');
                }
                o.extend(serde_json::to_vec(k).map_err(|e| e.to_string())?);
                o.push(b':');
                write(&m[*k], o)?;
            }
            o.push(b'}');
        }
        Value::Array(a) => {
            o.push(b'[');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    o.push(b',');
                }
                write(x, o)?;
            }
            o.push(b']');
        }
        Value::Number(n) if !n.is_i64() && !n.is_u64() => {
            return Err(format!("Nicht-ganze Zahl {n} in einem ACI-Dokument"));
        }
        other => o.extend(serde_json::to_vec(other).map_err(|e| e.to_string())?),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sorts_keys_and_drops_whitespace() {
        let v: Value =
            serde_json::from_str(r#"{ "b": [1, {"z":null,"a":"x"}], "a": true }"#).unwrap();
        assert_eq!(
            canon(&v).unwrap(),
            br#"{"a":true,"b":[1,{"a":"x","z":null}]}"#
        );
    }

    #[test]
    fn rejects_floats_and_non_ascii_names() {
        let f: Value = serde_json::from_str(r#"{"a":1.5}"#).unwrap();
        assert!(canon(&f).unwrap_err().contains("Nicht-ganze Zahl"));
        let n: Value = serde_json::from_str(r#"{"ä":1}"#).unwrap();
        assert!(canon(&n).unwrap_err().contains("Nicht-ASCII"));
        let big: Value = serde_json::from_str(r#"{"a":18446744073709551615,"b":-5}"#).unwrap();
        assert!(canon(&big).is_ok());
    }
}
