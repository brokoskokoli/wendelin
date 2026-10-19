# M5 auf dem Telefon testen (Geräte-Prüfliste)

Jedes M5-Arbeitspaket ergänzt hier seinen Block. Befehle am Telefon führt nur der Maintainer aus.

## WP87 Wetter und Meer

- [ ] **Einschalten.** Einstellungen → Integrationen → „Wetter und Meer“ einschalten. Erwartet: aktiv ohne Berechtigungsfrage; „Heimatort“ als optionaler offener Schritt.
- [ ] **Dienst und Heimatort.** In „Wetterdienst und Heimatort“ Open-Meteo gewählt, Heimatort „Kiel“ eingetragen, Speichern. Erwartet: Seite schließt; erneut öffnen zeigt Kiel; unbekannter Name („Xyzzy“) zeigt „Ort … nicht gefunden“ und speichert nichts.
- [ ] **Frage mit Ort.** „Wie wird das Wetter morgen in Hamburg?“ Erwartet: kurze, gerundete Antwort (Grad, Regen, Wind), Tool-Karte „Wetter: Hamburg“.
- [ ] **Frage ohne Ort.** „Brauche ich heute Abend eine Regenjacke?“ Erwartet: Wetter für den Heimatort (WP86 aktiv: für den aktuellen Standort).
- [ ] **Stunden.** „Wie wird es in den nächsten sechs Stunden?“ Erwartet: Stundenliste in der Antwort.
- [ ] **Meer.** „Wie hoch sind die Wellen bei Palma?“ Erwartet: Wellenhöhe, Dünung, Periode, Wassertemperatur; für einen Ort im Landesinneren: Hinweis „keine Meeresdaten“.
- [ ] **Dienstwechsel.** Bright Sky (DWD) wählen, nach Berlin fragen; dann MET Norway. Erwartet: jeweils Antwort, Quelle im Datenblock des Tools; Flugmodus an: Meldung „nicht erreichbar“, kein Absturz.

## WP91 Home Assistant

Voraussetzung: eine eigene Home-Assistant-Instanz im selben WLAN (oder über Tailscale erreichbar) und ein Long-Lived Access Token (Profil → Sicherheit).

- [ ] **Suche im WLAN**: Einstellungen → Integrationen → Home Assistant → „Einrichten“ → „Im WLAN suchen“. *Erwartet*: die Instanz erscheint unter „Gefunden“ (mit Multicast-Sperre aus `MulticastChannel`); Antippen füllt die Adresse. Bei Mobilfunk/Tailscale ohne WLAN: „Nichts gefunden“, Adresse von Hand.
- [ ] **Adresse von Hand über Tailscale**: `http://100.x.y.z:8123` oder `http://<name>.<tailnet>.ts.net:8123` mit Token → „Verbunden“. `http://<öffentliche Adresse>` wird abgelehnt (Hinweis auf https).
- [ ] **Geräte freigeben**: Liste nach Räumen; Schalter an für ein Licht, einen Schalter, eine Szene, das Schloss. Nur diese Geräte kennt Wendelin („Welche Geräte gibt es?“).
- [ ] **Licht per Sprache** („Mach das Licht in der Küche aus“): läuft ohne Rückfrage, Karte mit „Rückgängig“; Rückgängig schaltet es mit der alten Helligkeit wieder ein.
- [ ] **Szene** („Filmabend“): läuft ohne Rückfrage; Rückgängig stellt die Lampen/Geräte der Szene wie vorher her; in Home Assistant bleibt keine Szene `wendelin_undo_…` zurück.
- [ ] **Schloss/Garage/Alarm** („Schließ die Haustür ab“, „Mach das Garagentor auf“): **immer** Bestätigungskarte mit Gerätename und Raum; „Nein“ ändert nichts; kein „Rückgängig“.
- [ ] **Falsches Token** (Token in Home Assistant löschen): Zustand „Fehler“, „Erneut versuchen“ nach neuem Token (Einrichtung erneut) wird wieder „Aktiv“.
- [ ] **Datenschutz**: Im Datenschutz-Log/Export stehen weder Token noch Adresse.

Emulator (E2E-Agent): Adresse `http://10.0.2.2:<Port>` auf einen lokalen Fake-HA (Dart-Testserver `packages/wendelin_integrations/test/home_assistant/ha_server.dart`); die mDNS-Suche liefert im Emulator nichts (kein WLAN-Multicast).

## WP84 Spotify

Voraussetzung: Spotify Premium, Spotify-App auf dem Telefon installiert und mindestens einmal angemeldet.

