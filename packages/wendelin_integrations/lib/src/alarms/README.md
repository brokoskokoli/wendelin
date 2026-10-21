# Wecker und Timer (`alarms`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `alarms__set_alarm` | write | Wecker `HH:MM`, optional Name und Wiederholungstage (1 = Montag … 7 = Sonntag) |
| `alarms__set_timer` | write | Timer in Sekunden (1 s bis 24 h) |
| `alarms__list` | read | Gestellte Wecker, wo die Plattform das erlaubt (Android: nur der nächste, `only_next: true`, leere Liste = kein Wecker); sonst Fehler mit Hinweis |

**Undo**: nur, wenn der Port eine Id zurückgibt (`AlarmPort.cancel`, `supportsCancel`). Android-`AlarmClock`-Intents liefern keine Id; dort gibt es weder Undo noch Liste, und `cancel` wirft `PortException(unsupported)`.

**Erwartungen an die Plattform-Implementierung (WP08)**:
- `isAvailable()` meldet, ob Wecker überhaupt gestellt werden können; `checkAvailability` der Integration nutzt das.
- Android: Unterstützt keine Uhr-App den `AlarmClock`-Intent (Gerät ohne Google-Uhr, K7), stellt der Port den Wecker bzw. Timer selbst als exakte lokale Benachrichtigung (`SCHEDULE_EXACT_ALARM`). Nur wenn auch das nicht geht, ist `isAvailable()` `false`.
- Der Vertrag `alarmPortContract` stellt nur dann Wecker und Timer, wenn `supportsCancel` gilt, und löscht sie wieder. Ohne Abbrechbarkeit prüft er nur die Argumentprüfung und `cancel`; auf dem Gerät bleibt nichts zurück.

**Port**: `AlarmPort` (`isAvailable`, `supportsCancel`, `setAlarm`, `setTimer`, `cancel`, `listAlarms` → `null` wenn nicht unterstützt, `listsOnlyNext`: Android kennt nur den nächsten Wecker per `AlarmManager.getNextAlarmClock`, Kanal `app.wendelin/alarm`). Fake: `FakeAlarmPort` (`returnsIds`, `canList`, `onlyNext`), Vertrag: `alarmPortContract`.

**Umsetzung**: Android `AlarmClock.ACTION_SET_ALARM`/`ACTION_SET_TIMER` mit `SKIP_UI` (Berechtigung `com.android.alarm.permission.SET_ALARM`), iOS AlarmKit (iOS 26+), sonst lokale Benachrichtigung. **Plattformen**: Android, iOS. **Sensibel**: nein.
