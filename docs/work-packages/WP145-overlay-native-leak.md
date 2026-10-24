# WP145 – Nativer Speicher wächst je Overlay

**Zuordnung:** Befund WP143 (2026-10-24), Fortsetzung in derselben Sitzung. Gerätebefund des Maintainers: Wendelin belegte 0,9 GB bei 141 MB freiem RAM. Entscheidung Maintainer: rc3 mit WP143, das Leck direkt danach.

## Befund
- Langzeitmessung am Emulator, 20 Overlay-Zyklen, Debug-Build: Der Native Heap wächst linear um +3,7 MB je Overlay, ohne Plateau (407 → 485 MB). Java, Graphics und Objekte bleiben flach. Ohne Overlay ist der Verlauf flach.
- Verdacht: (1) Die Silero/ORT-Sitzung wird je Overlay angelegt und freigegeben, ORT gibt aber nicht vollständig frei. (2) Je Overlay entsteht eine neue Flutter-Engine mit Isolate (`AssistantActivity`, ohne Engine-Group bzw. Cache).

## Inhalt
- Ursache mit Gegenprobe belegen: ein Lauf ohne Silero, ein Lauf mit gecachter Engine. Beheben: Modelle je Prozess einmal halten bzw. teilen, Overlay-Engine vorwärmen bzw. cachen oder per Engine-Group starten.
- Test bzw. Messskript: Native Heap über ≥ 20 Overlay-Zyklen mit Plateau (Schwelle dokumentieren), reproduzierbar per E2E.
- Prüfen, ob Parakeet und Whisper ähnlich je Overlay neu geladen werden (Lade- und Freigabezähler).

## Abnahmekriterien
- [ ] Ursache belegt (Messung vorher/nachher), Heap nach 20 Zyklen mit Plateau.
- [ ] Gate `--changed`, CI grün, Review FREIGABE, E2E grün, Gerätetest-Block (Speicher am Handy nach vielen Aufrufen).
