# ADR 0021 – Engine-Group statt Flutter-Engine je Overlay (WP145)

Status: vorgeschlagen · 2026-10-24

## Kontext
Messung WP143 (Emulator, Debug-Build): Silero 30× laden/freigeben und Whisper 15× laden/freigeben sind flach, 20× Overlay öffnen und schließen lässt den Native Heap um rund 4,2 MB je Öffnung ohne Plateau wachsen, Java, Objekte und Activities bleiben flach. Ursache: Jedes Overlay (`AssistantActivity`, `StationActivity`) startete über den Standardweg von `FlutterActivity` eine neue Engine in einer **eigenen** `FlutterEngineGroup` (je Delegate neu angelegt). Damit teilt sich keine Engine Ressourcen mit einer anderen, und nach dem Zerstören bleibt Native-Speicher der Engine-Schicht hängen.

## Entscheidung
- Ein prozessweiter `FlutterEngineGroup` (`EngineGroups`, `app/android/.../EngineGroups.kt`, Zähllogik in `EnginePool`). Daraus entstehen: die headless Engines (`RecognizerEngine`: `recognizerMain`, `wakeWordMain`), `AssistantActivity` (`assistantMain`) und `StationActivity` (`stationMain`). Die erste Engine läuft allein, jede weitere wird von einer lebenden Geschwister-Engine gespawnt (geteilte Dart-VM-Ressourcen, Isolate-Gruppe). Der Wake-Dienst läuft dauerhaft, sodass Overlays normalerweise gespawnt werden.
- Die Overlays liefern ihre Engine über `provideFlutterEngine` und überschreiben `shouldDestroyEngineWithHost() = true`: eine Engine aus `provideFlutterEngine` gehört nach Flutters Vorgabe sonst dem Host und würde nie zerstört. Plugins werden beim Spawn registriert (`automaticallyRegisterPlugins`), `FlutterActivity.configureFlutterEngine` registriert bei Host-Engines nicht noch einmal; unsere Kanäle (`WendelinActivity.configureFlutterEngine`/`cleanUpFlutterEngine`) laufen unverändert. `MainActivity` und `WendelinActivity` bleiben unverändert.
- Log je Engine: `<tag>-engine-source group=new|shared fromSibling=… siblings=N live=M` (für die Messung).

## Abwägung
- **Gecachte Engine** (`FlutterEngineCache`, vorgewärmt): schnellster Start, aber Zustand (Dart-Statics, Provider, offene Sheets) bleibt zwischen Overlays hängen; ein Overlay muss immer frisch sein (kein Rest einer früheren Sitzung, kein persönlicher Inhalt hinter dem Sperrbildschirm). Außerdem hält eine dauerhaft lebende zusätzliche Engine ihren Speicher.
- **Engine-Group**: frischer Dart-Zustand je Overlay bleibt (neue Engine, neues Isolate), die Ressourcen werden geteilt, Kosten je Start etwas geringer. Preis: Das Zerstören der Overlay-Engine liegt in unserer Hand (siehe oben).
- Restrisiko: Läuft keine andere Engine (Wake aus), ist das Overlay die erste und einzige Engine; dann entfällt der Teil des Gewinns, der aus dem Teilen stammt. Ob das Plateau erreicht wird, belegt `docs/testing/m5/wp145.md` am Emulator.

## Folgen
- Alle Engines teilen sich Gruppe und Dart-VM; ein Absturz des Isolates einer Engine bleibt auf sie begrenzt, die Dart-VM aber ist gemeinsam.
- Neue Engines in Kotlin laufen über `EngineGroups.spawn`, nie über `FlutterEngine(context)`.
