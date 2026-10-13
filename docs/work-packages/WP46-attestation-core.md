# WP46 – Attestierungs-Kern: PhalaVerifier und AttestedProvider (`packages/wendelin_providers/lib/src/tee/`)

Abhängig von: WP43 (Feldlayout, `report_data`, Kanonisierung, Fixtures). Teil a kann mit den Fixtures der Probe vom 13.10. beginnen. Andockpunkte: `LlmProvider`/`ChatEvent` (`packages/wendelin_core/lib/src/provider/`, `src/messages/`), `OpenAiAdapter` (`packages/wendelin_providers/lib/src/openai/openai_adapter.dart`), HTTP-Stack `src/common/http_transport.dart` (kein neuer Stack, N3), `ProviderFactory`, Phala-Vorlage in `src/catalog/provider_template.dart` (`teeModelsOnly`), `PrivacyLevel.tee`. Konzept „TEE-Provider und Attestierung“, K2. ADR 0014 legt dieses Paket an.

## Port (zuerst committen, WP47 implementiert ihn)

```dart
abstract interface class AttestationCrypto {
  /// TDX/SGX-Quote gegen Kollateral prüfen; liefert Report-Felder + TCB-Status.
  Future<QuoteVerdict> verifyQuote(Uint8List quote, QuoteCollateral collateral, DateTime now);
  /// Kollateral für eine Quote holen (Intel PCS) bzw. aus dem Cache.
  Future<QuoteCollateral> collateralFor(Uint8List quote);
  bool verifyEd25519(Uint8List publicKey, Uint8List message, Uint8List signature);
  Uint8List sha256(Uint8List data);
  Uint8List sha384(Uint8List data);
  Uint8List spkiSha256(Uint8List certificateDer);
}
```
Die genaue Form (Sync/Async, Fehlertypen) legt das Paket fest und meldet sie WP47 vorab.

## Teil a – Verifier
- Parser für Gateway-Attestierung (`api_version`, `workload_keyset`, `report_data`, `evidence`, `event_log`, `app_compose`, `source_provenance`, optional `workload_id`, `freshness`) und Quittung (`event_log`: `request.received`, `route.selected`, `upstream.verified`, `response.returned`). Unbekannte Felder werden toleriert, fehlende Pflichtfelder ergeben einen Fehler mit Prüfstufe.
- `AttestationVerifier` (Konzept-Interface) und `PhalaVerifier`: Prüfstufen jeweils als eigenes Ergebnis, damit das Prüfprotokoll jede Stufe zeigen kann: Quote/TCB, Nonce-Bindung, Keyset-Digest, Keyset-Endorsement, `not_after`/`stale_after`, Event-Log/Compose-Hash, Provenance gegen Liste vertrauenswürdiger Commits (leer = nur protokollieren), TLS-SPKI. Bei der Quittung: Signatur, `body_hash` gegen die gesendeten Bytes, `wire_hash`/`body_hash` von `response.returned` gegen die empfangenen Bytes, `upstream.verified.result == verified`, Bindung an `workload_keyset_digest` (und `workload_id`).
- Richtlinie → Status `green|yellow|red` je Sitzung und je Antwort, nach dem Fehlerverhalten im Konzept (gesperrt, 3 Wiederholungen, Pinning-Wechsel) und dem Vorschlag in `M4.md` (gelb nur Zwischenstand bzw. TCB-Hinweis).
- Pinning-Zustand (`AttestationPinStore`-Port: Keyset-Digest, Commit, Compose-Hash, Zeitpunkt). Bei einem Wechsel folgen eine neue Attestierung und ein Hinweis an den Nutzer.

## Teil b – Decorator und Ereignis
- `AttestedProvider implements LlmProvider`: Er umhüllt den OpenAI-kompatiblen Adapter. Vor der ersten Anfrage und nach `not_after` oder Pinning-Wechsel attestiert er. Er hält die exakten Request-Bytes und die empfangenen Antwort-Bytes (Rohbytes-Zugriff im Transport ergänzen, ohne Wire-Typen nach außen). Nach dem Stream-Ende (Konzept: Streaming erst danach) holt er die Quittung, prüft sie und sendet das Ergebnis.
- Neues `AgentEvent` (z. B. `AttestationStatusChanged(stepId, status, logId)`) in `packages/wendelin_core/lib/src/agent/agent_event.dart`. Kernvertrag, ADR 0002 ergänzen, Konzeptabweichung 11.
- Tools: `external`-Aufrufe einer TEE-Antwort warten auf die geprüfte Quittung (Konzeptabweichung 8). Die Andockstelle im `ToolRound` stimmt WP46 mit dem Agent-Paket ab (kleiner Hook, z. B. `ToolGate`-Port, kein Umbau der Schleife).
- Fehler: Attestierung fehlgeschlagen → kein Request, `ProviderError` mit Grund, Fallback nur mit Nutzererlaubnis. Quittung rot → weitere Anfragen gesperrt bis zur neuen Attestierung.

## Abnahmekriterien
- [ ] Fixture-Tests (echte Probe-Daten): grüner Pfad mit `FakeAttestationCrypto` und ein Lauf gegen die echte Prüfung über einen Test-Hook für WP47. Je Manipulation (Quote, Nonce, Keyset, Quittungssignatur, `body_hash`, `upstream.verified`, abgelaufenes `not_after`) genau die erwartete rote Stufe.
- [ ] Tabellentest der Richtlinie (Stufenergebnisse → Status), inkl. Netzfehler → gelb → nach 3 Versuchen rot.
- [ ] `AttestedProvider` besteht `llmProviderContract`. Ein Stream mit Tool-Aufruf meldet den Status nach dem Ende. Ein `external`-Tool startet erst nach grüner Quittung, bei Rot gar nicht.
- [ ] Gesperrter Provider sendet nachweislich keinen Request (Fake-Transport zählt).
- [ ] Keine Quittungs- oder Prompt-Inhalte im Log; Diagnose `Wendelin/attest:` mit Stufe und Ergebnis.
- [ ] ADR 0014 angelegt; Größe je Teil ≤ ~1 500 Zeilen Produktivcode; Gate grün.
