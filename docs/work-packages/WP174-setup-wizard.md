# WP174 – Einrichtungsassistent beim ersten Start

**Zuordnung:** Wunsch des Maintainers vom 2026-10-28. Baut auf WP173 auf (getrennte Menüs Sprache/Weckwort, Weckwort-Modell oben).

## Wunsch (sinngemäß)
Beim ersten Öffnen läuft ein Einrichtungsassistent, der einmal **bis zum Ende** durchlaufen werden muss; vorher ist die App nicht nutzbar (nach Abbruch beim nächsten Öffnen an derselben Stelle weiter). Entscheidung Maintainer: **auch bestehende Installationen** sehen ihn nach dem Update einmal (bereits erfüllte Schritte sind abgehakt).

Seiten:
1. **Willkommen** (kurz, was Wendelin ist).
2. **KI-Anbieter** (Pflicht): Knopf „Anbieter eintragen“ öffnet den bestehenden Anbieter-Dialog. Zurück führt auf diese Seite; dort steht dann, dass ein Anbieter eingerichtet ist, und erst dann geht „Weiter“.
3. **Sprache** (Pflicht): Silero VAD und ein unterstütztes Erkennungsmodell herunterladen. Auf der Seite ein Auswahlfeld mit dem Modell (Standard **Parakeet**) und „Herunterladen“, darunter Silero VAD. Erst wenn beides geladen ist, „Weiter“ (Fortschritt sichtbar).
4. **Weckwort** (optional): Knopf öffnet das Weckwort-Menü (WP173). Zum Einschalten muss das trainierte Weckwort-Modell geladen werden. Zurück → Seite zeigt den Stand (eingerichtet und in Ordnung bzw. nicht eingerichtet); „Weiter“ geht immer, „Ohne fortfahren“ ausdrücklich möglich.
5. **Integrationen** (optional): Knopf öffnet das Integrationen-Menü; keine Pflicht, „Weiter“ geht immer.
6. **Personalisierung** (optional): Sprechererkennung („Möchtest du, dass Wendelin dich erkennt?“): Erkennungsmodell herunterladen, Sätze einsprechen (bestehender Einlern-Ablauf), dann „Weiter“.
7. **Abschluss** → App normal nutzbar.

Während der Assistent nicht abgeschlossen ist, führt **Zurück** in jedem aus dem Assistenten geöffneten Einstellungsmenü immer auf die passende Seite des Assistenten (auch System-Zurück). **Nach dem Abschluss** funktionieren die Einstellungsseiten wieder wie vorher (normale Navigation).

## Abnahmekriterien
- [ ] Widget-Tests je Seite (Pflichtseiten sperren „Weiter“ ohne Voraussetzung, optionale nie), Zurück-Verhalten vor/nach Abschluss, Fortsetzen nach Abbruch, Bestandsinstallation sieht den Assistenten einmal mit abgehakten Schritten; Mutationsbelege.
- [ ] E2E auf dem Emulator: frische Installation durch den Assistenten (Downloads per Fake bzw. Test-Server), danach App nutzbar; Update-Fall.
- [ ] Texte de/en/fr, Goldens, Gerätetest-Anleitung `docs/testing/m5/wp174.md`.
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Start nach dem Merge von WP173. Berührt App-Start/Router (`app/lib/ui/`), Einstellungsseiten nur über einen gemeinsamen „Zurück zum Assistenten“-Mechanismus.
