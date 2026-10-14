# M3 auf dem eigenen Telefon testen (Geräte-Testanleitung)

Diese Anleitung prüft Meilenstein M3 und die Nachbesserungen M2.1 (Sprach-UX, vorlesefreundliche Antworten, Power-Taste nach Pause) auf einem echten Android-Telefon. Auf dem Emulator ist vieles automatisch geprüft (`docs/notes/m3-e2e-2026-10-14.md`). Hier steht, was nur das Telefon zeigt: Tailscale zum Homeserver, echte Dienste (Bring!, Home Assistant, Claude), echte Stimme, Laufzeit, Speicher, Herstellerverhalten der Power-Taste.

**So wird sie benutzt:** Die Punkte sind fortlaufend nummeriert (1.1, 1.2 …). Jeder Schritt sagt, was zu tun ist und was erscheinen muss („Erwartet“). Wer die Anleitung mit dir abarbeitet (Test-Agent oder du allein), hakt die Kästchen ab und schreibt bei Abweichungen auf, was stattdessen passiert ist. Es ist kein Vorwissen nötig. Wo ein Befehl auf dem Rechner nötig ist, steht er im Wortlaut da.

Zeitbedarf: etwa 2 Stunden, dazu Wartezeit für Punkt 9 (Power-Taste nach einer Pause von mehreren Stunden).

Namen in „Anführungszeichen“ sind Beschriftungen in der App. Der Einstellungsbildschirm heißt **Einstellungen** und hat Zeilen **Provider**, **Routing**, **Integrationen**, **MCP-Server**, **HTTP-Tools**, **Obsidian**, **Listen**, **Web-Suche**, **Gedächtnis**, **Datenschutz und Logs**, **Kosten**, **Assistent**, **Sprache**.

## 0. Voraussetzungen und Vorbereitung

- [ ] **0.1 Telefon:** Android 10 oder neuer, die Wendelin-App aus `docs/testing/m2-device.md` Abschnitt 1 installiert (Release-APK `arm64-v8a`). Die M2-Einrichtung (Onboarding, Mikrofon, Standard-Assistent, Vault, Sprachmodell) ist erledigt. Falls nicht: zuerst `docs/testing/m2-device.md` Abschnitte 1 bis 5.
- [ ] **0.2 Provider-Keys:** Ein Anthropic-Key (für das Profil „Claude“) und ein zweiter Provider als Standard (z. B. Phala, Mistral oder ein zweites Anthropic-Profil mit Haiku). Beides nur in der App eintragen, nie in Chats oder Notizen weitergeben. Budget klein halten: Der ganze Test braucht unter 1 Euro.
- [ ] **0.3 Tailscale:** Auf dem Telefon und dem Homeserver ist Tailscale installiert und angemeldet. Auf dem Telefon: Tailscale-App öffnen, Status „Verbunden“. Auf dem Rechner: `tailscale status` zeigt den Homeserver mit einer `100.x.y.z`-Adresse und einem Namen `*.ts.net`. Notiere die Adresse: `HOMESERVER = ______________`.
- [ ] **0.4 Testserver für MCP und HTTP:** Auf dem Homeserver (oder einem Rechner im Tailnet) läuft ein MCP-Server. Zwei Wege:
  - **Weg A, Home Assistant:** Die Integration „Model Context Protocol Server“ ist in Home Assistant eingerichtet, der Endpunkt ist `http://HOMESERVER:8123/mcp_server/sse` (ältere Versionen) bzw. die in der Integration angezeigte Adresse; dazu ein langlebiges Zugriffstoken (Profil → Sicherheit → Langlebige Zugriffstokens). Notiere `MCP_URL` und `MCP_TOKEN` (Token nur im Passwortmanager).
  - **Weg B, Test-Server aus dem Repo (ohne Home Assistant):** Auf dem Rechner im Repo `cd app && WENDELIN_MCP_TOKEN=testtoken dart run tool/mcp_test_server.dart`. Das Programm gibt `port=<MCP-Port>` und `http_port=<REST-Port>` aus. Er lauscht nur auf `127.0.0.1`; für das Telefon muss er über das Tailnet erreichbar sein, z. B. mit `tailscale serve --bg --http=<MCP-Port> http://127.0.0.1:<MCP-Port>` (und ebenso für den REST-Port). `MCP_URL = http://HOMESERVER:<MCP-Port>/mcp`, `MCP_TOKEN = testtoken`. Der Server hat die Tools `get_state` (lesen), `echo`, `get_time` (lesen), `toggle_light` (schreiben), `delete_thing` und `delete_scene` (löschen). Beenden mit Strg+C, danach `tailscale serve reset`.
  - Notiere `MCP_URL = ______________` und ob Weg A oder B.
