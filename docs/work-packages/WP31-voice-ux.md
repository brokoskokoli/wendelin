# WP31 – Sprach-UX: Rückmeldungen, Zuhör- und Sprech-Anzeige, „Neues Gespräch“ (`app/`, wenig `wendelin_voice`/`wendelin_integrations`)

Abhängig von: **WP30** (gemeinsame Stellen in `voice_controller.dart`, `preparing`-Signal), **WP26** (Kopf des Hauptbildschirms, Anzeige „Unterhaltung privat“ mit Aktion „Neue Unterhaltung“). Bezug: Gerätetest 2026-10-13 (`M2-fixes.md`), Befunde **B5, B8, B9, B13** und die UX-Wünsche zu Zuhören und Sprechen; B11 nur die Anzeige. Andockpunkte: `app/lib/ui/design/mic_button.dart` (`MicState`, `_ThinkingDots`, `_ListeningPainter`), `app/lib/ui/design/waveform.dart`, `app/lib/ui/screens/main_screen.dart`/`main_parts.dart` (`MainHeader`, Eingabezeile), `app/lib/ui/overlay/assistant_overlay.dart`/`overlay_sheet.dart`, `app/lib/voice/voice_controller.dart` (`VoiceUiState`, `cancel`), `app/lib/agent/agent_controller.dart` (`newTopic`, `isNewTopicCommand`, Undo), `app/lib/ui/settings/voice_screen.dart`, Bestätigungstext der Obsidian-Schreibtools (`packages/wendelin_integrations/lib/src/obsidian/obsidian_write_tools.dart`) und `confirmationPrompt`. Design: `docs/design/DESIGN.md`, `screens/main*`, `screens/overlay*`.

## Inhalt

**Abbruch und Rückgängig**
- **B5 „Stopp“:** Eine Stopp-Äußerung (`VoiceCancelled` mit Grund Stopp-Wort) blendet den alten Austausch aus und zeigt kurz den Status „Abgebrochen“. Im Overlay schließt sich das Sheet danach von selbst (Wunsch des Testers, Standard an; Einstellung „Stopp schließt das Overlay“ unter Sprache, siehe Fragen). Im Hauptbildschirm bleibt der Verlauf, und „Abgebrochen“ erscheint als Meta-Zeile. Das gilt sinngemäß auch für den Tipp-Abbruch.
- **B9 Rückgängig während der Sprachausgabe:** „Rückgängig“ stoppt die laufende Antwort-TTS sofort und sagt bzw. zeigt „Zurückgenommen.“ in der Sprache der Anfrage. Der Ton kommt nur, wenn die Anfrage per Stimme kam. Die `ToolResultCard` wechselt sichtbar in den Zustand „rückgängig“ (Design-Status, nicht nur Text). Im Hauptbildschirm erscheint zusätzlich eine Snackbar.

**Bestätigung**
- **B8 unscharfe Notizzuordnung vor der Freigabe:** Die Bestätigungskarte der Obsidian-Schreibtools zeigt den aufgelösten Notizpfad deutlich. Weicht der gesuchte Titel vom gefundenen ab (gefaltet verglichen; nach WP33 die Trefferart „unscharf“), steht ein Hinweis auf der Karte („Gefunden: Wendelin-Test“). Die gesprochene Frage nennt die Notiz („In Wendelin-Test den Abschnitt Status ersetzen, soll ich?“). Der Hinweis kommt also vor der Antwort, nicht danach.
- **Ring beim Warten auf Ja/Nein:** Bei `awaitingAnswer` zeigt der Mikrofon-Knopf in Hauptbildschirm und Overlay den Zuhör-Ring, im Overlay auch die Wellenform. Ein Tipp beendet das Zuhören (wie bisher: gilt als „nein“ bzw. Tippen).

**Anzeige von Zuhören und Sprechen**
- **Deutlichere Zuhör-Anzeige im Hauptbildschirm:** Beim Zuhören erscheint über der Eingabezeile eine Pegel-/Wellenform-Leiste (`Waveform` wie im Overlay, Design-Tokens) mit „Ich höre zu …“. Der Ring bleibt.
- **Eigener Sprech-Zustand:** `MicState.speaking` getrennt von `thinking`. Beim Sprechen bewegen sich die drei Punkte (Animation, respektiert `MediaQuery.disableAnimations`). Semantics-Label „Sprachausgabe stoppen“.
- **„Moment …“ (B11, Anzeige):** Solange WP30 `preparing` meldet (Modelle laden, nach dem Entsperren), zeigt der Knopf einen Vorbereitungszustand mit dem Text „Moment …“. Sprechen ist erst ab dem Ring sinnvoll. Weil WP30 puffert, geht auch ein früher Satzanfang nicht verloren.

