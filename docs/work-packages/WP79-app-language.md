# WP79 – App-Sprache einstellbar, Übersetzungen de/en/fr prüfen (`app/`, ggf. Pakete mit Texten)

Bezug: Gerätetest 2026-10-16 (Wunsch Prio 2: App-Sprache in der App, unabhängig vom System; Prio 3: Texte wirken teils seltsam übersetzt, z. B. Stufennamen).

## Inhalt
1. **Bestandsaufnahme:** Wie sind Texte heute organisiert (ARB/gen-l10n, eigene Textklassen je Paket, hart codierte Strings)? Welche Teile sind nur deutsch (K36: Wake-Word-UI nur deutsch)? Liste im Bericht.
2. **Einstellung „App-Sprache“:** System / Deutsch / English / Français unter Einstellungen → Allgemein (und im Onboarding optional). Wirkt sofort auf die ganze UI inkl. Overlay-Engine; unabhängig von Sprache der Spracheingabe/-ausgabe (eigene Einstellungen bleiben).
3. **Übersetzungen:** Alle UI-Texte in de/en/fr vollständig und natürlich (Fachbegriffe TEE/Attestierung verständlich, einheitliche Begriffe – Glossar in `docs/` anlegen). Fehlende Übersetzungen ergänzen, seltsame korrigieren. Prüfung per Test: keine fehlenden Schlüssel je Sprache.
4. Goldens je Sprache für 2–3 zentrale Bildschirme.

## Abnahmekriterien
- [ ] Test: alle Schlüssel in allen drei Sprachen vorhanden; Umschalten wirkt (Widget-Test), Overlay übernimmt die Einstellung.
- [ ] Glossar; Gate grün.
