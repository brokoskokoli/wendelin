# Phala (RedPill/TEE) vs. Claude: Latenz vor dem ersten Token

Stand: main 3e845fe, Messung 2026-10-16 vom Mac (WLAN/Heim-Internet), Rohdaten und Skripte unter
`<lokales Scratchpad>/latency/`
(`measure.dart`, `nras.dart`, `nras2.dart`, `rs/` = Rust-Zeitmessung). Kein Repo-Code geändert.

## 1. Kurzfassung

- Kalt (erste Frage nach Engine-Start): Phala **TTFT ~4,0 s** (Median von 8 Läufen: 3,6 bis 4,2 s, 2 Ausreißer 5,7 und 9,5 s) gegen Claude Haiku **~1,1 s**.
- Davon sind **~2,3 s unsere Vorarbeit**, die vor dem Senden blockiert: Attestierungsabruf (~1,1 s) und danach **sequentiell** der GPU-Evidenz-Abruf (~1,15 s). Der Rest (~1,7 s) ist die Chat-Anfrage selbst.
- Warm (Sitzung gültig, Verbindung offen): Phala **~1,7 s** gegen Claude ~1,1 s. Die ~0,6 s Rest sind Anbieter/Gateway (E2EE im TEE); unsere Client-Krypto ist vernachlässigbar (<1 ms je Feld).
- Hauptursache der "spürbar später"-Beobachtung: **kalte Attestierung + GPU-Evidenz-Abruf vor der ersten Anfrage, und das Overlay (eigene Flutter-Engine) wärmt nicht vor.** Die Haupt-App wärmt beim Start vor (`main_screen.dart:92`), das Overlay (`assistantMain`, `main.dart:42`) nicht.
- Sicherheitsnotwendig vor dem Senden ist nur: geprüfte Attestierung (Quote, Keyset, TLS-SPKI-Pin, E2EE-Schlüssel). Der **GPU-Abruf im Modus Aus ist es nicht** (nur lokale Nonce-Bindung, keine NVIDIA-Prüfung), und er lässt sich parallel legen oder vorwärmen.

## 2. Messwerte

Prompt: "Nenne drei deutsche Städte." (System: "Antworte kurz auf Deutsch."), max_tokens 30, Streaming.

