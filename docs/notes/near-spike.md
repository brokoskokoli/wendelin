# NEAR AI Cloud Spike (Stand 2026-10-15): Teil 1 belegt, Teil 2 blockiert (keine Credits)

Skripte und Rohdaten: `<lokales Scratchpad>/near-spike/` (`nearlib.py` = fertiger E2EE-Client, `att.py` = Quote-Prüfung, `att_*.json` = Attestierungen). Key nie ausgegeben.
Markierung **[?]** = nicht belegt.

## Ergebnis in einem Satz
Der Key ist gültig, aber die Organisation hat **kein Spending-Limit/keine Credits**: jeder `POST /v1/chat/completions` liefert **HTTP 402 `no_limit_configured`** ("No spending limit configured. Please contact support to set up credits."). Damit sind die Punkte 3, 4 (Quittung), 5 (Qualität/Latenz/Kosten) und die Fehlerbilder aus 6 **nicht gemessen**. Attestierung (Punkt 2) und Modellliste (Punkt 1) sind vollständig belegt, da kostenlos. Verbraucht: 1 Chat-Request (abgelehnt, 0 Kosten), sonst nur GETs und 3 Attestierungsabrufe. Zum Weitermachen: auf `cloud.near.ai` Credits kaufen bzw. Limit setzen (Maintainer), dann `t1.py` und Evals laufen lassen (Client ist vorbereitet).

## 1. Key und Modelle
- `GET /v1/models` mit Key: 200, 58 Modelle. Eigene NEAR-Flotte (`owned_by: nearai`, E2EE-fähig laut Doku) mit Tools:

| Modell | USD/Mio. ein/aus | Kontext / max. Ausgabe | Features |
|---|---|---|---|
| `z-ai/glm-5.3-flash` | 0,08 / 0,50 | 1 M / 1 M | tools, structured_outputs, reasoning, json_mode |
| `Qwen/Qwen3.6-35B-A3B-FP8` | 0,17 / 1,10 | 262K / 8192 | tools, json_mode, structured_outputs, logprobs, reasoning |
| `Qwen/Qwen3.8-27B` | 0,04 / 1,35 | 262K / 65536 | tools, structured_outputs, reasoning |

  `Qwen3-VL-30B-A3B-Instruct` (ohne Tools), Embedding, Reranker, Whisper, FLUX ebenfalls NEAR-eigen, für Wendelin nicht relevant (Whisper als E2EE-STT wäre ein Seitenthema **[?]**). Alle größeren Modelle (Kimi, Qwen3.5-397B, DeepSeek V3.2) sind `attested 3p` (Chutes), nicht E2EE zum Modell. Kein größeres E2EE-Modell als GLM-5.3-flash / Qwen3.6-35B verfügbar. Vergleich Phala (aus `evals/profiles/phala-tee-small.json`): GLM-5.3-flash dort 0,15 / 0,50, Qwen3.8-27B 0,20 / 2,50. NEAR ist bei GLM und Qwen3.8 billiger.
- Ob die Tools-Fähigkeit mit E2EE tatsächlich funktioniert: **[?]** nicht messbar (402).

