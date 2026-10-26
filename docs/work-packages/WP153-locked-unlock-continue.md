# WP153 – Gesperrtes Gerät: nach dem Entsperren sauber weitermachen

**Zuordnung:** Gerätebefund des Maintainers vom 2026-10-26 (rc5). Eigener Lauf, Ergebnis offen: zuerst Analyse.

## Befund
Befehl bei gesperrtem Gerät → Overlay meldet „Gerät muss entsperrt werden“. Nach dem Entsperren kam keine sinnvolle Anzeige: Wendelin hörte nicht mehr zu, das Fenster ging zu bzw. die Anfrage lief nicht weiter.

## Inhalt
1. **Analyse zuerst** (Regel „Erst verstehen, dann ändern“): Ablauf von der Sperr-Antwort bis nach dem Entsperren nachvollziehen. Andockpunkte: `app/lib/voice/locked_agent_run.dart` (welche Werkzeuge gesperrt erreichbar sind), `app/lib/ui/overlay/unlock_window.dart`, `assistant_overlay.dart`, `overlay_sheet.dart`, Kotlin-Seite (`requestDismissKeyguard` o. ä. unter `app/android/app/src/main/kotlin`). Fragen: Wer übernimmt nach dem Entsperren (Overlay oder App)? Geht die ausstehende Anfrage verloren? Wird das Overlay beim Keyguard-Wechsel oder `onStop` geschlossen? Endet die Aufnahme bzw. der Gesprächsmodus? Ursache mit Datei:Zeile und, wenn möglich, mit einem Emulator-Log belegen (Sperre am Emulator: `adb -s emulator-5554 shell input keyevent 26`, PIN setzen).
2. **Gewolltes Verhalten** (Vorschlag, bei Abweichung vor dem Fix melden): Nach dem Entsperren läuft genau die ausstehende Anfrage weiter (ohne erneutes Sprechen), die Antwort wird angezeigt und gesprochen, danach normaler Gesprächsmodus. Bricht der Nutzer das Entsperren ab, schließt das Fenster mit einem klaren Hinweis. Zeitgrenze für das Entsperren (z. B. 30 s), danach verworfen.
3. Fix an der Ursache, Tests für die Zustandsfolge (gesperrt → Entsperr-Aufforderung → entsperrt → Anfrage läuft; Abbruch; Zeitüberschreitung).

## Abnahmekriterien
- [ ] Bericht mit `Ursache:` (Datei:Zeile) und `Widerlegt:`.
- [ ] Tests für die drei Zustandsfolgen, je mit Mutationsbeleg.
- [ ] E2E auf dem Emulator mit Sperre und PIN: Anfrage läuft nach dem Entsperren weiter (Log).
- [ ] Gerätetest-Anleitung `docs/testing/m5/wp153.md`.
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Berührt Overlay und Sprachablauf: nicht gleichzeitig mit WP149 (Wake-Übergabe) und WP151 (Barge-in). Nach WP148 starten (Dev-Logging hilft bei der Analyse).
