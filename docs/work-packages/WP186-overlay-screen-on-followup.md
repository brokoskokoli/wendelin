# WP186 – Overlay hält Bildschirm aktiv (FLAG_KEEP_SCREEN_ON) und schließt nicht vor Ende des Follow-Up-Fensters

**Zuordnung:** Befund Maintainer 2026-10-30 (Gerät geht nach Antwort bzw. während des 5-Sekunden-Follow-Up-Countdowns in den Ruhemodus, K148).

## Kontext & Problem
1. **Bildschirm-Timeout im gesperrten Modus:**
   Wenn das Weckwort das Telefon bei ausgeschaltetem Bildschirm aufweckt (`AssistantActivity.setTurnScreenOn(true)`), schaltet Android das Display ein. Da bei reiner Sprachbedienung keine Touch-Ereignisse auf dem Bildschirm stattfinden, greift der native Display-Inaktivitäts-Timeout (auf dem Sperrbildschirm ca. 15–20 Sekunden).
   Dauert die Sprachinteraktion (Befehl erkennen + Denken + Antwort vorlesen) rund 15–20 Sekunden, schaltet Android das Display mitten in der Sprachausgabe oder zu Beginn des 5-Sekunden-Follow-Up-Zuhörfensters aus (`SurfaceFlinger: Setting power mode 0 on display 0`).
   Das Abschalten des Displays ruft `AssistantActivity.onStop()` auf, was `closeOverlay()` -> `_close('platform')` -> `_voice.suspend()` auslöst und die gesamte Sprachsession abrupt abbricht.
2. **Follow-Up-Zuhörfenster im Overlay (`IdleCloser`):**
   Das Overlay muss während des aktiven 5-Sekunden-Follow-Up-Zählers (`voice.followUp`) zuverlässig offen bleiben. `nothingLeftToDo` muss `voice.followUp` berücksichtigen, und `IdleCloser` muss auf das Ende des Follow-Up-Fensters lauschen und erst danach per Idle (`by=idle`) schließen, falls keine weitere Spracheingabe erfolgte.

## Ziele & Maßnahmen
1. **`FLAG_KEEP_SCREEN_ON` in `AssistantActivity`:**
   - In `AssistantActivity.onCreate`: `window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)`.
   - Bei Beendigung des Overlays (`closeOverlay()`, `releaseHost()`, `onDestroy()`): `window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)`.
   - Dadurch bleibt der Bildschirm aktiv, solange das interaktive Overlay sichtbar ist, und geht erst nach regulärem Schließen des Overlays wieder in den Ruhezustand.
2. **Follow-Up-Schutz in `overlay_idle_close.dart`:**
   - In `nothingLeftToDo`: Bedingung um `voice.followUp` erweitern (`if (voice.active || voice.followUp || ...)`).
   - In `IdleCloser.listen()`: Listener auf `voiceControllerProvider.select((v) => v.followUp)` ergänzen (`if (was == true && !now) scheduleMicrotask(recheck);`).
3. **Tests:**
   - Kotlin-Unit-Tests in `AssistantActivityTest.kt` oder entsprechendem Test für das Setzen von `FLAG_KEEP_SCREEN_ON`.
   - Dart-Unit-Tests in `app/test/overlay/overlay_autoclose_test.dart` für:
     - Overlay bleibt während des Follow-Up-Fensters (`followUp = true`) geöffnet.
     - Overlay schließt nach Ablauf des Follow-Up-Fensters automatisch (`by=idle`).
     - Overlay schließt nicht während Sprachausgabe gefolgt von Follow-Up.

## Abnahmekriterien
- [ ] `AssistantActivity` setzt `FLAG_KEEP_SCREEN_ON` bei Erstellung und hält den Bildschirm während der gesamten Overlay-Sitzung aktiv.
- [ ] `FLAG_KEEP_SCREEN_ON` wird beim Schließen des Overlays entfernt.
- [ ] `nothingLeftToDo` schützt aktive Follow-Up-Fenster (`voice.followUp`).
- [ ] `IdleCloser` lauscht auf das Ende des Follow-Up-Fensters und schließt erst danach automatisch (`by=idle`).
- [ ] Tests in Dart und Kotlin grün, Gate grün, CI grün.