## 2. Attestierung (belegt, für alle 3 Modelle abgerufen)
`GET /v1/attestation/report?model=…&provider=near&signing_algo=ed25519&nonce=<32 B hex>&include_tls_fingerprint=false`, Header `x-no-aliasing: true`, Key nötig, ohne Credits abrufbar (200, ca. 310-350 KB je Antwort).
- Struktur: `gateway_attestation` (eigene CVM) und `model_attestations[]` (hier je 1 Kandidat): `intel_quote` (hex, TDX v4, 5006/5010 Byte), `signing_public_key`/`signing_address` (Ed25519, 32 Byte), `request_nonce`, `event_log`, `info.tcb_info` (mrtd, rtmr0-3, `compose_hash`, `app_compose`, `os_image_hash`), `nvidia_payload` (8 H100/Hopper-Evidenzen + Nonce), `compose_manager_attestation` (eigene Quote über Container-Aktionsprotokoll, 186 Aktionen, Image-Digests), `ohttp_attestation`.
- **Bindung des E2EE-Schlüssels (selbst geprüft):** `report_data` (64 B) im Quote = `signing_public_key` (32 B) || `nonce` (32 B). Gilt für Gateway und Modell, bei allen 3 Modellen `True` (`att.py`). Der Verschlüsselungsschlüssel ist der Ed25519-Signaturschlüssel, per ed25519→x25519 konvertiert. Kein TLS-SPKI im Modus `include_tls_fingerprint=false`.
- `MRCONFIGID` = `0x01 || SHA256(app_compose)` und `compose_hash` stimmen überein (True); RTMR3 im Quote = `info.tcb_info.rtmr3` (True); MRTD identisch. TD_ATTRIBUTES `0x0000001000000000` (Bit 28 SEPT_VE_DISABLE, Debug-Bit 0 nicht gesetzt).
- **dcap-qvl** (Python-Binding, Intels PCS/Phala-PCCS): Modell-Quote `UpToDate`, keine Advisories. **Gateway-Quote `OutOfDate`** (INTEL-SA-01192, -01245, -01312, -01313): Policy muss TCB-Status ausdrücklich behandeln (Phala-Pipeline verlangt vermutlich UpToDate/SWHardeningNeeded **[?]**). Für das E2EE-Geheimnis zählt nur die Modell-Quote; das Gateway sieht nur Chiffrat und Metadaten.
- **NVIDIA NRAS:** `POST https://nras.attestation.nvidia.com/v3/attest/gpu` mit `nvidia_payload` unverändert: 200, JWT, `x-nvidia-overall-att-result: true`, `eat_nonce` = unsere Nonce. Die GPU-Evidenz ist nur über dieselbe Nonce an die TDX-Quote gebunden (nicht über `report_data`-Hash) **[?]** ob mehr Bindung geprüft werden sollte.
- Gleich wie Phala: dstack/TDX, `dcap-qvl`, Kollateral, NRAS, `compose_hash`/MRCONFIGID, RTMR3-Ereignislog-Replay, Nonce in `report_data`. Anders: `report_data`-Layout (Schlüssel||Nonce statt Phala-Format), mehrere Modell-Kandidaten, zusätzlich Gateway-Bericht, Compose-Manager-Quote, Allowlist für Compose-Hashes (Modell-Compose je Modell verschieden: GLM `55db164f…`, beide Qwen `d4c89033…`; Gateway `4abb5557…`; es gibt keine offizielle Allowlist, siehe Risiken). Image-Provenance (Sigstore) ist eine getrennte Policy.

## 3. E2EE-Rundlauf (nicht ausgeführt)
Client `nearlib.py` ist fertig (Ed25519-Identität, X25519/HKDF(`ed25519_encryption`)/XChaCha20-Poly1305, Verschlüsselung von `messages[].content`, `tools[].function.{name,description,parameters}`, `tool_choice.function.name`, `tool_calls`, Header inkl. `X-Encrypt-All-Fields`). Offline geprüft: Verschlüsselung → simulierter Server entschlüsselt, und Server → Client Rundlauf, beides korrekt. Streaming (SSE-Chunk-Entschlüsselung) und Wire-Prüfung auf Hex-Felder sind im Skript vorgesehen, aber nicht gelaufen. **Alle Wire-/Tool-Aussagen bleiben Doku-/Code-Lesung (`e2ee-chat-completions.mdx`, `encryption.rs`), keine Messung.**

## 4. Quittung/Signatur (aus Doku, nicht gemessen)
`GET /v1/signature/<chat_id>?signing_algo=ed25519`; `provider_tee`: Text `MODEL_ID:req_hash:resp_hash`, vom Modell-Schlüssel signiert; `gateway`: `req_hash:resp_hash`. **Gestreamte Antworten signiert standardmäßig das Gateway** (es entfernt Usage-Daten pro Chunk), ebenso bei Alias-Auflösung und Responses API; die Signatur deckt die exakt empfangenen Bytes inkl. Stream-Rahmen ab (`response-signatures.mdx:51`). Wendelin streamt immer, also ist eine Modell-TEE-Quittung bei Streaming vermutlich **nicht** erreichbar **[?]**; ob Hash über Klartext oder Chiffrat bildet, bleibt offen (vermutlich die Chiffrat-Bytes, da der Proxy die Bytes hasht, **[?]**). Doku warnt selbst: Kette Modell-Gateway-Endantwort nicht lückenlos gebunden, Instanzen eines Modells teilen den Schlüssel.

