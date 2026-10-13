# M2 auf dem eigenen Telefon testen

Diese Anleitung prüft Meilenstein M2 auf einem echten Android-Telefon: Der lange Druck auf die Power-Taste öffnet Wendelin als Standard-Assistent, und ein gesprochener Befehl ergänzt eine Notiz im Obsidian-Vault. Auf dem Emulator ist das automatisch geprüft (`docs/notes/m2-e2e-2026-10-13.md`). Was nur ein echtes Gerät zeigt, steht hier: echtes Mikrofon und echte Stimme, Laufzeit auf dem Telefon, Sperrbildschirm, Power-Taste, die System-Spracherkennung in einer fremden App.

Zeitbedarf: etwa 45 Minuten, dazu der Download der Sprachmodelle (160 bis 380 MB).

## 0. Voraussetzungen

- Telefon mit **Android 10 oder neuer** (Assistenten-Rolle). Wendelin startet ab Android 8, aber den Standard-Assistenten haben wir nur auf Android 10+ geprüft.
- Mit oder ohne Google-Dienste. Ohne Google (z. B. LineageOS ohne GApps, GrapheneOS) ist der eigentliche Zielfall: Wendelin braucht dort nichts von Google.
- Ein **API-Key** eines Providers, am einfachsten Anthropic (Claude Haiku, ein Testlauf kostet Bruchteile eines Cents). Der Key wird nur im sicheren Speicher des Telefons abgelegt.
- Ein **Obsidian-Vault auf dem Telefon**, also ein Ordner mit `.md`-Dateien, z. B. über Obsidian Sync, Syncthing oder Git. Für den Test reicht auch ein neuer, leerer Ordner, etwa `Documents/WendelinTest`. Die Obsidian-App selbst ist nicht nötig.
- **WLAN** für den Modell-Download.
- Für Variante A der Installation und für die Logs: ein Rechner mit `adb` (Android SDK Platform-Tools) und ein USB-Kabel.

**Was das Telefon verlässt:** Nur der erkannte **Text** geht an den Provider. Die Aufnahme bleibt auf dem Gerät und wird nicht gespeichert. Für den Test also nichts Vertrauliches sagen.

## 1. APK bauen und installieren

Auf dem Rechner, im Repo:

```sh
cd app
flutter build apk --release --split-per-abi
cd ..
tool/check_apk.sh app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

`check_apk.sh` prüft das APK: keine Google-Klassen, kein Backup, nur die erwarteten Berechtigungen und exportierten Komponenten. Die Ausgabe muss nur `ok:`-Zeilen enthalten. Fast alle aktuellen Telefone brauchen `arm64-v8a` (etwa 51 MB). Ältere 32-Bit-Geräte brauchen `armeabi-v7a`.

**Variante A: per adb**
1. Auf dem Telefon die Entwickleroptionen einschalten: Einstellungen → Über das Telefon → 7× auf „Build-Nummer“ tippen. Dann unter Einstellungen → System → Entwickleroptionen „USB-Debugging“ einschalten.
2. Telefon per USB verbinden, die Rückfrage „USB-Debugging zulassen?“ bestätigen.
3. `adb devices` zeigt das Telefon als `device`.
4. `adb install -r app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

Xiaomi/HyperOS (auch MIUI): Dort braucht `adb install` zusätzlich in den Entwickleroptionen „Über USB installieren“ (dafür ist eine Anmeldung mit dem Xiaomi-Konto nötig), und beim Installieren erscheint am Telefon eine Rückfrage, die bestätigt werden muss. Ohne beides bricht `adb install` mit `INSTALL_FAILED_USER_RESTRICTED` ab.

**Variante B: als Datei**
1. Die APK aufs Telefon kopieren (Kabel, Cloud oder Mail an dich selbst).
2. In der Dateien-App antippen. Android fragt einmal, ob diese App „unbekannte Apps installieren“ darf: erlauben, zurück, „Installieren“.
3. Auf Telefonen mit Google kann Play Protect warnen („Unbekannte App“). Das liegt an der eigenen Signatur: „Trotzdem installieren“.

