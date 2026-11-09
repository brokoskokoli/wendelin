# WP188 – Audio-Einstellungen: Mikrofon und Ausgabe wählen (`app/lib/ui/settings`, `app/lib/platform/voice`, `app/android/.../wendelin`)

**Zuordnung:** Wunsch Maintainer 2026-11-09, K149. Baut auf der zentralen Aufnahme auf (ADR 0024, K144, K145, K147).

Bezug: Der Maintainer will in der App einstellen, welches Mikrofon und welcher Lautsprecher verwendet wird. Standard ist das System; ein gewähltes Gerät wird immer benutzt, wenn es verfügbar ist.

## Entscheidungen des Maintainers (2026-11-09)
1. **Eine Wahl je Richtung:** Für Mikrofon und Ausgabe gibt es je „System“ (Standard) oder ein bestimmtes Gerät. Das gewählte Gerät ist zugleich der Favorit: Ist es da, wird es benutzt; fehlt es, gilt das System; kommt es zurück, wird automatisch wieder umgeschaltet. Es gibt keine einmalige Umstellung und keine Rangliste.
2. **Bluetooth-Mikrofon nur im Gespräch:** Das Weckwort hört weiter über das Handy-Mikrofon, erst im Dialog wird auf das Headset umgeschaltet (der Telefonmodus verschlechtert Musik und kostet Headset-Akku).

## Befund (Stand main, 2026-11-09)
- **Mikrofon:** Eine zentrale Aufnahme in `RecognizerAudio.kt:77` (`AudioRecord.Builder`, `VOICE_RECOGNITION`); dort ist `setPreferredDevice` möglich. Der Dienst und die Abonnenten: `CentralAudioHub.kt`, `CentralAudioChannel.kt`, `WakeWordService.kt`, Ringpuffer `AudioRingBuffer.kt`.
- **Ausgabe:** Beide Wege können kein Zielgerät wählen.
  - `audio_playback.dart:24`: `audioplayers` (`MediaPlayer`) bietet nur `isSpeakerphoneOn`. Benutzt in `voice_providers.dart:396`, `wake_providers.dart:427`, `wake_settings.dart:58`.
  - `system_tts.dart:21`: `flutter_tts`, die Engine spielt selbst ab.
- **Falle:** `WakePolicy.kt:253-258` wertet jedes `MODE_IN_COMMUNICATION` als Telefonat. Der eigene Telefonmodus für das Headset darf das Mikrofon nicht als Fremdkonflikt pausieren. Dasselbe gilt für `WakeConflictWatcher.kt`.

## Inhalt
1. **Geräteliste und Port:** Port mit Geräteliste (Eingabe, Ausgabe) und Änderungs-Stream über `AudioManager.getDevices` und `AudioDeviceCallback`, dazu Fake. Gespeichert wird ein stabiler Schlüssel (Typ, Produktname, Adresse), nicht `AudioDeviceInfo.id`, die sich beim Wiederverbinden ändert. Keine Geräteadressen in Logs.
2. **Einstellung und Oberfläche:** Zwei Einstellungen (Mikrofon, Ausgabe) mit „System“ und den verfügbaren Geräten, erreichbar aus den Einstellungen. Ein gewähltes, gerade fehlendes Gerät bleibt sichtbar und markiert („nicht verbunden, System wird benutzt“). Die Zeile zeigt, was gerade benutzt wird. Texte über l10n (de/en). Hinweis: Die Wahl gilt nur für Wendelins Sprache und Töne, nicht für Musik anderer Apps. Nur auf Android sichtbar.
3. **Ausgabe-Weg:** Kleiner eigener Abspielweg in Kotlin (`AudioTrack` mit `setPreferredDevice`, `USAGE_ASSISTANT`, `CONTENT_TYPE_SPEECH`) hinter dem bestehenden Port `AudioPlayback` (`sherpa_tts.dart:26`). Verhalten wie bisher: Ende-Meldung, Stopp sofort (Barge-in), Ducking und Fokus (`DuckingTextToSpeech`). Alle Aufrufer von `AudioplayersPlayback` prüfen; Wendelins Töne folgen derselben Wahl. System-Stimme: Bei gewähltem Gerät in eine Datei synthetisieren und über diesen Weg abspielen; bei „System“ bleibt der direkte Weg ohne Zusatzlatenz.
4. **Mikrofon-Weg:** Gewähltes Gerät in der zentralen Aufnahme setzen; die Einstellung muss den Dienst erreichen, auch nach Neustart und ohne laufende Flutter-Oberfläche. Kabel und USB gelten auch für das Weckwort. Bluetooth nur im Dialog: API 31+ `setCommunicationDevice`, API 29–30 `startBluetoothSco`, am Dialogende sicher zurück, auch bei Abbruch und Absturz des Dialogs. Die Falle aus dem Befund behandeln, ohne die Erkennung echter Telefonate zu verlieren.
5. **Laufzeitverhalten:** Gerät kommt oder geht während der Aufnahme bzw. Ausgabe: automatisch umschalten nach Entscheidung 1, kein Abbruch der Sitzung, kein Hänger, Zusammenspiel mit dem Ringpuffer.

