# WP64b – „Stopp“ allein unterbricht die Ausgabe (`app/`, `wendelin_voice`)

Abhängig von: WP64 (gemergt). Bezug: Gerätetest 2026-10-15, K23 c, K24 a.

## Befund
Der Barge-in-Zuhörer während der Sprachausgabe erkennt nur das eingelernte „Wendelin“ (`wake_barge_in.dart`, `KeywordSpec.wendelin`); die Art `stop` wird nie ausgelöst. „Wendelin, stopp“ geht seit WP64, „Stopp“ allein nicht.

## Inhalt
- „Stopp“ einlernen wie „Wendelin“ (WP60): im Einlernen ein kurzer zusätzlicher Schritt (z. B. 8–10 Mal „Stopp“), nur Embeddings, kein Audio. Für bereits eingelernte Nutzer: Hinweis auf der Seite „Aktivierungswort“ („Stopp einlernen, damit du die Ansage unterbrechen kannst“).
- Der Barge-in-Detektor nutzt beide Vorlagensätze mit derselben Merkmalskette; Treffer „Stopp“ → Ausgabe stoppen und Overlay schließen (Einstellung „Stopp schließt das Overlay“, K18 e), Treffer „Wendelin“ → wie WP64.
- Schwelle/Kalibrierung für „Stopp“ eigenständig (kurzes Wort, mehr Fehlalarme möglich); Echo der eigenen Sprachausgabe darf nicht auslösen (Test mit TTS-Ausgabe als Eingang).
- Ohne eingelerntes „Stopp“ bleibt das Verhalten wie heute (nur „Wendelin, stopp“), sichtbar erklärt.

## Abnahmekriterien
- [ ] Tests: Einlernen „Stopp“ (nur Embeddings gespeichert), Detektor meldet `stop` bzw. `wake` je Vorlage, Ausgabe stoppt und Overlay schließt; eigene TTS-Ausgabe löst nicht aus.
- [ ] Emulator (separater E2E-Agent) mit synthetischer Stimme.
- [ ] Prüfpunkt 11.6 in `docs/testing/m4-device.md` aktualisiert.
- [ ] Gate grün.
