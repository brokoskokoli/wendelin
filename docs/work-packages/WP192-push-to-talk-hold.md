# WP192 – Push-to-Talk: Mikrofon-Button gedrückt halten

**Zuordnung:** Wunsch Maintainer 2026-11-13, für längere und komplexe Anweisungen mit Denkpausen.
**Konzept:** K151 (offen).

## Verhalten
- **Drücken und Halten des Mikrofon-Buttons** (Hauptbildschirm `app/lib/ui/screens/main_parts.dart:276` und Overlay `app/lib/ui/overlay/overlay_sheet.dart:385`, Widget `app/lib/ui/design/mic_button.dart`): Die Aufnahme beginnt beim Herunterdrücken. Solange der Finger auf dem Display bleibt, endet sie nicht. Das Endpointing (Stille-Ende, No-Speech-Fenster, Maximaldauer im vernünftigen Rahmen, siehe unten) ist ausgesetzt, Pausen von mehreren Sekunden sind erlaubt.
- **Wegrutschen** vom Button beendet nichts. Erst das Loslassen beendet die Aufnahme, ein Abbruch der Geste durch das System zählt wie Loslassen. Danach wird die ganze Aufnahme als eine Äußerung verarbeitet.
- **Kurzer Tipp** (Loslassen vor der Haltegrenze, etwa 400–500 ms, als Konstante): Das Verhalten bleibt wie bisher, also Start bzw. Stopp per Tipp mit normalem Endpointing.
- **Halten, während schon zugehört wird** (auch im 5-s-Folgefenster des Gesprächsmodus): Das Fenster und das Stille-Ende laufen nicht ab, solange gehalten wird. Beim Loslassen wird verarbeitet. Ein kurzer Tipp während des Zuhörens beendet wie bisher.
- **Halten während der Sprachausgabe:** Die Ausgabe wird unterbrochen wie beim Tipp, dann folgt die Aufnahme wie oben.
- **Obergrenze** gegen ein Hängenbleiben: eine harte Maximaldauer (Vorschlag 2 min, Konstante). Danach wird verarbeitet, und der Nutzer erhält einen Hinweis.
- **Sichtbar:** Der Button zeigt während des Haltens einen eigenen Zustand (z. B. Haltering, „Loslassen zum Senden“). Semantics und TalkBack bleiben bedienbar: Die Tipp-Aktion bleibt erhalten.

## Umsetzungshinweise
- Die Pipeline (`packages/wendelin_voice`) bekommt einen Haltemodus, z. B. `holdStart()`/`holdRelease()` bzw. einen Endpointer ohne Stille-Ende. Die Nachverarbeitung (STT, Weckwort-Strip, Stoppwörter) bleibt gleich. Lange Aufnahmen: Prüfen, ob die STT-Engine (Parakeet/Whisper) 1–2 min am Stück verarbeitet. Sonst wird segmentiert und verbunden.
- Die Geste wird mit `Listener`/`RawGestureDetector` (pointer down/up/cancel) umgesetzt, nicht mit `onLongPress`, damit die Aufnahme schon beim Drücken startet und Wegrutschen nichts abbricht.

## Abnahmekriterien
- [ ] Widget-Test: Druck länger als die Grenze, Wegschieben außerhalb des Buttons, 3 s Pause im Audio (Fake), dann Loslassen. Ergebnis: genau eine Äußerung mit dem ganzen Audio, kein vorzeitiges Ende.
- [ ] Ein kurzer Tipp verhält sich unverändert (bestehende Tests grün).
- [ ] Halten im Folgefenster des Gesprächsmodus verhindert dessen Ablauf. Loslassen verarbeitet.
- [ ] Die Maximaldauer greift (fakeAsync).
- [ ] Mutationsbelege für Stille-Ende im Haltemodus, Wegrutschen und Haltegrenze.
- [ ] E2E bzw. Gerät: eine Anweisung von etwa 30 s mit 2–3 s Denkpausen wird vollständig erkannt (Gerätetest-Block in `docs/testing/m5/`).

## Nicht im Paket
- Push-to-Talk-Widget auf dem Startbildschirm (K137), Hardware-Tasten.
