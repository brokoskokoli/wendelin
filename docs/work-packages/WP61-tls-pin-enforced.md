# WP61 – TLS-Pin erzwingen (Phala/RedPill, fail-closed)

Abhängig von: WP46/47/49/52 (gemergt). Bezug: Recherche Phala-E2EE 2026-10-14, Konzept K37 (offen), ADR 0014.

## Befund
`PhalaVerifier` kann den TLS-Schlüssel der Verbindung mit `tls_public_keys` aus der Attestierung vergleichen (`observedSpki`, `enforceTlsPin`), wird in `packages/wendelin_providers/lib/src/provider_factory.dart:162-171` aber ohne beides gebaut. Die Stufe meldet immer „nicht geprüft“; Inhalte gehen über normales WebPKI-TLS. Live-Messung 2026-10-14: der SPKI von `api.redpill.ai` passt zu `tls_public_keys`.

## Inhalt
- **Dieselbe Verbindung prüfen:** Der SPKI-Hash wird an der Verbindung gemessen, über die die Anfrage läuft, **bevor** ein Byte des Request-Bodys gesendet wird (z. B. `HttpClient.connectionFactory` → `SecureSocket`, `peerCertificate` prüfen, erst dann die Verbindung freigeben; Alternative mit gleicher Garantie ist ok). Kein separater Probe-Request als Ersatz.
- **SPKI aus DER:** SubjectPublicKeyInfo aus dem Zertifikat extrahieren und hashen (Format wie `tls_public_keys`); Parsing in Rust (`native/attest`, z. B. `x509-parser`) oder sauber in Dart, mit Testvektoren aus dem echten Zertifikat (öffentliche Daten, ok fürs Repo).
- **Fail-closed:** Pin fehlt in der Attestierung, passt nicht oder ist nicht messbar → Anfrage wird nicht gesendet, `AgentFailed` mit Grund (K28: kein Anbieterwechsel, nur Meldung). `enforceTlsPin` ist für Phala immer an (kein Schalter für den Nutzer).
- **Zertifikatswechsel:** Passt der Pin nicht, einmal frisch attestieren (neue `tls_public_keys`), dann erneut prüfen; erst danach Fehler.
- **Gilt für alle Phala-Aufrufe** (Chat, Streaming, KI-Prüfung WP55), nicht für die Attestierungs-Endpunkte selbst (die sind über die Quote gebunden).
- **Prüfprotokoll:** Stufe TLS zeigt „geprüft“/„abweichend“ statt „nicht geprüft“.
- **Doku:** Konzept Zeile ~170 und ADR 0014:41 (veraltete Aussage „SPKI passt nicht“) zur Korrektur an den Orchestrator melden.

## Abnahmekriterien
- [ ] Tests: passender Pin → Anfrage geht raus; falscher/fehlender Pin → keine Anfrage (Fake-Server zählt Bytes/Requests), Fehler mit Grund; Pinwechsel → eine Re-Attestierung, dann Erfolg bzw. Fehler.
- [ ] Test, dass der geprüfte Schlüssel von derselben Verbindung stammt (Fake-Connection-Factory).
- [ ] SPKI-Testvektor aus echtem Zertifikat.
- [ ] Live-Test (`@Tags(['live'])`, ein kleiner Request) gegen RedPill grün.
- [ ] Emulator-Lauf durch separaten E2E-Agenten (Phala-Fixture grün/rot).
- [ ] Gate grün.
