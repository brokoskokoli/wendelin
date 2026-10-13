# WP19 – End-to-End M2 und Geräte-Testanleitung

Abhängig von: WP15–WP18.

## Inhalt
- Emulator (AOSP ohne GMS): Integrationstest, der statt Mikrofon eine WAV-Datei einspeist (Test-AudioInput), Whisper `base` lokal ausführt, den Agenten mit Fake- oder Live-Provider fährt und eine Notiz in einem Test-Vault ergänzt.
- Assistent setzen per adb (`cmd role add-role-holder android.app.role.ASSISTANT app.wendelin` bzw. Settings), Session-Start per adb simulieren.
- **Geräte-Testanleitung** `docs/testing/m2-device.md` für den Maintainer: APK installieren, Onboarding, Modell laden, Standard-Assistent setzen, Vault wählen, Testsätze (de/fr/en), erwartetes Ergebnis, Checkliste zum Abhaken, wie Logs/Audit exportiert werden.
- Live-Durchlauf (sparsam) mit Claude Haiku: gesprochener Satz aus WAV → Notiz ergänzt.
- README-Demo-Anleitung M2.
- Offene Punkte aus dem WP18-Review: (a) Mikrofon-Berechtigung erst anfragen, wenn Sprachmodelle vorhanden sind (sonst Hinweis „Spracherkennung laden“), (b) Widget-Tests „Berechtigung verweigert → Erklärung, kein Start“ für Hauptbildschirm und Overlay (N12/N14), (c) Test „Abbruch stoppt die gesprochene Bestätigungsfrage“ (N11), (d) Hinweis in Einstellungen → Assistent: nach Wechsel des Assistenten die Spracherkennung neu wählen, (e) Prüfpunkt Zwei-Engines (Overlay-Kaltstart → App öffnen → Overlay schließen → App schreibt weiter) auf dem Emulator.
- Offene Punkte aus dem WP20-Review: Test „App-Modellfehler: kein Ausweichen“ (Aufrufe von startWhisper zählen, N7); h3_ prüft „keine rms nach stopListening“ (K3) oder Vermerk; Frist für geteilte Erkennung auf ~20 s kürzen bzw. auf dem Gerät messen; eigene Client-App für den Pfad „Aufrufer hat Berechtigung, Wendelin nicht“; Aufnahme aus fremder App im Vordergrund und geteiltes Whisper auf dem Gerät prüfen.
- Laufzeitmessung Whisper base/small auf dem Emulator (und Vorlage für das Gerät des Maintainers) als Grundlage für den Standard (K-Vorschlag: small mit fester Sprache).

- Prüfpunkt aus WP18 (ADR 0006): Overlay kalt starten, dann die App öffnen, dann das Overlay schließen. Danach schreibt die App weiter: Anfrage senden, Verlauf und Audit-Log vorhanden, Index-Aufbau läuft (gemeinsamer drift-Isolate beider Engines). Außerdem nach Entzug der Assistenten-Rolle `WendelinRecognitionService` deaktiviert.

## Abnahmekriterien
- [ ] Integrationstest auf dem AOSP-Emulator grün (Log).
- [ ] Testanleitung vollständig, vom Reviewer gegengelesen.
