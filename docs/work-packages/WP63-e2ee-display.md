# WP63 – Ehrliche Anzeige der Verschlüsselung (`app/`, wenig `wendelin_providers`)

Abhängig von: WP62. Bezug: K37 (offen).

## Inhalt
- **Prüfprotokoll:** neue Stufe „E2EE“ (verschlüsselt / fehlgeschlagen), neben TLS-Pin.
- **Hinweis** an Phala-Antworten mit Tool-Nutzung bzw. im Prüfprotokoll: „Tool-Argumente nur über gepinntes TLS geschützt.“ Erklärtext: Verschlüsselung endet im Gateway des Anbieters, nicht im Modell.
- **Optional „Phala ohne Tools“:** Schalter je Phala-Profil; aus = Tools wie bisher. An = keine Tools senden, damit alles E2E-verschlüsselt ist.
- Texte deutsch, kurz.

## Abnahmekriterien
- [ ] Widget-Tests und Goldens für Stufe und Hinweis.
- [ ] Test: „ohne Tools“ sendet keine Tool-Definitionen.
- [ ] Gate grün.
