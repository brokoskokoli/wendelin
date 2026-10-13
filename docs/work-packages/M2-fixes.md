# Nachbesserungen aus dem Gerätetest 2026-10-13 (WP30–WP33)

Grundlage: Gerätetest des Maintainers 2026-10-13 nach `docs/testing/m2-device.md` (Release-APK arm64, Provider Claude Haiku, ein Telefon Xiaomi/HyperOS, Android 16, mit GMS). Die Ergebnisdatei selbst liegt nicht im Repo, weil sie Gerätedaten enthält. Diese Übersicht fasst die Befunde sachlich zusammen.

## Ergebnis in Kürze

M2 läuft auf dem echten Telefon im Kern: Power-Taste → Overlay → gesprochener Befehl → Tagesnotiz ergänzt, Rückgängig byte-genau, Sperrbildschirm, Screenshot-Schutz, Abbruch, Bestätigung per Stimme (auch die strenge Zustimmung) und de/fr/en. Kein Absturz, keine Secrets im Log. Der inkrementelle Index-Sync greift auch bei extern abgelegten Notizen.

Whisper auf dem Gerät: base Ø 0,46 s je Satz (RTF 0,11), small Ø 1,32 s (RTF 0,33). small hat alle Testsätze in de/fr/en richtig erkannt, base hat Eigennamen verfehlt. **Entscheidung des Maintainers (2026-10-13):** whisper-small mit fester Sprache wird Standard, base bleibt als „schnell“ wählbar (K11 a bestätigt, Umsetzung WP33).

## Befunde und Zuordnung

| # | Schwere | Befund | Paket |
|---|---|---|---|
| B1 | niedrig | API-Key-Feld ohne Autofill (Passwort-Manager) | WP32 |
| B2 | niedrig | Verbindungstest ohne deutliche Erfolgsmeldung | WP32 |
| B3 | mittel | Onboarding-Download: Knopfführung unklar (Silero-Pflicht verdeckt, „Weiter“ fehlt scheinbar) | WP32 |
| B4 | niedrig | Zurück-Geste im Onboarding schließt die App | WP32 |
| B5 | mittel | „Stopp“ im Overlay ohne Rückmeldung, die alte Antwort bleibt stehen | WP31 |
| B6 | mittel | base erkennt Eigennamen falsch (Notiztitel, Assistentenname) | WP33 |
| B7 | hoch | Nach der Ja/Nein-Frage wird sporadisch nicht zugehört (keine zweite Aufnahme) | WP30 |
| B8 | mittel | Hinweis auf unscharfe Notizzuordnung kommt erst nach der Bestätigung | WP31 |
| B9 | mittel | Rückgängig während der Sprachausgabe: liest weiter vor, kaum Rückmeldung | WP31 |
| B10 | hoch | Power-Taste öffnet das Overlay sporadisch nicht, bis die App beendet wird | WP30 |
| B11 | mittel | Erster Mikrofon-Tipp nach einer Pause: ~2 s bis zur Aufnahme (auch nach dem Entsperren) | WP30 (Ursache), WP31 („Moment …“-Zustand) |
| B12 | hoch | Auf HyperOS mit GMS bleibt `voice_recognition_service` bei Google; Wendelin wird nicht System-Spracherkennung (Konzeptabweichung) | WP32 |
| B13 | niedrig | „Probe hören“ in der App-Sprache statt in der gesprochenen Sprache | WP31 |
| B14 | mittel | Speicher mit small ≈ 1,3 GB PSS statt ≈ 0,5 GB | WP30 |

## UX-Wünsche und Zuordnung

| Wunsch | Paket |
|---|---|
| Deutlichere Zuhör-Anzeige im Hauptbildschirm (Pegel/Wellenform, nicht nur der Ring) | WP31 |
| Beim Warten auf Ja/Nein den Mikrofon-Knopf mit Ring zeigen | WP31 |
| Animierte Punkte, während Wendelin spricht | WP31 |
| Sichtbarer Knopf „Neues Gespräch“ im Kopf des Hauptbildschirms, tolerantere Erkennung („neues Gespräch“, „vergiss das“) | WP31 (mit WP26 abstimmen) |
| Senden-Knopf bei Texteingabe | WP31 |
| „Moment …“, bis die Aufnahme bereit ist (erster Tipp, nach dem Entsperren) | WP31 |
| „Stopp“ im Overlay schließt es | WP31 |
| Onboarding Provider-Schritt vertikal mittig | WP32 |
| Hinweis „Ohne Mikrofon-Zugriff geht nur Text.“ präsenter | WP32 |
| Einstellungen → Assistent: Persönlichkeit mehrzeilig, Hilfstext weg, Knopf weg wenn schon Standard-Assistent | WP32 |
| Tagesnotizen: `Journal` vorbelegt | WP32 |
| Index: Hinweis, dass er sich selbst aktualisiert | WP32 |
| Gesprächsmodus als Einstellung | nicht eingeplant: Wunsch hoher Priorität, bleibt in M4 (Entscheidung Maintainer 2026-10-13) |
| Doppelte/ähnliche Einträge in der Tagesnotiz erkennen und nachfragen | nicht eingeplant (Idee, nicht beobachtet; später als eigenes Paket) |

