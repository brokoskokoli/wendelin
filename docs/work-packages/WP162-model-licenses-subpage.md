# WP162 – Lizenzen der Sprachmodelle als Unterseite

**Zuordnung:** Wunsch des Maintainers vom 2026-10-27.

## Befund
- Die Einstellungsseite Sprache zeigt am Ende den Abschnitt „Lizenzen der Sprachmodelle“ mit einer Zeile je Modell (Name, Lizenz, Namensnennung) direkt auf der Seite (`app/lib/ui/settings/voice_screen.dart:118-127`). Die Liste ist lang und macht die Seite unnötig groß.

## Inhalt
- Auf der Sprachseite bleibt nur eine Zeile „Lizenzen der Sprachmodelle“ (wie „Messwerte“, `voice_screen.dart:107-117`, mit `AppRoutes`-Eintrag). Ein Tipp öffnet eine eigene Seite mit der bisherigen Liste (gleiche Inhalte, gleiche Reihenfolge).
- Route in `app/lib/ui/routes.dart` (z. B. `/settings/voice/licenses`), Texte über l10n (de/en/fr, vorhandenen Schlüssel weiterverwenden).

## Abnahmekriterien
- [ ] Sprachseite zeigt keine Lizenzzeilen mehr, nur den Eintrag; Tipp öffnet die Unterseite mit allen Modellen aus dem Katalog (Widget-Test, Mutationsbeleg).
- [ ] Goldens der Sprachseite ggf. auf macOS aktualisiert.
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- WP160 (HA-Stufen) und WP161 (Spotify) laufen; keine gemeinsamen Dateien erwartet. l10n: nur eigene Schlüssel anhängen; Routen-Datei: eine Zeile.
