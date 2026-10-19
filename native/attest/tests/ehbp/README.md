# EHBP-Konformanzvektoren (eingefroren)

`crypto.json` ist unverändert `test-vectors/conformance/crypto.json` aus
https://github.com/tinfoilsh/encrypted-http-body-protocol, Tag `v0.4.1`,
Commit `6de58891fd9166508047ec3f88e5cc4796d9932b`. Lizenz des Projekts: MIT, Copyright (c) 2025
Tinfoil, Inc. Die Datei enthält ausschließlich synthetische Testdaten.

35 Einträge: 25 Antwort-/Ableitungsvektoren (`derive_keys`, `decrypt_response`,
`decrypt_response_streaming`, `compute_nonce`) werden von `src/ehbp_tests.rs` ausgeführt; die 10
`token_roundtrip`-Vektoren betreffen das Sitzungs-Wiederherstellungs-Token der Referenz und gehören
nicht zu Wendelin (es gibt kein Token).