Hinweis: Das Release-APK ist vorerst mit dem Debug-Schlüssel des Rechners signiert (`app/android/app/build.gradle.kts`). Ein Update mit `adb install -r` klappt deshalb nur vom selben Rechner. Sonst Wendelin vorher deinstallieren (das löscht seine Daten).

## 2. Onboarding

Wendelin öffnen. Das Onboarding hat vier Schritte, jeder lässt sich überspringen. Ab Schritt 2 gehen der Zurück-Pfeil und die Zurück-Geste einen Schritt zurück, erst in Schritt 1 schließt die Geste die App.

1. **Willkommen**: Sprache wählen (für diesen Test „Deutsch“).
2. **Sprachmodell (Provider)**: „Provider einrichten“ → Vorlage „Claude“ (Anthropic) → API-Key einfügen (ein Passwort-Manager mit Android-Autofill kann das Feld füllen) → „Verbindung testen“. Über der Modellliste steht dann „Verbindung steht“ mit grünem Haken. Als Modell z. B. Claude Haiku → Datenschutzstufe lassen → „Speichern“.
3. **Spracherkennung laden**: Whisper-Modell antippen, dann den einen Knopf „Laden“.
   - Vorausgewählt ist „Whisper small – genauer (empfohlen)“: 375 MB, erkennt Deutsch, Französisch und Namen deutlich besser (Wortfehler auf unseren Testsätzen 9 % statt 21 %; Standard seit WP33). „Whisper base – schnell, für schwache Geräte“: 161 MB, etwa dreimal schneller, verfehlt aber öfter Eigennamen wie Notiztitel.
   - Hat das Telefon wenig Arbeitsspeicher (unter 3,5 GB laut System, also Geräte mit 3 GB oder weniger), ist base vorausgewählt, und der Schritt nennt den Grund.
   - Eine bestehende Installation behält ihr Modell. War nur base geladen, bleibt base aktiv; Einstellungen → Sprache empfiehlt dann small.
   - Silero VAD (0,6 MB, die Sprachaktivitätserkennung) gehört dazu und wird automatisch mitgeladen.
   - Darunter steht, was noch fehlt („Noch nötig: …“), bzw. „Bereit“. Dann erscheint „Weiter“.
   - **Im WLAN laden.** „Im Hintergrund weiterladen“ geht weiter zum nächsten Schritt. Ein abgebrochener Download wird später fortgesetzt (Einstellungen → Sprache, „Fortsetzen“).
   - Für die Laufzeitmessung (Abschnitt 8) brauchst du beide Modelle. Das zweite lädst du in Einstellungen → Sprache.
4. **Was darf Wendelin?**: Für diesen Test ist nichts nötig. „Fertig“.

## 3. Mikrofon

Die Mikrofon-Berechtigung fragt Wendelin erst, wenn die Spracherkennung geladen ist.

1. Im Hauptbildschirm auf das Mikrofon tippen. Solange Whisper oder Silero fehlen, ist es ausgegraut, und darunter steht „Spracherkennung laden: Einstellungen → Sprache“. Das ist richtig so.
2. Wendelin erklärt zuerst, wozu er das Mikrofon braucht („Mikrofon erlauben?“): „Erlauben“ → Android-Dialog → „Bei Nutzung der App“.
3. Wer „Nicht jetzt“ wählt, sieht über der Eingabezeile eine Karte „Ohne Mikrofon-Zugriff geht nur Text.“ mit dem Knopf „Erlauben“ und kann trotzdem tippen. „Erlauben“ lässt Android fragen.
4. Wer im Android-Dialog ablehnt, sieht kurz „Ohne Mikrofon geht nur Text. In den Android-Einstellungen unter Apps → Wendelin erlauben.“ Die Karte bietet dann „Android-Einstellungen“ an. Nach dem Erlauben dort und der Rückkehr in Wendelin verschwindet sie.

## 4. Standard-Assistent setzen