- [ ] **0.5 Bring!-Konto:** E-Mail und Passwort eines Bring!-Kontos, das Einkaufslisten hat (am besten ein Testkonto mit einer Liste „Test“). Die App nutzt eine inoffizielle Schnittstelle (siehe Hinweis in der App).
- [ ] **0.6 Testdaten:** In der Bring!-App auf der Liste „Test“ sind „Milch“ und „Brot“ eingetragen.
- [ ] **0.7 Rechner mit adb** (nur für Punkt 9 und das Sammeln von Logs): `adb devices` zeigt das Telefon als `device` (USB-Debugging an). Merke die Seriennummer: `SERIAL = ______________`.

## 1. Routing: Profile und Regeln

Ziel: „Claude, …“ geht an das Claude-Profil, alles andere an das Standardprofil, die Testsatz-Funktion zeigt die greifende Regel.

- [ ] **1.1 Profile anlegen.** Einstellungen → **Provider**. Es gibt ein Standardprofil (aus dem Onboarding). Tippe **+ Provider**, wähle die Vorlage **Anthropic**, Name **Claude API**, Key eintragen, Modell **claude-haiku-5-5** (das kleinste Modell reicht). Speichern. *Erwartet:* In der Liste stehen mindestens zwei Profile, eines davon ist als Standard markiert (nicht „Claude API“).
- [ ] **1.2 Regel „Starkes Modell“ anlegen.** Einstellungen → **Routing** → **+ Regel hinzufügen**. Name **Starkes Modell**, Bedingung **Präfix** mit dem Wort **Claude**, Ziel: Profil **Claude API**, Modell wie gewählt. Der Schalter „Auslöser aus dem Satz entfernen“ (Text dazu: „Präfix, Schlüsselwort oder Treffer gehen nicht ans Modell; im Verlauf bleibt der Satz vollständig.“) ist an. Speichern. *Erwartet:* Die Regel steht in der Liste, aktiv („Regel aktiv“), vor „Default“. Daneben gibt es die Regel **Privat** (vom System angelegt).
- [ ] **1.3 Testfeld.** Auf der Routing-Seite im Feld **Testsatz** (Hinweistext „Welche Regel greift für diesen Satz?“) eintippen: `Claude, wie spät ist es?`. *Erwartet:* „Starkes Modell“ greift, Ziel Claude API. Danach `Wie spät ist es?`: *Erwartet:* Default, Ziel Standardprofil. Danach `Frag mal Claude, wie spät es ist`: *Erwartet:* Default (Claude steht nicht am Anfang). Danach `Das ist privat: mein Arzttermin`: *Erwartet:* Regel „Privat“.
- [ ] **1.4 Im Hauptbildschirm.** Zurück zum Hauptbildschirm, ins Textfeld tippen: `Claude, wie spät ist es?` und senden. *Erwartet:* Eine Antwort kommt; am Provider-Chip (Name des Profils über oder neben der Antwort) steht **Claude API** und die Regel **Starkes Modell**. Im Verlauf steht der Satz vollständig mit „Claude,“.
- [ ] **1.5 Ohne Präfix.** Tippe `Wie spät ist es?`. *Erwartet:* Antwort vom Standardprofil, der Chip zeigt dessen Namen, keine Regel.
- [ ] **1.6 Prüfprotokoll.** Einstellungen → **Datenschutz und Logs** → Prüfprotokoll. *Erwartet:* Zwei Zeilen der Art „Routing“: `claude · claude-haiku-5-5` mit Grund „Starkes Modell“ und eine für das Standardprofil mit Grund „Standard“. Kein API-Key in einer Zeile.
- [ ] **1.7 Sprache.** Mit Mikrofon sagen: „Claude, wie spät ist es?“ *Erwartet:* Dasselbe wie 1.4 (Regel greift auch bei erkanntem Text; Satzzeichen und Groß-/Kleinschreibung der Erkennung stören nicht).
- [ ] **1.8 Wirkung der Bedingungen prüfen (Offline).** Flugmodus an. Testsatz `Wie wird das Wetter?` im Routing-Testfeld. *Erwartet:* Keine Absturzmeldung; ist eine Offline-Regel eingerichtet (optional), greift sie, sonst Default. Flugmodus wieder aus.

