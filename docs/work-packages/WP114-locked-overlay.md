# WP114 – Gesperrtes Handy: Overlay bleibt nach dem Entsperren, harmlose Aktionen ohne Entsperren (`app/`, Android)

**Zuordnung:** M5-Nachtest (Gerätetest 2026-10-20, T20-Z.5, T20-Z.6, L.6). Entscheid Maintainer 2026-10-21: Overlay bleibt nach dem Entsperren offen, die Anfrage von vorher wird ausgeführt und die Antwort kommt im Overlay; harmlose Aktionen gehen ohne Entsperren (K85).

## Befund
- Z.5: Gesperrt, „Taschenlampe an“ verlangt Entsperren, statt die LED einzuschalten.
- Z.6: Nach dem Entsperren schließt sich das Overlay. Log `conv-exit engine=overlay reason=tap`, `voice-cancelled … reason=tap phase=listening`, dann `release … reason=overlay-close`: die Entsperr-Geste zählt als Tippen.

## Inhalt
1. Entsperren beendet das Overlay nicht (Tap-Erkennung während/um `requestDismissKeyguard` ignorieren bzw. Keyguard-Übergang erkennen). Die gemerkte Anfrage läuft nach erfolgreichem Entsperren weiter; bei Abbruch des Entsperrens wird sie verworfen (Hinweis im Overlay).
2. Liste der Aktionen, die ohne Entsperren erlaubt sind (mindestens Taschenlampe; Vorschlag des Coders mit Begründung je Werkzeug, Sicherheitsprüfung im Review). Alles mit persönlichen Daten oder Außenwirkung verlangt weiter Entsperren.
3. Protokoll-Widerspruch Z.6/L.6 auflösen: Gerätetest-Datei `docs/testing/m5/wp114.md` mit der neuen Erwartung.

## Abnahmekriterien
- [ ] Unit-/JVM-Tests für „Entsperren ≠ Tippen“ und für die Freigabeliste (Mutationsbeleg).
- [ ] E2E auf dem Emulator (gesperrt → Anfrage → entsperren → Antwort; Taschenlampe gesperrt).
- [ ] Gate `--changed` grün, CI grün, Review FREIGABE (Schwerpunkt Sicherheit: nichts Persönliches ohne Entsperren).

## Parallel-Hinweise
- Sprach-Controller-Paket: startet erst nach dem Merge von WP113.