1. In Wendelin: Einstellungen → Assistent → „Als Standard-Assistent setzen“. Android öffnet „Standard-App für digitalen Assistenten“.
   - Direkt in Android heißt der Pfad meist Einstellungen → Apps → Standard-Apps → Digitaler Assistent → „Standard-App für digitalen Assistenten“ (Pixel und AOSP), bei Samsung Einstellungen → Apps → Standard-Apps auswählen → Digitaler Assistent.
2. „Wendelin“ wählen und bestätigen.
3. Zurück in Wendelin steht dort „Wendelin ist Standard-Assistent“ mit Haken. Der Knopf ist dann weg, zum Wechseln gibt es den Link „In Android ändern“.
4. **System-Spracherkennung** für andere Apps (Schalter „Als Spracherkennung für andere Apps anbieten“, Standard an): Sie folgt der Assistenten-Rolle nur, wenn Android die Einstellung `voice_recognition_service` mitzieht (AOSP, viele Custom-ROMs). Auf Geräten mit Google-Diensten (z. B. HyperOS) bleibt sie oft bei Google und lässt sich dort nicht umstellen. Einstellungen → Assistent zeigt den tatsächlichen Zustand: „Android nutzt Wendelin für die Spracheingabe anderer Apps.“ oder, ausgegraut, „Auf diesem Gerät nicht verfügbar“ mit dem Namen des Dienstes, den Android stattdessen nutzt. Zeigt Android zwar auf Wendelin, ist dessen Spracherkennung aber aus (Schalter aus oder keine Assistenten-Rolle), steht dort „Android verweist für andere Apps auf Wendelin, die Spracherkennung ist aber aus …“. Prüfen per adb: `adb shell settings get secure voice_recognition_service`.
5. Die **Power-Taste**: Auf HyperOS (Xiaomi) öffnet langes Drücken Wendelin ohne zusätzliche Einstellung. Auf vielen Telefonen startet langes Drücken erst nach einer Einstellung den Assistenten, sonst kommt das Ausschaltmenü. Pixel: Einstellungen → System → Gesten → „Ein-/Aus-Taste gedrückt halten“ → „Digitaler Assistent“. Samsung: Einstellungen → Erweiterte Funktionen → Seitentaste → „Gedrückt halten“. Andere Auslöser: Wischen aus der unteren Ecke (Gestennavigation) oder langes Drücken der Home-Taste (3-Tasten-Navigation).

## 5. Vault wählen und Tagesnotizen

1. Einstellungen → Obsidian → „Vault-Ordner wählen“. Die Android-Ordnerauswahl öffnet sich: zum Vault-Ordner gehen → „Diesen Ordner verwenden“ → „Zulassen“.
   - Der Ordner `Download` selbst und die Speicher-Wurzel sind gesperrt. Unterordner gehen.
2. Danach steht dort „Zugriff erteilt“, und die Integration Obsidian ist eingeschaltet (Einstellungen → Integrationen).
3. **Tagesnotizen** wie im Obsidian-Plugin „Daily notes“ eintragen:
   - Ordner, vorbelegt mit `Journal` (leer = Vault-Wurzel; ein schon gespeicherter Wert bleibt),
   - Datumsformat, Standard `YYYY-MM-DD`,
   - Vorlage optional, z. B. `Vorlagen/Tagesnotiz`.
   - „Tagesnotizen speichern“. Die Zeile „Heute: Journal/2026-10-13.md“ zeigt, welche Datei Wendelin ergänzt.
4. „Index aufbauen“ (die Suche braucht ihn, Fortschritt wird angezeigt). Danach aktualisiert er sich selbst, beim Start und vor jeder Suche, auch für Notizen, die ein Sync-Dienst ablegt. Der Knopf ist nur für den ersten Aufbau nötig.
5. Für die Testsätze eine Notiz `Wendelin-Test.md` im Vault anlegen, z. B. in Obsidian oder per `adb push`:

   ```markdown
   # Wendelin-Test

   ## Status
   offen
   ```

## 6. Testsätze

Langsam und normal laut sprechen, etwa 30 cm vom Telefon. Nach dem Ende des Satzes wartet Wendelin 0,8 s Stille ab, erst dann erkennt er.

