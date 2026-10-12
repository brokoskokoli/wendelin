# WP06 – Eingebaute Integrationen (`packages/wendelin_integrations`)

Abhängig von: `wendelin_core`, `http`, `html` (für web_fetch-Textauszug). Konzept-Bezug: „Eingebaute Integrationen“ (MVP-Zeilen), „Gedächtnis im Detail“, „Kalender-Hinweis“, „Datenfluss → Tool-Ergebnisse kürzen“.

Jede Integration in `lib/src/<id>/` mit `README.md`. Gerätezugriff ausschließlich über **Ports** (abstrakte Klassen); für jeden Port gibt es einen Fake unter `lib/testing/` und eine Contract-Suite, die die spätere Flutter-Implementierung bestehen muss.

## Integrationen und Tools
- **calendar** (`CalendarPort`: listCalendars, listEvents(range, calendarIds), createEvent, updateEvent, deleteEvent, defaultCalendarId)
  - `calendar__list_calendars` (r), `calendar__list_events` (r), `calendar__find_free_slots` (r, reine Dart-Logik: Arbeitszeitfenster, Mindestdauer, Puffer), `calendar__create_event` (w, mit Undo = löschen), `calendar__update_event` (w, Undo = alter Zustand), `calendar__delete_event` (e).
  - Zeitangaben ISO 8601; ohne Offset = Gerätezeitzone. Ergebnisse gekürzt: Titel, Start, Ende, Ort, Kalender – keine Teilnehmer/Beschreibung, außer `include_details: true`.
  - `describeForConfirmation`: „Termin ‚Tauchen‘ Do 10:00–11:00 löschen“ (deutsch formatiert).
- **clipboard** (`ClipboardPort`): `clipboard__read` (r), `clipboard__write` (w, Undo = alter Inhalt).
- **alarms** (`AlarmPort`: setAlarm(hour, minute, label, days?), setTimer(duration, label), listAlarms → nullable wenn nicht unterstützt): `alarms__set_alarm` (w), `alarms__set_timer` (w), `alarms__list` (r).
- **memory** (`MemoryStorePort`: save, search, forget, list – App verdrahtet mit `MemoryRepository`): `memory__save` (w), `memory__search` (r), `memory__forget` (w). Speichern nur, wenn Nutzer es ausdrücklich wollte – Tool-Beschreibung sagt das; sensible Kategorien werden abgewiesen (Port wirft → `isError`).
- **web** (`WebSearchBackend`-Interface mit `BraveSearchBackend`, `TavilyBackend`, `SearxngBackend`; `WebFetcher` über `http.Client`): `web__search` (r), `web__fetch` (r, nur http/https, keine privaten IP-Bereiche außer explizit erlaubt, max. Größe 2 MB, HTML → Text, Ergebnis als Daten markiert). Flag `serverSideAvailable`: Bei Anthropic-Profilen mit serverseitiger Suche wird die Integration nicht gebraucht (Entscheidung in der App).

Jede Integration implementiert `Integration` aus core (Availability, SetupSteps z. B. Kalender-Berechtigung, `sensitive`).

## Abnahmekriterien
- [ ] Alle Tool-Namen gültig, Schemas mit `required` und Beschreibungen, die ein kleines Modell versteht (kurz, Beispiele für Zeitformat).
- [ ] Tests je Tool mit Fake-Port (Erfolg, Port-Fehler, ungültige Argumente, Undo).
- [ ] `find_free_slots` tabellengetestet (Überlappungen, ganztägige Termine, Grenzen, Zeitzonen inkl. Sommerzeitwechsel).
- [ ] web: Fixtures für Brave/Tavily/SearXNG-Antworten, `web_fetch` blockt `file:`, `localhost`, `10.x`, `192.168.x` (außer Allowlist).
- [ ] Contract-Suites für alle Ports.
- [ ] README pro Integration.
- [ ] Gate grün, Abdeckung ≥ 85 %.