## 2. MCP-Server über Tailscale

Voraussetzung: 0.3 und 0.4.

- [ ] **2.1 Erreichbarkeit vom Telefon.** Im Browser des Telefons `MCP_URL` öffnen (bei Weg B ohne Token kommt eine Fehlerseite „401“ oder „Unauthorized“; das ist richtig, es zeigt, dass der Server erreichbar ist). *Erwartet:* Eine Antwort, kein Zeitüberschreitungsfehler. Sonst Tailscale prüfen (0.3).
- [ ] **2.2 Server hinzufügen.** Einstellungen → **MCP-Server** → **+ MCP-Server** (bzw. „Server hinzufügen“). Wähle „Eigener Server“, Adresse `MCP_URL`, Anmeldung **Bearer-Token**, Token eintragen. Das Formular zeigt den Hinweis „Unverschlüsselt (http): nur im Heimnetz oder über …“ und den Status **Tailscale erlaubt**. Tippe **Verbindung prüfen**. *Erwartet:* „Prüfe …“, dann ein grünes „Erreichbar“. Kein Token im Klartext sichtbar.
- [ ] **2.3 Speichern und Tools sehen.** **Speichern**. Öffne den Server in der Liste. *Erwartet:* Status „Server aktiv“, eine Liste mit Tools (bei Weg B: `get_state`, `echo`, `get_time`, `toggle_light`, `delete_thing`, `delete_scene`).
- [ ] **2.4 Tool-Risikostufen.** Tippe auf ein Tool. *Erwartet:* Lesende Tools (`get_state`, `get_time`, `echo`) sind „read“; `toggle_light` „write“; `delete_thing` und `delete_scene` „external“ („fragt immer nach“, der Schalter „Ohne Nachfrage ausführen“ ist bei „external“ gesperrt, Text: „Außenwirkung: fragt immer nach, das lässt sich nicht …“).
- [ ] **2.5 Lesendes Tool per Sprache oder Text.** Hauptbildschirm: `Frag den Server nach dem Zustand von licht.wohnzimmer` (bei Weg B: `Rufe get_time auf dem Server auf`). *Erwartet:* Eine Tool-Karte mit dem Namen `mcp_<servername>__…`, kein Nachfragen, danach eine Antwort mit dem Ergebnis.
- [ ] **2.6 Zerstörendes Tool fragt nach.** Sage/tippe: `Lösche die Szene Abend auf dem Server` (bei Weg B: `Rufe delete_thing auf`). *Erwartet:* Eine Bestätigungskarte, die den Servernamen nennt und das Tool („…: delete_…“). Tippe **Nein**. *Erwartet:* Das Tool läuft nicht (bei Weg B zeigt `tools/call`-Zähler des Servers am Ende keinen Aufruf für `delete_thing`; bei Home Assistant bleibt die Szene erhalten). Wiederhole mit **Ja**: *Erwartet:* Das Tool läuft, es gibt **kein Rückgängig** (Text „Kein Rückgängig“ bzw. keine Undo-Schaltfläche).
- [ ] **2.7 Ohne Tailscale.** Tailscale auf dem Telefon ausschalten. Wiederhole 2.5. *Erwartet:* Eine verständliche Fehlermeldung („nicht erreichbar“), kein Absturz, kein Hängen länger als etwa 30 Sekunden. Tailscale wieder an, 2.5 klappt erneut (eventuell „Neu laden“ in der Serverliste).
- [ ] **2.8 Löschen.** MCP-Server öffnen → **Server löschen**. *Erwartet:* Rückfrage („Konfiguration, Tool-Liste und alle Zugangsdaten dieses Servers …“), nach Bestätigung ist er weg. (Für die weiteren Punkte kann er für Punkt 7 und 10 noch einmal angelegt werden.)

