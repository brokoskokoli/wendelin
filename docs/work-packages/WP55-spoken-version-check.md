# WP55 – Sprechfassung: Schutzstufen und KI-Prüfung (`wendelin_agent`, `wendelin_voice`, wenig `app/`)

Abhängig von: **WP41** (gemergt). Bezug: Wunsch des Maintainers 2026-10-14, Konzept K19/K20.

## Ziel
Statt des Schalters „Antwort in zwei Fassungen“ gibt es **eine** Einstellung mit vier Stufen. Sie legt fest, ob es einen eigenen Sprechtext gibt und wie er geschützt wird, wenn die Unterhaltung fremde Inhalte gesehen hat (Web, MCP, Kalender von Dritten …, Regel aus K20 c).

| Stufe | Bezeichnung (Vorschlag) | Verhalten |
| --- | --- | --- |
| aus (Standard) | „Aus“ | kein Sprechtext; vorgelesen wird die sichtbare Antwort (Stufe 1 + lokale Aufbereitung) |
| immer | „Immer eigene Sprechfassung“ | Sprechtext wird immer genutzt, auch nach fremden Inhalten (Nutzer verlässt sich auf den Bildschirm) |
| geschützt | „Geschützt“ | heutiges Verhalten aus WP41: nach fremden Inhalten wird die sichtbare Antwort vorgelesen |
| geprüft | „Mit KI-Prüfung“ | nach fremden Inhalten prüft ein frischer Modellaufruf, ob Sprechtext und geschriebene Antwort inhaltlich übereinstimmen; nur bei „passt“ wird der Sprechtext vorgelesen, sonst die sichtbare Antwort |

Ohne fremde Inhalte verhalten sich „immer“, „geschützt“ und „geprüft“ gleich (Sprechtext, keine Prüfung, keine Zusatzkosten).

## Inhalt
- **Einstellung:** `VoiceSettings.twoVersions` (bool) wird zu `spokenVersion` (Enum `off/always/protected/checked`); Migration: `true` → `protected`, `false` → `off`. Auswahl unter Sprache mit je einem Satz Erklärung; bei „Immer“ ein Hinweis auf das Restrisiko („Was vorgelesen wird, kann von dem abweichen, was auf dem Bildschirm steht“).
- **KI-Prüfung (`checked`):**
  - Erst wenn beide Fassungen vollständig sind; vorher wird nichts vorgelesen (Hinweis: dadurch beginnt die Sprachausgabe später – Latenz messen).
  - Frischer Aufruf an **dasselbe Ziel** (gleicher Provider/Modell, gleiche Datenschutzstufe und Untergrenze, K10/K13; keine Eskalation), **ohne** Verlauf, Tools, Gedächtnis oder System-Prompt des Assistenten. Eingabe nur: Sprache, geschriebene Antwort, Sprechtext – klar als Daten markiert.
  - Auftrag: „Gibt der Sprechtext denselben Inhalt wieder wie die geschriebene Antwort (gleiche Fakten, Zahlen, Namen, Handlungsaufforderungen; nichts hinzugefügt, nichts Wichtiges weggelassen) und ist er für die Aussprache in <Sprache> geeignet?“ Antwort nur als strukturiertes Urteil (`{"match": bool, "reason": "…"}` bzw. Tool-Call mit Schema); alles andere gilt als „passt nicht“ (fail-closed).
  - Zusätzlich lokal: Zahlen, Uhrzeiten, Telefonnummern, URLs/Domains im Sprechtext müssen in der geschriebenen Fassung vorkommen; sonst „passt nicht“ ohne Modellaufruf.
  - Zeitlimit (z. B. 5 s); bei Fehler/Zeitüberschreitung sichtbare Antwort vorlesen.
  - Kosten des Prüfaufrufs zählen ins Token-Budget der Anfrage (K8 c) und in die Kostenanzeige; im Audit-Log nur Urteil und Grund, keine Inhalte.
- Ergebnis „passt nicht“ zeigt an der Antwort einen kleinen Hinweis („Vorgelesen wurde die angezeigte Fassung“).

## Abnahmekriterien
- [ ] Migration bool → Enum getestet; UI-Auswahl mit Erklärungen (Widget-Test, Golden).
- [ ] Je Stufe Tests mit Fake-LLM: ohne fremde Inhalte immer Sprechtext; mit fremden Inhalten: `always` → Sprechtext, `protected` → sichtbare Antwort, `checked` → Prüfaufruf, „match“ → Sprechtext, „kein match“/kaputtes Urteil/Zeitüberschreitung → sichtbare Antwort.
- [ ] Prüfaufruf: ohne Verlauf/Tools/Gedächtnis (Test prüft den Request), gleiches Ziel und gleiche Datenschutz-Untergrenze, keine Eskalation; Kosten im Budget.
- [ ] Lokale Vorprüfung (Zahlen, Nummern, URLs) mit Tabellentests (de/fr/en).
- [ ] Eval: 10 Fälle (5 passend, 5 manipuliert, z. B. andere Nummer, zusätzliche Aufforderung) mit Haiku und dem Phala-Standardmodell; Trefferquote und Zusatzlatenz im Bericht.
