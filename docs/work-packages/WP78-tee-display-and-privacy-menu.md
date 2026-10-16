# WP78 – TEE-Anzeige im Chat, Erklärseite zu den Stufen, Menü „Datenschutz und Logs“, Modellwechsel (`app/`)

Bezug: Gerätetest 2026-10-16 (`ergebnisse.md` Nachtest 3e845fe, Wünsche Prio 2/3).

## Inhalt
1. **Chat nur mit Haken:** An Antworten nur noch das Schild (gelb „wird geprüft“ → grün „geprüft“ / grau / rot) ohne Zusatztext zu „nur protokolliert“-Stufen. Die anbieterspezifischen Einschränkungen (was der Anbieter nicht liefert, z. B. keine Endorsement, keine Herkunftsliste, Gateway-Hinweis bei NEAR) werden **einmal** bei der Einrichtung bzw. „Modell prüfen“ gezeigt und dort als akzeptiert festgehalten; danach gilt das Ergebnis als grün. Neue/geänderte Einschränkung → erneuter Hinweis. Der Tool-Hinweis (Phala) bleibt im Prüfprotokoll.
2. **Erklärseite „Details“:** Button „Details“ im TEE-Prüfprotokoll-Eintrag und bei „Modell prüfen“ öffnet eine eigene Seite: je Stufe (TDX-Quote, TCB, Nonce, Schlüsselsatz-Digest/-Signatur, Frische, Ereignisprotokoll, Compose-Hash, Herkunft, TLS, E2EE, GPU, Quittung-Stufen, Gateway …) kurz, was geprüft wird, Ergebnis dieser Prüfung, und was es für die Sicherheit bedeutet.
3. **Datenschutz und Logs:** Reihenfolge „Bildschirminhalt schützen“, „Aufbewahrung“, dann Zwischenüberschrift „Prüfprotokoll“ mit „Allgemeines Prüfprotokoll“ und „TEE-Prüfprotokoll“ direkt hintereinander.
4. **Modellwechsel leert den Chat (Entscheidung Orchestrator, Maintainer kann ändern):** Nur der **manuelle** Wechsel von Modell/Profil (Einstellungen, Provider-Chip) beginnt ein neues Gespräch (mit kurzer Bestätigung, falls der Verlauf nicht leer ist). „Nochmal mit X“ und Routing-Regeln behalten den Verlauf (dafür sind sie da).

## Abnahmekriterien
- [ ] Widget-Tests/Goldens für 1–4; Test, dass eine geänderte Einschränkung erneut gezeigt wird.
- [ ] Gate grün.
