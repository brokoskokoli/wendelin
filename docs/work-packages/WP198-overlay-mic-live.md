# WP198 – Overlay (Assistent) zeigt „Moment …“, obwohl schon aufgenommen wird; Overlay-Logs fehlen

**Zuordnung:** Gerätetest v0.1.8-rc2 durch den Maintainer, 2026-11-13. Start über den Assistenten (Overlay, `AssistantActivity`): Es steht noch „Moment …“, das sofort gesagte „eins“ wird trotzdem erkannt. Die Aufnahme läuft also, nur die Anzeige schaltet nicht auf „Ich höre zu“ um. Das widerspricht WP194/K153.
**Konzept:** keine Änderung (Fehler zu K153).

## Befund
- Das Overlay ist angeschlossen: `assistant_overlay.dart:446` (`preparing: voice.preparing && !voice.micLive`), `micStateFor` (`voice_ui_state.dart:147`). `micLive` setzt nur `_onFirstFrame` (`voice_controller.dart:367`), und das nur, wenn `_timing.awaitingFirstFrame` gilt und `PrimedAudioInput` den ersten Block meldet.
- Vermutung 1: `PrimedAudioInput.prime()` (`primed_audio_input.dart:84`) kehrt bei `isRunning` sofort zurück. Läuft das Mikrofon schon (zentrales Mikrofon des Dienstes, Weckwort-Übergabe), kommt kein erster Block, und der Ton erreicht die Pipeline auf anderem Weg (Ringpuffer, Vorlauf).
- Vermutung 2: In der Overlay-Engine liefert `CentralAudioInput` bzw. der Fallback den Ton über einen Weg, der `onFirstFrame` umgeht. Oder der Ton kommt ganz aus dem Vorlauf bzw. der Weckwort-Übergabe (`_wake.begin`, `takePreRoll`), nicht aus dem vorab geöffneten Mikrofon.
- **Diagnoselücke:** Im Handy-Log (Release, MIUI) erscheinen aus der Overlay-Engine keine Zeilen `Wendelin/voice` (23:04–23:40 aktiv, keine einzige Zeile). Zeilen der Weckwort-Engine (`engine=wake`) und `Wendelin/dev` erscheinen dagegen. Ohne diese Zeilen ist `mic-ready` am Gerät nicht prüfbar.

## Inhalt
- **Teil A, Diagnose:** Ursache finden und beheben, warum `voiceLog` aus der Overlay-Engine nicht im Logcat landet (z. B. debugPrint bzw. stdout der zweiten Engine, eigener Isolate, Log-Weiterleitung über den Kanal der Weckwort-Engine). Beleg am Release-Build: Im Logcat erscheint eine Zeile mit `engine=overlay` (bzw. dem Namen der Engine).
- **Teil B, Ursache der Anzeige:** Mit einem roten Test die Startwege des Overlays nachstellen: Assistentengeste kalt (Modelle laden), mit laufendem zentralem Mikrofon und nach einem Weckwort-Treffer. Zeigen, an welcher Stelle der erste Block nicht gemeldet wird.
- **Teil C, Fix:** „Ich höre zu“ erscheint, sobald auf **irgendeinem** Weg Ton für diese Anfrage ankommt: vorab geöffnetes Mikrofon, schon laufendes zentrales Mikrofon oder Übergabe bzw. Vorlauf. Das Signal stammt nicht aus der Annahme, sondern aus dem tatsächlich eingetroffenen Ton.

## Abnahmekriterien
- [ ] Roter Test vor dem Fix, grün danach, für den Startweg des Overlays, der heute „Moment …“ zeigt, obwohl Ton ankommt.
- [ ] Test: Ohne Ton (Mikrofon liefert nichts) bleibt „Moment …“.
- [ ] Mutationsbelege.
- [ ] Gerät (Maintainer): Beim Start über den Assistenten wechselt die Anzeige auf „Ich höre zu“, bevor die Modelle geladen sind. Die `mic-ready`-Zeile der Overlay-Engine steht im Logcat (Gerätetest-Block `docs/testing/m5/wp198.md`).

## Parallel
- WP197 (Bestätigungston in der Ruhezeit) berührt `wake_pre_roll.dart`, hier nur lesen bzw. abstimmen.