## 3. HTTP-Tools

Voraussetzung: Ein Dienst im Tailnet, der per HTTP-GET Daten liefert. Bei Weg A (Home Assistant): `http://HOMESERVER:8123/api/states/<entity_id>` mit demselben Bearer-Token. Bei Weg B: `http://HOMESERVER:<REST-Port>/api/states/light.wohnzimmer`.

- [ ] **3.1 Tool anlegen.** Einstellungen → **HTTP-Tools** → **+ HTTP-Tool**. Name `ha_state`, Beschreibung „Zustand einer Entität lesen“, Methode **GET**, URL-Vorlage `http://HOMESERVER:<Port>/api/states/{entity_id}`, Argument `entity_id` (Pflicht, Text). Anmeldung **Bearer-Token**, Token eintragen. Schalter **Heimnetz-Ziel** an (Text: „Darf auf private Adressen zeigen, dann auch http“). Speichern.
- [ ] **3.2 Testen.** Im Editor Abschnitt „Testen“: `entity_id` = `light.wohnzimmer` (bei Home Assistant eine echte Entität), **Testen**. *Erwartet:* „Läuft …“, danach Abschnitt „Gesendet“ (URL, Methode, Header; der Token ist **verborgen**) und „Antwort“ mit JSON, das `light.wohnzimmer` enthält.
- [ ] **3.3 Per Agent.** Hauptbildschirm: `Ist das Licht im Wohnzimmer an?` *Erwartet:* Tool-Karte `http__ha_state`, danach eine Antwort. Die Karte zeigt kein Token.
- [ ] **3.4 Kein Fremdziel.** Ändere die URL-Vorlage auf eine öffentliche Adresse mit `http://` (nicht https). *Erwartet:* Beim Speichern oder Testen eine Warnung bzw. Ablehnung („nur https“), kein Aufruf. Änderung wieder rückgängig machen.
- [ ] **3.5 Schreibendes Tool fragt nach.** Lege ein zweites Tool mit Methode **POST** an (z. B. Home Assistant `light/turn_on`, Body-Vorlage `{"entity_id": "{entity_id}"}`). *Erwartet:* Stufe „write“; beim Aufruf per Agent erscheint eine Bestätigung (es sei denn, „Ohne Nachfrage ausführen“ ist eingeschaltet, das ist beim Anlegen aus).

## 4. Bring!

- [ ] **4.1 Anmelden.** Einstellungen → **Integrationen** → **Bring!** (oder Zeile „Bring!“). Hinweis lesen („Inoffizielle Schnittstelle …“). **E-Mail** und **Passwort** eintragen, **Anmelden**. *Erwartet:* „Angemeldet“, Integration an. Bei falschem Passwort: eine verständliche Meldung („Login fehlt“ bzw. Fehlertext), kein Absturz.
- [ ] **4.2 Listen lesen.** Hauptbildschirm: `Welche Bring-Listen habe ich?` *Erwartet:* Tool-Karte `bring__list_lists`, Antwort nennt deine Listen.
- [ ] **4.3 Artikel lesen.** `Was steht auf der Bring-Liste Test?` *Erwartet:* `bring__get_items`; „Milch“ und „Brot“ werden genannt.
- [ ] **4.4 Artikel hinzufügen.** `Setz 2 Liter Hafermilch auf die Bring-Liste Test.` *Erwartet:* `bring__add_items`, die Karte hat **Rückgängig**. In der Bring!-App erscheint „Hafermilch“ mit „2 Liter“ (kann einige Sekunden dauern).
- [ ] **4.5 Rückgängig.** Tippe **Rückgängig**. *Erwartet:* Hafermilch ist wieder weg (Bring!-App prüfen).
- [ ] **4.6 Erledigt markieren.** `Ich habe die Milch gekauft, hak sie bei Bring ab.` *Erwartet:* `bring__complete_item`, Milch steht in Bring! unter „Zuletzt gekauft“. Rückgängig legt sie zurück.
- [ ] **4.7 Französisch.** `Ajoute des œufs et du beurre à ma liste Bring.` *Erwartet:* Zwei Artikel (Eier, Butter) landen auf der Liste. Rückgängig entfernt beide.
- [ ] **4.8 Fehlerfall.** Flugmodus an, `Was steht auf der Bring-Liste?`. *Erwartet:* Meldung „Bitte später erneut versuchen“ mit Hinweis auf die Bring!-App als Ausweg, Integration bleibt **nicht** im Zustand „Fehler“. Flugmodus aus.
- [ ] **4.9 Abmelden.** Bring! → **Abmelden**, Rückfrage „Bei Bring! abmelden?“ bestätigen. *Erwartet:* „E-Mail, Passwort und Sitzung werden vom Gerät gelöscht“; Status „Login fehlt“.

