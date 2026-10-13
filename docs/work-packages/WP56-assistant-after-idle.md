# WP56 – Power-Taste nach längerer Pause, Akku-Hinweise (`app/` Android + Einstellungen)

Abhängig von: – (sofort). Bezug: Rückmeldung des Maintainers 2026-10-14 (Xiaomi 15T Pro, HyperOS/Android 16): Wurde Wendelin länger nicht benutzt, öffnet langes Drücken der Power-Taste Wendelin nicht. Erst nachdem die App einmal geöffnet wurde, klappt es wieder.

## Vermutungen (zu prüfen, nicht vorab festlegen)
1. Hersteller-Akkusparer (HyperOS: „Akkusparer“, Autostart aus) friert den Prozess ein oder hindert das System daran, `WendelinVoiceInteractionService`/`WendelinVoiceSessionService` neu zu starten bzw. die Overlay-Activity aus dem Hintergrund zu starten.
2. Android App-Standby-Buckets (`rare`/`restricted`) oder Doze verzögern bzw. verhindern den Start.
3. Eigener Fehler: Kaltstart-Pfad der Sitzung (Flutter-Engine, Vorwärmen nur bei Sprachnutzung in den letzten 24 h, WP30) wartet, bricht still ab oder ein Timeout greift; `onShow`/`showSession` wird nicht erneut verbunden, nachdem der Prozess beendet wurde.

## Inhalt
**Diagnose (Emulator `Wendelin_AOSP_35`, nie echtes Gerät)**
- Szenarien nachstellen: Prozess beenden (`am kill`, `am force-stop` nur zum Vergleich), `am set-standby-bucket app.wendelin rare|restricted`, `dumpsys deviceidle force-idle`, `am set-inactive app.wendelin true`; danach Assistent auslösen (`cmd voiceinteraction show` bzw. äquivalent) und Startzeit/Erfolg messen. `dumpsys voiceinteraction` vor/nach prüfen (Dienst gebunden?).
- Diagnose-Log (ohne Inhalte, wie `voiceLog`): Zeitpunkte `service bound`, `onShow`, Engine-Start, erstes Bild, Abbruchgrund. Gerätetest-Skript für den Maintainer, das diese Log-Zeilen nach einem Fehlversuch per `adb logcat` sammelt (Anleitung, nicht von Agenten ausgeführt).
- Ergebnis als Notiz `docs/notes/assistant-after-idle-<datum>.md`.

**Fix je nach Befund**
- Eigener Fehler → beheben, erst roter Test (Kotlin-Unit oder Integrationstest), dann Fix.
- Kaltstart robust: Die Sitzung zeigt sofort ein natives Platzhalter-Fenster („Wendelin startet …“) und startet die Engine danach, statt still zu warten.

**Akku-Prüfung in der App**
- Status „Akku-Optimierung“: `PowerManager.isIgnoringBatteryOptimizations`. Wenn aktiv: Hinweis unter Einstellungen → Assistent (und im Onboarding-Schritt „Standard-Assistent“) mit Knopf, der `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (Permission `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; kein Play-Store, K7) bzw. als Rückfall die Systemliste öffnet.
- App-Standby-Bucket anzeigen (`UsageStatsManager.getAppStandbyBucket`), wenn `rare`/`restricted`.
- Hersteller-Hinweise: Für Xiaomi/HyperOS (und als Tabelle erweiterbar: Samsung, OnePlus, Huawei) kurze Anleitung „Autostart an, Akkusparer: Keine Einschränkungen“ mit Deep-Link, falls die Einstellungsseite per Intent erreichbar ist (vorher per `resolveActivity` prüfen, sonst nur Text). Diese Werte lassen sich nicht zuverlässig auslesen – der Hinweis ist eine Checkliste, kein Status.
- Gemeinsame Bausteine so bauen, dass WP50 (Wake-Word-Dienst) sie wiederverwendet.

## Abnahmekriterien
- [ ] Notiz mit nachgestellten Szenarien und Befund (welches Szenario reproduziert das Verhalten).
- [ ] Bei eigenem Fehler: roter Test → Fix; Szenario auf dem Emulator danach grün.
- [ ] Akku-Status und Hinweise mit Widget-Tests (aktiv/inaktiv, Bucket, Hersteller erkannt/unbekannt) und Golden; Kanal-Methoden im `app/channels.json` (Gate `check_channels`).
- [ ] Prüfpunkte für den Handytest des Maintainers in der Geräte-Testanleitung (vorher/nachher mit „Keine Einschränkungen“, nach 2 h / über Nacht).
