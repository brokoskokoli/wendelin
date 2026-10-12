# WP11 – End-to-End, Live-Tests, Demo-Anleitung

Abhängig von: allen. Konzept-Bezug: Meilenstein M1 „Fertig, wenn …“, „Integrationstests auf Emulator“.

## Inhalt
- `app/integration_test/`: auf dem Android-Emulator (AVD `Medium_Phone_API_35`):
  1. Onboarding mit Fake-Provider durchlaufen.
  2. „Trag mir morgen um 10 Tauchen ein“ → Kalender-Berechtigung (per `adb shell pm grant` vorab) → Termin im echten Gerätekalender (lokaler Kalender) angelegt → Rückgängig entfernt ihn.
  3. external-Tool (`calendar__delete_event`) → Bestätigung.
- Live-Durchlauf (manuell ausgelöst, Keys aus Env): derselbe Satz mit Claude Haiku und mit einem OpenAI-kompatiblen Modell gegen die echte Agent-Schleife (Dart-Test mit Fake-Kalenderport) und, falls möglich, im Emulator.
- Kurzer Eval-Lauf (10 Fälle) je Live-Provider, Report in `evals/reports/`.
- `README.md` im Repo-Root: Was ist Wendelin, Status, Aufbau, Gate, Demo-Anleitung M1, Lizenzhinweise (Fonts OFL).
- GitHub Actions: Gate auf jedem Push (ohne live).

## Abnahmekriterien
- [ ] Integrationstests laufen auf dem Emulator grün (Log im PR).
- [ ] Live-Ergebnis dokumentiert (welches Modell, Erfolg, Kosten).
- [ ] CI grün auf `main`.
