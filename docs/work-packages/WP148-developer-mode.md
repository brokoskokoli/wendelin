# WP148 – Entwicklermodus mit erweitertem Logging

**Zuordnung:** Wunsch des Maintainers vom 2026-10-26 nach einem Gerätetest mit rc5. Ein Lauf brach nach 8 Werkzeugrunden ab (`calls=9 tools=8`, `toolRoundLimit`), und das Log konnte nicht zeigen, welche Werkzeuge mit welchem Ergebnis liefen. Die App loggt bisher bewusst nur Zahlen (Privacy-Positivliste).

## Inhalt
- **Ein- und Ausschalten:** Einstellungen → App-Sprache: 10× auf die Auswahl „System“ tippen schaltet den Entwicklermodus ein. Ab etwa dem 7. Tippen zählt ein Hinweis herunter („Noch 3× tippen …“), wie bei Android. Am Ende kommt „Entwicklermodus an“. Derselbe Weg schaltet ihn wieder aus („Entwicklermodus aus“). Ob Tippen auf die bereits gewählte Auswahl „System“ die Sprache neu setzt, prüfen: Das darf nichts kaputt machen. Der Schalter ist ein gespeichertes Flag und bleibt über Neustarts erhalten. Texte de/en/fr.
- **Erweitertes Logging nur mit Flag:** Ist der Modus an, loggt die App zusätzlich (logcat, Tag `Wendelin/dev`), auch Inhalte, die sonst nie geloggt werden:
  - erkannte Texte je Transkription (zu `stt-lang`), auch Texte, die verworfen werden (Gate, nur Weckwort, wake-strip);
  - je Agentenrunde den Werkzeugnamen, die Argumente (gekürzt, z. B. 300 Zeichen) und das Ergebnis (ok/Fehler mit Fehlertext, gekürzt), dazu die Antwort des Modells, gekürzt;
  - die Latenzzeile mit allen Runden (heute nur bis `m4`);
  - bei einem Abbruch (`toolRoundLimit`, Fehler) die Liste der Runden als eine Zusammenfassung.
  Schlüssel, Tokens und Passwörter werden auch im Entwicklermodus nie geloggt (bestehende Schwärzung nutzen, Test). Ohne Flag ändert sich am heutigen Logging nichts: Privacy-Positivliste und Checks bleiben. Ein Test belegt, dass ohne Flag kein Inhalt im Log landet.
- **Sichtbarer Hinweis:** Solange der Modus an ist, steht in den Einstellungen ein dezenter Hinweis „Entwicklermodus an – erweitertes Logging“, damit er nicht vergessen wird.
- **Entwickler-Einstellungen verbergen:** Die Einstellung „Bonus Hinweisbegriffe“ (WP146, heute unter Sprache → Gesprächsmodus → „Erweitert“, `barge_debug_sheet.dart`) wird nur im Entwicklermodus angezeigt. Ein gesetzter Wert bleibt nach dem Ausschalten wirksam. Prüfen und im Bericht vorschlagen, welche weiteren Optionen im Sheet „Erweitert“ reine Entwickler-Optionen sind; die Entscheidung trifft der Maintainer.
- **Doku:** `docs/architecture/privacy.md` (Entwicklermodus als bewusste Ausnahme), Gerätetest-Block `docs/testing/m5/wp148.md`.

## Abnahmekriterien
- [ ] 10× „System“ schaltet ein, 10× wieder aus, das Flag überlebt einen Neustart (Widget-Test plus Test der Speicherung).
- [ ] Ohne Flag: kein Inhalt im Log (Test, Mutationsbeleg). Mit Flag: Texte, Werkzeuge, Argumente, Ergebnisse und alle Runden erscheinen, Secrets bleiben geschwärzt (Test).
- [ ] „Bonus Hinweisbegriffe“ ist nur im Entwicklermodus sichtbar, der Wert bleibt (Test).
- [ ] Gate `--changed`, CI grün, Review FREIGABE, E2E auf dem Emulator (Ein-/Ausschalten, ein Lauf mit Werkzeug zeigt die Dev-Zeilen).

## Parallel-Hinweise
- WP147 (Doku, Konzept-Werkzeuge) läuft parallel und berührt `tool/` und `docs/architecture/`; `privacy.md` nur im eigenen Abschnitt ändern.
- WP149 (Wake-Übergabe) und WP150 (Home-Assistant-Schleife) folgen danach und nutzen das Dev-Logging.
