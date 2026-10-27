# WP160 – Home Assistant: Sicherheitsstufe für `ha__call`/`ha__call_secure` einstellbar, Licht gesperrt steuerbar

**Zuordnung:** Meldung des Maintainers vom 2026-10-27 nach WP154 (ADR 0022, K123).

## Befund (Maintainer)
- Für jedes Werkzeug soll die Stufe A–D wählbar sein. Bei den Home-Assistant-Aufrufen `ha__call` und `ha__call_secure` ist sie nicht einstellbar.
- Gesperrt lässt sich immer noch nicht einmal Licht steuern.

## Stand laut ADR 0022 (Z. 20, 43, 57)
- Die HA-Aufruf-Tools bekommen bewusst **keine** Tool-Stufe; es entscheidet die Gerätestufe (`ha_policy.dart`: `haDefaultLevel`, `haEffectiveLevel`, `haDecide`). Ein altes „immer bestätigen“ (D) auf den Tools bleibt wirksam, bis der Nutzer es entfernt.
- Licht hat den Standard B: gesperrt nur mit erkannter Stimme. Ohne aktive Sprechererkennung läuft gesperrt also nur Stufe A.
- Mögliche Ursachen, warum Licht gesperrt nicht geht: Standard B ohne Stimme, ein altes D auf `ha__call`, eine wirkungslose Gerätestufe A, `lockedCommandTools`/Modelllauf gesperrt, oder der Weg über die Einstellungen ist nicht auffindbar. Erst die Ursache belegen (Tests, Emulator mit Fake-HA, Dev-Log des Maintainers falls vorhanden).

## Inhalt
- Ursache für „Licht gesperrt geht nicht“ belegen und beheben (Gerät auf A bzw. B mit Stimme muss gesperrt laufen).
- Die Stufe für die HA-Aufrufe in den Werkzeug-Einstellungen sichtbar und einstellbar machen, ohne dass sie die Gerätestufe still lockert. Wie genau, klärt die Sitzung mit dem Maintainer (z. B. Stufe am Tool als Obergrenze bzw. Voreinstellung für Geräte ohne eigene Stufe, oder Sammelauswahl „alle Lichter“, oder ein Verweis auf die Gerätestufen). Entscheidung als Nachtrag in ADR 0022 und als Abweichung melden.
- Prüfen, ob es weitere Tools ohne Stufenauswahl gibt, und sie mit erfassen.

## Abnahmekriterien
- [ ] Ursache als Datei:Zeile bzw. Log belegt, Test vor dem Fix rot (Mutationsbeleg).
- [ ] Gesperrt: Licht auf Stufe A läuft ohne Entsperren; Schloss (D) weiter nie (Tests).
- [ ] Für `ha__call` und `ha__call_secure` ist in den Einstellungen eine Stufe sichtbar und wählbar (bzw. die mit dem Maintainer vereinbarte Form), fail-closed bei kaputten Werten.
- [ ] Alle Werkzeuge haben eine Stufenauswahl (Test über die Tool-Liste).
- [ ] Gerätetest-Anleitung `docs/testing/m5/wp160.md`; ADR-0022-Nachtrag; `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- WP159 läuft gleichzeitig (Anbieter-Setup `provider_setup/`, Android-Kanäle für SMS/Benachrichtigungen). Keine gemeinsamen Dateien erwartet; l10n-Dateien beide: nur eigene Schlüssel anhängen.
