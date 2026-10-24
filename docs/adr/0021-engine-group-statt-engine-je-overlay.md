# ADR 0021 – Engine-Group statt Flutter-Engine je Overlay (WP145)

Status: vorgeschlagen · 2026-10-24

## Kontext
Messung WP143 (Emulator, Debug-Build): Silero 30× laden/freigeben und Whisper 15× laden/freigeben sind flach, 20× Overlay öffnen und schließen lässt den Native Heap um rund 4,2 MB je Öffnung ohne Plateau wachsen, Java, Objekte und Activities bleiben flach. Jedes Overlay (`AssistantActivity`, `StationActivity`) startete über den Standardweg von `FlutterActivity` eine neue Engine in einer **eigenen** `FlutterEngineGroup`. Zunächst war das als Ursache des Wachstums vermutet.

**Messung WP145 widerlegt das:** Mit einer prozessweiten Gruppe bleibt der Native Heap unverändert (Release: weiterhin etwa +4 MB je Overlay, Ursache offen und nicht Teil dieser ADR). Die Gruppe bringt nur eine kürzere Startzeit (Overlay öffnet in etwa 1,0 statt 1,4 s, weil Dart-VM-Ressourcen geteilt statt neu aufgebaut werden). Sie wird deshalb nur dieses Nutzens wegen eingesetzt, nicht als Leck-Behebung.

## Entscheidung
- Ein prozessweiter `FlutterEngineGroup` (`EngineGroups`, `app/android/.../EngineGroups.kt`, Zähllogik in `EnginePool`). Daraus entstehen: die headless Engines (`RecognizerEngine`: `recognizerMain`, `wakeWordMain`), `AssistantActivity` (`assistantMain`) und `StationActivity` (`stationMain`). Die erste Engine läuft allein, jede weitere wird von einer lebenden Geschwister-Engine gespawnt (geteilte Dart-VM-Ressourcen, Isolate-Gruppe). Der Wake-Dienst läuft dauerhaft, sodass Overlays normalerweise gespawnt werden.
- Die Overlays liefern ihre Engine über `provideFlutterEngine` und überschreiben `shouldDestroyEngineWithHost() = true`: eine Engine aus `provideFlutterEngine` gehört nach Flutters Vorgabe sonst dem Host und würde nie zerstört. Beim Schließen der `AssistantActivity` gilt das nicht mehr: Dart meldet `releaseHost`, die Activity endet sofort (der Wake-Dienst hört wieder zu, ein neuer Assist öffnet eine neue Activity mit neuer Engine), die Engine bleibt kopflos in `EnginePool` gehalten, bis Dart `teardownDone` meldet oder 14 s um sind, und wird dann über den Pool zerstört. So kann ein noch ladendes Whisper-Modell fertig geladen und freigegeben werden, ohne das Overlay zu blockieren. Plugins werden beim Spawn registriert (`automaticallyRegisterPlugins`), `FlutterActivity.configureFlutterEngine` registriert bei Host-Engines nicht noch einmal; unsere Kanäle (`WendelinActivity.configureFlutterEngine`/`cleanUpFlutterEngine`) laufen unverändert. `MainActivity` und `WendelinActivity` bleiben unverändert.
- Log je Engine: `<tag>-engine-source group=new|shared fromSibling=… siblings=N live=M` (für die Messung).

## Abwägung
- **Gecachte Engine** (`FlutterEngineCache`, vorgewärmt): schnellster Start, aber Zustand (Dart-Statics, Provider, offene Sheets) bleibt zwischen Overlays hängen; ein Overlay muss immer frisch sein (kein Rest einer früheren Sitzung, kein persönlicher Inhalt hinter dem Sperrbildschirm). Außerdem hält eine dauerhaft lebende zusätzliche Engine ihren Speicher.
- **Engine-Group**: frischer Dart-Zustand je Overlay bleibt (neue Engine, neues Isolate), die Ressourcen werden geteilt, der Start ist um etwa 0,4 s kürzer. Preis: Das Zerstören der Overlay-Engine liegt in unserer Hand (siehe oben).
- Restrisiko: Läuft keine andere Engine (Wake aus), ist das Overlay die erste und einzige Engine; dann entfällt der Teil des Gewinns, der aus dem Teilen stammt. Das Heap-Plateau liefert die Gruppe nicht (siehe Kontext).

## Folgen
- Alle Engines teilen sich Gruppe und Dart-VM, also auch den Dart-Heap und die Garbage Collection; ein Absturz des Isolates einer Engine bleibt auf sie begrenzt, die Dart-VM aber ist gemeinsam. Hintergrund-Isolates des Overlays (zum Beispiel der Drift-Server) können die Overlay-Engine überleben, solange die Gruppe lebt; der Teardown schließt die Datenbankverbindung deshalb ausdrücklich.
- Bekanntes Risiko: Die Plugin-Registrierung läuft beim Spawn. Im Release (R8) gab es dabei einen `NullPointerException` in `findAppBundlePath`, weil der Loader erst durch den `FlutterEngineGroup`-Konstruktor initialisiert wurde; `EngineGroups.spawn` initialisiert ihn jetzt selbst (Commit 04464bf9). Release-Start muss je Stand im Gerätetest geprüft werden.
- Neue Engines in Kotlin laufen über `EngineGroups.spawn`, nie über `FlutterEngine(context)`.
