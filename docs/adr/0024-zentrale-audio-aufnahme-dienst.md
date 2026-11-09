# ADR 0024 – Zentrale Audio-Aufnahme und Ringpuffer im Dienst

Status: vorgeschlagen (WP180, K145) · 2026-10-29

## Kontext
Auf Android (insbesondere Android 10+ und herstellerspezifischen Builds wie Huawei EMUI) darf zu jedem Zeitpunkt nur eine Komponente eine Audioaufnahme über `AudioRecord` (`VOICE_RECOGNITION`) aktiv betreiben. Parallele Aufnahmen werden entweder mit `ERROR_INVALID_OPERATION` verweigert oder von AudioFlinger stummgeschaltet (`isClientSilenced = true`, nur Nullen).

Bisher gab es zwei getrennte Aufnahmewege:
1. `WakeWordService` in Kotlin hielt ein `AudioRecord` für die Weckwort-Erkennung im Hintergrunddienst (ADR 0013).
2. Die Flutter-App öffnete über `RecordAudioInput` (`package:record`) eigene `AudioRecord`-Instanzen für Sprachbefehle, das Sprecher-Einlernen (`SpeakerEnrollScreen`) und das Weckwort-Einlernen (`WakeEnrollScreen`).

Um das Weckwort an den Sprachbefehl zu übergeben, wurde das Kotlin-Mikrofon gestoppt und ein neues Flutter-Mikrofon gestartet. Die entstandenen Lücken und Überlappungen mussten über aufwändige Heuristiken (`bridgeWakeTail`, `WakeMicTap`, `overlapGuard`, Kreuzkorrelation) überbrückt werden (WP68, WP146, WP149). Dies führte auf physischen Geräten zu zwei gravierenden Problemen:
- Bei schnellem Sprechen („Wendelin <Kommando>“) ging Audio zwischen Weckwort und Sprachbefehl verloren.
- Beim Sprecher- und Weckwort-Einlernen blockierte der laufende `WakeWordService` die Aufnahme der Einstellungs-Screens, sodass keine Sprache ankam oder die Spracherkennung blockiert war.

## Entscheidungen
1. **Zentrale Audio-Aufnahme (Single Capture Source).**
   Das Hardware-Mikrofon (`AudioRecord`, 16 kHz, 16-Bit Mono PCM) wird auf Android exklusiv von einer zentralen Stelle im `WakeWordService` geführt.
2. **Fortlaufender Ringpuffer in Kotlin.**
   Der Dienst führt einen kontinuierlichen Ringpuffer mit mindestens 5–6 Sekunden Historie (gemäß K144/K145). Alle erfassten Audiodaten rollen fortlaufend durch diesen Speicher.
3. **Multi-Subscriber-Modell für alle Konsumenten.**
   Alle Komponenten greifen auf die zentrale Audioquelle zu:
   - **Weckwort-Erkennung:** erhält kontinuierlich die Audioblöcke.
   - **Sprachbefehl / STT (Dialog-Pipeline):** Bei einem Weckwort-Treffer oder Push-to-Talk stoppt das Mikrofon *nicht*. Die Pipeline erhält den Vorlauf (Pre-Roll) sowie den unmittelbar danach gesprochenen Befehl aus dem Ringpuffer und streamt unterbrechungsfrei weiter.
   - **Sprecher- und Weckwort-Einlernen:** `WakeEnrollScreen` und `SpeakerEnrollScreen` fordern Audiodaten direkt von der zentralen Quelle an, statt ein eigenes `AudioRecord` zu starten.
   - **Barge-In:** greift auf denselben kontinuierlichen Audiopuffer zu.
4. **Einheitlicher Flutter-Audio-Input.**
   Unter Android wird `audioInputProvider` über einen Kanal an den zentralen Dienst angebunden. Flutter öffnet kein eigenes `package:record` mehr, wenn der Dienst verfügbar ist.
5. **Konfliktbehandlung.**
   Bei externen Konflikten (eingehender Anruf, Dritt-App benötigt Mikrofon) pausiert `WakeConflictWatcher` die zentrale Aufnahme und reaktiviert sie nach Ende des Konflikts automatisch.
6. **Entfall fragiler Handoff-Überbrückung.**
   Da das Mikrofon beim Übergang vom Weckwort zum Sprachbefehl unterbrechungsfrei weiterläuft, entfallen Mikrofon-Neustarts und komplexe Übergabe-Überbrückungen.

## Folgen
- Keine Mikrofon-Kollisionen oder Stummschaltungen mehr auf Android 10+ / EMUI.
- Lückenlose Erfassung schneller Kommandos („Wendelin <Kommando>“) ohne Audioverlust.
- Sprecher-Einlernen und Spracherkennung funktionieren zuverlässig parallel zum Weckwort-Dienst.
- Erhebliche Vereinfachung des Handoff-Codes zwischen Kotlin und Dart.

## Nachtrag WP189 (Weckwort-Vorlauf doppelt)
Punkt 6 ist nur teilweise umgesetzt: Die Übergabe nach einem Treffer läuft weiter über `WakeHandoff` und `WakeMicTap` (Nachlauf ab der Stream-Position `pos` des Treffers). Seit dem zentralen Mikrofon zählte der Tap jeden Mikrofonblock seit dem Öffnen, die Position des Dart-Listeners beginnt aber bei jedem Fortsetzen (nach dem Overlay) bei 0, und während eines Dialogs hält der Hub den Weckwort-Strom zurück. Der Tap lief daher voraus und gab bei jedem Treffer seinen ganzen Puffer (3 s, mit dem Weckwort) als Nachlauf zurück. Der Endpointer entschied dann schon im doppelten Vorlauf („nicht verstanden“ oder das verstümmelte Weckwort als Anfrage).
Seit WP189 zählt `WakeEngineFeed` nur die Blöcke, die an die Engine gehen, und beginnt bei jedem `startMic` des Listeners bei 0. Ein Token in `startMic` und `audio` sorgt dafür, dass Dart Blöcke eines älteren Stroms verwirft, sodass beide Seiten dieselben Blöcke zählen.
