# WP149 – Wake-Übergabe ohne Audiolücke

**Zuordnung:** Gerätetest des Maintainers mit rc5 (2026-10-26, Log 00:05:29): Nach dem Weckwort steht `wake-gap engine=overlay ms=674 afterTake=886 mode=overlap tail=200 trim=0 silence=674`. WP146 hatte als Ziel unter 50 ms ohne Lücke; jetzt wird die Lücke nur mit Stille gefüllt. Entscheidung des Maintainers: Die Aufnahme muss durchgehend laufen, ohne Lücke. Auch wenn es heute wenig stört, sprechen andere Leute ohne Pause weiter.

## Inhalt
- **Erst verstehen:** Warum entsteht trotz WP146 (Dienst nimmt bis zum ersten App-Frame auf, `bridgeWakeTail`) eine Lücke von 674 ms mit `mode=overlap`? Den Ablauf mit Zeitstempeln nachverfolgen: wann der Dienst das letzte Sample liefert, wann die App ihr erstes, ob der Schwanz des Dienstes (`tail=200`) zu kurz übergeben wird oder verloren geht, und was `afterTake=886` bedeutet. Die Ursache belegen (Diagnose-Logs, Test), bevor geändert wird.
- **Ziel:** Audio vom Wake-Dienst bis zur App ohne Lücke und ohne doppelte Samples, auch im Overlay bei gesperrtem Gerät, im Chat und in der Folgerunde. Wenn Android zwei gleichzeitige Aufnahmen nicht sauber liefert, eine Lösung mit einer einzigen durchgehenden Aufnahme prüfen, z. B. dass die App die laufende Aufnahme des Dienstes übernimmt, statt eine neue zu öffnen.
- Die Stillefüllung bleibt nur als Notfall-Rückfall, mit Log.
- Gerätetest-Block `docs/testing/m5/wp149.md`: 10 Rufe „Hey Wendelin <Befehl>“ ohne Pause, Erwartung `wake-gap ms` < 50 und `silence=0`.

## Abnahmekriterien
- [ ] Ursache der 674 ms belegt (Bericht `Ursache:`/`Widerlegt:`).
- [ ] Emulator und Handy: `wake-gap` < 50 ms, `silence=0` bei bereiten Modellen; ein Befehl ohne Pause wird vollständig erkannt.
- [ ] Keine zwei Aufnahmen länger als nötig (Grenze aus WP146 einhalten oder begründet ersetzen).
- [ ] Gate `--changed`, CI grün, Review FREIGABE, E2E grün, Gerätetest-Block.

## Parallel-Hinweise
- Baut auf WP146 auf (Übergabe, `bridgeWakeTail`, `appVoiceActive`). Nutzt das Dev-Logging aus WP148, falls es schon gemergt ist.