## 5. Deutsch/Tool-Qualität, Latenz, Kosten
Nicht gemessen. Vorbereitet: 7 Fälle (Kalender Tauchen morgen 10, Zahnarzt Freitag halb drei, Timer 12 Min Nudeln, Taschenlampe an, Wecker halb sieben, Rückfrage bei „Trag mir einen Termin ein“, Hauptstadt von Australien) aus `evals/cases/de.yaml`. Geschätzte Kosten gesamt unter 0,01 USD. Hinweis: Evals haben keinen Taschenlampenfall; er wäre neu zu schreiben.

## 6. Limits und Fehlerbilder
- Belegt: ohne Spending-Limit HTTP 402 `no_limit_configured` (Antwortzeit 0,4 s, `x-request-id` gesetzt). `/v1/users/me` und `/v1/organizations` mit API-Key: 401 (nur Session-Token).
- Preise siehe Tabelle. Rate Limits, falscher Schlüssel, unverschlüsselt trotz Header: **[?]** nicht gemessen. Aus Doku: Attestierungsabruf kostet nichts und zählt nicht gegen die Nutzung.

## Implementierungsvorschlag (aus Recherche + Attestierungsbefund)
- **WP A, Krypto in `native/attest` (ca. 4 h):** `chacha20poly1305` (XChaCha), `ed25519-dalek` `to_montgomery`, `x25519-dalek`/`hkdf` vorhanden; Hex-Wire; eigene Testvektoren mit `nearlib.py` erzeugen.
- **WP B, `NearVerifier` (ca. 5 h):** Quote-Parsing/`dcap-qvl`/NRAS wiederverwenden; neu: `report_data = key||nonce`, Kandidatenwahl, Gateway-Quote optional (OutOfDate tolerieren, wenn nur Metadaten), RTMR3-Replay (falls bei Phala nicht vorhanden **[?]**), Compose-Hash-Allowlist als Konfiguration.
- **WP C, Dart-Codec + Adapter (ca. 4 h):** `NearE2eeCodec` für Nachrichten/Tools/`tool_calls`/SSE-Deltas, Provider-Profil, Integration in die Router-/Cost-Logik, Evals-Profil `near-tee`.
- **WP D, Quittung (optional):** Gateway-Signatur akzeptieren (Streaming), Chiffrat-Hash.
- Gesamt ca. 1,5-2 Tage, wie Recherche; Attestierungsteil durch den Spike bestätigt.
- Risiken: (1) Protokoll jung, nur Doku/Code spezifiziert, keine AAD, kein Replay-Schutz; (2) Streaming-Quittung nur Gateway (**[?]**); (3) keine offizielle Compose-Allowlist, Updates der Flotte brechen Pinning; (4) nur kleine/mittlere Modelle (GLM-5.3-flash, Qwen 27-35B) als E2EE; (5) Konto/Credits/Zahlungsweg und Rate Limits ungeklärt; (6) Gateway-TCB aktuell OutOfDate.

## Empfehlung
**Vorläufig: ja, aber erst nach einem Bezahl-Smoketest.** Technisch deckt die Attestierung (Schlüssel an `report_data` gebunden, gleiche TDX/NRAS-Familie) alles ab, was Phala-Wiederverwendung verspricht, und NEAR schließt mit `X-Encrypt-All-Fields` die Tool-Lücke. Da Tool-Treue, Deutsch und Streaming-Wire nicht gemessen sind, vor einem WP: Credits (ca. 2-5 USD reichen) einrichten, dann die vorbereiteten 3 Tests (Rundlauf, Streaming-Wire, 7 Eval-Fälle, Signaturabruf) in ca. 15 Requests nachholen. Standardmodell-Kandidat: `z-ai/glm-5.3-flash` (günstigster Output, 1 M Kontext, bei Phala bereits im Profil, daher direkter Qualitätsvergleich möglich); Fallback `Qwen/Qwen3.8-27B`. Das ist eine Annahme, keine Messung.