## 5. App-Erkennung

Prüft, ob Wendelin erkennt, welche Fremd-Apps installiert sind (nur die in der App deklarierten: Obsidian, Bring!).

- [ ] **5.1 Obsidian installiert.** Ist die Obsidian-App (`md.obsidian`) installiert: Einstellungen → **Integrationen** → **Obsidian**. *Erwartet:* Status „Installiert“. Falls nicht installiert: „Nicht installiert“ (und die Integration zeigt den entsprechenden Hinweis).
- [ ] **5.2 Bring!-App.** Einstellungen → **Bring!**: Zeile „Bring!-App“ zeigt „Installiert“ oder „Nicht installiert“, passend zum Telefon (App-Liste des Telefons gegenprüfen).
- [ ] **5.3 Wechsel.** Installiere oder deinstalliere die Bring!-App, öffne Wendelin wieder (Rückkehr in die App). *Erwartet:* Der Status ändert sich ohne Neustart der App.
- [ ] **5.4 Sichtbarkeit.** Eine nicht deklarierte App (z. B. eine beliebige andere) taucht nirgends auf; Wendelin listet nicht die installierten Apps.

## 6. Sprach-UX (WP31)

Alle Schritte mit echter Stimme. Vorher: Einstellungen → **Sprache**: Sprachmodell installiert, Sprachausgabe an.

