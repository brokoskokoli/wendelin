# WP99 – Stationsmodus: Kern (`app/`, Android)

**Zuordnung:** M6.

Bezug: Konzept „UI/UX und Einstellungen“, Abschnitt Stationsmodus; K62, K63 (Entscheidungen Maintainer 2026-10-19).

## Inhalt
1. **Stationsbildschirm über dem Sperrbildschirm:** eigene Activity bzw. Route mit `showWhenLocked`/`turnScreenOn` (Muster: `app/android/app/src/main/kotlin/app/wendelin/AssistantActivity.kt`), Gerät bleibt gesperrt.
2. **Start nur manuell:** Button auf dem Hauptbildschirm, Schnellkachel, Sprachbefehl „Stationsmodus“ (nur entsperrt). Kein Autostart beim Laden, Abstecken beendet nicht.
3. **Ende:** Button „Beenden“ verlangt Entsperren (`KeyguardManager.requestDismissKeyguard`); danach bleibt das Gerät gesperrt. Kein Sprachbefehl zum Beenden.
4. **Ruhezustand:** Uhr, Datum, Wetter (WP87), nächste Termine und fällige Aufgaben mit Titeln (Kalender, WP88). Bereiche einzeln ausblendbar (Einstellung „Stationsmodus“). Platzhalter-Slots für Wiedergabe und Kacheln (WP100).
5. **Bildschirmmodi (auswählbar):** „immer an, gedimmt“ (Standard; Helligkeit nach Umgebungslicht, Inhalt wandert leicht gegen Einbrennen), „aus, an bei Wake Word oder Berührung“, „tagsüber an, in den Ruhezeiten aus“. Ruhezeiten einstellbar (Standard 22–7 Uhr), hier nur als Einstellung und für die Bildschirmmodi; Ton-Verhalten in WP101.

## Umsetzung
- Wake Word bleibt Pflicht; die Station nutzt den vorhandenen Foreground Service. Das Gespräch auf der Station kommt in WP100, bis dahin öffnet das Wake Word wie bisher das Overlay.
- Texte über ARB (de/en/fr), Einstellungen über `AppSettings`.
- Nicht dazu: Kacheln, Wiedergabe, Gesprächsansicht (WP100), Ruhezeit-Ton, Bluetooth, Wecker-Ansage (WP101).
- Parallel: keins (WP99 zuerst, WP100/WP101 danach).

## Abnahmekriterien
- [ ] Widget-Tests: Ruhezustand je Bereich ein/aus, Bildschirmmodi samt Ruhezeit-Wechsel (virtuelle Uhr), Termine mit Titeln.
- [ ] Test: „Beenden“ ohne Entsperren beendet nicht; Sprachbefehl beendet nicht; Abstecken beendet nicht. Mutationsbeleg.
- [ ] Goldens Ruhezustand hell/dunkel/Ruhezeit (macOS).
- [ ] E2E (Emulator): Start per Button und Kachel, Gerät sperren, Station bleibt sichtbar, Beenden verlangt PIN.
- [ ] Prüfpunkte für den Gerätetest (Einbrennen, Wärme, Akku über Nacht) in der Gerätetest-Doku. Gate grün.
