# Wecker und Timer (`alarms`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `alarms__set_alarm` | write | Wecker `HH:MM`, optional Name und Wiederholungstage (1 = Montag … 7 = Sonntag) |
| `alarms__set_timer` | write | Timer in Sekunden (1 s bis 24 h) |
| `alarms__list` | read | Gestellte Wecker, wo die Plattform das erlaubt; sonst Fehler mit Hinweis |

**Undo**: nur, wenn der Port eine Id zurückgibt (`AlarmPort.cancel`). Android-`AlarmClock`-Intents liefern keine Id; dort gibt es weder Undo noch Liste.

**Port**: `AlarmPort` (`setAlarm`, `setTimer`, `cancel`, `listAlarms` → `null` wenn nicht unterstützt). Fake: `FakeAlarmPort` (`returnsIds`, `canList`), Vertrag: `alarmPortContract`.

**Umsetzung**: Android `AlarmClock.ACTION_SET_ALARM`/`ACTION_SET_TIMER` mit `SKIP_UI` (Berechtigung `com.android.alarm.permission.SET_ALARM`), iOS AlarmKit (iOS 26+), sonst lokale Benachrichtigung. **Plattformen**: Android, iOS. **Sensibel**: nein.