**Gesprochene Sprache:** Mit „Wie die App“ (Standard) erkennt Whisper nur Deutsch zuverlässig. Für die französischen und englischen Sätze in Einstellungen → Sprache → „Gesprochene Sprache“ auf „Français“ bzw. „English“ stellen, danach wieder zurück. „Automatisch erkennen“ geht auch, ist aber bei kurzen Sätzen unsicherer.

| # | Sprache | Sagen | Erwartet |
|---|---|---|---|
| D1 | de | „Ergänze in meiner Tagesnotiz, dass ich den Zahnarzt angerufen habe.“ | Karte „Tagesnotiz 2026-10-13: …“ mit „Rückgängig · 10 s“. In der Tagesnotiz steht eine neue Zeile (etwa „- Zahnarzt angerufen“). Fehlte die Tagesnotiz, ist sie aus der Vorlage angelegt. Wendelin bestätigt kurz und spricht die Antwort. |
| D2 | de | „Was steht in meiner Notiz Wendelin-Test?“ | Keine Rückfrage (nur lesen). Wendelin liest „Status: offen“ sinngemäß vor. |
| D3 | de | „Ersetze in meiner Notiz Wendelin-Test den Abschnitt Status durch erledigt.“ | Bestätigung mit Zeilen-Diff (`- offen` / `+ erledigt`). Wendelin fragt laut „Soll ich das tun? Ja oder nein?“. Auf „Ja“ wird ersetzt, auf „Nein“ bleibt alles. „Ja, bitte“ gilt hier als unklar (strenge Zustimmung bei `external`), dann fragt er einmal nach, danach geht nur noch der Tipp. |
| F1 | fr | « Note dans mon journal que la réunion est reportée. » | Wie D1, Text sinngemäß „la réunion est reportée“. Antwort auf Französisch. |
| F2 | fr | « Qu'est-ce qu'il y a dans ma note Wendelin-Test ? » | Wie D2, Antwort auf Französisch. |
| E1 | en | “Append to my daily note that the meeting moved to Friday.” | Wie D1, auf Englisch. |
| E2 | en | “Search my notes for dentist.” | Treffer mit der Tagesnotiz aus D1 (falls der Index aktuell ist), Antwort auf Englisch. |

Vor D3 kann die Notiz auch anders aussehen, wenn D2 sie nicht verändert hat. Nach dem Test bei Bedarf „Rückgängig“ tippen bzw. die Testzeilen in Obsidian löschen.

## 7. Checkliste

Jeden Punkt abhaken und Auffälliges notieren (Modell, Sprache, was erkannt wurde).

**Assistent und Overlay**
- [ ] Langer Druck auf die Power-Taste (oder die Assistenten-Geste) öffnet das Wendelin-Overlay über der aktuellen App. Wendelin hört sofort zu (Wellenform). Die Wellenform gibt es nur im Overlay, im Hauptbildschirm zeigt der Ring um den Mikrofon-Knopf das Zuhören (bis WP31 gemergt ist).
- [ ] D1 über das Overlay: Die Notiz ist ergänzt, das Overlay zeigt nur diese Anfrage (Zitat, Karte, Antwort).
- [ ] Tipp neben das Sheet, „Beenden“ oder Zurück schließen das Overlay. Danach ist das Mikrofon aus (das Mikrofon-Symbol in der Statusleiste verschwindet).
- [ ] Erneuter Aufruf bei offenem Overlay startet eine neue Anfrage.
- [ ] Zwei Engines in einem Prozess (auf dem Emulator geprüft): Zuerst die Wendelin-App öffnen, dann das Overlay darüber (Power-Taste), das Overlay schließen und in der App eine getippte Anfrage senden. Sie läuft, Verlauf und Prüfprotokoll zeigen sie. Umgekehrt geht es nicht: Wer bei offenem Overlay die App öffnen will, tippt neben das Sheet und schließt damit das Overlay.
- [ ] Verlauf leeren: „Neues Thema“ tippen oder sagen, oder 5 min nichts tun. Danach beginnt eine neue Unterhaltung (nach WP31 kommen der Knopf „Neues Gespräch“ und weitere Formulierungen hinzu).

