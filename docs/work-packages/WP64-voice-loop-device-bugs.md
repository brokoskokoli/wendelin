# WP64 – Gesprächsmodus und Barge-in auf dem Gerät reparieren (`app/`, `wendelin_voice`)

Bezug: freier Gerätetest des Maintainers 2026-10-15 (Samsung, APK a290667), WP45/WP51, K23 c/d.

## Befunde vom Gerät
1. **Weiterhören nach der Antwort scheitert immer:** Ist der Gesprächsmodus an, erscheint nach jeder gesprochenen Antwort unten im Chat „Bad state: Die Aufnahme läuft bereits.“ Quellen der Meldung: `app/lib/voice/primed_audio_input.dart:130`, `app/lib/platform/voice/record_audio_input.dart:121`. Verdacht: Der Barge-in-Zuhörer während der Ausgabe (oder Pre-Roll/Priming) hält die Aufnahme noch, wenn das Weiterhören startet; im Emulator fiel das nicht auf, weil dort Barge-in nicht aktiv war.
2. **Barge-in geht nicht:** „Stopp“ oder „Wendelin“ während der Sprachausgabe unterbricht nicht. „Stopp“ schließt auch das Fenster nicht. „Stopp“ während einer Aufnahme funktioniert.
3. **Gewünschtes Verhalten (Maintainer):** „Wendelin“ während der Ausgabe → Ausgabe stoppen und sofort zuhören. „Stopp“ während der Ausgabe → Ausgabe stoppen und Overlay/Sitzung schließen.

## Inhalt
- Ursache von 1 finden und beheben: eine einzige Instanz besitzt das Mikrofon; Übergaben Ausgabe → Barge-in-Zuhören → Weiterhören sind ein sauberer Zustandsautomat (stop/await vor start, kein doppelter Start). Fehler dieser Art nie roh („Bad state“) anzeigen.
- Ursache von 2 finden (wird der Barge-in-Zuhörer auf dem Gerät überhaupt gestartet? Echo-Unterdrückung/`VOICE_COMMUNICATION` vs. `VOICE_RECOGNITION`, Erkennung von „Stopp“/„Wendelin“ während TTS, Lautstärke) und beheben; Verhalten aus 3.
- Diagnose-Logs (ohne Inhalte/Audio) für die Übergaben, damit der Maintainer per `adb logcat` liefern kann, falls es auf dem Gerät weiter hakt; Filter-Tag in `docs/testing/m4-device.md` nennen.

## Abnahmekriterien
- [ ] Unit-/Widget-Tests mit Fake-Audio: Ausgabe endet → Weiterhören startet ohne Fehler (auch bei schnellem Wechsel, auch mit aktivem Barge-in); doppelter Start ist unmöglich.
- [ ] Tests: „Wendelin“ während Ausgabe → Ausgabe stoppt, Zuhören startet; „Stopp“ während Ausgabe → Ausgabe stoppt, Overlay schließt.
- [ ] Emulator (separater E2E-Agent): Gesprächsmodus-Folgerunde ohne Fehlermeldung; Barge-in mit eingespeistem Audio, soweit der Emulator das erlaubt.
- [ ] Prüfpunkte in `docs/testing/m4-device.md` aktualisiert.
