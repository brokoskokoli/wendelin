# WP76d Tinfoil (TEE)
> Stand: gültig

Voraussetzung: ein Tinfoil-Konto mit API-Key (nur am Telefon des Maintainers, nie im Repo). Router und Modelle: inference.tinfoil.sh, Standardmodell `gpt-oss-120b`.

- [ ] **Einrichten**: Einstellungen → Anbieter → Vorlage „Tinfoil (TEE)“, Key eingeben, Modelle laden. *Erwartet*: Einrichtungsprüfung zeigt alle Stufen (SNP-Report, AMD-Kette, Richtlinie, TLS-Pin, HPKE-Bindung, Sigstore-Release, Messwert, Release-Untergrenze, Verschlüsselungsschlüssel) grün; „Keine Quittung je Antwort“ als Hinweis, den man annimmt.
- [ ] **Antwort im Gespräch** („Wie spät ist es?“ mit einem Werkzeug, z. B. Timer): grünes Schild „geprüft“ auch ohne Quittung; Prüfprotokoll zeigt die Sitzung mit den Stufen und den Info-Eintrag `receipt.none`.
- [ ] **Streaming und Werkzeugzug**: Antwort erscheint fortlaufend; ein Werkzeugaufruf läuft, die Antwort danach verwendet das Ergebnis.
- [ ] **Keine Anfrage bei Prüffehler**: Flugmodus während der Sitzungsprüfung bzw. blockierter Zugriff auf `kdsintf.amd.com`/`api.github.com` (z. B. Mobilfunk-Firewall): Meldung „derzeit nicht prüfbar“, nichts an den Router gesendet, kein anderer Anbieter; nach „Neu prüfen“ geht es wieder.
- [ ] **Gerätetest (E2E-Agent)**: `tool/e2e_android.sh app/integration_test/tinfoil_app_e2e_test.dart` (grüner Lauf mit Werkzeugzug, Release-Rückschritt und falscher TLS-Pin schicken keine Anfrage).
