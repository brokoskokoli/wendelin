# WP150 – Home Assistant: Werkzeugschleife bei einem Licht mit Personennamen

**Zuordnung:** Gerätetest des Maintainers mit rc5 (2026-10-26, 00:04:17): Der Befehl, ein Licht, dessen Name ein Personenname im Genitiv ist („<Name>s Licht“), in Home Assistant zu schalten, lief über `ha__call` in eine Schleife: `latency calls=9 tools=8`, danach Abbruch mit `toolRoundLimit` (`maxToolRounds = 8`) und `conv-exit reason=error`, gesprochene Fehlermeldung nach ~9,6 s. Andere Befehle im selben Log brauchen 1 Modellaufruf und 0–1 Werkzeug. Welche Werkzeuge mit welchem Ergebnis liefen, zeigt das Log nicht (nur Zahlen).

## Inhalt
- **Erst verstehen:** Die Schleife reproduzieren (Eval mit Fake-Provider bzw. Fake-HA mit einem Licht „Annas Licht“ und typischen Varianten wie „Anna Licht“, „Licht Anna“, Raum „Anna“). Hypothesen prüfen und belegen: Auflösung des Namens (`ha_context.dart:108` `resolve`, Genitiv-„s“, Groß-/Kleinschreibung, Umlaute, Synonyme aus WP135), mehrdeutige Treffer, Fehlertext von `ha__call` (`ha_call_tools.dart:225-247`), den das Modell nicht versteht und deshalb wiederholt, oder eine Bestätigung bzw. Policy, die immer wieder abgelehnt wird. Am Gerät mit dem Entwicklermodus (WP148) gegenprüfen, sobald er da ist.
- **Fix an der Ursache.** Dazu allgemein: Wiederholt das Modell denselben Werkzeugaufruf mit demselben Fehler, bricht die Schleife früh ab, und Wendelin sagt, was nicht ging (z. B. „Ich finde kein Gerät ‚Annas Licht‘. Meinst du …?“), statt 8 Runden zu drehen und nur „Fehler“ zu melden. Fehlertexte für das Modell so, dass es eine sinnvolle nächste Aktion wählt (z. B. Kandidatenliste mitliefern).
- Eval-Fall „Annas Licht an/aus“ dauerhaft in die Smart-Home-Evals aufnehmen.

## Abnahmekriterien
- [ ] Ursache belegt (Eval, Test; `Ursache:`/`Widerlegt:`), Gerät gegengeprüft oder als offen benannt.
- [ ] „Annas Licht an“ läuft mit höchstens 2 Modellaufrufen bzw. über den Schnellweg; eine echte Wiederholung desselben Fehlers endet spätestens nach der 2. Wiederholung mit einer verständlichen Antwort (Test, Mutationsbeleg).
- [ ] Gate `--changed`, CI grün, Review FREIGABE, E2E (Fake-HA) grün, Gerätetest-Block `docs/testing/m5/wp150.md`.

## Parallel-Hinweise
- WP148 (Entwicklermodus) ändert Logging in Agent und Pipeline; WP150 ändert Agent-Schleife und HA. Bei Überschneidung in `agent_runner.dart` nach dem WP148-Merge rebasen.
