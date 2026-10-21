# WP119 – Nächster Wecker auslesen, Tools vorab mitschicken

**Zuordnung:** M6, Testbefund Stefan 2026-10-21. Entscheidungen Stefan 2026-10-21: Wecker „nur nächster Wecker“; Start jetzt, parallel zu WP113. Tool-Vorauswahl: Stefan ohne Präferenz, Orchestrator-Empfehlung „Tools der erkannten Bereiche vorab mitschicken, Suche bleibt Fallback“ (K89).

## Inhalt

### 1. Nächster Wecker (Android)
- `alarms__list` liefert auf Android heute immer „nicht möglich“ (`app/lib/platform/android_alarm_port.dart:105`). Android bietet keine Liste der Wecker anderer Apps, aber `AlarmManager.getNextAlarmClock()` (Zeitpunkt des nächsten Weckers, app-übergreifend).
- Neu: Der Port liefert den nächsten Wecker (Datum + Uhrzeit, ohne Label/Wiederholung). Das Tool sagt dem Modell ehrlich, dass nur der nächste Wecker bekannt ist (z. B. Feld `only_next: true` bzw. eigenes Tool `alarms__next`; Wahl begründen, kleinste Änderung am `AlarmPort` bevorzugt).
- Kein Wecker gestellt → leere Antwort, kein Fehler. Methodenkanal klein halten (bestehenden Kanal wiederverwenden, falls vorhanden).

### 2. Tools vorab mitschicken
- Heute bekommt das Modell ab 30 aktiven Tools nur `tools__search` (`packages/wendelin_tools/lib/src/registry/tool_registry.dart:198`); fast jede Aktion kostet dadurch einen zusätzlichen Modellaufruf.
- Neu: Vor dem ersten Modellaufruf einer Anfrage werden die Tools der Integrationen freigeschaltet, die die Anfrage ohne Modell erkennbar braucht (Wortliste `KeywordToolCategoryMatcher`, `packages/wendelin_agent/lib/src/routing/tool_category_matcher.dart`). `tools__search` bleibt als Fallback im Angebot.
- Wortliste auf alle eingebauten Integrationen erweitern (de/en/fr; u. a. alarms, calendar, gtasks/tasks/todoist, lists, bring, spotify, media, weather, web, maps, location, contacts, phone/sms/msg, ha, obsidian, memory, clipboard, station); Schlüssel = Integrations-ID (heute z. B. `alarm` statt `alarms` prüfen).
- Datenschutzfilter (K10) gilt unverändert: freigeschaltet wird nur, was der Provider der Stufe sehen darf. Höchstens ~3 Integrationen vorab, damit kleine Modelle nicht überladen werden.
- Suche selbst verbessern: `ToolSearchTool.search` zählt nur Wortgleichheit in Name/Beschreibung/Integrationsname (`packages/wendelin_tools/lib/src/registry/tool_search.dart:113`). Tool-Beschreibungen sind englisch, das Modell sucht oft deutsch („Wecker“) → Treffer hängen vom Integrationsnamen ab. Die Suche nutzt zusätzlich die Wortliste aus dem Matcher (de/en/fr) je Integration; Test „Wecker“/„réveil“ findet `alarms__*`.
- Einstiegsstelle: `app/lib/di/agent_factory.dart:91` bzw. Agent-Schleife; Abhängigkeitsregeln aus `docs/ENGINEERING.md` beachten (`wendelin_tools` importiert `wendelin_agent` nicht – ggf. Callback/Port).

## Abnahmekriterien
- [ ] Android-Port liefert den nächsten Wecker; Tool-Antwort sagt „nur nächster Wecker“; Test für „kein Wecker“; Kotlin-Unit-Test.
- [ ] Anfrage „Stell mir einen Wecker um 7“ → erster Modellaufruf enthält `alarms__*` ohne vorherigen `tools__search` (Test mit Fake-Provider, Mutationsbeleg). Unerkannte Anfrage → wie bisher nur Suche.
- [ ] Sensitive Tools werden für zu niedrige Datenschutzstufe nicht vorab freigeschaltet (Test).
- [ ] Evals gegen Fake-Provider grün; `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE.
- [ ] Gerätetest `docs/testing/m5/wp119.md`: „Wann klingelt mein nächster Wecker?“, Wecker stellen ohne Tool-Suche im Verlauf.

## Parallel-Hinweise
- Läuft neben WP113 (Stopp, Sprachsteuerung/Overlay). WP119 berührt Wecker-Port/Kotlin-Alarm, `wendelin_tools` Registry, `wendelin_agent` Routing-Wortliste, `agent_factory.dart`. Keine Audio-Dateien. Bei Konflikt in `agent_factory.dart` oder `MainActivity.kt`: kleine Einschübe, nicht umbauen.
- Kein Emulator nötig außer kurzem E2E, falls frei.
