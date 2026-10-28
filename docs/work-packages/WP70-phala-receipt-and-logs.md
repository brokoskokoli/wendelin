# WP70 – Phala-Quittung auf dem Gerät, ehrliche Warnkarte, Attest-Logs (`wendelin_providers`, `app/`)

Bezug: Gerätetest 2026-10-15 (Testtelefon, Android 16, APK 81ef3b9), `ergebnisse.md` im lokalen Testordner des Maintainers Prio 1 Nr. 1, Prio 2 Nr. 4/5.

## Befunde
1. **Jede Phala-Antwort wird rot:** Sitzung grün (inkl. TLS-Pin und E2EE-Schlüssel), danach `receipt.fetch = unavailable` („Quittung nicht abrufbar“): gelb → gelb → rot nach 3 Versuchen im Abstand von ~3 s. 4/4 Antworten, Modelle `google/gemma-4-31b-it` und `meta-llama/llama-3.3-70b-instruct`, „Ohne Tools“ an. „Neu prüfen“ hebt die Sperre auf, nächste Antwort wieder rot. Auf dem Emulator (Fixture) war es grün → Unterschied zum echten Dienst seit WP61/WP62 (E2EE-Header, Pinned-Client für den Quittungsabruf, Antwort-ID aus verschlüsselter Antwort, Endpunkt/Parameter, Verzögerung beim Anbieter).
2. **Warnkarte nennt falschen Grund:** spricht von Signaturfehler/Prüfsummen/Manipulation, Ursache war „Quittung nicht abrufbar“. Die Karte nennt den tatsächlichen Grund der fehlgeschlagenen Stufe (nicht abrufbar ≠ manipuliert; Text und Empfehlung je Grund).
3. **Keine `Wendelin/attest`-Zeilen im Release-Log**, obwohl Prüfungen liefen (Anleitung 12.1/12.11 erwartet Stufen und Ergebnisse, ohne Inhalte).

## Inhalt
- Ursache von 1 mit einem sparsamen Live-Test gegen RedPill finden (Key in `~/.wendelin-live.env`, hat wieder Guthaben; höchstens ~10 kleine Anfragen, kleinstes Modell, z. B. `google/gemma-4-31b-it` mit wenigen Tokens). Prüfen: welcher Endpunkt/welche ID die Quittung liefert, ob sie verzögert verfügbar ist (Backoff anpassen, z. B. bis ~20 s, Ergebnis gelb bis dahin), ob der Abruf über den gepinnten/messenden Client richtig läuft, ob E2EE die Antwort-ID verändert. Live-Test, der genau diesen Weg (E2EE-Chat + Quittung + Prüfung) grün belegt, inkl. Streaming.
- Auch der in WP62 offene Punkt: Request-`body_hash` gegen echte Quittung (Serialisierung Dart vs. Gateway) live verifizieren.
- Warnkarte je Grund (de), Test je Grund.
- Attest-Logs (Stufe, Ergebnis, Grundcode, nie Inhalte/Keys) im Release-Build sichtbar unter Tag `Wendelin/attest`; Test.

## Abnahmekriterien
- [ ] Live-Test grün: E2EE-Chat (nicht-streaming und streaming) → Quittung abgerufen → alle Quittungsstufen grün.
- [ ] Unit-Tests für den gefundenen Fehler (rot vorher, grün nachher) und für die Warnkarten-Texte.
- [ ] Emulator-Fixture weiter grün (separater E2E-Agent).
- [ ] Gate grün.
