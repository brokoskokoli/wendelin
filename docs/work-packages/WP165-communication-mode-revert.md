# WP165 – Kommunikationsmodus zurück auf den früheren Stand (Antwort wird leiser)

**Zuordnung:** Meldung des Maintainers vom 2026-10-27 (rc10). Bezug: WP51 (Gesprächsmodus, AEC, ADR 0015), WP72 (Barge-in-Aufnahme), WP118 (Antwort als Gesprächston, K88/K93), WP146/WP151 (Sonderfälle bei Gesprächston).

## Befund (Maintainer)
- Sobald der Kommunikationsmodus angeht, während Wendelin spricht, wird die Stimme plötzlich leiser. Das wirkt „hier und da sehr komisch“.
- Wunsch: die Echo-Unterdrückung nicht mehr über den Kommunikationsmodus machen und den früheren, einfachen Stand wiederherstellen. Die seitdem eingebauten Sonderfälle analysieren und zurückbauen.

## Stand laut Historie (zu prüfen, nicht belegt)
- Früher (WP51/WP72): Aufnahme während der Ausgabe mit `VOICE_COMMUNICATION` und `AcousticEchoCanceler` (`app/lib/platform/voice/record_audio_input.dart`), Wiedergabe normal mit `USAGE_ASSISTANT` (`audio_playback.dart`, `AudioFocusChannel.kt`).
- WP118 (c6a6aa77, 89cad086, 7c543982; Merge 983346c4) und WP125 (07b4e365, 86a92998, 1d1fd6f9): Schalter `voice.speechCommunication` (`app/lib/di/app_settings.dart:41`, Standard aus), `SpeechRoute.kt`, `MODE_IN_COMMUNICATION`/`USAGE_VOICE_COMMUNICATION`, Lautsprecher-Route, Wiederherstellung, `WakeConflictWatcher`, Ausnahme in `WakePolicy.kt`, audioplayers-`audioMode inCommunication`, Berechtigung `MODIFY_AUDIO_SETTINGS`.
- Später: Sonderfälle bei Gesprächston in WP146 (4f815310) und WP151 (Prüfer B beim Unterbrechen, Parakeet-Rückfall, Echo-Filter ca27c1cf).
- Auf dem Handy des Maintainers ist der Schalter an (Aussage 2026-10-27), der Standard ist aus. WP118 ist damit die naheliegende Ursache. Trotzdem prüfen, ob die Ausgabe auch ohne Schalter leiser wird, z. B. durch die Aufnahme mit `VOICE_COMMUNICATION` während der Ausgabe.

## Entscheidung Maintainer (2026-10-27)
- Der Schalter „Antwort als Gesprächston“ wird ausgebaut, ebenso der ganze Code, der daran hängt. Es gibt nur noch den früheren Modus (Wiedergabe normal, Echo-Unterdrückung nur über die Aufnahme), keinen Kommunikationsmodus mehr. Sonderfälle, die nur für den Gesprächston gebaut wurden, fallen mit weg; was davon auch ohne Gesprächston wirkt, listet Teil A und bleibt nur nach Rückfrage.

## Inhalt
- **Teil A (Analyse):** Alle Änderungen seit WP51/WP72 am Audiopfad der Ausgabe und der Barge-in-Aufnahme auflisten (Datei:Zeile, Commit, Zweck). Ursache des Leiserwerdens belegen: Emulator-Log (`speech-route`, Audiomodus, Stream-Lautstärken), ggf. Dev-Log des Maintainers (nur mit seiner Freigabe). Ergebnis mit dem Maintainer klären: Was genau wird zurückgebaut (Schalter ganz entfernen oder nur Verhalten), was bleibt (z. B. Prüfer B beim Unterbrechen, Echo-Filter), falls es unabhängig vom Gesprächston nützt.
- **Teil B (Rückbau):** Den vereinbarten früheren Stand wiederherstellen. Gespeicherte Einstellung sauber migrieren (alter Wert wirkt nicht mehr), Audiomodus nach Updates nie im `IN_COMMUNICATION` hängen lassen. Nicht mehr gebrauchte Berechtigungen, Texte (ARB de/en/fr) und Tests entfernen. Gesprächsmodus, Barge-in und Weckwort beim Unterbrechen dürfen nicht schlechter werden als vor WP118 (Vergleich mit den Tests von WP113/WP151).
- Konzept: K88/K93 werden zurückgenommen bzw. ersetzt; als Abweichung melden.

## Abnahmekriterien
- [ ] Liste der Änderungen und belegte Ursache in der Fertigmeldung bzw. im Review-Ordner.
- [ ] Test, der den Kommunikationsmodus während der Ausgabe ausschließt (vor dem Rückbau rot, Mutationsbeleg).
- [ ] E2E auf dem Emulator: Antwort, Stopp und Folgerunde laufen; Audiomodus danach `NORMAL`.
- [ ] Gerätetest-Anleitung `docs/testing/m5/wp165.md` (Lautstärke während der Antwort gleichbleibend, Stopp/Unterbrechen 10×, Bluetooth).
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Start nach dem Merge von WP163 (Entscheidung Maintainer 2026-10-27), zusammen mit WP164.
- WP163 läuft (Overlay gesperrt, `overlay_sheet.dart`, Sprach-Controller für „nach Entsperren ausführen“). Konflikte möglich im Sprach-Controller; Audiopfad-Dateien (`audio_playback.dart`, `record_audio_input.dart`, `SpeechRoute.kt`, `WakePolicy.kt`) berührt WP163 voraussichtlich nicht.
