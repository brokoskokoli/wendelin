# WP189 – Weckwort-Vorlauf nicht mehr doppelt (Tap-Position je Listener-Strom)

**Zuordnung:** Befund Maintainer 2026-11-09. Nach dem Weckwort kommt schon nach rund 2 s „nicht verstanden“ und das Overlay schließt, oder es werden Wörter erkannt, die nicht gesagt wurden. Seit v0.1.3 (WP180).
**Konzept:** keine Änderung (Fehlerbehebung zu K145, ADR 0024, Nachtrag dort).

## Befund (Gerätelog 0.1.7, nur Zahlen)
- Bei jedem Treffer meldet `wake-handoff-take` `captured=3100ms`, obwohl zwischen `wake-hit` und Übernahme nur rund 140 ms liegen. 3 s sind genau der Puffer von `WakeMicTap`.
- `preroll-fed ms≈5600 from=2500`, danach sofort `listen-end kind=utterance reason=silence` mit `speechStartMs≈4100`. Der Endpointer entscheidet also allein im Vorlauf, bevor das Live-Mikrofon etwas beiträgt.
- Die Erkennung liefert das verstümmelte Weckwort („Vanilla?“, „Having.“, „Vene?“). `wake-strip removed=false` lässt es als Anfrage durch, oder es bleibt leer und die Antwort lautet „nicht verstanden“.

## Ursache
`WakeMicTap` zählte jeden Mikrofonblock seit dem Öffnen des Mikrofons. Die Trefferposition `pos` des Dart-Listeners beginnt aber bei jedem Fortsetzen bei 0. Seit WP180 bleibt das zentrale Mikrofon offen, ein Neustart mit `tap.reset()` findet nicht mehr statt, und während eines Dialogs hält der Hub den Weckwort-Strom zurück. Deshalb lief `sent - pos` weit voraus, und `tailAfter` gab den ganzen 3-s-Puffer zurück: Audio vor dem Treffer, einschließlich des Weckworts, landete ein zweites Mal hinter dem Weckwort im Vorlauf.

## Lösung
- `WakeEngineFeed` (Kotlin) zählt nur die Blöcke, die an die Engine gehen (WAKE-Abonnent, beim Verteilen). Bei jedem `startMic` des Listeners beginnt die Zählung bei 0.
- `startMic` übergibt ein `token`, und jeder `audio`-Block trägt das Token, unter dem er gezählt wurde. `ServiceAudioInput` verwirft Blöcke eines älteren Stroms, sodass beide Seiten dieselben Blöcke zählen.

## Abnahmekriterien
- [x] Kotlin-Test stellt den Ablauf nach (Dialog hält den Weckwort-Strom zurück, Listener setzt fort, Treffer): Es werden nur die Blöcke übergeben, die noch unterwegs waren (`WakeEngineFeedTest`).
- [x] Dart-Test: Ein Block mit älterem Token zählt nicht zur Trefferposition (`wake_host_test.dart`, schlägt ohne die Prüfung fehl).
- [ ] Gerät: Nach dem Weckwort zeigt `wake-handoff-take` nur noch `captured` im Bereich der Übergabezeit (≈ 100–300 ms), und bei Schweigen nach dem Weckwort wird mindestens das No-Speech-Fenster lang zugehört.

## Offen / Folge
- WP184 hat dasselbe Symptom als Ausklingen des Weckworts gedeutet und `wakeEndMargin` auf 350 ms erhöht. Nach diesem Fix lässt sich prüfen, ob 100 ms wieder reichen.