**Sperrbildschirm**
- [ ] Telefon sperren, Power-Taste lang drücken: Das Overlay zeigt nur „Gerät entsperren“. Kein Verlauf, kein Zuhören, nichts wird gesprochen.
- [ ] „Entsperren“ → PIN/Fingerabdruck → erst dann hört Wendelin zu.
- [ ] Entsperren abbrechen: Es bleibt bei „Gerät entsperren“, bis „Entsperren“ oder „Beenden“ getippt wird.
- [ ] Im Overlay sind keine Screenshots möglich (schwarz bzw. Hinweis).

**Abbruch**
- [ ] Während Wendelin zuhört, „Stopp“ sagen: Die Anfrage endet, nichts wird ausgeführt.
- [ ] Während Wendelin denkt oder spricht, auf das Mikrofon bzw. den Knopf tippen: Er hört sofort auf.
- [ ] D3, und während er „Soll ich das tun?“ fragt, tippen (Abbruch): Die Frage verstummt, er hört nicht mehr auf eine Antwort, der Abschnitt bleibt unverändert.
- [ ] App in den Hintergrund schicken (Home), während Wendelin zuhört oder spricht: Alles stoppt.

**Bestätigung per Stimme**
- [ ] D3 mit „Ja“ → ersetzt.
- [ ] D3 mit „Nein“ → nichts geändert, Wendelin sagt das.
- [ ] D3 mit „Ja, bitte“ → einmal „Bitte sag ja oder nein.“, dann geht nur noch der Tipp.
- [ ] Getippte Anfrage mit Bestätigung: Es wird nichts vorgelesen, nur die Karte („Antworte per Tipp“).

**Rückgängig**
- [ ] D1, dann innerhalb von 10 s „Rückgängig“ tippen: Die Zeile ist weg, der Rest der Notiz unverändert (in Obsidian prüfen).
- [ ] D3 mit „Ja“, dann „Rückgängig“: Der alte Abschnitt ist wieder da.

**Mikrofon-Berechtigung**
- [ ] In den Android-Einstellungen Wendelin das Mikrofon entziehen, dann auf das Mikrofon tippen: zuerst Wendelins Erklärung „Mikrofon erlauben?“, kein Absturz. „Nicht jetzt“ → Karte „Ohne Mikrofon-Zugriff geht nur Text.“ mit „Erlauben“. „Erlauben“ und in Android ablehnen (oder Android fragt nicht mehr, weil schon zweimal abgelehnt) → Hinweis auf die Android-Einstellungen, die Karte bietet „Android-Einstellungen“ an. Dort erlauben, zurück: Die Karte ist weg.

**System-Spracherkennung in einer anderen App**

Test-App: **Kõnele** (F-Droid, `ee.ioc.phon.android.speak`). Sie nutzt die `SpeechRecognizer`-Schnittstelle von Android. Tastaturen wie FlorisBoard wechseln für die Spracheingabe nur zu einer Sprach-Tastatur und eignen sich nicht. Es gibt zwei Wege, sie prüfen Verschiedenes:

- **(a) Wendelin ausdrücklich wählen:** In Kõneles Einstellungen den Erkennungsdienst „Wendelin“ wählen. Kõnele bindet ihn dann direkt, unabhängig davon, welchen Dienst Android als Standard nutzt. Das prüft nur den Dienst selbst und geht deshalb auch auf Geräten, auf denen Einstellungen → Assistent „Auf diesem Gerät nicht verfügbar“ zeigt (B12). „Wendelin“ ist nur auswählbar, solange Wendelin Standard-Assistent ist und der Schalter „Als Spracherkennung für andere Apps anbieten“ an ist.
- **(b) System-Standard:** Den Standard-Dienst von Android nutzen (in Kõnele den vom System vorgegebenen Dienst wählen, falls angeboten, oder eine andere App, die den Standard-Erkenner aufruft). Das prüft, ob Android Spracheingaben anderer Apps wirklich an Wendelin gibt (B12). Zeigt Einstellungen → Assistent „Auf diesem Gerät nicht verfügbar“, nutzt Android einen anderen Dienst: Weg (b) überspringen. Ob Kõnele einen solchen Standard-Eintrag anbietet, ist noch nicht geprüft.