- [ ] **S.1 Entwickler-App.** Nach der Anleitung unter Einstellungen → Integrationen → Spotify → „Spotify-Konto“ auf developer.spotify.com/dashboard eine App anlegen (Redirect URI genau wie in der App angezeigt, „Web API“ angekreuzt), das eigene Konto unter „User Management“ eintragen. *Erwartet:* Die Seite zeigt die Redirect-Adresse `app.wendelin://oauth/spotify`; „Adresse kopieren“ legt sie in die Zwischenablage.
- [ ] **S.2 Anmelden.** Client-ID eintragen, „Bei Spotify anmelden“. *Erwartet:* Der Browser (Custom Tab) zeigt die Spotify-Zustimmung mit den Rechten „Wiedergabestatus lesen“ und „Wiedergabe steuern“; nach „Zustimmen“ kehrt die App zurück, die Seite zeigt „Angemeldet · Aktiv“, die Kachel ist „Aktiv“. Eine falsche Client-ID bzw. fehlende Redirect-Adresse zeigt Spotifys Fehlerseite, in der App einen abgebrochenen Login (kein Absturz).
- [ ] **S.3 „Spiel Bohemian Rhapsody von Queen.“** Spotify-App ist **geschlossen** (aus den Zuletzt-Apps gewischt). *Erwartet:* Wendelin startet die Spotify-App, nach wenigen Sekunden läuft der Titel; die Antwort nennt „Bohemian Rhapsody – Queen“. Notiere die Dauer bis zum ersten Ton: ______. (Prüft den Intent `spotify:` zum Aufwecken; klappt er nicht, steht „Kein aktives Spotify-Gerät …“.)
- [ ] **S.4 „Pause.“ / Rückgängig.** *Erwartet:* Musik pausiert, die Karte bietet „Weiter abspielen“; Tippen setzt fort.
- [ ] **S.5 „Was läuft gerade?“** *Erwartet:* Titel, Künstler und Gerät werden genannt, bei Pause auch „pausiert“.
- [ ] **S.6 „Nächster Titel“, „Vorheriger Titel“.** *Erwartet:* Wechsel hörbar, Antwort kurz.
- [ ] **S.7 „Spiel die Playlist …“ / „Spiel das Album …“ / „Spiel etwas von …“** (je eins aus der eigenen Bibliothek bzw. bekannt). *Erwartet:* Passender Kontext läuft; das Rückgängig der Karte spielt das vorherige Stück an derselben Stelle (falls vorher etwas lief) bzw. pausiert.
- [ ] **S.8 „Leg … in die Warteschlange.“** *Erwartet:* Der Titel erscheint in Spotifys Warteschlange (Spotify-App öffnen); ein Rückgängig gibt es nicht (Spotify kann die Warteschlange nicht per API ändern).
- [ ] **S.9 Fehlertexte.** (a) Spotify-App beenden und Telefon im Flugmodus: „… nicht erreichbar“, keine Dauerschleife. (b) In der Spotify-App unter „Apps mit Zugriff“ den Zugriff von Wendelin entfernen, dann „Pause“: Die Kachel zeigt „Fehler … pausiert“, „Erneut versuchen“ bzw. neu anmelden führt zurück. (c) Mit einem Free-Konto (falls zur Hand): „Die Wiedergabe steuern kann Spotify nur mit einem Premium-Konto.“
- [ ] **S.10 Abmelden.** Spotify-Seite → „Abmelden“. *Erwartet:* Rückfrage, danach die Anmeldemaske; Kachel „Login fehlt“.

## WP88 Aufgaben (Listen mit Fälligkeit)
- [ ] Einstellungen → Listen: Liste „Aufgaben“ anlegen, Schalter „Standard-Aufgabenliste“ an. Eine zweite Liste mit dem Schalter macht die erste wieder aus.
- [ ] Sagen: „Erinnere mich an die Steuer, fällig am 20. Oktober, hohe Priorität“ → Datei in Obsidian zeigt `- [ ] Steuer ⏫ 📅 2026-10-20` und das Tasks-Plugin (falls installiert) listet sie mit Datum. Mit Uhrzeit („um 14:30“) steht `⏰ 14:30` vor `⏫ 📅 …`, das Plugin findet die Fälligkeit trotzdem.
- [ ] „Welche Aufgaben sind heute fällig?“ / „Was ist überfällig?“ nennt nur passende Aufgaben, überfällige zuerst.
- [ ] „Hak die Steuer ab“ → Zeile `- [x] … ✅ <heute>`; Rückgängig stellt die Zeile ohne `✅` her.

## WP90 Medien (`media`)

Vorbereitung: Einstellungen → **Integrationen** → **Medien** einschalten. Android öffnet die Seite „Benachrichtigungszugriff“: **Wendelin** einschalten (bei Sideload-Installation unter Android 13 oder neuer vorher App-Info → Menü → „Eingeschränkte Einstellungen zulassen“). Ohne den Zugriff steht die Integration auf „aktiv“, der optionale Schritt „Benachrichtigungszugriff erlauben“ bleibt offen.

