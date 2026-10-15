# WP73 – „Wendelin, mach …“ ohne Pause auf dem Gerät (`app/`, Kotlin-Dienst, `wendelin_voice`)

Bezug: Gerätetest 2026-10-15, `ergebnisse.md` Prio 2 Nr. 3 und 8; WP68.

## Befunde
- Schnell gesprochen („Wendelin, Licht an“) hört das Overlay **nichts**; langsam ohne Pause kommt der Text, aber **immer mit Bestätigungston**. In 11/12 Handoffs `continues=false`, `captured=200–600 ms`; Nachprüfung (Kandidat → `wake-verify`) 0,9–3,9 s. Was in dieser Zeit gesprochen wird, landet offenbar nicht im Pre-Roll/Puffer. Einziger `continues=true` endete mit `conv-exit reason=stopWord` („Licht an“ als „Stopp“ erkannt?).
- `wake-gap` 561–742 ms (Ziel < 150 ms).
- Nachprüfung lehnt viele echte „Wendelin“ ab: 10/21 Kandidaten `wake-verify result=no`, gleicher Score (0,85–0,88) wie bestätigte.

## Inhalt
- Ursache für `continues=false`/kleines `captured` finden: Wird der Puffer erst nach `wake-verify` statt ab Kandidat gefüllt? Geht das Audio der Nachprüfungszeit (Dart-Engine) im Pre-Roll verloren? Rechnet `speechAfterWakeWord` mit falschem Bereich? Beheben, sodass die gesamte Zeit ab Wake-Ende lückenlos beim Overlay ankommt.
- `wake-gap` senken (Overlay-Mikrofon früher öffnen / Dienst-Mikrofon bis zum ersten Overlay-Sample halten) oder belegen, dass die Lücke durch Puffer überbrückt wird (dann Log-Semantik klarstellen).
- „Stopp“ darf im Overlay-Start nicht aus der Anfrage heraus auslösen (Stoppwort nur als ganze Äußerung bzw. erst nach der Anfrage).
- Nachprüfung: Ursache der Ablehnungen analysieren (Whisper-Transkripte als Kategorien loggen – nur „Variante erkannt / anderes Wort / leer“, nie Text; Fenster zu kurz/zu spät?). Fix oder Einstellung (z. B. Nachprüfung toleranter, Fenster anpassen), mit Begründung.

## Abnahmekriterien
- [ ] Tests (Dart + JVM) für die Ursache: ohne Pause gesprochener Befehl kommt vollständig an, `continues=true`, kein Ton.
- [ ] Logs/Prüfanleitung 10.4a aktualisiert.
- [ ] Emulator (separater E2E-Agent) weiter grün.
- [ ] Gate grün.

## Umsetzung (2026-10-15, Branch `wp/73-wake-continuous-device`)
**Befund `continues=false` (belegt durch Test, Gerät offen):** Das Audio der Nachprüfungszeit ging nicht verloren: `ms=2,2–3,8 s` im Log ist Pre-Roll (300 ms vor dem Wortende + 0,9 s Nachlauf + `_since` während der Nachprüfung), `captured` zählt nur den Rest nach der Bestätigung bis zur Übernahme (Kotlin `WakeHandoff.take`, `WakePolicy.kt`). Die Ursache lag in `speechAfterWakeWord`: Der Pre-Roll reichte nur 300 ms vor das Wortende (`WakeWordListener.preRoll`-Standard), also bestand das „Grundrauschen“ (20. Perzentil, `noiseFloor`) aus dem lauten Wake Word selbst; Schwelle = min(3 × Wortpegel, 2500) lag über normaler Sprache, `continues` wurde falsch `false`, der Ton kam und die Lautstärke-Prüfung entschied nie auf Weitersprechen. Fix: Pre-Roll des Dienstes 2,5 s (`wakePreRoll`, `wake_host.dart`), `speechAfterWakeWord` lässt die letzten 0,8 s vor dem Wortende aus dem Grundpegel heraus (`wordSamples`) und nimmt ohne Raum davor nur die Mindestschwelle. Tests: `wake_continuous_test.dart` („Gerät: Pre-Roll nur aus dem Wake Word…“), `assistant_overlay_test.dart` („Gerätepegel (WP73)“).
**`wake-gap` 561–742 ms:** nicht durch den Puffer überbrückt; das Dienst-Mikrofon schließt (`stopAndWait` bis 300 ms), das Overlay öffnet seines erst nach der Übernahme (zwei Aufnahmen gleichzeitig bleiben ausgeschlossen, WP51). Zusatzlogs: `wake-gap … afterTake=`, `wake-handoff-take … close=`, damit am Gerät klar wird, welcher Teil die Lücke füllt. Wirkung: Die Übernahme geschieht erst nach der Nachprüfung (1–3 s nach dem Wort), die Lücke fällt meist in die Pause nach der Anfrage; lange Sätze können 0,6 s verlieren (offen, nur am Gerät messbar).
**Stopp aus „Licht an“:** Im Text- und Overlay-Pfad nicht reproduzierbar (nur ganze Äußerung aus Stop- und Füllwörtern, Test `Stoppwort nur als ganze Äußerung`). Der Dienst-Detektor kennt „Stopp“ nicht. Wahrscheinlich kam das `stopWord` aus dem Barge-in während der Antwort (WP64b/WP72). Diagnose: `stop-word source=transcript|barge-in`.
**Nachprüfung 10/21 abgelehnt:** Nur Fenster/Matching analysierbar: Whisper bekommt die letzten 3 s (2 s vor Wortende + 0,9 s Nachlauf), der Abgleich erlaubte eine Änderung. Jetzt zwei Änderungen bei Wörtern, die mit w/v/f beginnen und mindestens 6 Zeichen haben (`wake_verifier.dart`), und `wake-verify-text cat=…` (nur Kategorie: exact, variant, other, empty). Ob Fehlablehnungen so verschwinden, zeigen erst die Gerätedaten (Kategorie `other` = Whisper hört etwas anderes).