- [ ] Weg (a): In Kõnele mit Wendelin als Dienst diktieren. Der Text kommt von Wendelin (Whisper auf dem Gerät).
- [ ] Weg (b), sofern nicht „nicht verfügbar“: Diktieren über den System-Standard. Der Text kommt ebenfalls von Wendelin.
- [ ] Dasselbe, während die Wendelin-App offen im Hintergrund ist (die Erkennung nutzt dann deren Whisper mit). Im Log (Abschnitt 9) stehen Zeilen „Erkenner: Whisper-Zeit …“.
- [ ] Kaltstart des Erkenners: Wendelin-App ganz schließen (aus „Zuletzt verwendet“ wischen oder `adb shell am force-stop app.wendelin`), dann in der fremden App die Spracheingabe starten, einen kurzen Satz sagen und die Zeit vom Satzende bis zum ersten Text stoppen (mehrmals, Mittelwert notieren). Das Log zeigt die reine Whisper-Zeit („Erkenner: Whisper-Zeit …“, Abschnitt 8).
- [ ] Speicher: während bzw. direkt nach einer Erkennung `adb shell dumpsys meminfo app.wendelin` und „TOTAL PSS“ notieren, einmal mit offener Wendelin-App (geteiltes Whisper) und einmal ohne (eigenes Modell des Erkenners, wird 30 s nach der letzten Anfrage freigegeben), je für base und small.
- [ ] Einstellungen → Assistent → „Als Spracherkennung für andere Apps anbieten“ aus: Die Spracheingabe der anderen App meldet einen Fehler. Wendelin bleibt Assistent.
- [ ] Zu einem anderen Assistenten (oder „Keiner“) wechseln: Die System-Spracherkennung antwortet nicht mehr. Der Hinweis in Einstellungen → Assistent beschreibt das.

**Sprachausgabe**
- [ ] Mit Systemstimme (falls vorhanden) und ohne: Einstellungen → Sprache → Sprachausgabe „Offline-Stimme“, eine Stimme laden, „Probe hören“.

**Laufzeit** (siehe Abschnitt 8)
- [ ] Tabelle für base und small ausgefüllt.

## 8. Laufzeit messen (base gegen small)

Wendelin schreibt nach jeder Erkennung eine Zeile ins Android-Log, mit Modell, Sprache und Dauer, aber ohne den erkannten Text. Das gilt auch im Release-Build. Mit dem Telefon per adb verbunden:

```sh
tool/whisper_timing.sh --clear     # Log leeren
```

Dann in Wendelin (Einstellungen → Sprache: Whisper base, Gesprochene Sprache „Wie die App“) die Sätze D1, D2 und D3 sprechen, jeweils als Push-to-talk im Hauptbildschirm. Nach jeder Anfrage auf „Rückgängig“ tippen oder bei D3 „Nein“ sagen. Danach:

```sh
tool/whisper_timing.sh             # Tabelle: Ø Audio, Ø Rechenzeit, max, RTF
```

Dasselbe mit Whisper small wiederholen (Einstellungen → Sprache → small wählen, `--clear`, die drei Sätze, auswerten). Gefühlte Wartezeit nach dem Satzende = 0,8 s Endstille + Rechenzeit + erste Antwort des Providers.

Vorlage zum Ausfüllen:

| Telefon / Android | Modell | Sätze | Ø Audio | Ø Rechenzeit | max | RTF | erkannt wie gesagt? | Eindruck |
|---|---|---:|---:|---:|---:|---:|---|---|
| | whisper-base | | | | | | | |
| | whisper-small | | | | | | | |

Zum Vergleich (Emulator auf Apple Silicon, 4 Kerne, siehe `docs/notes/m2-e2e-2026-10-13.md`): base Ø 182 ms je Satz (RTF 0,05), small Ø 539 ms (RTF 0,15). Ein Telefon ist langsamer: Ist small dort im Mittel unter etwa 2 s je Satz (RTF ≲ 0,5), empfehlen wir small mit fester Sprache als Standard.

