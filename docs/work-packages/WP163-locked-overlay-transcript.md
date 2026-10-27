# WP163 – Gesperrt: Anfrage und Antwort im Overlay zeigen, Entsperren-Knopf oben

**Zuordnung:** Wunsch des Maintainers vom 2026-10-27 (nach WP154/WP160, Stufen A–D).

## Befund
- Gesperrt zeigt das Overlay nur „Gerät entsperren“ (fett) und den festen Text „Auf dem Sperrbildschirm zeigt und sagt Wendelin nichts aus deinen Daten. Nur die Taschenlampe geht auch gesperrt …“ (`app/lib/ui/overlay/overlay_sheet.dart:255-264`, `overlayLockedText` in `app_de.arb:1317`). Das stimmt seit den Stufen A–D (ADR 0022) nicht mehr: Werkzeuge und HA-Geräte auf Stufe A (bzw. B mit erkannter Stimme) laufen gesperrt.
- Gehörter Text und Antworttext sind gesperrt nicht zu sehen.

## Wunsch (Maintainer, sinngemäß)
- Gesperrt zeigt das Overlay wie entsperrt, nur kleiner, den gehörten Text und den Antworttext.
- Oben ein Knopf „Entsperren“.
- Der pauschale Satz entfällt. Nur bei Aktionen, die gesperrt nicht gehen, sagt Wendelin „dafür musst du entsperren“ bzw. „darauf habe ich gesperrt keinen Zugriff“.

## Inhalt
- Gesperrte Ansicht umbauen: Entsperren-Knopf oben, darunter Anfrage und Antwort (kleinere Schrift, Stil wie im entsperrten Overlay); keine Eingabe per Tastatur, keine Bestätigungskarten für Aktionen über Stufe A/B.
- Fester Sperrtext nur noch als Antwort, wenn eine Aktion an der Stufe scheitert (vorhandener „Entsperren nötig“-Pfad, ADR 0022 Z. 43). `overlayLockedText` entfernen bzw. umformulieren; l10n de/en/fr.
- Datenschutz prüfen und im Review belegen: Was gesperrt angezeigt wird, ist nur, was ohnehin gesprochen wird (Antwort aus erlaubten Aktionen). Kein Gesprächsverlauf, keine älteren Unterhaltungen, keine Werkzeugdetails, keine Inhalte aus Aktionen über der erlaubten Stufe. Sitzungssperre (WP157) und Entsperr-Ablauf (WP153) unverändert.
- Konzeptabweichung melden (bisher: „gesperrt zeigt Wendelin nichts aus deinen Daten“).

## Teil B – Aktionen, die nur entsperrt wirken (Gerätetest 2026-10-27)
- Befund: Gesperrt, Stufe A/B: `maps__navigate` („Navigiere zum Bahnhof“) startet `google.navigation:` an Google Maps (Android lässt den Start zu), das Tool meldet „Google Maps ist geöffnet“. Maps kommt hinter dem Sperrbildschirm an und verwirft die Navigation; nach dem Entsperren ist Maps offen, ohne Route. Entsperrt startet derselbe Aufruf sofort (Log 19:12:56 gesperrt vs. 19:15:06 entsperrt; Auszug `../james-wt/handoff/wp163-maps-locked-log-2026-10-27.txt`, nicht ins Repo). Keine fehlende Berechtigung.
- Entscheidung des Maintainers (2026-10-27): Wendelin erkennt das Kommando und weiß, was es ausführen würde. Es sagt, dass dafür entsperrt werden muss, bietet das Entsperren direkt an und führt die Aktion sofort nach dem Entsperren aus.
- Umsetzung: Werkzeuge, die eine fremde App in den Vordergrund bringen (mindestens `maps__navigate`; weitere wie Maps-Suche, App-Starts, Anrufe/Dialer prüfen und auflisten), bekommen ein Merkmal „wirkt nur entsperrt“. Gesperrt führt der Executor sie nicht aus, sondern merkt sich den Aufruf (Werkzeug + Argumente), zeigt bzw. sagt „Zum Navigieren bitte entsperren“ und öffnet die Entsperr-Abfrage. Nach erfolgreichem Entsperren läuft genau dieser gemerkte Aufruf, ohne neuen Modelllauf. Bei Abbruch wird er verworfen. Nutzt den Entsperr-Ablauf aus WP153 (gemerkte Anfrage), keine zweite Mechanik. Die Stufe des Werkzeugs gilt weiter (gesperrt nicht erlaubt → wie bisher „Entsperren nötig“).
- Sicherheit: Der gemerkte Aufruf läuft nur einmal, nur nach echtem Entsperren (Keyguard), verfällt nach kurzer Zeit (z. B. 60 s) und beim Schließen des Overlays. Kein Ausführen vor dem Entsperren.

## Abnahmekriterien
- [ ] Widget-Tests: gesperrt sind Anfrage und Antwort sichtbar, Entsperren-Knopf oben; Aktion über erlaubter Stufe → Hinweis „Entsperren nötig“, kein pauschaler Sperrtext (Mutationsbeleg).
- [ ] Kein Verlauf und keine Daten jenseits von Anfrage und aktueller Antwort gesperrt sichtbar (Test).
- [ ] Goldens Overlay gesperrt auf macOS aktualisiert.
- [ ] Teil B: gesperrt `maps__navigate` → nicht ausgeführt, Entsperr-Abfrage, nach Entsperren genau einmal ausgeführt; Abbruch/Ablauf → nicht ausgeführt (Tests, Mutationsbeleg); Liste der Werkzeuge mit „wirkt nur entsperrt“ in der Fertigmeldung.
- [ ] Gerätetest-Anleitung `docs/testing/m5/wp163.md` (inkl. Navigation gesperrt → Entsperren → Route); `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- WP160 (HA-Stufen, Sprechererkennung, ha_locked_e2e_test) läuft; berührt das Overlay nicht. WP161 (Spotify), WP162 (Sprachseite, Lizenzen) laufen ebenfalls. l10n nur eigene Schlüssel.
