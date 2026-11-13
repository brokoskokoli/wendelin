# WP195 – Nichts gehört: nach 5 s still mit Stopp-Ton beenden

**Zuordnung:** Wunsch Maintainer 2026-11-13. Hört Wendelin nach dem Aufruf gar kein Wort, soll er nach 5 s ohne Sprachausgabe beenden: ein kurzer Stopp-Ton, dann Ruhe. „Nicht verstanden“ soll er nur sagen, wenn tatsächlich gesprochen wurde, aber nichts Brauchbares erkannt wurde.
**Konzept:** K154 (offen).

## Befund (Code)
- `packages/wendelin_voice/lib/src/pipeline/voice_pipeline.dart:291`: Bei `EndpointKind.nothing` (erste Runde) folgt `_nothingUnderstood`, und mit `speakNothingUnderstood` wird „nichts verstanden“ gesprochen (`voice_pipeline_text.dart:63`).
- Das No-Speech-Fenster ist 8 s (`EndpointConfig.noSpeechTimeout`, `endpointer.dart:16`) plus `listenGrace`.
- Ein leeres Transkript nach erkannter Sprache (`voice_pipeline.dart` ~310) soll weiter „nicht verstanden“ sagen.
- Es gibt einen Bestätigungston beim Weckwort (`wakeConfirmToneProvider`, `assistant_overlay.dart:126`), aber noch keinen Stopp-Ton.

## Inhalt
- No-Speech-Fenster der ersten Runde: 5 s ab dem Zeitpunkt, an dem das Mikrofon läuft (nicht ab dem Antippen). Für den Stationsmodus und den Gesprächsmodus gelten die eigenen Werte unverändert. Im Push-to-Talk-Haltemodus ist das Fenster ohnehin ausgesetzt.
- Bei `EndpointReason.noSpeech` (kein Wort erkannt): keine Sprachausgabe. Ein kurzer, leiser Stopp-Ton (eigenes kurzes Asset oder ein Systemton), Overlay bzw. Anzeige schließen, Gesprächsende `silence`. Wie beim Bestätigungston hängt der Ton an der Einstellung „Bestätigungston“ (aus = ganz still) und an den Ruhezeiten des Stationsmodus (kein Ton).
- Wurde Sprache erkannt, aber das Transkript ist leer oder unbrauchbar: wie bisher „nicht verstanden“.
- Ein Hinweis in der Oberfläche (ohne Sprache) ist erlaubt, z. B. „Nichts gehört“ kurz im Overlay.

## Abnahmekriterien
- [ ] Test (fakeAsync): Start ohne Sprache ergibt nach 5 s (+ Grace) Ende `silence`, keine Sprachausgabe, genau ein Stopp-Ton-Ereignis.
- [ ] Test: Sprache erkannt, Transkript leer, ergibt weiter „nicht verstanden“.
- [ ] Test: Bestätigungston aus bzw. Ruhezeit ergibt keinen Stopp-Ton. Das Folgefenster des Gesprächsmodus ist unverändert (still, kein Ton, oder Ton nach Entscheidung, siehe Rückfrage).
- [ ] Mutationsbelege (Zweig noSpeech vs. leeres Transkript, 5-s-Grenze, Tonschalter).
- [ ] Gerät: Antippen und schweigen ergibt nach etwa 5 s einen Ton, Ruhe, keine Ansage (Gerätetest-Block `docs/testing/m5/wp195.md`).

## Parallel
- WP194 ändert den Start in `voice_controller.dart` (wann das Mikrofon läuft). Das 5-s-Fenster soll ab dem ersten Mikrofonblock zählen; das bitte mit WP194 abstimmen (wer zuerst mergt, der andere zieht main nach). WP196 ändert nur die Schriftgröße.

## Nicht im Paket
- Ton für andere Ereignisse (Antwortende usw.).
