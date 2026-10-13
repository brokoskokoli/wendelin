# WP53 – Gesperrtes Gerät: Taschenlampe ohne Entsperren (`app/` Overlay-Pfad)

Abhängig von: WP48 (Integration, Flag `allowedWhileLocked`), WP50 (Wake Word bei Sperre). Andockpunkte: Overlay mit Entsperr-Pfad (`app/lib/ui/overlay/assistant_overlay.dart`, `overlay_sheet.dart`, `AssistantChannel.kt`), Abfangen vor dem Routing wie bei „Neues Gespräch“ (`app/lib/agent/new_topic_command.dart`), Textfaltung `foldForMatch` (`packages/wendelin_core/lib/src/text/fold.dart`), Whisper im Overlay. Bezug: K16, K11 f.

## Inhalt
- Wird das Overlay bei gesperrtem Gerät geöffnet (Power-Taste oder Wake Word), hört es zu, ohne Inhalte anzuzeigen. Whisper erkennt lokal.
- Ein lokaler Befehlsabgleich (Regeln in de/fr/en, z. B. „Taschenlampe an/aus“, „Licht an“, „Lampe aus“, „allume la lampe“, „flashlight on“) führt das Taschenlampen-Tool direkt aus, **ohne Modellaufruf**. Rückmeldung als kurzer Ton bzw. „Taschenlampe an“ (keine Inhalte) und Undo nur nach dem Entsperren.
- Alles andere: „Bitte entsperre das Telefon“ (gesprochen nur dieser feste Satz), danach der bisherige Entsperr-Pfad mit der erkannten Äußerung erst nach dem Entsperren (oder verworfen, Entscheidung im Paket, Vorschlag: verwerfen, Datenschutz).
- Der Befehlsabgleich liegt als reine Logik in einem Paket (z. B. `wendelin_voice/src/text/`), nicht in `app/lib/di/`.
- Audit-Eintrag wie bei jedem Tool, mit Markierung „bei Sperre“.

## Abnahmekriterien
- [ ] Tabellentest des Befehlsabgleichs (positiv und negativ, drei Sprachen). Nichts außer Taschenlampen-Befehlen wird bei Sperre ausgeführt.
- [ ] Widget-Test Overlay „gesperrt“: Es wird kein Gesprächsverlauf, kein Text und keine Tool-Karte angezeigt. Bei Nicht-Taschenlampe gibt es keinen Agent-Aufruf (Fake-Agent zählt 0).
- [ ] Emulator (`Wendelin_AOSP_35`, Sperre per `locksettings set-pin` im Testlauf, danach entfernt): eingespeiste „Taschenlampe an“ bei Sperre → Fake-Torch meldet an. „Wie spät ist es“ → Entsperr-Hinweis, kein Modellaufruf.
- [ ] Gate grün.

## Prüfliste für den Maintainer (echtes Telefon)
- [ ] Gesperrt: „Wendelin, Taschenlampe an“ → LED an, ohne Entsperren. „Wendelin, Taschenlampe aus“ → aus.
- [ ] Gesperrt: „Wendelin, was steht morgen im Kalender?“ → nur „Bitte entsperre das Telefon“, keine Inhalte auf dem Sperrbildschirm.
