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
