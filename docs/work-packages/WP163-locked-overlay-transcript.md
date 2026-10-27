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

## Abnahmekriterien
- [ ] Widget-Tests: gesperrt sind Anfrage und Antwort sichtbar, Entsperren-Knopf oben; Aktion über erlaubter Stufe → Hinweis „Entsperren nötig“, kein pauschaler Sperrtext (Mutationsbeleg).
- [ ] Kein Verlauf und keine Daten jenseits von Anfrage und aktueller Antwort gesperrt sichtbar (Test).
- [ ] Goldens Overlay gesperrt auf macOS aktualisiert.
- [ ] Gerätetest-Anleitung `docs/testing/m5/wp163.md`; `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- WP160 (HA-Stufen, Sprechererkennung, ha_locked_e2e_test) läuft; berührt das Overlay nicht. WP161 (Spotify), WP162 (Sprachseite, Lizenzen) laufen ebenfalls. l10n nur eigene Schlüssel.
