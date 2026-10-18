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