Dazu kommen Ergänzungen der Geräte-Anleitung `docs/testing/m2-device.md` (HyperOS „Über USB installieren“, Reihenfolge „Zwei Engines“, „Neues Thema“, Test-App für die System-Spracherkennung, Hinweis auf B12). Sie gehören zu WP32.

## Pakete

| Paket | Inhalt | Abhängig von |
|---|---|---|
| WP30 Sprach-Robustheit | B7, B10, B11 (Ursache), B14: Diagnose-Logging ohne Inhalte, Reproduktion, Fix, Messkriterien | – |
| WP31 Sprach-UX | B5, B8, B9, B13, Zuhör-/Sprech-Anzeigen, „Neues Gespräch“, Senden-Knopf, „Moment …“ | WP30 (gemeinsame Stellen in `voice_controller.dart`), WP26 (Kopf des Hauptbildschirms, „Neue Unterhaltung“) |
| WP32 Onboarding und Einstellungen | B1–B4, B12, Einstellungs-/Onboarding-Wünsche, Geräte-Anleitung | – |
| WP33 STT-Qualität | Standard small (K11 a, bestätigt), base als „schnell“; B6: Erkennungshilfe, phonetische Titelsuche, Rückfrage mit Vorschlag | – |

Gesprächsmodus: Wunsch hoher Priorität, bleibt in M4 (Entscheidung Maintainer 2026-10-13).

## Reihenfolge und Parallelität

```
Welle 1 (sofort, parallel zu WP26/WP27/WP29)
  WP30 Sprach-Robustheit       app/lib/voice, app/lib/di/voice_providers.dart, Kotlin-Session
  WP32 Onboarding/Einstellungen app/lib/ui/onboarding, app/lib/ui/settings, Kotlin (Erkennung B12), docs/testing
  WP33 STT-Qualität            wendelin_voice, wendelin_integrations/obsidian, app/lib/platform/voice, Voreinstellung
Welle 2
  WP31 Sprach-UX               -> WP30 (voice_controller), WP26 (Hauptbildschirm-Kopf)
```

Dateiüberschneidungen:
- WP30 und WP33 berühren beide `app/lib/di/voice_providers.dart` (WP30: Modell-Lebenszyklus, WP33: Standardmodell, Erkennungshilfe). Die Konflikte sind klein. Wer zuerst merged, setzt den Rahmen, der andere rebased.
- WP31 und WP33 berühren beide die Obsidian-Notizauflösung (WP31 B8: aufgelöster Pfad und unscharfe Zuordnung in Karte und Frage, WP33 B6: phonetische Suche und Vorschlag). WP33 besitzt `resolveNote` und dessen Rückgabe. WP31 nutzt den vorhandenen Stand (Vergleich gefalteter Titel) und übernimmt nach dem Merge von WP33 dessen Trefferart.
- WP31 und WP26: WP26 bringt die Anzeige „Unterhaltung privat“ mit der Aktion „Neue Unterhaltung“ im Hauptbildschirm und Overlay. Der Knopf „Neues Gespräch“ aus WP31 nutzt dieselbe Aktion (`AgentController.newTopic`) und dieselbe Benennung. Deshalb startet WP31 erst nach dem Merge von WP26.
- WP32 und WP27/WP28: B1 (Autofill) gilt für alle Secret-Felder. Die Felder aus WP28 (HTTP-Tool-Secrets, Bring!-Passwort, schon auf main) nimmt WP32 mit. Die Token-Felder aus WP27 (MCP-Bearer, eigene Header) bekommen den Hinweis über WP27 bzw. nach dessen Merge über WP32.
- WP29 (E2E M3) schreibt eine eigene Geräte-Anleitung. Die HyperOS-Hinweise aus WP32 sollen dort übernommen werden.

## Konzeptänderungen

Abweichungen melden die Pakete in ihrem Abschlussbericht. Vorgeschlagen sind (Eintrag durch den Orchestrator nach Bestätigung, K14):
- B12: Die System-Spracherkennung folgt der Assistenten-Rolle nur dort, wo Android `voice_recognition_service` mitzieht (AOSP, viele Custom-ROMs). Auf Geräten mit GMS (z. B. HyperOS) lässt sie sich nicht umstellen. Wendelin erkennt das und kennzeichnet den Schalter.
- K11 (a) ist bestätigt (Standard whisper-small mit fester Sprache, base als „schnell“ wählbar). Der Status im Änderungsprotokoll wird entsprechend gesetzt.
- „Neues Thema“ wird um gleichwertige Befehle und einen Knopf ergänzt.

## Gerätetests

Wie in `M3.md`, Abschnitt „Gerätetests – nur Emulator“: Agenten installieren nie auf ein echtes Gerät. Sie nutzen ausschließlich den AVD `Wendelin_AOSP_35` mit explizitem Serial (`DEVICE=emulator-xxxx`, `adb -s emulator-xxxx`, `flutter … -d emulator-xxxx`) und prüfen vorher `ro.kernel.qemu=1`. `E2E_ALLOW_DEVICE=1` setzt kein Agent. Was nur das echte Telefon zeigt, steht in jedem Paket als kurze Prüfliste für den Maintainer.
