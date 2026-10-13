# WP32 – Onboarding, Einstellungen und System-Spracherkennung (`app/` + Kotlin, Doku)

Abhängig von: – (sofort startbar auf main). Bezug: Gerätetest 2026-10-13 (`M2-fixes.md`), Befunde **B1, B2, B3, B4, B12** und die Wünsche zu Onboarding und Einstellungen. Ergänzt die Geräte-Anleitung `docs/testing/m2-device.md`. Andockpunkte: `app/lib/ui/onboarding/onboarding_screen.dart` (`_step`, `showBack`), `voice_download_step.dart`, `app/lib/ui/settings/provider_setup_screen.dart`, `web_search_screen.dart`, `bring_screen.dart`, `http_tool_editor_screen.dart` (die beiden letzten aus WP28), `assistant_screen.dart`, `obsidian_screen.dart`, `app/lib/ui/voice/microphone_access.dart`, Kotlin `RecognizerSwitch.kt` und `AssistantChannel.kt`. ADRs: 0005 (Einstellungen/Onboarding), 0008 (System-Erkenner).

## Inhalt

**Eingaben und Rückmeldungen**
- **B1 Autofill:** Alle Secret-Felder bekommen `autofillHints` (`AutofillHints.password`) in einer `AutofillGroup` (bzw. `username` + `password` beim Bring!-Login). Am besten geht das über einen gemeinsamen Baustein (z. B. `SecretField` in `ui/design/`): maskiert, Autofill, kein Vorschlagsspeicher der Tastatur (`enableSuggestions: false`, `autocorrect: false`), nach dem Speichern nur ersetzbar. Er gilt für Provider-Key, Websuche-Key, Bring!-Zugang und HTTP-Tool-Secrets. WP27 (MCP-Token/Header) nutzt denselben Baustein. Ist WP27 vorher gemergt, stellt WP32 dessen Felder um.
- **B2 Verbindungstest:** Nach erfolgreichem Test erscheint über der Modellliste ein Status-Element „Verbindung steht“ mit `CheckStatusIcon` ok (Kreis), wie bei anderen Prüfungen. Ein Fehler wird entsprechend angezeigt.

**Onboarding**
- **B3 Download-Schritt:** Silero VAD erscheint nicht als eigene Zeile mit eigenem Knopf. Es wird mit dem gewählten Whisper automatisch mitgeladen und unter der Auswahl als „gehört dazu (0,6 MB)“ genannt. Es gibt genau einen Weg zum Laden (Modellwahl + ein „Laden“). Die Knöpfe je Zeile entfallen. Darunter steht klar „Noch nötig: …“ oder „Bereit“. „Weiter“ ist aktiv, sobald die gewählte Kombination installiert ist. „Im Hintergrund weiterladen“ bleibt. Weitere Modelle lädt man in Einstellungen → Sprache. Das Standardmodell der Vorauswahl setzt WP33.
- **B4 Zurück:** `PopScope` im Onboarding. Die System-Zurück-Geste geht ab Schritt 2 einen Schritt zurück und schließt erst in Schritt 1 die App. Zusätzlich gibt es ab Schritt 2 einen Zurück-Pfeil (`showBack: true`).
- **Provider-Schritt:** Inhalt vertikal mittig wie auf der Willkommen-Seite, solange er auf den Bildschirm passt, sonst scrollbar ab oben.
- **Mikrofon-Hinweis präsenter:** „Ohne Mikrofon-Zugriff geht nur Text.“ als gut sichtbarer Hinweis (Karte bzw. Hinweiszeile mit Icon über der Eingabezeile, mit Aktion „Erlauben“ bzw. „Android-Einstellungen“), nicht klein am unteren Rand.

**Einstellungen → Assistent**
- **Persönlichkeit:** mehrzeilig, wächst beim Tippen mit (`minLines: 2`, `maxLines: 5`).
- Der Hilfstext unter „Als Standard-Assistent setzen“ entfällt.
- Ist Wendelin schon Standard-Assistent, verschwindet der Knopf. Es bleibt der Status mit Haken und ein Textlink „In Android ändern“, damit man wechseln kann.
- **B12 System-Spracherkennung:** Kotlin liest `Settings.Secure` `voice_recognition_service` (wie heute schon `assistant` in `RecognizerSwitch.holdsAssistantRole`) und meldet einen von drei Zuständen: **aktiv** (Wert zeigt auf `app.wendelin/.WendelinRecognitionService`), **anderer Dienst** (Wert zeigt auf eine andere Komponente, deren App-Name angezeigt wird) oder **unbekannt** (Wert leer oder nicht lesbar). Ist der Wert nicht lesbar, gibt es eine Rückfallprüfung: ein kurzer Selbsttest über `SpeechRecognizer.createSpeechRecognizer(context)`, der prüft, ob `WendelinRecognitionService` gebunden wird, ohne Mikrofon und ohne Aufnahme. Ob das ohne Mikrofon geht, prüft das Paket zuerst; sonst bleibt „unbekannt“. Bei „anderer Dienst“ ist der Schalter „Als Spracherkennung für andere Apps anbieten“ ausgegraut und als „Auf diesem Gerät nicht verfügbar“ gekennzeichnet, mit dem Hinweis „Android nutzt für andere Apps <Dienst>. Das lässt sich auf diesem Gerät nicht umstellen.“ Die gespeicherte Einstellung bleibt erhalten. Neuprüfung bei Rückkehr in die App. Das System wird nie umgestellt (keine `WRITE_SECURE_SETTINGS`).

