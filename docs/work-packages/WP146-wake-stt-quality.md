# WP146 – Spracherkennung nach dem Wake Word unbrauchbar

**Zuordnung:** Gerätebefund des Maintainers vom 2026-10-25 (Build mit WP143/WP145, Erkenner Parakeet v3). Mit dem Weckwort „Hey Wendelin“ kommen Texte an, die mit dem Gesagten kaum etwas zu tun haben. Ohne Wake Word erkennt die App dieselben Befehle sauber. Entscheidung Maintainer: Fix-Paket mit Diagnose-Logs (nur Zahlen).

## Befund (logcat Testhandy, 12:32–12:44)
Die App loggt keine Transkripte. `lp` ist die mittlere Log-Wahrscheinlichkeit des Erkenners (näher an 0 ist besser).

| Lauf | Auslöser | Ergebnis |
|---|---|---|
| Wake-Dienst aus | Tippen in der App | lp −0,06 / −0,13 / −0,81 |
| Wake-Dienst an | Tippen in der App | lp −0,52 / −1,45 (conf 0,36) / −1,12 |
| 12:38:08, Overlay, Treffer direkt | Wake Word | Vorlauf 2 760 ms, `continues=true`, danach 8 s Zuhören → `nothing-understood reason=noSpeech` |
| 12:38:25, Overlay | erneut getippt | Modell neu geladen (3,6 s, RTF 2,09), lp −1,34 |
| 12:43:22, Chat, Stufe 2 (Parakeet-Prüfung 2,9 s) | Wake Word | Vorlauf 7 180 ms. Endpunkt liegt schon im Vorlauf (Mikrofon 3 ms nach dem Start wieder zu), 1 880 ms erkannt, danach erneutes Zuhören. Folgerunden lp −1,34 und −2,99 |

Auffälligkeiten:
1. **Lücke bei der Übergabe:** Jede Übergabe hat zwischen dem letzten Sample des Dienstes und dem ersten Frame des App-Mikrofons ein Loch von 600–700 ms (`wake-gap ms=605 afterTake=499`, `ms=717 afterTake=592`). Vorlauf und Live-Audio werden ohne Markierung aneinandergehängt, sodass Wörter mittendrin zerschnitten werden.
2. **Vorlauf verworfen:** In `VoicePipeline._run` setzt `stripWake` bei leerem Rest `pre = null` und hört live weiter. Alles im Vorlauf nach dem ersten Segment (bei Stufe 2 oft der ganze Befehl, der während der Prüfung gesprochen wurde) geht verloren. Ein Endpoint im Vorlauf greift erst mit dem ersten Live-Frame (`_feedPreRoll` wertet das Ergebnis nicht aus), das App-Mikrofon wird also unnötig geöffnet.
3. **Modell unter dem Overlay freigegeben:** `release engine=app reason=idle` (12:38:26.9) gibt Parakeet frei, während das Overlay es teilt (`model-share engine=overlay`). Das Overlay lädt dann ein eigenes Exemplar (3,6 s Wartezeit und doppelter Speicher).
4. **Mikrofon-Überlappung (Verdacht):** Zwischen zwei App-Aufnahmen meldet der Dienst `wake-resume` und öffnet sein `AudioRecord` wieder. Die App öffnet ihres ~250 ms später, und erst der Konflikt-Watcher schließt den Dienst (z. B. 12:38:51.162 → 51.430 → 51.451). Zwei gleichzeitige `VOICE_RECOGNITION`-Aufnahmen können auf dem Gerät das Audio der zweiten verschlechtern. Das würde auch die schlechteren Werte beim Tippen mit laufendem Dienst erklären.
5. **Erkenner geteilt mit dem Prüfer (zu prüfen):** Die Stufe-2-Prüfung läuft mit Parakeet in der Wake-Engine (`stt-lang engine=wake`). Zu klären ist, ob Prüfer und Befehlserkennung dieselbe Instanz bzw. denselben Zustand nutzen (Hotwords/Hinweis-Begriffe, Sprache) und ob die Prüfung die Erkennung beeinflusst.

## Inhalt
- **Diagnose-Logs (nur Zahlen, kein Audio, kein Text):** je Aufnahme RMS/Peak pro Sekunde und Anteil digitaler Stille (Nullframes). Dazu `wakeEnd` und Vorlauflänge in ms, Länge des eingespeisten Vorlaufs, Grund für das erneute Zuhören (nur Weckwort, Gate-Ablehnung) und Erkenner-Instanz (Engine, Sharing-Zähler).
- **Lücke schließen:** Der Dienst nimmt weiter auf, bis das App-Mikrofon den ersten Frame liefert (Übergabe nach dem ersten Frame statt vorher), oder das Overlay liest bis dahin aus dem Dienst. Ziel: `wake-gap` < 50 ms ohne zwei gleichzeitige Aufnahmen über die Übergabe hinaus. Falls doch eine Lücke bleibt, wird sie als Stille eingefügt statt hart verklebt.
- **Vorlauf vollständig nutzen:** Nach „nur Weckwort“ wird der restliche Vorlauf ab dem Ende des ersten Segments weiter eingespeist, statt ihn zu verwerfen. Ein Endpoint im Vorlauf wird korrekt behandelt.
- **Modell-Sharing:** Die App-Engine gibt ein geteiltes Modell nicht frei, solange ein Overlay es nutzt (Referenzzähler in `whisper_share`/`whisper_registry` bzw. Release-Regel). Test dazu.
- **Mikrofon-Überlappung:** Der Dienst öffnet sein Mikrofon nicht wieder, solange die App eine Aufnahme vorbereitet (Pause über die ganze Sitzung statt pro Aufnahme oder kurze Verzögerung vor `startMic`). Belegen mit Pegel-Logs vorher/nachher.
- **Prüfer/Erkenner:** Punkt 5 klären. Bei geteiltem Zustand die Befehlserkennung unabhängig vom Prüfer machen.
- Gerätetest-Block `docs/testing/m5/wp146.md`: je 10 Befehle mit Weckwort (Overlay gesperrt, Chat sichtbar), mit und ohne Pause nach „Hey Wendelin“, Vergleich mit Tippen. Auswertung über lp und Pegel-Logs.

## Abnahmekriterien
- [ ] Diagnose-Logs vorhanden, nur Zahlen (Privacy-Positivliste geprüft).
- [ ] `wake-gap` am Emulator und am Handy < 50 ms, keine Überlappung zweier Aufnahmen über die Übergabe hinaus.
- [ ] Befehl direkt nach dem Weckwort (auch während Stufe 2 gesprochen) wird vollständig erkannt (Test mit WAV-Fixture im E2E).
- [ ] Geteiltes Modell bleibt geladen, solange das Overlay es nutzt (Unit-Test, Log ohne Neuladen).
- [ ] Gate `--changed`, CI grün, Review FREIGABE, E2E grün, Gerätetest-Block (Erkennung mit Weckwort so gut wie beim Tippen).
