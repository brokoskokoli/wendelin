# WP182 – Overlay schließt nicht während Ansage oder 10-Sekunden-Rückgängig-Fenster

**Zuordnung:** Auftrag Maintainer 2026-10-30. Konzeptänderung K146 (ändert K140).

## Ausgangslage & Problem
Mit WP172 wurde das automatische Schließen des Overlays eingeführt (`overlay-close by=idle`), wenn das Zuhören endet und scheinbar „nichts mehr zu tun ist“ (`nothingLeftToDo`).
In der Praxis (Gerätetest 2026-10-30) führte das zu zwei kritischen Problemen:
1. **Rückgängig-Fenster wird abgeschnitten:** Wurde eine Aktion mit 10-Sekunden-Rückgängig-Möglichkeit ausgeführt (z. B. Termin anlegen, Lampe schalten, Aufgabe erledigen), schloss sich das Overlay nach dem Ende der Aufnahme bzw. nach der Antwort sofort. Das 10-Sekunden-Zeitfenster für „Rückgängig“ auf der Tool-Karte wurde dadurch vorzeitig geschlossen und der Nutzer konnte die Aktion nicht mehr rückgängig machen.
2. **Ansage / Sprachausgabe:** Solange Wendelin redet (Ansage / TTS-Sprachausgabe läuft), darf das Overlay keinesfalls schließen, sondern erst danach.

## Kernanforderungen des Maintainers
1. **Kein Schließen während Ansage:** Solange Wendelin redet (TTS-Sprachausgabe aktiv), bleibt das Overlay geöffnet.
2. **Kein Schließen während Rückgängig-Fenster:** Solange ein 10-Sekunden-Fenster für Rückgängigmachen aktiv ist (`UndoPhase.pending` bzw. `UndoPhase.running`), bleibt das Overlay geöffnet, sodass der Nutzer den Rückgängig-Button sehen und betätigen kann.
3. **Automatisches Schließen danach:**
   - Sobald die Ansage fertig ist UND kein Rückgängig-Fenster (mehr) offen ist, schließt das Overlay wie gewohnt automatisch per Idle (`by=idle`).
   - Läuft nach Ende der Ansage noch das 10-Sekunden-Rückgängig-Fenster, schließt das Overlay automatisch per Idle (`by=idle`), sobald die 10 Sekunden abgelaufen sind (`UndoPhase.expired`) und keine andere Interaktion offen ist.
   - Tippt der Nutzer währenddessen auf „Rückgängig“, spricht Wendelin die Bestätigung („Zurückgenommen.“) und das Fenster schließt danach.

## Abnahmekriterien
- [ ] `nothingLeftToDo` prüft zusätzlich, ob ein Rückgängig-Fenster offen ist (`hasPendingUndo` in `ConversationState` bzw. `UndoManager`) und ob noch eine Sprachausgabe aktiv ist.
- [ ] `IdleCloser` lauscht auf das Auslaufen des Rückgängig-Countdowns sowie auf das Ende der Sprachausgabe und stößt danach die Schließprüfung an.
- [ ] Unit-Tests in `overlay_autoclose_test.dart` (und ggf. `assistant_overlay_test.dart`):
  - Aktion mit Rückgängig-Fenster: Overlay bleibt während der gesamten Countdown-Dauer offen; schließt erst nach Ablauf der 10 s per `by=idle`.
  - Ansage läuft: Overlay bleibt offen, solange Wendelin spricht; schließt danach (falls kein Rückgängig offen).
  - Rückgängig angetippt: Wendelin sagt „Zurückgenommen.“, Overlay schließt danach.
- [ ] `--changed` grün, CI grün, Review FREIGABE.
