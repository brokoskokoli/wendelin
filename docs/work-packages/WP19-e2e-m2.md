# WP19 – End-to-End M2 und Geräte-Testanleitung

Abhängig von: WP15–WP18.

## Inhalt
- Emulator (AOSP ohne GMS): Integrationstest, der statt Mikrofon eine WAV-Datei einspeist (Test-AudioInput), Whisper `base` lokal ausführt, den Agenten mit Fake- oder Live-Provider fährt und eine Notiz in einem Test-Vault ergänzt.
- Assistent setzen per adb (`cmd role add-role-holder android.app.role.ASSISTANT app.wendelin` bzw. Settings), Session-Start per adb simulieren.
- **Geräte-Testanleitung** `docs/testing/m2-device.md` für den Maintainer: APK installieren, Onboarding, Modell laden, Standard-Assistent setzen, Vault wählen, Testsätze (de/fr/en), erwartetes Ergebnis, Checkliste zum Abhaken, wie Logs/Audit exportiert werden.
- Live-Durchlauf (sparsam) mit Claude Haiku: gesprochener Satz aus WAV → Notiz ergänzt.
- README-Demo-Anleitung M2.

## Abnahmekriterien
- [ ] Integrationstest auf dem AOSP-Emulator grün (Log).
- [ ] Testanleitung vollständig, vom Reviewer gegengelesen.
