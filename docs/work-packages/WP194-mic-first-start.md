# WP194 – Start: Mikrofon zuerst, „Ich höre zu“, sobald es läuft

**Zuordnung:** Wunsch Maintainer 2026-11-13 (Gerätetest v0.1.8-rc1). Beim Start (Button, Halten, Weckwort, Assistentengeste) zeigt Wendelin noch „Moment …“, und Gesprochenes am Anfang geht verloren. Gewünscht ist: Das Mikrofon nimmt als Allererstes auf. Sobald es Ton liefert, zeigt die Oberfläche „Ich höre zu“, auch wenn die Modelle noch laden. Alles, was ab dann gesagt wird, wird verarbeitet.
**Konzept:** K153 (offen).

## Befund (Code, 2026-11-13, noch am Gerät zu belegen)
- `app/lib/voice/voice_controller.dart:200–275`: Sind die Modelle installiert, wird das Gerätemikrofon vorab geöffnet (`_primedFor(...).prime()`) und puffert, während `_loadComponents()` lädt. `state.preparing` bleibt dabei aber bis zum Ende des Ladens `true`. Die Oberfläche zeigt so lange „Moment …“: `mic_button.dart:104`, `overlay_sheet.dart:346`, `main_parts.dart:259`.
- `_startAfterLoading` (Modelle noch nicht bereit bzw. nicht geprüft): Prüfen, ob dort ebenfalls zuerst das Mikrofon geöffnet wird. Vermutlich nicht.
- Vor `prime()` liegen noch `await takePreRoll()` und `_askPrepare` (Berechtigungserklärung). Prüfen, was davon vor dem Mikrofon nötig ist.
- WP192-Folgepunkt: Wird Push-to-Talk losgelassen, bevor das Mikrofon läuft (Modelle laden), ergibt das „nichts verstanden“, und das Gesagte geht verloren.

## Inhalt
- **Teil A, Messen:** Gerätelog-Zeitstempel (nur Zahlen) für Trigger → Mikrofon offen → erster Block → Modelle geladen → Anzeige „hört zu“, je Startweg (kalt und warm). Damit ist belegt, wo heute Zeit und Ton verloren gehen.
- **Teil B, Mikrofon zuerst:** Auf allen Startwegen ist das Öffnen des Mikrofons der erste Schritt, auch in `_startAfterLoading`. Ausnahmen: Berechtigung fehlt, oder der Weckwort-Treffer hält das Mikrofon noch (Übergabe wie WP68/WP189, kein doppelter Ton). Der Puffer geht vollständig in die Erkennung.
- **Teil C, Anzeige:** Ein neuer Zustand bzw. ein Signal „Mikrofon liefert Ton“. Ab dem ersten Block zeigen Button, Overlay und Hauptbildschirm „Ich höre zu“ (bzw. den Push-to-Talk-Haltezustand) statt „Moment …“. Laden die Modelle danach noch, darf das höchstens als dezenter Hinweis erscheinen.
- **Teil D, Push-to-Talk:** Loslassen während des Ladens verarbeitet den gepufferten Ton, sobald die Modelle bereit sind.
- Endpointing bzw. VAD dürfen erst entscheiden, wenn sie laufen. Der Puffer wird nachgespielt (keine Stille-Entscheidung über ungeprüften Ton).

## Abnahmekriterien
- [ ] Test (fakeAsync, Fake-Mikrofon, verzögertes Laden): Gesprochenes ab dem ersten Mikrofonblock vor Ende des Ladens landet vollständig im Transkript.
- [ ] Test: Die Anzeige wechselt mit dem ersten Mikrofonblock auf „hört zu“, nicht erst nach dem Laden. Ohne Block (Mikrofon startet nicht) bleibt „Moment …“, und der bestehende Fehlerpfad greift.
- [ ] Test: Push-to-Talk wird während des Ladens losgelassen, und der gepufferte Ton wird verarbeitet.
- [ ] Der `_startAfterLoading`-Pfad öffnet das Mikrofon ebenfalls zuerst (Test).
- [ ] Mutationsbelege für Anzeige-Umschaltung, Pufferübergabe und den Pfad nach dem Laden.
- [ ] Gerät: Die Log-Zeitstempel vorher und nachher stehen im Paket. Ein Satz, der direkt nach dem Antippen gesprochen wird, wird vollständig erkannt (Gerätetest-Block `docs/testing/m5/wp194.md`).

## Parallel
- WP195 (Ende bei Schweigen) ändert den No-Speech-Zweig der Pipeline (`voice_pipeline.dart` ~291) und das Endpoint-Timeout. WP196 (Schriftgröße) ändert nur die Anzeige des Transkripts. Konfliktpunkte sind `overlay_sheet.dart` (WP196) und `voice_controller.dart` (nur hier).

## Nicht im Paket
- Modell-Ladezeiten selbst verkürzen.