- [ ] **6.1 Zuhör-Anzeige.** Hauptbildschirm: Mikrofon tippen. *Erwartet:* Nach kurzem „Moment …“ (nur beim ersten Mal nach einer Pause) erscheint der Ring um den Knopf, über dem Eingabefeld eine Wellenform-Leiste mit „Ich höre zu …“; sie reagiert auf deine Stimme.
- [ ] **6.2 Sprech-Anzeige.** Sage: „Wie spät ist es?“ *Erwartet:* Nach der Erkennung „denkt“ der Knopf, beim Vorlesen bewegen sich drei Punkte (eigener Zustand, Label „Sprachausgabe stoppen“). Tippe auf den Knopf während des Vorlesens: *Erwartet:* Die Sprachausgabe stoppt sofort.
- [ ] **6.3 Stopp.** Öffne das Overlay (Power-Taste lang oder Geste). Frage etwas Langes („Erzähl mir etwas über Hamburg“). Sobald es antwortet, tippe das Mikrofon und sage „Stopp“. *Erwartet:* „Abgebrochen“ erscheint kurz, die alte Antwort ist verschwunden, das Overlay schließt sich. Einstellungen → Sprache → **Stopp schließt das Overlay** ausschalten und wiederholen: *Erwartet:* Das Overlay bleibt offen. (Danach wieder einschalten.)
- [ ] **6.4 Warten auf Ja/Nein.** Sage im Hauptbildschirm: „Trag morgen um 10 Uhr Tauchen in den Kalender ein, dann lösche den Termin wieder.“ Bei der Bestätigungsfrage („… soll ich?“) *Erwartet:* Der Zuhör-Ring ist wieder da, man kann „Ja“ oder „Nein“ sagen.
- [ ] **6.5 Rückgängig stoppt die Sprachausgabe.** Sage: „Trag mir morgen um 10 Uhr Tauchen ein.“ (Rückgängig-Karte erscheint). Sobald die Antwort vorgelesen wird, tippe **Rückgängig**. *Erwartet:* Die Sprachausgabe verstummt sofort, es kommt „Zurückgenommen.“ (hörbar, weil per Stimme gefragt, und sichtbar), die Karte zeigt den Zustand „rückgängig“. Prüfe im Kalender, dass der Termin weg ist.
- [ ] **6.6 Unscharfer Notizname.** Sage: „Ergänze in der Notiz Wendeline Test, dass ich Milch gekauft habe“ (leicht falscher Name; die Notiz `Wendelin-Test` muss im Vault existieren, sonst anlegen). *Erwartet:* Die Bestätigungskarte nennt den gefundenen Pfad („Gefunden: Wendelin-Test“) **vor** dem Ja/Nein, die gesprochene Frage nennt ihn ebenfalls.
- [ ] **6.7 „Neues Gespräch“.** Nach einigen Nachrichten im Hauptbildschirm: Tippe im Kopf auf das Symbol **Neues Gespräch** (erscheint nur bei nicht leerem Verlauf; Tooltip). *Erwartet:* Der Verlauf ist leer, eine neue Sitzung beginnt. Wiederhole mit der Stimme: Nachricht senden, dann sagen „Vergiss das“. *Erwartet:* Dasselbe. Gegenprobe: „Vergiss, dass ich morgen Urlaub habe“ ist **keine** Neustart-Aktion, sondern eine normale Anfrage.
- [ ] **6.8 Senden-Knopf.** Im Textfeld etwas tippen. *Erwartet:* Ein Senden-Knopf erscheint, Tippen darauf sendet. Bei leerem Feld ist es das Mikrofon.
- [ ] **6.9 „Probe hören“.** Einstellungen → **Sprache**. Gesprochene Sprache auf **Français** stellen, **Probe hören**. *Erwartet:* Die Probe klingt französisch („Bonjour …“), nicht deutsch. Dann auf **Automatisch** bzw. „Wie die App“: Die Probe klingt in der App-Sprache. (Danach die gewünschte Sprache einstellen.)

## 7. Vorlesefreundliche Antworten (WP41)

- [ ] **7.1 Standard (Hinweis ans Modell).** Einstellungen → Sprache: **Antwort in zwei Fassungen** ist **aus**. Sage: „Was steht heute in meinem Kalender?“ (lege vorher 2 Termine an, z. B. 10 Uhr Zahnarzt und 14 Uhr Besprechung). *Erwartet:* Die vorgelesene Antwort besteht aus ganzen Sätzen („um zehn Uhr Zahnarzt und um vierzehn Uhr Besprechung“), nicht aus „Termine Doppelpunkt …“ oder Aufzählungszeichen. Notiere, was gesprochen wurde: ____________________.
- [ ] **7.2 Zahlen und Zeiten.** Sage: „Wann ist mein nächster Termin?“ *Erwartet:* Uhrzeit und Datum klingen sprechbar („um zehn Uhr“, „am Dienstag“), nicht „10:00“ Ziffer für Ziffer.
- [ ] **7.3 Getippt bleibt unverändert.** Tippe dieselbe Frage. *Erwartet:* Die geschriebene Antwort darf Listen und Zeiten wie „10:00“ enthalten (der Hinweis gilt nur für Spracheingaben).
- [ ] **7.4 „Antwort in zwei Fassungen“ einschalten.** Einstellungen → Sprache → **Antwort in zwei Fassungen** an (Erklärung: „Mehr Tokens, natürlichere Sprache.“). Wiederhole 7.1 per Stimme. *Erwartet:* Gesprochen wird ein kurzer, natürlicher Text, auf dem Bildschirm steht die ausführlichere geschriebene Antwort. Auf dem Bildschirm erscheint **nie** ein Block „<spoken>“ oder dessen Inhalt doppelt. Notiere Unterschiede zu 7.1: ____________________.
- [ ] **7.5 Fallback.** Wenn es dein Standardmodell klein/schwach ist: Wiederhole 7.4 mit diesem Profil. *Erwartet:* Auch wenn das Modell den Block vergisst, wird die geschriebene Antwort vorgelesen (kein Schweigen, kein Fehler).
- [ ] **7.6 Kosten.** Einstellungen → **Kosten**: Vergleiche die Kosten der Anfragen aus 7.1 und 7.4 (Tokens der Antwort). *Erwartet:* 7.4 braucht etwas mehr Ausgabe-Tokens. Notiere Werte: ____ gegen ____.
- [ ] **7.7 Wieder ausschalten** (Standard ist aus), sofern du es nicht behalten willst.