**Einstellungen → Obsidian**
- Tagesnotiz-Ordner ist mit `Journal` vorbelegt, wenn noch nichts gespeichert ist. Leer bleibt erlaubt (= Vault-Wurzel). Der Hinweistext nennt das. Bestehende gespeicherte Werte bleiben unverändert.
- Unter „Index aufbauen“: „Wird automatisch aktualisiert (beim Start und vor jeder Suche). Der Knopf ist nur für den ersten Aufbau nötig.“

**Geräte-Anleitung `docs/testing/m2-device.md`**
- Abschnitt 1, Variante A: Xiaomi/HyperOS braucht in den Entwickleroptionen „Über USB installieren“ und die Bestätigung am Telefon. Sonst kommt `INSTALL_FAILED_USER_RESTRICTED`.
- Abschnitt 4: Auf HyperOS öffnet die Power-Taste den Assistenten ohne zusätzliche Einstellung. Punkt 4 (System-Spracherkennung) wird eingeschränkt: Sie folgt der Assistenten-Rolle nur, wenn Android `voice_recognition_service` mitzieht. Auf Geräten mit GMS (z. B. HyperOS) bleibt sie oft bei Google (B12). Die Einstellungsseite zeigt den tatsächlichen Zustand.
- Abschnitt 7, „Zwei Engines“: Zuerst die App öffnen, dann das Overlay darüber. Umgekehrt schließt der Tipp neben das Sheet das Overlay.
- Abschnitt 7, Hauptbildschirm: Die Wellenform gibt es nur im Overlay, im Hauptbildschirm zeigt der Ring das Zuhören (bis WP31 gemergt ist, danach anpassen).
- Den Verlauf leeren „Neues Thema“ (Text oder Stimme) oder 5 min Inaktivität. Nach WP31 kommen der Knopf „Neues Gespräch“ und weitere Phrasen hinzu.
- System-Spracherkennung: eine konkrete Test-App nennen, die den System-`SpeechRecognizer` nutzt und über F-Droid erhältlich ist (z. B. Kõnele oder FlorisBoard; vor dem Eintragen prüfen, ob die App den Standard-Erkenner aufruft). Dazu der Hinweis, den Abschnitt zu überspringen, wenn Einstellungen → Assistent „nicht verfügbar“ zeigt (B12).
- „Bekannte Grenzen“: Speicherwert nach WP30 aktualisieren. Standardmodell nach WP33 aktualisieren.

## Abnahmekriterien
- [ ] B1: gemeinsamer Secret-Baustein mit Autofill-Hints. Widget-Test prüft `autofillHints` und `obscureText` für Provider, Websuche, Bring!, HTTP-Tool-Secret.
- [ ] B2: Erfolgselement nach dem Verbindungstest (Widget-Test mit Fake-Provider, Golden).
- [ ] B3: Download-Schritt mit einem Ladeweg, Silero automatisch, „Noch nötig: …“, „Weiter“ aktiv genau bei fertiger Kombination (Tabellentest der Zustände, Golden).
- [ ] B4: Zurück-Geste geht im Onboarding einen Schritt zurück, in Schritt 1 schließt sie (Widget-Test mit `handlePopRoute`). Zurück-Pfeil ab Schritt 2.
- [ ] Provider-Schritt mittig, Mikrofon-Hinweis präsent (Goldens).
- [ ] Assistent: Persönlichkeit mehrzeilig, Hilfstext weg, Knopf nur ohne Rolle (Widget-Tests beider Fälle).
- [ ] B12: Kotlin-Kanal liefert aktiv/anderer Dienst/unbekannt, getestet mit Mock-Kanal (Dart) und JVM-Test der Auswertung (Komponentenvergleich). Schalter-Kennzeichnung „Auf diesem Gerät nicht verfügbar“ im Widget-Test. Emulator (AOSP): nach dem Setzen der Rolle per adb Zustand „aktiv“. Mit `adb -s emulator-xxxx shell settings put secure voice_recognition_service <andere Komponente>` Zustand „anderer Dienst“, danach den Ausgangswert wiederherstellen.
- [ ] Obsidian: `Journal` vorbelegt nur ohne gespeicherten Wert (Test mit gespeicherten M2-Einstellungen, Wert bleibt), Index-Hinweis sichtbar.
- [ ] `m2-device.md` um alle Punkte oben ergänzt (keine Gerätekennungen, keine Namen).
- [ ] Touch-Ziele ≥ 44, Semantics-Labels für neue Elemente.
- [ ] Gerätetests nur auf `Wendelin_AOSP_35` mit explizitem Serial.
- [ ] Gate grün, APK baut, `tool/check_apk.sh` grün (keine neue Berechtigung).

## Prüfliste für den Maintainer (echtes Telefon)
- [ ] Provider-Key und Bring!-Passwort lassen sich per Passwort-Manager (Bitwarden) ausfüllen.
- [ ] „Verbindung testen“ zeigt deutlich „Verbindung steht“.
- [ ] Neu-Installation: Der Download-Schritt ist ohne Nachdenken verständlich, „Weiter“ kommt nach dem einen Download. Die Zurück-Geste geht einen Schritt zurück.
- [ ] Einstellungen → Assistent auf HyperOS: Schalter „Als Spracherkennung für andere Apps anbieten“ zeigt „Auf diesem Gerät nicht verfügbar“ und nennt Google als aktuellen Dienst. Der Knopf „Als Standard-Assistent setzen“ ist weg, solange Wendelin Assistent ist.
- [ ] Persönlichkeit mit zwei Zeilen tippen: Das Feld wächst mit.