- [ ] **WP90.1 Was läuft.** Hörbuch in Audible (oder Podcast-App) starten, „Was läuft gerade?“ sagen. *Erwartet:* Tool-Karte `media__now_playing`, Antwort nennt App, Titel, Position.
- [ ] **WP90.2 Pause/Weiter.** „Pause“, dann „Weiter“. *Erwartet:* Player pausiert bzw. spielt; Rückgängig auf der Karte macht das Gegenteil. Zweimal „Pause“: „Es ist schon pausiert.“
- [ ] **WP90.3 Spulen.** „Spul 30 Sekunden zurück“. *Erwartet:* Position im Player 30 s früher, Karte „Gespult auf …“, Rückgängig springt zurück. Player ohne Spul-Unterstützung: Fehlertext, keine Wirkung.
- [ ] **WP90.4 Nächstes/Vorheriges.** „Nächstes Kapitel“ / „Vorheriges“. *Erwartet:* Player wechselt, kein Rückgängig.
- [ ] **WP90.5 Ohne Zugriff.** Benachrichtigungszugriff ausschalten. *Erwartet:* „Pause“ und „Weiter“ wirken per Medientaste; „Was läuft?“ und Spulen melden, dass der Benachrichtigungszugriff fehlt.
- [ ] **WP90.6 Audible öffnen.** „Öffne Audible“ bzw. „Öffne Audible und suche Kafka“. *Erwartet:* Audible öffnet (ggf. mit Suche); ohne Audible: „Audible ist nicht installiert.“
- [ ] **WP90.7 Sprachausgabe und Player.** Hörbuch läuft, Wendelin antworten lassen. *Erwartet:* Das Hörbuch wird leiser (nicht pausiert), solange Wendelin spricht (ganze Antwort, auch bei Offline-Stimme), und läuft danach mit voller Lautstärke weiter (Audiofokus `GAIN_TRANSIENT_MAY_DUCK`). Beim Zuhören (Aufnahme) pausiert es kurz und läuft danach weiter (`GAIN_TRANSIENT`). Nach „Pause“ bleibt es pausiert.

Emulator (E2E-Agent): `cmd notification allow_listener app.wendelin/app.wendelin.MediaListenerService` per `adb -s emulator-xxxx shell`, eine Player-App mit Media-Session installieren (z. B. AntennaPod oder VLC aus F-Droid, eine kurze Audiodatei abspielen), dann `tool/e2e_android.sh integration_test/media_e2e_test.dart`.

## WP85 Kontakte, SMS und Anrufe (`contacts`)

Vorbereitung: Einstellungen → **Integrationen** → **Kontakte & Telefon** einschalten; Android fragt Kontakte, SMS und Telefon ab (erst jetzt). Kontakte „Anna Meier“ (Mobil) und „Ben Schmidt“ mit der Nummer des Emulators bzw. einer eigenen Testnummer anlegen. Emulator-Nummer 5554 (SMS: `adb -s emulator-xxxx` zweiter Emulator oder `adb emu sms send`).

- [ ] **WP85.1 Kontakt suchen.** „Wie ist die Nummer von Anna?“ *Erwartet:* `contacts__find`, Antwort nennt die Nummer; bei „Ben“ (mehrere Treffer) wird zur Auswahl nachgefragt.
- [ ] **WP85.2 SMS-Vorschau.** „Schreib Anna: Ich komme später.“ *Erwartet:* Popup mit Name, Nummer und editierbarem Text, Wendelin liest „Nachricht an Anna Meier: Ich komme später. Soll ich sie absenden?“ vor und hört zu. Es wird noch nichts gesendet.
- [ ] **WP85.3 Absenden per Tipp.** Text im Popup ändern, „Absenden“ tippen. *Erwartet:* Die SMS mit dem geänderten Text kommt an (Emulator-Konsole bzw. zweites Gerät); Kachel zeigt Erfolg.
- [ ] **WP85.4 Sprachbestätigung.** Wie 2, dann „absenden“ sagen (einzeln zusätzlich „ja“). *Erwartet:* SMS gesendet. „Anrufen“ als Antwort auf die SMS-Frage sendet nichts.
- [ ] **WP85.5 Abbrechen und Unklares.** „nein“/„abbrechen“: nichts gesendet. „Vielleicht“: Wendelin bittet „Bitte sag „absenden“ oder „abbrechen““; nach zweimal Unklarem bleibt nur Tipp, nichts wurde gesendet.
- [ ] **WP85.6 Geänderter Text.** Während des Vorlesens den Text im Popup ändern, dann „ja“ sagen. *Erwartet:* Nichts gesendet, Hinweis auf Tipp.
- [ ] **WP85.7 Anruf.** „Ruf Ben an.“ *Erwartet:* Popup mit Name und Nummer, „Soll ich anrufen?“; „anrufen“ startet den Anruf (mit `CALL_PHONE`; ohne die Berechtigung öffnet sich der Wählbildschirm), „abbrechen“ nicht.
- [ ] **WP85.8 Gesprächsmodus.** Gesprächsmodus an, SMS wie in 2: nur „absenden“/Tipp sendet.
- [ ] **WP85.9 Gesperrt.** Bildschirm sperren, Assistent starten, „Schreib Anna …“. *Erwartet:* „Bitte entsperre …“, keine Vorschau, nichts gesendet.
- [ ] **WP85.10 Audit.** Einstellungen → Protokoll: Eintrag mit Empfängername, ohne Nachrichtentext.

