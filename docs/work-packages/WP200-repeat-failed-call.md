# WP200 – Identischen fehlgeschlagenen Werkzeugaufruf nicht erneut ausführen

**Zuordnung:** Gerätetest v0.1.8-rc3 durch den Maintainer, 2026-11-14, mit einem MCP-Server fürs Smart Home. Das Modell ruft `set_device` mit `{"position":"0"}` (Zahl als Text) auf. Der Server lehnt ab („'position' muss eine Zahl sein …“), das Modell schickt **denselben** Aufruf noch zweimal. Jeder dieser Aufrufe geht an den Server und fragt vorher erneut nach Bestätigung (MCP-Werkzeug, Stufe `external`). Erst `maxSameFailures = 3` beendet den Lauf mit „technischer Fehler“. Der Server akzeptiert numerische Strings inzwischen, der Fall in Wendelin bleibt.
**Konzept:** voraussichtlich Präzisierung des Schutzes gegen wiederholte Fehler (WP150). Abweichungen meldet die Paket-Sitzung, der Orchestrator trägt sie ein.

## Befund
- `packages/wendelin_agent/lib/src/run/tool_round.dart:342`: `maxSameFailures = 3`. `repeatedFailure` zählt erst **nach** der Ausführung; ein identischer Aufruf (gleiches Werkzeug, gleiche Argumente, `_sameContent` :396) wird bis dahin erneut ausgeführt, inklusive Bestätigungsfrage.
- Logcat (Release, `Wendelin/dev`): `tool-call n=3,4,5` mit gleichen Argumenten, jeweils `status="error"`, danach `agent-failed kind=repeatedToolError repeats=3`.

## Inhalt
- Ein Aufruf, der mit **gleichem Werkzeug und gleichen Argumenten** in diesem Lauf schon mit Fehler endete, wird nicht erneut ausgeführt und löst **keine** Bestätigungsfrage aus. Das Modell bekommt stattdessen ein Ergebnis, das den früheren Fehlertext wiederholt und ausdrücklich sagt, dass derselbe Aufruf gerade fehlgeschlagen ist und die Argumente geändert werden müssen (Wortlaut im Stil von `refuse`, :406).
- Wiederholt das Modell ihn trotzdem, endet der Lauf früher als heute (Grenze in der Paket-Sitzung festlegen und begründen), mit der bisherigen Meldung `repeatedToolError`.
- Geänderte Argumente (z. B. `{"position":0}` statt `"0"`) werden normal ausgeführt.
- Prüfen, ob es Werkzeuge gibt, bei denen eine Wiederholung mit gleichen Argumenten sinnvoll ist (vorübergehende Fehler wie Zeitüberschreitung, Netz). Falls ja: diese Fehlerart unterscheiden und begründen, nicht pauschal sperren.

## Abnahmekriterien
- [ ] Roter Test vor dem Fix: Ein identischer Aufruf nach einem Fehler wird heute erneut ausgeführt (Werkzeug-Fake zählt Aufrufe) und fragt erneut nach Bestätigung.
- [ ] Danach: Ausführung nur einmal, keine zweite Bestätigungsfrage, Ergebnis für das Modell mit dem Fehlertext und dem Hinweis.
- [ ] Geänderte Argumente laufen normal.
- [ ] Vorübergehende Fehler nach der Entscheidung aus „Inhalt“ abgedeckt.
- [ ] Mutationsbelege.
- [ ] Gerätetest-Block `docs/testing/m5/wp200.md` für den Maintainer.

## Parallel
- Keins aktiv.
