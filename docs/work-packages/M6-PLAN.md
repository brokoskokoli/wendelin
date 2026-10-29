# M6 – Ausbau 2 (Android): Plan

Stand und Pakete: `STATUS.md` (maßgeblich). Offene Pakete starten nur mit Go des Maintainers. Kamera/Bild ist gestrichen (K99); iOS (M7) ist zurückgestellt, bis die Android-Version komplett ist (K99).

## Stationsmodus (spezifiziert 2026-10-19, K62/K63)
- WP99 Kern und WP158 Stationskanal sind gemergt.
- Offen mit Go: WP100 Gespräch, Wiedergabe und Kacheln (braucht WP90, WP92, nach WP99 und WP158), WP101 Ruhezeiten, Bluetooth, Wecker-Ansage.
- Konfliktstellen: Einstellungen „Stationsmodus“ (WP99 hat sie angelegt, WP100/WP101 ergänzen je eigene Felder), ARB-Texte.

## Weckwort-Vergleich und Modell-Empfehlung
- Gemergt: WP106 (Spike Stationsmodus), WP111 (Vergleich alternativer Wake Words), WP121, WP133, WP137 (Weckwort-Aufnahmen, Stufe 2, Prüfer), WP112 (Modell-Empfehlung), WP128.

## Weitere offene Pakete mit Go
- WP132 Store-Variante, WP138 kompaktes Overlay.