| Variante | Läufe TTFT (s) | Gesamt (s) | Bemerkung |
|---|---|---|---|
| (a) Claude `claude-haiku-5-5` (Adapter, effort low) | 1,07 / 1,58 / 0,67 | = TTFT + 0,01 bis 0,07 | Median 1,07 |
| (b) Phala roh, Klartext, curl (`gemma-4-31b-it`) | TTFB 1,52 / 1,45 / 1,48 | 1,71 / 1,70 / 1,68 | TTFB enthält DNS+TCP+TLS = 0,51 s, Server-TTFT also ~0,97 s |
| (c) Phala E2EE, **warm** (Sitzung+Verbindung da) | 1,81 / 1,61 / (11,96 Ausreißer) | 2,00 / 1,76 / 12,09 | Median ~1,7 |
| (c') Phala E2EE, **kalt** (Attestierung + GPU-lokal + Chat) | 3,64 / 3,85 / 3,92 / 3,99 / 4,00 / 4,21 / 5,74 / 9,52 | TTFT + 0,05 bis 0,25 | Median ~4,0 |
| Quittung grün (Abstand zu Done) | | +2,5 bis 3,0 s | Receipt-GET 0,15 bis 0,66 s, danach Upstream-Session-GET ~1,9 bis 2,0 s |

Ausreißer: 2 von 14 Phala-Läufen hatten 9,5 und 12 s TTFT (Gateway/Modell, nicht reproduzierbar), bei Claude 0 von 3.
Die Stichprobe ist klein (je 3 bis 8); die Aussage "kalt ~4 s, warm ~1,7 s" ist stabil, Bruchteile nicht.

### Einzelschritte (Netz in ms, gemessen mit Zeitwrapper um die Pinned-Clients)

| Schritt | Zeit | Anmerkung |
|---|---|---|
| `GET /v1/aci/attestation` (frische TLS-Verbindung, Client "messend") | 0,75 bis 1,06 s Header + 0,15 s Body = **~1,0 bis 1,2 s** | neue Verbindung, `Connection: close` |
| Quote-Prüfung (Rust `verify_quote`, Host, release) | 2,4 bis 3,4 ms | Phone mit `opt-level=z` grob 10x = 20 bis 40 ms |
| Intel PCS Kollateral (4 GETs sequentiell: pckcrl 0,80 / tcb 0,51 / qe 0,47 / root-CRL 0,32) | **2,1 s** (curl, je neue Verbindung) | nur bei Cache-Miss; `nextUpdate` heute +30 Tage |
| `build_collateral` / `collateral_request` | 0,5 ms / 0,9 ms | |
| `GET /v1/attestation/report` (GPU-Evidenz, **lokale** Nonce-Bindung) | 0,80 bis 0,85 s Header + 0,3 s Body = **~1,1 bis 1,2 s** | läuft in JEDEM Modus, sequentiell NACH der Attestierung |
| NRAS `POST /v3/attest/gpu` (nur Modus "Vorher"/"Nachher") | 0,18 bis 0,20 s | siehe Befund 6: antwortet derzeit 400 |
| E2EE je Feld, Rust (Host) | 0,07 ms | Dart-Referenz (nur Test/Demo) 4,3 ms |
| `GET /v1/aci/receipts/<id>` (erzwingender Client, offene Verbindung) | 0,15 s (warm), 0,64 s (nach neuer Verbindung) | |
| `GET /v1/aci/sessions/<id>` (messender Client, neue Verbindung) | 0,8 s Header + ~1,1 s Body = **~1,9 bis 2,0 s** | `session_id` war in 2 Läufen verschieden, Cache-Treffer unklar |

Bilanz kalt: 1,1 (Attestierung) + 1,15 (GPU-lokal) + ~1,7 (Chat inkl. ggf. TLS) = ~4,0 s. Passt zur Messung.

## 3. Codepfad (Datei:Zeile)

### Claude (Anthropic)
1. `AgentRunner` -> `AnthropicMessagesAdapter.chat`: ein einziger HTTPS-POST (Stream), Verbindung des `http.Client` bleibt offen (Dart-`HttpClient` Standard-idleTimeout 15 s). Kein Vorlauf, keine Nachprüfung.

### Phala (`ProviderFactory` `provider_factory.dart:196-262`)
Drei Clients pro Profil, alle auf einem `TlsPinGate`:
- "messend" (`build(gate, enforce:false)`, `provider_factory.dart:240`): für Attestierung/Upstream-Session; setzt `Connection: close` und verwirft die Verbindung bei jedem Request (`tls_pinned_client.dart:90-92`).
- "erzwingend" (`enforce:true`): Chat und Quittung; Verbindung wird erst nach SPKI-Vergleich mit dem Pin freigegeben (`tls_pinned_client.dart:63-80`). Keep-Alive ja, Standard-idleTimeout 15 s (`HttpClient()` `tls_pinned_client.dart:51`, kein Override).
- GPU-Client: `client ?? defaultHttpClient()` (`provider_factory.dart:254-257`), eigene Verbindung, ohne Pin (nur öffentliche Evidenz, ohne Key).

Reihenfolge je Anfrage (`AttestedProvider.chat`, `attested_provider.dart:235`):

| # | Schritt | Netz | Blockiert Senden? | Stelle |
|---|---|---|---|---|
| 1 | Sitzung gültig? sonst attestieren (Einzelflug via `_attesting`) | `GET aci/attestation?nonce` (messender Client, neue TLS) | ja | `_prepareSession` :339, `_doAttest` |
| 1a | Kollateral: Dateicache bis `nextUpdate`, erneuert ab < 3 Tage Restlaufzeit; bei Miss 4 sequentielle PCS-GETs | Intel PCS | ja (nur bei Miss/Ablauf) | `rust_attestation_crypto.dart:82-100`, `pcs_collateral_client.dart:32-52`, Aufruf `phala_verifier.dart:202` |
| 1b | Quote (Rust), TCB, Nonce-Bindung, Keyset-Digest/-Endorsement, Freshness, Eventlog, Compose, Provenance, TLS-SPKI, E2EE-Schlüssel; Pin speichern | lokal | ja | `phala_verifier.dart:200-239` |
| 2 | GPU-Gate `before`: Evidenz holen + Nonce prüfen, **einmal je Modell und Sitzung, in jedem Modus**; Modus "Vorher" zusätzlich NRAS-POST (je Modell gecacht bis Neu-Attestierung) | `GET attestation/report` (+ `POST` NRAS) | ja | `gpu_gate.dart:61-85`, `gpu_attestation.dart:107-113` |
| 3 | E2EE: Anfragefelder verschlüsseln (Rust-FFI synchron je Feld), Antwort-Deltas je Feld entschlüsseln | lokal, µs bis ms | ja (je Feld) | `e2ee_v2.dart:332`, `:425` |
| 4 | Chat-POST (erzwingender Client; neue TLS mit Pin-Prüfung, wenn keine offene Verbindung) | POST | - | `attested_provider.dart:259` |
| 5 | Nach `Done`: Quittung holen (bis 3 Versuche, Wartezeit 2/4/6 s bei Netzfehler), prüfen, Upstream-Session holen und TCB prüfen; Bericht gelb -> grün/rot; Modus "Nachher": NRAS asynchron | `GET aci/receipts/<id>`, `GET aci/sessions/<id>` (messend, neue TLS) | nein, aber `external`-Tools warten | `attested_provider.dart:273,415`, `phala_verifier.dart:291,320,333`, `gpu_gate.dart:87` |

Wann (neu) attestiert wird:
- Je **Provider-Instanz** (also je Flutter-Engine/Prozessstart): erste Anfrage, wenn `_session == null`.
- Danach bis `session.notAfter` (Keyset `not_after`, heute ~30 Tage, `attested_provider.dart:339-344`). `stale_after` wird nur beim Abruf geprüft.
- Neu-Attestierung ausgelöst durch: TLS-SPKI weicht ab (`:261`), E2EE-Fehler (`:285`), Quittung mit geändertem Keyset (`:450`), `reattest()`. Beim Start jeder Attestierung ruft der Verifier `gate.expect(null)` (`phala_verifier.dart:174`), das erhöht `generation` und verwirft die offene erzwingende Verbindung (kostet danach einen Handshake).
- Rot sperrt den Anbieter bis "neu prüfen".
- Vorwärmen: `warmUp()` (`:221`) wird nur von `MainScreen.initState` (`main_screen.dart:87-98`) über `warmUpAttestation` (`attestation_hub.dart:140`) gerufen, nur wenn `restoreSession`. **Das Overlay (`assistantMain`, `main.dart:42-58`, eigene Engine, eigene Provider-Instanz) ruft es nie.** Die Sitzung wird nicht zwischen Engines geteilt, nur der Pin (DB).
- Kein erneutes Vorwärmen bei Netzwiederkehr, kein Pre-Connect des erzwingenden Clients, GPU-Evidenz nicht im Vorwärmen.

Agent-Seite: `external`-Tools warten auf die grüne Quittung (`tool_round.dart:157-185`), alle anderen laufen sofort. Seiteneffekt-freie Reads und `write`-Tools mit Undo sind bereits nicht blockiert.

## 4. Bewertung

| Anteil | Kalt | Warm |
|---|---|---|
| Anbieter/Gateway (Modell, Server-TTFT) | ~1,0 s | ~1,0 s |
| Gateway-E2EE-Mehraufwand (Differenz warm vs. roh, nicht auflösbar) | ~0,6 bis 0,7 s | ~0,6 bis 0,7 s |
| Unsere Prüfung vor dem Senden | **~2,3 s** (Attestierung 1,1 + GPU-Evidenz 1,15) | ~0 |
| Unsere Client-Krypto (E2EE, Quote) | < 0,05 s | < 0,01 s |
| Claude zum Vergleich | 1,1 s | 1,1 s |

- Der Abstand zu Claude besteht kalt zu ~80 % aus **unserer** Vorarbeit und warm zu ~100 % aus Anbieter/Gateway. Client-Krypto ist kein Faktor.
- Das Bild "Phala ist spürbar langsamer" kommt hauptsächlich von der Overlay-Nutzung: jede neue Engine zahlt 2,3 s vor dem ersten Byte (plus Intel PCS ~2 s bei Cache-Miss, etwa monatlich).
- Zusätzlich gilt nach 15 s Pause der Handshake der erzwingenden Verbindung (curl: 0,16 s TCP + 0,35 s TLS) erneut.

### Was ist sicherheitsnotwendig vor dem Senden?
- **Ja:** geprüfte Attestierung der Gegenstelle (Quote -> TCB, Nonce, Keyset-Digest, Endorsement, Compose/Eventlog), TLS-Pin (SPKI) aus der geprüften Attestierung und der E2EE-Schlüssel aus demselben Keyset. Ohne diese gingen Inhalte an eine ungeprüfte Gegenstelle. Das bleibt fail-closed.
- **Nein:** GPU-Evidenz-Abruf im Modus Aus (prüft nur, dass die Evidenz unsere Nonce enthält; die Signaturprüfung macht NVIDIA, und die läuft nur im Modus Vorher/Nachher). Er braucht weder den Key noch Nutzerinhalt. Intel-Kollateral-Refresh (Cache gültig bis `nextUpdate` reicht). Quittung/Upstream-TCB (sind schon nachgelagert). Handshake-Aufwärmen. Modus "Vorher" ist dagegen gewollt blockierend.

## 5. Befunde

1. GPU-lokal läuft **sequentiell nach** der Attestierung und vor dem Chat, auch bei Modus Aus (`attested_provider.dart:334-337`, `gpu_gate.dart:61-85`). Die Evidenz ist unabhängig von der Attestierung.
2. Overlay-Engine wärmt nicht vor (`main.dart:42`, `main_screen.dart:87`).
3. Intel-PCS-Abruf ist sequentiell (4 GETs) und liegt im blockierenden Pfad, wenn der Cache abgelaufen ist (`pcs_collateral_client.dart:32-52`); Erneuerung erst ab < 3 Tage Restlaufzeit und nur auf der Anfrage.
4. Erzwingende Verbindung läuft nach 15 s Leerlauf ab (Dart-Standard, `tls_pinned_client.dart:51`) und wird bei jeder Attestierung verworfen (`generation`).
5. Upstream-Session-GET der Quittungsprüfung geht über den messenden Client mit `Connection: close` (neue TLS) und dauert ~2 s; das verzögert grün und damit `external`-Tools auf ~2,5 bis 3 s nach Antwortende.
6. **Eigener Befund, nicht Latenz:** NRAS lehnt die vom Gateway gelieferte GPU-Evidenz heute ab (`POST nras.../v3/attest/gpu` -> HTTP 400 `INVALID_EVIDENCE`, errorCode 4005; Nonce stimmt, Payload hat `nonce`, `evidence_list`, `arch`; reproduziert mit rohem Aufruf, `nras2.dart`). Im Modus "Vorher" wäre damit jede Anfrage blockiert, im Modus "Nachher" gäbe es jedes Mal die Warnung. Ursache ungeklärt (Gateway-Format oder NRAS-Änderung); sollte separat untersucht werden.

## 6. Vorschläge (Arbeitspakete)

| WP | Inhalt | Ersparnis (kalt) | Sicherheit |
|---|---|---|---|
| **A** Overlay wärmt vor | In `assistantMain`/Overlay-Start (`assistant_overlay.dart`, sobald die Engine steht, noch bevor die Spracheingabe fertig ist) `warmUpAttestation` aufrufen, wenn Default-Provider TEE ist und online. Zusätzlich Re-Warm bei Netzwiederkehr und beim Wake-Word-Treffer. Attestierung dauert 1 bis 3 s und läuft parallel zum Sprechen/Whisper. | **~2,3 s** (fast immer; Sprechzeit des Nutzers verdeckt den Rest) | unverändert, nur früher |
| **B** GPU-Evidenz nicht seriell | `AttestedProvider._prepare`: Attestierung und `gpu.before` mit `Future.wait` parallel starten (Evidenz braucht keine Sitzung); zusätzlich in `warmUp()` die Evidenz für das Default-Modell holen und cachen. Für Modus Aus optional ganz nach der Antwort (Ergebnis nur Log/Warnung), Modus Vorher bleibt fail-closed. | **~1,1 s** (ohne A); mit A entfällt der Block ganz | Aus: kein Verlust, da ohne NVIDIA-Prüfung ohnehin schwach; Vorher: gleich |
| **C** Verbindung vorwärmen/halten | Nach grüner Attestierung einen leichten Request über den erzwingenden Client (z. B. `GET /v1/models`) im `warmUp()` (Pin-Prüfung + TLS im Voraus); `HttpClient.idleTimeout` auf 2 bis 5 min; `gate.expect(null)` nur bei echter Pin-Änderung verwerfen, nicht bei Re-Attestierung mit gleichem Pin | **~0,4 bis 0,5 s** erste Frage, gleich viel bei Fragen > 15 s nach der letzten | Pin wird weiter je Verbindung erzwungen |
| **D** Quittungspfad | Upstream-Session-GET und Receipt über die offene erzwingende Verbindung (kein `Connection: close`, kein neuer Handshake); Bericht gelb bleibt. | **~0,5 bis 1 s** bis grün (nur `external`-Tools und Badge; nicht TTFT) | gleich oder strenger (gepinnt) |
| **E** PCS | Drei unabhängige GETs (pckcrl, tcb, qe) parallel, danach Root-CRL; Kollateral im Hintergrund erneuern, wenn < 7 Tage Rest (statt 3) und beim App-Start/Warmup, nie auf der Anfrage | **~0,8 bis 1,5 s**, einmal je ~30 Tage | unverändert (gleiches Kollateral, Cache bis `nextUpdate`) |
| F (prüfen, optional) | Persistente Sitzung zwischen Engines (Schlüssel/Pin aus der DB statt neu attestieren). Nicht empfohlen vor A bis C: ohne Frische-Nachweis (Nonce) ist es ein Vertrauensverlust. | | Maintainer-Entscheidung |
| G (Untersuchung) | NRAS 400 INVALID_EVIDENCE aufklären (siehe Befund 6) | | |

Empfohlene Reihenfolge: A + B (zusammen ~2,3 s kalt, kleinste Änderung, ein WP), dann C, dann D/E. Nach A bis C liegt die kalte erste Frage bei ~1,7 s wie die warme, die verbleibende Differenz zu Claude (~0,6 s) liegt beim Gateway und ist mit unseren Mitteln nicht verkürzbar (dazu ggf. andere Phala-Modelle, kleinere Modelle oder Direktanbieter vergleichen).

## 7. Grenzen der Messung
- Mac im Heimnetz, nicht das Telefon (Rust im App-Build `opt-level=z`, Mobilfunk): Netzanteile dort eher größer, Rechenanteile 5- bis 10-fach, aber immer noch < 0,1 s.
- Attestierung mit `FakeAttestationCrypto` (kein Quote-Check in der App-Kette), die echte Quote-Prüfung separat mit dem Rust-Crate gemessen (3 ms). E2EE mit Dart-Referenzkrypto (4 ms je Feld), echte Rust-Zeit 0,07 ms je Feld; die Differenz ist in den TTFT-Werten enthalten und höchstens ~50 ms.
- Rohmessung (b) per curl mit Klartext (Gateway akzeptierte es), nur Messprompt, keine sensiblen Inhalte.
- Anzahl Chat-Requests: 16 (Claude 3, Phala roh 3, Phala E2EE warm 4, kalt 6), plus Attestierungs-/GPU-/Quittungs-/PCS-/NRAS-GETs ohne Modellkosten.

## 8. Nachher-Messung (WP77, 2026-10-16, gleicher Mac, gleiches Skript `m2.dart`)

| Variante | TTFT (ms) | Quittung grün (ms nach Start) |
|---|---|---|
| Kalt, Modus Aus (Provider neu, Attestierung + Chat; GPU-Abruf entfällt) | 2251 / 1834 / 1930 (vorher ~4000) | 3130 / 2774 / 2772 |
| Vorgewärmt (`warmUp` fertig, dann Chat), Modus Aus | 412 / 427 / 358 (vorher kalt ~4000, warm ~1700) | 1322 / 1293 / 1225 (vorher TTFT + 2,5 bis 3 s) |
| Vorgewärmt, Modus Vorher (glm-5.3, NRAS grün) | 1177 | 2838 |
| `warmUp` selbst (Attestierung + Verbindung, im Hintergrund) | 1930 bis 2060 | |

- Quittung: Upstream-Session-GET jetzt 0,16 s (vorher ~1,9 s) über die offene gepinnte Verbindung.
- Vorgewärmt liegt die TTFT unter der Claude-Messung; die Werte schwanken mit dem Gateway (Stichprobe 3, Cache-Effekte möglich).
- NRAS (Ursache Befund 6): das Gateway liefert für `google/gemma-4-31b-it`, `z-ai/glm-5.2` und `deepseek/deepseek-v4-flash-0731` eine **leere** `evidence_list` (nur Nonce, `arch`); NVIDIA antwortet darauf mit 400 `INVALID_EVIDENCE` (errorCode 4005). Mit echter Evidenz (`z-ai/glm-5.3`: 8 × Hopper, `qwen/qwen3.8-27b`: 1) antwortet NRAS 200 und `x-nvidia-overall-att-result` ist true. `qwen/qwen3.6-27b` liefert `nvidia_payload: null` (Evidenz nur in `all_attestations`, 8 Einträge, Abruf 14 s). Es liegt am Anbieter/Modell, nicht an unserem Format. Offen: Auswertung von `all_attestations` (WP-Kandidat).

