# WP116 – Einstellungsseiten: Überschriften, Info-Texte, Links (`app/`, UI)

**Zuordnung:** M5-Nachtest (Gerätetest 2026-10-20, T20-0.9), Wunsch Maintainer.

## Inhalt
1. Überschriften auf allen Einstellungsseiten klar als Überschrift erkennbar (Größe/Gewicht nach `docs/design/DESIGN.md`).
2. Info-Texte abgesetzt (z. B. Fläche mit Hintergrund, Einzug), deutlich anders als Einträge und Überschriften.
3. Links/Aktionen wie „Einstellungen des Herstellers öffnen“ als Link bzw. Knopf erkennbar.
4. Umsetzung über gemeinsame Bausteine (ein Widget je Rolle), nicht Seite für Seite; DESIGN.md ergänzen.

## Abnahmekriterien
- [ ] Gemeinsame Widgets, alle Einstellungsseiten umgestellt; Goldens aktualisiert (nur macOS).
- [ ] Gerätetest-Datei `docs/testing/m5/wp116.md` (Sichtprüfung).
- [ ] Gate `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Reine Oberfläche, viele Dateien unter `app/lib/` (Einstellungen). Konflikte mit WP113/WP115 klein halten: nur Darstellung ändern, keine Logik; ARB-Texte nicht anfassen außer neuen.