## 8. Speicher und Latenz (K14 c)

Ziel: höchstens ca. 1,1 GB bei aktiver Sprachnutzung, unter 200 MB im Hintergrund. Messen mit dem Rechner (adb).

- [ ] **8.1 Frischer Start.** Wendelin per Taskmanager wegwischen. Telefon 1 Minute liegen lassen.
- [ ] **8.2 Ruhewert.** Wendelin öffnen (Hauptbildschirm), nichts sagen, 30 Sekunden warten. Auf dem Rechner: `adb -s SERIAL shell dumpsys meminfo app.wendelin | grep -E "TOTAL PSS|TOTAL RSS|Native Heap"`. Notiere **TOTAL PSS**: ______ MB.
- [ ] **8.3 Nach Sprachnutzung.** Eine Spracheingabe im Hauptbildschirm, danach eine im Overlay (Power-Taste). Direkt danach dieselbe Messung. *Erwartet:* **TOTAL PSS ≤ etwa 1100 MB**. Notiere: ______ MB. Nur **ein** Modellladen: `adb -s SERIAL logcat -d | grep "Wendelin/voice" | grep "model-load whisper"` zeigt höchstens eine Zeile je Prozessstart.
- [ ] **8.4 Im Hintergrund.** Wendelin verlassen (Home), 3 Minuten warten (das Modell wird nach 2 Minuten im Hintergrund freigegeben). Messung wiederholen. *Erwartet:* **TOTAL PSS < etwa 200 MB**. Notiere: ______ MB.
- [ ] **8.5 Latenz Erkennung.** Sage einen Satz von etwa 4 Sekunden. Stoppuhr: vom Ende des Sprechens bis zum sichtbaren Text. *Erwartet:* höchstens etwa 2 Sekunden mit Whisper small (Richtwert aus der M2-Messung: Ø 0,5 s Rechenzeit je Satz auf dem Mac-Emulator, Telefon langsamer). Notiere: ______ s. Genauer: `tool/whisper_timing.sh` (siehe `docs/testing/m2-device.md` Abschnitt 8).
- [ ] **8.6 Latenz bis Antwort.** Ende des Sprechens bis zum Beginn der Sprachausgabe („Wie spät ist es?“ mit Standardprofil). Notiere: ______ s. Richtwert: unter 5 s.
- [ ] **8.7 Erster Tipp nach Pause.** Telefon 10 Minuten liegen lassen, dann Mikrofon tippen. *Erwartet:* Kurz „Moment …“, dann der Ring; der erste Satz geht nicht verloren (nach dem Ring sprechen). Notiere die Wartezeit bis zum Ring: ______ s.

## 9. Power-Taste nach Pause und „Zuverlässig öffnen“ (WP56)

Die ausführliche Anleitung dazu steht in `docs/testing/wp56-device.md`. Hier die Schritte in Reihenfolge; wenn dein Telefon kein Xiaomi/HyperOS ist, steht trotzdem, was erwartet wird.

