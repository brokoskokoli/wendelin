# Kalender (`calendar`)

Alle Systemkalender des Geräts (Google, Exchange, CalDAV, lokal). Neue Termine landen im vom Nutzer gewählten Standardkalender (`CalendarPort.defaultCalendarId`), sonst im ersten beschreibbaren.

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `calendar__list_calendars` | read | Kalender mit Id, Name, Schreibrecht, Standard |
| `calendar__list_events` | read | Termine im Zeitraum; gekürzt auf Titel, Start, Ende, Ort, Kalender. Notizen und Teilnehmer nur mit `include_details: true`. Höchstens 50 Termine, 92 Tage |
| `calendar__find_free_slots` | read | Freie Zeiten in einem Tagesfenster (Standard 08:00–20:00), Mindestdauer (30 min), Puffer, Wochentage; höchstens 31 Tage |
| `calendar__create_event` | write | Termin anlegen (Standard 1 h). Undo löscht ihn wieder |
| `calendar__update_event` | write | Termin ändern (nur genannte Felder; nur Start → Dauer bleibt). Undo stellt den alten Zustand her |
| `calendar__delete_event` | external | Termin löschen, immer mit Bestätigung: „Termin ‚Tauchen‘ Do 15.10. 10:00–11:00 löschen“ |

**Zeiten**: ISO 8601. Ohne Offset gilt die Gerätezeitzone (`ToolContext.timeZone`, IANA), mit `time_zone` eine vom Nutzer genannte Zone. Ausgaben tragen immer den Offset (`2026-10-15T10:00:00+02:00`). Ganztägige Termine: im Tool-API Datum und **letzter** Tag (inklusiv), im Port UTC-Mitternacht mit exklusivem Ende (wie Android `CalendarContract`). Umrechnung mit `package:timezone`, damit Sommerzeitwechsel stimmen.

**Freie Zeiten**: Termine mit `busy: false` (als „frei“ markiert, z. B. Geburtstage) blockieren nicht. Ganztägige belegte Termine blockieren die lokalen Tage ganz. Das Tagesfenster wird je lokalem Datum gebildet, am Tag der Zeitumstellung ist 00:00–06:00 also 5 bzw. 7 Stunden lang.

**Bestätigungstext**: `describeForConfirmation` ist synchron und kennt nur die Argumente. Die Integration merkt sich deshalb zuletzt gesehene Termine (bis 500), um beim Löschen Titel und Zeit zu nennen; unbekannte Ids erscheinen als „Termin (ID …) löschen“. Serientermine werden mit „(ganze Serie)“ markiert.

**Port**: `CalendarPort` (`hasPermission`, `listCalendars`, `defaultCalendarId`, `listEvents`, `getEvent`, `createEvent`, `updateEvent`, `deleteEvent`). Fake: `FakeCalendarPort`, Vertrag: `calendarPortContract`.

**Berechtigung**: `READ_CALENDAR`/`WRITE_CALENDAR` (Android), EventKit-Vollzugriff (iOS); Setup-Schritt `calendar_permission`. **Plattformen**: Android, iOS. **Sensibel**: ja.
