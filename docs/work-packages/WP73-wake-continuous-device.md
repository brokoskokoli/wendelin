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