- [ ] **9.1 Standard-Assistent gesetzt.** Einstellungen → **Assistent**: „Als Standard-Assistent setzen“ erledigt (Anzeige zeigt nicht „Nicht als Standard-Assistent gesetzt“).
- [ ] **9.2 Hinweise ansehen („Zuverlässig öffnen“).** Einstellungen → **Assistent** → Abschnitt „Zuverlässig öffnen“. Notiere, welche Hinweise stehen (z. B. „Akku-Optimierung aktiv“, „App-Standby: selten genutzt“, Herstellerhinweise zu Autostart): ____________________. *Erwartet:* Ein Text „Das ist eine Checkliste, kein Status.“ und die Knöpfe „Keine Einschränkung erlauben“, „Einstellungen des Herstellers öffnen“ bzw. „Akku-Einstellungen öffnen“.
- [ ] **9.3 Vorher-Messung.** Wendelin per Taskmanager wegwischen. Telefon 2 Stunden oder über Nacht liegen lassen (Display aus). Dann Power-Taste lang drücken. *Erwartet (Ziel):* Wendelin öffnet sich. Notiere, ob ja/nein und wie lange es dauert: ____________________. Bei Fehlversuch: `tool/diag_assistant_idle.sh SERIAL` **vor** dem Drücken starten (Pflichtargument ist die Seriennummer; das Skript leert per `logcat -c` den Gerätelog) und die Ausgabe an den Maintainer geben.
- [ ] **9.4 Ausnahmen erteilen.** Tippe „Keine Einschränkung erlauben“ und bestätige den Systemdialog. Tippe „Einstellungen des Herstellers öffnen“ bzw. „Akku-Einstellungen öffnen“: Autostart für Wendelin einschalten, Akkusparer auf „Keine Einschränkungen“. Zurück in die App. *Erwartet:* Die Hinweise aktualisieren sich (erledigte Punkte verschwinden bzw. wechseln).
- [ ] **9.5 Nachher-Messung.** Wie 9.3 (wegwischen, 2 Stunden bzw. über Nacht, Power-Taste lang). *Erwartet:* Wendelin öffnet sich zuverlässig. Notiere: ____________________.
- [ ] **9.6 Kaltstart-Platzhalter.** Wenn der Prozess nicht lief (Start nach 9.3/9.5), erscheint kurz **„Wendelin startet …“**, danach das Assistenten-Sheet (kein leerer Bildschirm, kein Flackern). Notiere: ja/nein, Dauer ungefähr ____ s.
- [ ] **9.7 Rückkehr aus den Systemseiten.** Nach 9.4: Hinweise aktualisieren sich beim Zurückkehren (siehe `docs/testing/wp56-device.md` Schritt 5).

## 10. Gesamtabnahme M3 (DoD)

- [ ] **10.1** „Claude, …“ geht an das Claude-Profil (Punkt 1.4 und 1.6).
- [ ] **10.2** Ein MCP-Server über Tailscale liefert Tools, ein lesendes läuft, ein zerstörendes fragt nach (2.3, 2.5, 2.6).
- [ ] **10.3** Ein HTTP-Tool und Bring! laufen gegen echte Dienste (3.3, 4.3, 4.4).
- [ ] **10.4** Sprach-UX und vorlesefreundliche Antworten verhalten sich wie beschrieben (6, 7).
- [ ] **10.5** Speicher und Latenz im Rahmen (8.3, 8.4).
- [ ] **10.6** Power-Taste nach Pause öffnet Wendelin (9.5).

## Aufräumen

- MCP-Test-Server beenden (Strg+C), `tailscale serve reset`, falls Weg B benutzt wurde.
- In Wendelin: MCP-Server, HTTP-Tools und Bring!-Login löschen, wenn das Testkonto nicht bleiben soll; Testtermine im Kalender und Testnotiz im Vault löschen.
- Den Test-Key bei Anthropic widerrufen, falls er nur für diesen Test angelegt wurde.

## Ergebnis zurückmelden

Pro Punkt: Haken oder ein Satz, was stattdessen passierte. Zusätzlich: Gerät und Android-Version, Messwerte aus 7.1 bis 8.7 (Texte, Zeiten, MB), Ausgabe von `tool/diag_assistant_idle.sh` bei Fehlversuchen in 9.3 oder 9.5, und Screenshots von auffälligen Bildschirmen (ohne Keys). Der Maintainer trägt Abweichungen als Befunde ein.
