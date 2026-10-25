# WP151 – Unterbrechen mit Weckwort bei Gesprächston

**Zuordnung:** Gerätetest des Maintainers mit rc5 (2026-10-26, 00:23:47 und 00:24:00, Gesprächston an, `mic-start profile=speechOutput mode=3`): Zweimal „Hey Wendelin“ während der Antwort, beide Male ohne Unterbrechung. Die Vorstufe erkannte beide (`barge-cand kind=wake sim=0.54` bzw. `0.56`, `thr=0.45`), die Prüfung lehnte ab (`barge-verify result=no`, Parakeet `lp=-2.20` bzw. `-1.90`, sonst um −0,1). Ein späterer, stärkerer Kandidat (`sim=0.73`) ging mit `busy=true` verloren.

## Inhalt
- **Erst verstehen:** Mit den Tonaufnahmen aus dem Entwicklermodus (WP148) anhören und messen, was die Prüfung bekommt: eigene Sprachausgabe im Ausschnitt (Echo), Echo-Unterdrückung im Kommunikationsmodus, Zuschnitt des Ausschnitts, Pegel. Ursache belegen, bevor geändert wird. Prüfen, warum ein Kandidat bei `busy=true` verworfen wird, statt nach der laufenden Prüfung dranzukommen.
- **Fix an der Ursache.** Mögliche Wege (erst nach dem Beleg wählen): Prüfer B mit den „Hey Wendelin“-Vorlagen statt Parakeet beim Unterbrechen, Echo vor der Prüfung herausrechnen, anderer Ausschnitt, ein stärkerer Kandidat ersetzt einen schwächeren in der Warteschlange.
- Fehlauslösungen durch die eigene Sprachausgabe dürfen nicht zunehmen (Messung mit langen Antworten ohne Ruf).

## Abnahmekriterien
- [ ] Ursache belegt (Aufnahmen, Messung; `Ursache:`/`Widerlegt:`).
- [ ] Gerät mit Gesprächston: 10 Unterbrechungen mit „Hey Wendelin“, mindestens 8 greifen; 10 lange Antworten ohne Ruf, keine Fehlauslösung.
- [ ] Ein Kandidat während einer laufenden Prüfung geht nicht verloren (Test, Mutationsbeleg).
- [ ] Gate `--changed`, CI grün, Review FREIGABE, E2E, Gerätetest-Block `docs/testing/m5/wp151.md`.

## Parallel-Hinweise
- Startet nach WP148 (braucht die Tonaufnahmen). Berührt `app/lib/voice/wake/wake_barge_in.dart` und den Barge-in-Prüfer; WP149 berührt die Wake-Übergabe, Absprache bei gemeinsamen Dateien.