## Umsetzung
- **Teile für die Coder-Aufträge**, je ein Auftrag ohne Übergabe, in dieser Reihenfolge: Teil A: Geräteliste, Port, Schlüssel, Einstellung (Inhalt 1). Teil B: Oberfläche (Inhalt 2). Teil C: Ausgabe-Weg (Inhalt 3). Teil D: Mikrofon ohne Bluetooth, Laufzeitwechsel (Inhalt 4, 5). Teil E: Bluetooth im Dialog (Inhalt 4).
- Vor Teil C und E prüfen und im Bericht belegen: Welche Berechtigungen sind nötig (`MODIFY_AUDIO_SETTINGS`, `BLUETOOTH_CONNECT`)? Das Manifest enthält heute keine Bluetooth-Berechtigung. Auf welchem Weg läuft die Ausgabe, während der Telefonmodus aktiv ist? Wirkt die Echounterdrückung beim Barge-in (`VOICE_COMMUNICATION`) weiter?
- Beim Umschalten auf das Headset läuft das Handy-Mikrofon weiter, bis Headset-Ton ankommt. So entsteht im Ringpuffer keine Lücke und der Befehlsanfang geht nicht verloren.
- ADR 0025 (eigener Abspielweg, Gerätewahl, Bluetooth nur im Dialog) als Entwurf auf dem Branch; `docs/architecture/` nachziehen.
- **Nicht im Paket:** Musik anderer Apps umleiten, Spotify- oder Cast-Gerätewahl, Rangliste, Testton oder Pegelanzeige, iOS, Weckwort über Bluetooth.
- Parallel: keine andere Paket-Sitzung läuft (Stand Start).

## Abnahmekriterien
- [ ] Standard „System“: Verhalten und Latenz wie vorher, ohne neue Berechtigungsabfrage (Tests).
- [ ] Auswahl übersteht Neustart und Wiederverbinden (stabiler Schlüssel, Test mit wechselnder `id`).
- [ ] Gewähltes Gerät fehlt: System wird benutzt, die Oberfläche zeigt das; Gerät kommt zurück: automatisch zurück, auch während einer Sitzung (Tests mit Fake).
- [ ] Sprachausgabe mit beiden Stimmen-Wegen auf dem gewählten Gerät; Stopp und Barge-in, Ende-Meldung und Ducking wie vorher (Tests, Kotlin-Unit-Tests für die reine Logik).
- [ ] Bluetooth gewählt: Weckwort nicht im Telefonmodus; Telefonmodus nur im Dialog und danach sicher beendet, auch bei Abbruch; der eigene Telefonmodus pausiert das Mikrofon nicht, ein echtes Telefonat weiterhin schon (Tests, Mutationsbeleg für diese Unterscheidung).
- [ ] Keine Lücke im Ringpuffer beim Umschalten (Test).
- [ ] E2E (separater Agent, Emulator): Standard „System“ ohne Regression im Dialog; Einstellungsseite; Gerät fehlt beim Start.
- [ ] Gerätetest `docs/testing/m5/wp188.md` für den Maintainer: Kabel oder USB falls vorhanden, Bluetooth-Kopfhörer, Bluetooth-Box, Trennen und Wiederverbinden während der Antwort, Musik plus Weckwort mit Bluetooth-Mikrofon, Befehl im selben Atemzug, Telefonat während des Dialogs.
- [ ] Doku nachgezogen, Abweichungen im Abschlussbericht. Gate und CI grün.