**Gespräch**
- **Knopf „Neues Gespräch“** im Kopf des Hauptbildschirms (`MainHeader`, Icon-Knopf mit Tooltip, ≥ 44, nur sichtbar bei nicht leerem Verlauf). Er ruft `AgentController.newTopic()` auf, dieselbe Aktion wie „Neue Unterhaltung“ aus WP26. Die Benennung wird mit WP26 vereinheitlicht (ein Begriff in der ganzen App, Vorschlag „Neues Gespräch“). Im Overlay gibt es keinen eigenen Knopf (jedes Overlay zeigt nur die aktuelle Anfrage).
- **Tolerantere Erkennung:** `isNewTopicCommand` erkennt die ganze Äußerung als Befehl, wenn sie nur aus einer dieser Phrasen besteht (plus Füllwörter wie „bitte“, „okay“): de „neues Thema“, „neues Gespräch“, „neue Unterhaltung“, „vergiss das“, „fang neu an“; fr „nouveau sujet“, „nouvelle conversation“, „oublie ça“; en „new topic“, „new conversation“, „forget that“, „start over“. Längere Sätze („vergiss, dass ich morgen …“) bleiben normale Anfragen (Gedächtnis-Tool). Das gilt für Text und Stimme.
- **Senden-Knopf:** Ein sichtbarer Senden-Knopf in der Eingabezeile erscheint, sobald Text im Feld steht. Er ersetzt dort das Mikrofon oder steht daneben, je nach Design. Enter sendet weiter.

**Sprache**
- **B13 „Probe hören“:** Bei fester gesprochener Sprache kommt die Probe in dieser Sprache, bei „Wie die App“/„Automatisch“ in der App-Sprache (`voice_screen.dart`, statt `languageProvider`).

## Abnahmekriterien
- [ ] B5: Widget-Tests für Hauptbildschirm und Overlay: Stopp-Äußerung → „Abgebrochen“, alter Austausch im Overlay ausgeblendet, Overlay schließt (bzw. bleibt bei ausgeschalteter Einstellung).
- [ ] B9: Test mit Fake-TTS: „Rückgängig“ während `speaking` stoppt die TTS und spricht „Zurückgenommen.“ (nur bei Sprach-Anfrage). Karte im Zustand „rückgängig“ (Golden).
- [ ] B8: Bestätigungskarte und gesprochene Frage nennen die aufgelöste Notiz. Test mit unscharfer Zuordnung („Wendeline Test“ → `Wendelin-Test.md`): Der Hinweis steht vor der Antwort auf Karte und Frage, Tabellentest de/fr/en.
- [ ] `MicState.speaking` mit animierten Punkten, Vorbereitungszustand „Moment …“, Ring bei `awaitingAnswer`. Goldens für alle Knopfzustände, Test mit abgeschalteten Animationen.
- [ ] Zuhör-Leiste im Hauptbildschirm (Golden, reagiert auf Pegel im Widget-Test).
- [ ] Knopf „Neues Gespräch“ im Kopf: leert den Verlauf und startet eine neue Sitzung (Widget-Test), gleiche Aktion und Benennung wie die WP26-Anzeige, Semantics-Label, Touch-Ziel ≥ 44.
- [ ] `isNewTopicCommand` als Tabellentest (alle Phrasen de/fr/en, mit Füllwörtern, Gegenbeispiele mit längeren Sätzen).
- [ ] Senden-Knopf erscheint nur mit Text und sendet (Widget-Test). Golden.
- [ ] B13: „Probe hören“ nutzt die gesprochene Sprache (Test mit Fake-TTS, Sprache geprüft).
- [ ] Goldens gegen `docs/design/screens/*@1x.png` aktualisiert. Abweichungen vom Design (neue Leiste, Sprech-Zustand, Knopf im Kopf) im Abschlussbericht gemeldet.
- [ ] Emulator (`Wendelin_AOSP_35`, expliziter Serial): bestehende E2E-Läufe grün, Overlay-Stopp-Fall mit eingespeistem „Stopp“.
- [ ] Gate grün, APK baut.

## Prüfliste für den Maintainer (echtes Telefon)
- [ ] Overlay: Frage stellen, danach Mikrofon und „Stopp“ sagen. „Abgebrochen“ erscheint, die alte Antwort ist weg, das Overlay schließt.
- [ ] D1, während der Bestätigung „Rückgängig“ tippen. Die Sprachausgabe verstummt, „Zurückgenommen.“ ist zu hören und zu sehen.
- [ ] D3 mit leicht falschem Notiznamen. Die Karte und die gesprochene Frage nennen „Wendelin-Test“ vor dem Ja/Nein.
- [ ] Hauptbildschirm: Zuhören ist sofort erkennbar (Leiste), beim Sprechen bewegen sich die Punkte, beim Warten auf Ja/Nein ist der Ring da.
- [ ] Erster Tipp nach einer Pause zeigt kurz „Moment …“, dann den Ring.
- [ ] „Neues Gespräch“ im Kopf leert den Verlauf. „Vergiss das“ gesprochen tut dasselbe.
- [ ] „Probe hören“ mit gesprochener Sprache Français klingt französisch.
