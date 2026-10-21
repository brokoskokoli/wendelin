# WP118 – Antwort als Gesprächston für bessere Echo-Unterdrückung (`app/`, Android)

**Zuordnung:** M5-Nachtest (Gerätetest 2026-10-20, T20-B.1). Entscheid Stefan 2026-10-21 (K88): zuerst nur ein Schalter, Messung per Ping und eigene Echo-Unterdrückung erst, wenn das nicht reicht.

## Hintergrund
Während der Ausgabe nimmt die App mit `VOICE_COMMUNICATION` und dem Android-`AcousticEchoCanceler` auf (`app/lib/platform/voice/record_audio_input.dart:18-60`), spielt die Antwort aber mit `USAGE_ASSISTANT` ab (`app/lib/platform/voice/audio_playback.dart:27`, `AudioFocusChannel.kt:58`). Viele Geräte unterdrücken das Echo nur im Telefonie-Pfad zuverlässig. Gemessen: „Stopp“ erreicht 0,72–0,94 statt der nötigen 0,95.

## Inhalt
1. Einstellung unter Sprache → „Erweitert“: „Antwort als Gesprächston (bessere Echo-Unterdrückung)“, Standard **aus**. Texte über ARB (de/en/fr), Hinweis auf die Nebenwirkungen (Anruf-Lautstärke, Klang, Bluetooth).
2. Wenn an: Während der Antwort laufen Wiedergabe mit `USAGE_VOICE_COMMUNICATION` (bzw. passender Kombination) und Audiomodus `MODE_IN_COMMUNICATION`. Die Ausgabe wird auf den Lautsprecher gelegt (`setCommunicationDevice` ab API 31, sonst `setSpeakerphoneOn`), außer ein Kopfhörer oder Bluetooth-Gerät ist aktiv. Nach der Antwort wird der vorige Zustand sauber wiederhergestellt, auch bei Abbruch, Fehler oder Stopp.
3. Beim Wechsel in den Gesprächsmodus prüfen, dass Wake Word und Erkennung nicht gestört werden (`WakePolicy.kt:184-193` behandelt `MODE_IN_COMMUNICATION` heute als „Telefonat“ und pausiert womöglich; die eigene Antwort darf das nicht auslösen).
4. Logzeile `speech-route` mit Modus, Usage und Ausgabegerät (kein Inhalt). `barge-diag` bleibt, damit der Gerätetest die Stopp-Werte mit und ohne Schalter vergleichen kann.

## Abnahmekriterien
- [ ] JVM-/Unit-Tests für Ein/Aus, Wiederherstellung nach Abbruch/Fehler, kein „Telefonat“-Fehlalarm in der WakePolicy durch die eigene Antwort (Mutationsbeleg).
- [ ] E2E auf dem Emulator: Antwort mit Schalter an läuft durch, Zustand danach wie vorher.
- [ ] Gerätetest-Datei `docs/testing/m5/wp118.md`: Stopp 10× mit Schalter aus und an, Werte aus `barge-diag` notieren; Lautstärke, Klang, Bluetooth prüfen.
- [ ] Gate `--changed` grün, CI grün, Review FREIGABE.

## Nicht dazu
Ping-/Sweep-Messung, eigene Echo-Unterdrückung (WebRTC AEC3): nur als Folgepaket, falls der Schalter nicht reicht.

## Parallel-Hinweise
- Startet nach dem Merge von WP113 (beide ändern Ausgabe/Barge-in). WP114 (Overlay bei Sperre) danach oder davor, nicht gleichzeitig mit WP113.
