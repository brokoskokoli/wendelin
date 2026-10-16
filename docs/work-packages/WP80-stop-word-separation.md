# WP80 – „Stopp“ während der Ausgabe trennt nicht, „Erweitert“ statt verstecktem Menü (`app/`, `wendelin_voice`)

Bezug: Gerätetest 2026-10-16 (Xiaomi, `ergebnisse.md` 11.6): Mit Kommunikation + AEC liegt die „Stopp“-Ähnlichkeit schon in Stille bei 0,91–0,92, beim Sprechen 0,91–0,93 (Schwelle 0,95) → kein Abstand; Aufschlag 0,00 → Selbstauslösung nach 2–3 s bei Stille im Mikrofon; ohne AEC übertönt die Ansage das Wort (0,67–0,86). „Wendelin“ trennt gut (Stille 0,81–0,84, Treffer 0,91).

## Inhalt
1. **Ursache klären:** Warum ist „Stopp“ in Stille so ähnlich (kurzes Wort, Vorlagen mit viel Stille/Rauschen, Merkmale unter AEC anders als beim Einlernen über VOICE_RECOGNITION)? Belege mit Merkmalsdaten aus Tests (synthetisch) und den Gerätewerten.
2. **Fix (mit Begründung, mehrere Bausteine möglich):** Vorlagen ohne Stille-Anteile (Trimmen per VAD beim Einlernen); Bewertung relativ zum laufenden Hintergrund (z. B. Treffer nur, wenn die Ähnlichkeit deutlich über dem gleitenden Stille-Niveau liegt und Sprache aktiv ist: RMS/VAD-Gate); Einlernen von „Stopp“ zusätzlich unter Barge-in-Bedingungen (während einer Probe-Ausgabe über Kommunikation + AEC) als Option; bestehende Vorlagen ggf. neu einlernen lassen (Hinweis in der UI).
3. **„Erweitert“ sichtbar:** Unter „Unterbrechen während der Antwort“ ein Button „Erweitert“ mit den Optionen (Quelle, Aufschlag) und je einer verständlichen Erklärung (Echo-Unterdrückung an/aus und Folgen; höher = weniger Fehlalarme, öfter überhört; niedriger = erkennt leichter, mehr Fehlalarme), „Standard“-Markierung und Zurücksetzen. Langes Drücken entfällt. Texte de/en/fr.
4. **Diagnose:** `barge-diag` zusätzlich mit Stille-Niveau und Abstand.

## Umsetzung
- Texte nur deutsch (App-Sprache ist WP79/M5), abweichend von „de/en/fr“ oben.
- Risiko: Die Stopp-Schwelle stammt aus dem Einlernen (ganzes Fenster) und gilt jetzt für das Fensterende (`stopTailShare`). Schlägt das am Gerät fehl, „Stopp“ neu kalibrieren.
- Ohne AEC schützt nur die niedrige Ähnlichkeit vor Echo.

## Abnahmekriterien
- [x] Tests für Ursache/Fix (Stille löst nicht aus, Sprache „Stopp“ über dem Hintergrund löst aus; Echo-Fall).
- [x] Widget-Tests/Goldens für „Erweitert“.
- [ ] Emulator (separater E2E-Agent): `voice_stop_word_e2e_test.dart` und `voice_barge_in_e2e_test.dart` grün.
- [ ] Prüfpunkte 11.6 aktualisiert. Gate grün.
