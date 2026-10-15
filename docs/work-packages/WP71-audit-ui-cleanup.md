# WP71 – Prüfprotokoll und Phala-Anzeige aufräumen (`app/`, wenig `wendelin_providers`)

Bezug: Gerätetest 2026-10-15, `ergebnisse.md` Prio 2 Nr. 6/7, Prio 3 Nr. 12–14; Entscheidung Maintainer 2026-10-15: Schalter „Ohne Tools“ entfällt, stattdessen Hinweis.

## Inhalt
1. **„Ohne Tools“ entfernen** (WP63): Schalter, Option `noTools`, Agent-Pfad (`caps.tools=false` aus diesem Grund), Prompt-Zusatz nur noch für Profile, die wirklich keine Tools können. Gespeicherte `noTools`-Werte beim Laden ignorieren (Migration ohne Fehler). Hinweis an Phala (Prüfprotokoll und an Antworten mit Tools): „Tool-Aufrufe sind über die geprüfte Verbindung bis in die Enklave geschützt, aber nicht zusätzlich verschlüsselt.“
2. **Einträge im TEE-Prüfprotokoll öffnen:** Tipp auf einen Eintrag öffnet die Detailansicht mit allen Stufen dieser Sitzung/Antwort (heute passiert nichts).
3. **Symbol je Stufe:** grüner Haken bestanden, rotes Kreuz fehlgeschlagen, gelb ausstehend/Warnung, graues Info-Symbol für „nur protokolliert“/„nicht verfügbar“ – keine Zeile ohne Symbol.
4. **Datenschutz und Logs:** Die Zeile „Prüfprotokoll“ selbst öffnet das Protokoll; der zusätzliche Button „Prüfprotokoll ansehen“ entfällt.
5. **Export:** „Als JSON exportieren“ steht oberhalb der Liste.
6. **Export ohne Inhalte:** Der Export des allgemeinen Prüfprotokolls enthält keine Anfrage-/Antworttexte (`payload.text` u. Ä. – heute 49 `request`-Einträge mit erkanntem Sprachtext). Prüfen, ob das Protokoll diese Texte überhaupt speichern darf (Konzept Audit-Log); wenn nicht vorgesehen: gar nicht mehr speichern, Altbestand beim Export auslassen.

## Abnahmekriterien
- [ ] Widget-Tests/Goldens für 2–5; Test, dass der Export keine Texte enthält (auch mit Altbestand).
- [ ] Migration: Profil mit `noTools` lädt ohne Fehler, Tools sind wieder aktiv.
- [ ] Gate grün.