## 9. Logs und Prüfprotokoll exportieren

- **Prüfprotokoll** (jede Anfrage mit Auslöser, Sprache, Tool-Aufrufen, Bestätigungen, Kosten): Einstellungen → Datenschutz und Logs → Prüfprotokoll → „Als JSON exportieren“ → über das Teilen-Menü speichern oder senden. Es enthält deine Anfragen im Klartext, also vor dem Weitergeben ansehen.
- **Android-Log** (per adb): Wendelin protokolliert keine Inhalte, nur Fehler, Längen und Zeiten.

  ```sh
  adb logcat -d -s flutter:I WendelinRecognizer:I AndroidRuntime:E > wendelin-log.txt
  ```

  Bei einem Absturz zusätzlich `adb logcat -d -b crash > wendelin-crash.txt`.
- Für einen Fehlerbericht: Telefonmodell, Android-Version, Whisper-Modell, gesprochener Satz, was passiert ist, beide Dateien.

## 10. Bekannte Grenzen

- **Kein Barge-in:** Während Wendelin spricht, stoppt ihn nur ein Tipp. „Stopp“ wirkt, solange er zuhört (ab v0.4 geplant).
- **Gesprächsmodus kommt mit M4.** Nach einer Antwort hört Wendelin nicht weiter zu, die Zeile unten im Overlay ist ausgegraut.
- **Kein Wake Word** (M4). Auslöser sind Power-Taste, Assistenten-Geste, Mikrofon-Knopf.
- **Whisper erkennt den Satz als Ganzes**, es gibt keinen Zwischentext beim Sprechen. Andere Apps bekommen über die System-Spracherkennung ebenfalls keine Teilergebnisse.
- **Feste Sprache:** Mit „Wie die App“ werden fremdsprachige Sätze falsch erkannt. „Automatisch erkennen“ hilft, ist bei kurzen Sätzen („Ja“) aber unsicher.
- **Zahlen und Uhrzeiten** schreibt Whisper mal als Ziffern, mal als Wort („halb sieben“ gegen „6:30“).
- **Speicher:** Whisper small (Standard) belegt geladen deutlich mehr RAM als base (gemessen bis ≈ 1,3 GB PSS, B14). Auf Telefonen mit wenig Speicher kann Android die App im Hintergrund beenden; dort „Whisper base – schnell“ wählen.
- **Eigennamen:** Notiztitel und „Wendelin“ korrigiert Wendelin nach der Erkennung lokal (Vokabular aus Notizindex und Listen, nur im Speicher). Findet er eine Notiz nur nach Klang, fragt er bei Änderungen immer nach („Meinst du die Notiz …?“); lesen darf er einen eindeutigen Treffer direkt und nennt ihn. Die System-Spracherkennung für andere Apps korrigiert nichts.
- **Assistentenwechsel:** Nach dem Wechsel zu einem anderen Assistenten zeigt die System-Spracherkennung unter Umständen noch auf Wendelin und antwortet dann nicht. In Android neu wählen.
- **SAF-Vault:** Wendelin schreibt eine Notiz in einem Zug neu (kein atomares Umbenennen über SAF). Ändert ein Sync-Dienst sie im selben Moment, erkennt die optimistische Sperre das und versucht es erneut.
- **Signatur:** Release-Builds sind vorerst mit dem Debug-Schlüssel signiert (siehe Abschnitt 1).
- Auf dem Emulator nicht prüfbar und deshalb hier wichtig: echtes Mikrofon und echte Stimmen, Raumhall, Power-Taste, Fingerabdruck, die Aufnahme aus einer fremden App im Vordergrund, das geteilte Whisper zwischen App und Erkenner.

## Ergebnis zurückmelden

Kurz an den Orchestrator bzw. ins Issue: abgehakte Checkliste, Laufzeittabelle, Auffälligkeiten mit Log. Danach entscheidet der Maintainer über den Standard für das Whisper-Modell.
