# WP196 – Langes Transkript kleiner anzeigen

**Zuordnung:** Wunsch Maintainer 2026-11-13. Lange gesprochene Anfragen (Push-to-Talk) erscheinen sehr groß. Man muss scrollen, und die Anzeige hinkt hinterher. Lange Texte sollen deutlich kleiner dargestellt werden.
**Konzept:** K155 (offen).

## Befund
- Das Transkript wird mit `WText.transcript` angezeigt: im Overlay (`app/lib/ui/overlay/overlay_sheet.dart:353`, „„$request““), auf dem Hauptbildschirm bzw. in der Chat-Blase des Nutzers (prüfen) und im Stationsmodus (`app/lib/station/ui/station_screen.dart:176`).

## Inhalt
- Die Schriftgröße des Nutzertexts hängt von der Länge ab: bis 200 Zeichen unverändert, ab 200 Zeichen 70 %, ab 500 Zeichen 55 % (Konstanten an einer Stelle, Zeilenhöhe passend). Untergrenze ist die Body-Größe, damit es lesbar bleibt.
- Das gilt für Overlay, Hauptbildschirm (Verlauf bzw. aktuelle Anfrage) und Stationsmodus. Die Systemschriftgröße (TextScaler) wird weiter beachtet, also eine relative Verkleinerung.
- Wird die Anzeige mitlaufend aktualisiert, springt die Schrift nicht hin und her (Schwellen mit Hysterese oder nur am Ende umschalten).

## Abnahmekriterien
- [ ] Widget-Tests: 150, 250 und 600 Zeichen ergeben die Stufen 100 %, 70 % und 55 % in Overlay, Hauptbildschirm und Station.
- [ ] Goldens für Overlay mit langem Text aktualisiert (Workflow `update-goldens`).
- [ ] Mutationsbeleg für die Schwellen.
- [ ] Gerät: Eine Anfrage von etwa 30 s passt ohne langes Scrollen ins Overlay (Gerätetest-Block `docs/testing/m5/wp196.md`).

## Parallel
- WP194 ändert die „Moment …“ / „hört zu“-Zeile in `overlay_sheet.dart` (~340–350). Hier nur die Transkriptzeile (~353) und das Styling, damit der Konflikt klein bleibt.

## Nicht im Paket
- Schriftgröße der Antworten des Assistenten.
