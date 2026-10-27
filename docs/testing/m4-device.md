# M3 und M4 zusammen auf dem eigenen Telefon testen (Geräte-Prüfliste)

Diese Liste ersetzt `docs/testing/m3-device.md` und `docs/testing/wp56-device.md`. Sie prüft Meilenstein M3 (Routing, MCP, HTTP-Tools, Bring!, App-Erkennung, Sprach-UX, Power-Taste nach Pause) und M4 (Wake Word, Gesprächsmodus, Barge-in, Phala mit Prüfstatus, Taschenlampe) in einem Durchgang auf dem Xiaomi mit HyperOS. Auf dem Emulator ist vieles automatisch belegt (`docs/notes/m3-e2e-2026-10-14.md`, Emulatorlauf WP54). Hier steht nur, was das Telefon zeigt: echte Stimme im Raum, Hersteller-Akkusparer, Mikrofon- und Lautsprecherverhalten, Akku über Stunden, echte Dienste (Tailscale, Bring!, Home Assistant, Claude, Phala) und die echte Taschenlampen-LED.

**So wird sie benutzt:** Die Punkte sind nach Blöcken nummeriert (1.1, 1.2 …). Jeder Punkt sagt, was zu tun ist und was erscheinen muss (*Erwartet*). Wer die Liste abarbeitet, hakt die Kästchen ab und schreibt bei Abweichungen auf, was stattdessen passiert ist. Wo ein Befehl auf dem Rechner nötig ist, steht er im Wortlaut da. **Alle `adb`-Befehle und Skripte am Telefon führt nur der Maintainer selbst aus; ein Test-Agent leitet nur an und führt sie nicht aus.** Keys, Tokens und Passwörter trägst du nur in der App ein, nie in Chats, Notizen oder Screenshots.

Zeitbedarf: etwa 3 bis 4 Stunden aktiv, dazu Wartezeiten: 30 Minuten Kalibrieren (Block 9), Punkt 13 (Power-Taste nach 2 Stunden bzw. über Nacht), Punkt 10 (Standby, Neustart) und 8 Stunden Alltag für Akku und Fehlalarme (Tabelle 15.3). Sinnvoll ist, am Vormittag mit Block 0 zu beginnen, den Alltagstest (10.7, 15.3) mitlaufen zu lassen und die Blöcke 1 bis 8 zwischendurch abzuarbeiten.

Namen in „Anführungszeichen“ sind Beschriftungen in der App. Der Einstellungsbildschirm heißt **Einstellungen** und hat Zeilen **Provider**, **Routing**, **Integrationen**, **MCP-Server**, **HTTP-Tools**, **Obsidian**, **Listen**, **Web-Suche**, **Gedächtnis**, **Datenschutz und Logs**, **Kosten**, **Assistent**, **Sprache**.

**Logfilter** (nur der Maintainer, Telefon per USB, `SERIAL` aus `adb devices`):
- Sprache, Modelle, Gespräch, Wake Word: `adb -s SERIAL logcat -d | grep "Wendelin/voice"` (die Dart-Seite loggt über den Präfix `Wendelin/voice:`, die Kotlin-Seite unter dem Tag `Wendelin/voice`; `adb -s SERIAL logcat -s Wendelin/voice` zeigt nur die Kotlin-Zeilen). Wichtige Zeilen: `model-load`, `model-free`, `barge-in kind=…`, `conv-exit reason=…`; mit dem Wake-Word-Dienst `wake-start`, `wake-alive`, `wake-hit`, `wake-cand`, `wake-verify result=ok|no|skip`, `wake-pause`, `wake-resume`, `wake-stop reason=…`, `wake-conflict`, `wake-failed`, `wake-handoff`. Filter nur dafür: `adb -s SERIAL logcat -d | grep "Wendelin/voice" | grep "wake-"`.
- Prüfung der TEE-Anbieter: `adb -s SERIAL logcat -d | grep "Wendelin/attest"` (Zeilen der Art `Wendelin/attest: <Art> <Stufe>=<Ergebnis>` und `Anfrage nicht gesendet (<Stufe>)`; nie Inhalte).
- Beides zusammen live: `adb -s SERIAL logcat | grep -E "Wendelin/(voice|attest)"`. Vor einer Messreihe `adb -s SERIAL logcat -c` (leert den Gerätelog).
- Es steht nie Audio, Text einer Äußerung oder Antwortinhalt im Log. Findest du so etwas, ist das ein Befund.

## 0. Einrichtung (einmal am Anfang)

- [ ] **0.1 Telefon und APK.** Android 10 oder neuer (Xiaomi 15T Pro, HyperOS / Android 16). Die Wendelin-App aus `docs/testing/m2-device.md` Abschnitt 1 installiert (Release-APK `arm64-v8a`, möglichst frisch aus dem Stand mit allen M4-Paketen). Die M2-Einrichtung (Onboarding, Mikrofon, Vault, Sprachmodell) ist erledigt; falls nicht, zuerst `docs/testing/m2-device.md` Abschnitte 1 bis 5. Das Onboarding enthält den Schritt „Gespräch“ (Weiter zuhören). Notiere Gerät, Android-Version und App-Version: ______________.
- [ ] **0.2 Provider-Keys.** Ein Anthropic-Key (für das Profil „Claude API“), ein zweiter Provider als Standard (z. B. Mistral oder ein zweites Anthropic-Profil mit Haiku) und ein Phala-Key (RedPill) für Block 12. Alles nur in der App eintragen. Budget klein halten: Der ganze Test braucht unter 2 Euro.
- [ ] **0.3 Tailscale.** Auf dem Telefon und dem Homeserver ist Tailscale installiert und angemeldet. Telefon: Tailscale-App öffnen, Status „Verbunden“. Rechner: `tailscale status` zeigt den Homeserver mit `100.x.y.z` und einem Namen `*.ts.net`. Notiere `HOMESERVER = ______________`.
- [ ] **0.4 Testserver für MCP und HTTP.** Auf dem Homeserver (oder einem Rechner im Tailnet) läuft ein MCP-Server. Zwei Wege:
  - **Weg A, Home Assistant:** Die Integration „Model Context Protocol Server“ ist eingerichtet, Endpunkt `http://HOMESERVER:8123/mcp_server/sse` (ältere Versionen) bzw. die in der Integration angezeigte Adresse; dazu ein langlebiges Zugriffstoken (Profil → Sicherheit → Langlebige Zugriffstokens). Notiere `MCP_URL` und `MCP_TOKEN` (Token nur im Passwortmanager).
  - **Weg B, Test-Server aus dem Repo (ohne Home Assistant):** Auf dem Rechner im Repo `cd app && WENDELIN_MCP_TOKEN=testtoken dart run tool/mcp_test_server.dart`. Das Programm gibt `port=<MCP-Port>` und `http_port=<REST-Port>` aus. Er lauscht nur auf `127.0.0.1`; für das Telefon muss er über das Tailnet erreichbar sein, z. B. mit `tailscale serve --bg --http=<MCP-Port> http://127.0.0.1:<MCP-Port>` (und ebenso für den REST-Port). `HOMESERVER` ist hier die Tailnet-Adresse des Rechners, auf dem der Test-Server läuft (nicht die des Homeservers aus 0.3, falls das ein anderer ist). `MCP_URL = http://HOMESERVER:<MCP-Port>/mcp`, `MCP_TOKEN = testtoken`. Der Server hat die Tools `get_state` (lesen), `echo`, `get_time` (lesen), `toggle_light` (schreiben), `delete_thing` und `delete_scene` (löschen). Beenden mit Strg+C, danach `tailscale serve reset`.
  - Notiere `MCP_URL = ______________` und ob Weg A oder B.
- [ ] **0.5 Bring!-Konto.** E-Mail und Passwort eines Bring!-Kontos mit Einkaufslisten (am besten ein Testkonto mit einer Liste „Test“, darauf „Milch“ und „Brot“). Die App nutzt eine inoffizielle Schnittstelle (Hinweis in der App).
- [ ] **0.6 Rechner mit adb.** `adb devices` zeigt das Telefon als `device` (USB-Debugging an). Notiere `SERIAL = ______________`. Ohne adb lassen sich Speicherwerte, Logzeilen und `tool/diag_assistant_idle.sh` nicht erheben; dann bleiben die entsprechenden Punkte offen.
- [ ] **0.7 Mikrofon und Benachrichtigungen.** Mikrofon für Wendelin erlaubt („Bei Nutzung der App“ reicht für den Anfang). Benachrichtigungen erlaubt (Android 13 und neuer), sie werden für den Wake-Word-Dienst und für die GPU-Warnung (12.9) gebraucht.
- [ ] **0.8 Standard-Assistent.** Einstellungen → **Assistent** → „Als Standard-Assistent setzen“, in den Android-Einstellungen Wendelin als Digitalen Assistenten wählen. *Erwartet:* Die Anzeige zeigt „Wendelin ist Standard-Assistent“ (nicht „Nicht als Standard-Assistent gesetzt“). Die Rolle ist Voraussetzung für das Wake Word (Entscheidung Maintainer, M4).
- [ ] **0.9 Akku-Ausnahmen (HyperOS).** Einstellungen → **Assistent** → Abschnitt „Zuverlässig öffnen“. Notiere die angezeigten Hinweise (z. B. „Akku-Optimierung aktiv“, „App-Standby: selten genutzt“, Herstellerhinweis): ______________. *Erwartet:* Ein Text „Das ist eine Checkliste, kein Status.“ und die Knöpfe „Keine Einschränkung erlauben“ und „Einstellungen des Herstellers öffnen“ bzw. „Akku-Einstellungen öffnen“. **Für die Messung „vorher/nachher“ in Block 13 ändere hier noch nichts**; ist 13.3 (Vorher-Messung) erledigt, folgt 0.9a.
- [ ] **0.9a Ausnahmen erteilen (nach 13.3).** „Keine Einschränkung erlauben“ tippen und den Systemdialog bestätigen. „Einstellungen des Herstellers öffnen“ bzw. „Akku-Einstellungen öffnen“: **Autostart** für Wendelin an, Akkusparer auf **„Keine Einschränkungen“**; zusätzlich Wendelin in „Letzte Apps“ sperren (Karte lang drücken, Schloss). Zurück in die App. *Erwartet:* Die Hinweise aktualisieren sich beim Zurückkehren (erledigte Punkte verschwinden bzw. wechseln).
- [ ] **0.10 Sprachmodelle.** Einstellungen → **Sprache**: Spracherkennungsmodell (Whisper) installiert, Sprachausgabe an, Stimme gewählt. Sprache stimmt (Deutsch).
- [ ] **0.11 Wake Word einlernen (kurz).** Einstellungen → **Sprache** → Abschnitt „Aktivierungswort“ → „Wendelin lernt deine Stimme“. Zuerst die Merkmalsmodelle laden („Merkmalsmodelle“, WLAN), dann „Stimme einlernen“. Das ausführliche Einlernen, Kalibrieren und Ausprobieren prüft Block 9; hier nur sicherstellen, dass mindestens eine Stimme eingelernt ist (Voraussetzung für 10.x).
- [ ] **0.12 Messwerte-Kopf.** Telefon mit Netz (WLAN), Akku ≥ 80 %, kein Energiesparmodus, Display-Auto-Aus nach 30 s oder kürzer.

## 1. Routing: Profile, Regeln, kein automatischer Wechsel

Ziel: „Claude, …“ geht an das Claude-Profil, alles andere an das Standardprofil, die Testsatz-Funktion zeigt die greifende Regel. Fällt ein gewähltes Ziel aus, ersetzt Wendelin es **nie** selbst (WP59).

- [ ] **1.1 Profile anlegen.** Einstellungen → **Provider**. Es gibt ein Standardprofil (aus dem Onboarding). Tippe **+ Provider**, wähle die Vorlage **Anthropic**, Name **Claude API**, Key eintragen, Modell **claude-haiku-5-5** (das kleinste reicht). Speichern. *Erwartet:* Mindestens zwei Profile in der Liste, eines als Standard markiert (nicht „Claude API“). Es gibt keinen Bereich für Eskalationsketten.
- [ ] **1.2 Regel „Starkes Modell“ anlegen.** Einstellungen → **Routing** → **+ Regel hinzufügen**. Name **Starkes Modell**, Bedingung **Präfix** mit dem Wort **Claude**, Ziel: Profil **Claude API**. Der Schalter **Auslöser entfernen** (Text: „Präfix, Schlüsselwort oder Treffer gehen nicht ans Modell; im Verlauf bleibt der Satz vollständig.“) ist an, **Aktiv** ist an. Speichern. *Erwartet:* Die Regel steht in der Liste, vor „Default“. Daneben gibt es die vom System angelegte Regel **Privat**.
- [ ] **1.3 Testfeld.** Auf der Routing-Seite im Feld **Testsatz** („Welche Regel greift für diesen Satz?“) eintippen: `Claude, wie spät ist es?`. *Erwartet:* „Starkes Modell“ greift, Ziel Claude API. Danach `Wie spät ist es?`: Default, Standardprofil. Danach `Frag mal Claude, wie spät es ist`: Default (Claude steht nicht am Anfang). Danach `Das ist privat: mein Arzttermin`: Regel „Privat“.
- [ ] **1.4 Hauptbildschirm.** Textfeld: `Claude, wie spät ist es?` senden. *Erwartet:* Antwort; am Provider-Chip steht **Claude API** und die Regel **Starkes Modell**. Im Verlauf steht der Satz vollständig mit „Claude,“.
- [ ] **1.5 Ohne Präfix.** `Wie spät ist es?` tippen. *Erwartet:* Antwort vom Standardprofil, Chip mit dessen Namen, keine Regel.
- [ ] **1.6 Prüfprotokoll Routing.** Einstellungen → **Datenschutz und Logs** → Protokoll. *Erwartet:* Zwei Zeilen der Art „Routing“: `claude · claude-haiku-5-5` mit Grund „Starkes Modell“ und eine für das Standardprofil mit Grund „Standard“. Kein API-Key in einer Zeile.
- [ ] **1.7 Sprache.** Mit Mikrofon sagen: „Claude, wie spät ist es?“ *Erwartet:* Dasselbe wie 1.4 (Satzzeichen und Groß-/Kleinschreibung der Erkennung stören nicht).
- [ ] **1.8 Offline: Fehler statt Wechsel (WP59).** Flugmodus an. Im Routing-Testfeld `Wie wird das Wetter?`: *Erwartet:* keine Absturzmeldung, Regel wie vorher (Default). Dann im Hauptbildschirm `Wie wird das Wetter?` senden. *Erwartet:* eine klare Fehlermeldung mit Grund (offline bzw. nicht erreichbar), **kein** Antworten eines anderen Anbieters, keine gelbe Rückfragekarte „Stärkeres Modell fragen?“, höchstens ein Wiederholungsversuch beim selben Ziel (am Log kein zweiter Anbieter). Bei Sprache ist die Meldung kurz („… ist gerade nicht erreichbar.“). Flugmodus wieder aus.
- [ ] **1.9 Ausfall des gewählten Ziels.** Ändere beim Profil „Claude API“ den Key absichtlich auf einen falschen Wert, speichere und sende `Claude, wie spät ist es?`. *Erwartet:* Fehlerkarte mit Grund (Anmeldung/Key), **kein** Wechsel auf das Standardprofil und keine Antwort von dort. Key wieder richtig eintragen.
- [ ] **1.10 „Nochmal mit …“ bleibt.** Nach einer Antwort vom Standardprofil sagen oder tippen: `Nochmal mit Claude`. *Erwartet:* Die Anfrage geht ausdrücklich an das Claude-Profil, Chip zeigt **Claude API**. Liegt das Ziel unter der Datenschutz-Untergrenze der Unterhaltung, fragt Wendelin nach bzw. lehnt ab.
- [ ] **1.11 Alte Ketten.** In den Provider- und Routing-Einstellungen sind nirgends Eskalationsketten oder „Eskalation“-Schalter sichtbar. (Ein Import mit Ketten meldet „… Eskalationsketten … übersprungen“, nur falls du eine alte Datei zum Importieren hast.)

## 2. MCP-Server über Tailscale

Voraussetzung: 0.3 und 0.4.

- [ ] **2.1 Erreichbarkeit vom Telefon.** Im Browser des Telefons `MCP_URL` öffnen (bei Weg B ohne Token kommt „401“ oder „Unauthorized“; das ist richtig). *Erwartet:* eine Antwort, kein Zeitüberschreitungsfehler. Sonst Tailscale prüfen (0.3).
- [ ] **2.2 Server hinzufügen.** Einstellungen → **MCP-Server** → **+ Server** (Seite „Server hinzufügen“). „Eigener Server“, Adresse `MCP_URL`, Anmeldung **Bearer-Token**, Token eintragen. Das Formular zeigt den Hinweis „Unverschlüsselt (http): nur im Heimnetz oder über …“ und den Status **Tailscale erlaubt**. Tippe **Verbindung prüfen**. *Erwartet:* „Prüfe …“, dann ein grünes „Erreichbar“. Kein Token im Klartext.
- [ ] **2.3 Speichern und Tools sehen.** **Speichern**, den Server in der Liste öffnen. *Erwartet:* Status „Server aktiv“, Tool-Liste (Weg B: `get_state`, `echo`, `get_time`, `toggle_light`, `delete_thing`, `delete_scene`).
- [ ] **2.4 Tool-Risikostufen.** Auf ein Tool tippen. *Erwartet:* `get_state`, `get_time`, `echo` sind „read“; `toggle_light` „write“; `delete_thing` und `delete_scene` „external“ („fragt immer nach“; der Schalter „Ohne Nachfrage ausführen“ ist bei „external“ gesperrt, Text „Außenwirkung: fragt immer nach, das lässt sich nicht …“).
- [ ] **2.5 Lesendes Tool.** `Frag den Server nach dem Zustand von licht.wohnzimmer` (Weg B: `Rufe get_time auf dem Server auf`). *Erwartet:* Tool-Karte `mcp_<servername>__…`, kein Nachfragen, danach eine Antwort mit dem Ergebnis.
- [ ] **2.6 Zerstörendes Tool fragt nach.** `Lösche die Szene Abend auf dem Server` (Weg B: `Rufe delete_thing auf`). *Erwartet:* Bestätigungskarte mit Servername und Tool („…: delete_…“). **Nein**: das Tool läuft nicht (Weg B: in der stderr-Ausgabe des Test-Servers keine Zeile `tools/call delete_thing`; Home Assistant: Szene bleibt). Wiederholen mit **Ja**: das Tool läuft, **kein Rückgängig** (Text „Kein Rückgängig“ bzw. keine Undo-Schaltfläche).
- [ ] **2.7 Ohne Tailscale.** Tailscale ausschalten, 2.5 wiederholen. *Erwartet:* verständliche Fehlermeldung („nicht erreichbar“), kein Absturz, kein Hängen länger als etwa 30 s. Tailscale wieder an, 2.5 klappt erneut (eventuell „Neu laden“ in der Serverliste).
- [ ] **2.8 Löschen.** MCP-Server öffnen → **Server löschen**. *Erwartet:* Rückfrage („Konfiguration, Tool-Liste und alle Zugangsdaten dieses Servers …“), nach Bestätigung ist er weg. (Für Block 12.6 wird er bei Bedarf neu angelegt.)

## 3. HTTP-Tools

Voraussetzung: ein Dienst im Tailnet, der per HTTP-GET Daten liefert. Home Assistant: `http://HOMESERVER:8123/api/states/<entity_id>` mit demselben Bearer-Token. Weg B: `http://HOMESERVER:<REST-Port>/api/states/light.wohnzimmer`.

- [ ] **3.1 Tool anlegen.** Einstellungen → **HTTP-Tools** → **+ HTTP-Tool**. Name `ha_state`, Beschreibung „Zustand einer Entität lesen“, Methode **GET**, URL-Vorlage `http://HOMESERVER:<Port>/api/states/{entity_id}`, Argument `entity_id` (Pflicht, Text). Anmeldung **Bearer-Token**, Token eintragen. Schalter **Heimnetz-Ziel** an („Darf auf private Adressen zeigen, dann auch http“). Speichern.
- [ ] **3.2 Testen.** Im Abschnitt „Testen“: `entity_id` = `light.wohnzimmer` (bei Home Assistant eine echte Entität), **Testen**. *Erwartet:* „Läuft …“, danach „Gesendet“ (URL, Methode, Header; der Token ist **verborgen**) und „Antwort“ mit JSON, das `light.wohnzimmer` enthält.
- [ ] **3.3 Per Agent.** `Ist das Licht im Wohnzimmer an?` *Erwartet:* Tool-Karte `http__ha_state`, danach eine Antwort. Die Karte zeigt kein Token.
- [ ] **3.4 Kein Fremdziel.** URL-Vorlage auf eine öffentliche Adresse mit `http://` (nicht https) ändern. *Erwartet:* beim Speichern oder Testen Warnung bzw. Ablehnung („nur https“), kein Aufruf. Änderung rückgängig machen.
- [ ] **3.5 Schreibendes Tool fragt nach.** Zweites Tool mit Methode **POST** (z. B. Home Assistant `light/turn_on`, Body `{"entity_id": "{entity_id}"}`). *Erwartet:* Stufe „write“; beim Aufruf per Agent erscheint eine Bestätigung (außer „Ohne Nachfrage ausführen“ ist an, beim Anlegen ist es aus).

## 4. Bring!

- [ ] **4.1 Anmelden.** Einstellungen → **Integrationen** → **Bring!**. Hinweis „Inoffizielle Schnittstelle …“ lesen. **E-Mail** und **Passwort**, **Anmelden**. *Erwartet:* „Angemeldet“, Integration an. Falsches Passwort: verständliche Meldung („Login fehlt“ bzw. Fehlertext), kein Absturz.
- [ ] **4.2 Listen lesen.** `Welche Bring-Listen habe ich?` *Erwartet:* Tool-Karte `bring__list_lists`, Antwort nennt deine Listen.
- [ ] **4.3 Artikel lesen.** `Was steht auf der Bring-Liste Test?` *Erwartet:* `bring__get_items`; „Milch“ und „Brot“.
- [ ] **4.4 Hinzufügen.** `Setz 2 Liter Hafermilch auf die Bring-Liste Test.` *Erwartet:* `bring__add_items`, die Karte hat **Rückgängig**. In der Bring!-App erscheint „Hafermilch“ mit „2 Liter“ (kann einige Sekunden dauern).
- [ ] **4.5 Rückgängig.** **Rückgängig** tippen. *Erwartet:* Hafermilch ist wieder weg.
- [ ] **4.6 Erledigt.** `Ich habe die Milch gekauft, hak sie bei Bring ab.` *Erwartet:* `bring__complete_item`, Milch unter „Zuletzt gekauft“. Rückgängig legt sie zurück.
- [ ] **4.7 Französisch.** `Ajoute des œufs et du beurre à ma liste Bring.` *Erwartet:* zwei Artikel (Eier, Butter). Rückgängig entfernt beide.
- [ ] **4.8 Fehlerfall.** Flugmodus an, `Was steht auf der Bring-Liste?`. *Erwartet:* Meldung „Bitte später erneut versuchen“ mit Hinweis auf die Bring!-App, Integration steht **nicht** auf „Fehler“. Flugmodus aus.
- [ ] **4.9 Abmelden.** Bring! → **Abmelden**, Rückfrage „Bei Bring! abmelden?“ bestätigen. *Erwartet:* „E-Mail, Passwort und Sitzung werden vom Gerät gelöscht“; Status „Login fehlt“.

## 5. App-Erkennung

Prüft, ob Wendelin erkennt, welche Fremd-Apps installiert sind (nur die deklarierten: Obsidian, Bring!).

- [ ] **5.1 Obsidian.** Ist die Obsidian-App (`md.obsidian`) installiert: Einstellungen → **Integrationen** → **Obsidian**. *Erwartet:* Status „Installiert“; sonst „Nicht installiert“ mit Hinweis.
- [ ] **5.2 Bring!-App.** Einstellungen → **Bring!**: Zeile „Bring!-App“ zeigt „Installiert“ oder „Nicht installiert“, passend zum Telefon.
- [ ] **5.3 Wechsel.** Bring!-App installieren oder deinstallieren, zu Wendelin zurückkehren. *Erwartet:* Status ändert sich ohne Neustart der App.
- [ ] **5.4 Sichtbarkeit.** Eine nicht deklarierte App taucht nirgends auf; Wendelin listet nicht die installierten Apps.

## 6. Sprach-UX (WP31)

Alle Schritte mit echter Stimme. Vorher 0.10 erledigt.

- [ ] **6.1 Zuhör-Anzeige.** Mikrofon tippen. *Erwartet:* nach kurzem „Moment …“ (nur beim ersten Mal nach einer Pause) der Ring um den Knopf und über dem Eingabefeld eine Wellenform-Leiste mit „Ich höre zu …“; sie reagiert auf die Stimme.
- [ ] **6.2 Sprech-Anzeige.** „Wie spät ist es?“ *Erwartet:* nach der Erkennung „denkt“ der Knopf, beim Vorlesen bewegen sich drei Punkte (Label „Sprachausgabe stoppen“). Tippen auf den Knopf während des Vorlesens: die Sprachausgabe stoppt sofort.
- [ ] **6.3 Stopp im Overlay.** Overlay öffnen (Power-Taste lang). Etwas Langes fragen („Erzähl mir etwas über Hamburg“). Sobald es antwortet, Mikrofon tippen und „Stopp“ sagen. *Erwartet:* „Abgebrochen“ erscheint kurz, die alte Antwort ist verschwunden, das Overlay schließt sich. Dann Einstellungen → Sprache → **Stopp schließt das Overlay** ausschalten und wiederholen: das Overlay bleibt offen. (Danach wieder einschalten.)
- [ ] **6.4 Warten auf Ja/Nein.** Im Hauptbildschirm: „Trag morgen um 10 Uhr Tauchen in den Kalender ein, dann lösche den Termin wieder.“ Bei der Bestätigungsfrage („… soll ich?“) ist der Zuhör-Ring wieder da, „Ja“ oder „Nein“ geht.
- [ ] **6.5 Rückgängig stoppt die Sprachausgabe.** „Trag mir morgen um 10 Uhr Tauchen ein.“ (Rückgängig-Karte erscheint). Sobald die Antwort vorgelesen wird, **Rückgängig** tippen. *Erwartet:* Sprachausgabe verstummt sofort, „Zurückgenommen.“ erscheint (hörbar, weil per Stimme gefragt, und sichtbar), die Karte zeigt „rückgängig“. Im Kalender ist der Termin weg.
- [ ] **6.6 Unscharfer Notizname.** „Ergänze in der Notiz Wendeline Test, dass ich Milch gekauft habe“ (die Notiz `Wendelin-Test` muss im Vault existieren, sonst anlegen). *Erwartet:* Die Bestätigungskarte nennt den gefundenen Pfad („Gefunden: Wendelin-Test“) **vor** dem Ja/Nein, die gesprochene Frage nennt ihn ebenfalls.
- [ ] **6.7 „Neues Gespräch“.** Nach einigen Nachrichten im Kopf auf das Symbol **Neues Gespräch** tippen (nur bei nicht leerem Verlauf; Tooltip). *Erwartet:* Verlauf leer, neue Sitzung. Mit der Stimme: Nachricht senden, dann „Vergiss das“ (auch „Neues Thema“ gilt). Dasselbe. Gegenprobe: „Vergiss, dass ich morgen Urlaub habe“ ist **keine** Neustart-Aktion, sondern eine normale Anfrage.
- [ ] **6.8 Senden-Knopf.** Im Textfeld tippen. *Erwartet:* Senden-Knopf erscheint, Tippen sendet. Bei leerem Feld ist es das Mikrofon.
- [ ] **6.9 „Probe hören“.** Einstellungen → **Sprache**, gesprochene Sprache **Français**, **Probe hören**. *Erwartet:* klingt französisch („Bonjour …“). Dann **Automatisch** bzw. „Wie die App“: Probe in der App-Sprache. Danach die gewünschte Sprache einstellen.

## 7. Vorlesefreundliche Antworten und Sprechfassung (WP41, WP55)

Die frühere Einstellung „Antwort in zwei Fassungen“ ist jetzt **Sprechfassung** unter Einstellungen → **Sprache** mit vier Stufen: **Aus** (Standard), **Immer eigene Sprechfassung**, **Geschützt**, **Mit KI-Prüfung**. Lege vorher im Kalender zwei Termine an (10 Uhr Zahnarzt, 14 Uhr Besprechung).

- [ ] **7.1 Stufe „Aus“.** *Sprechfassung* steht auf **Aus**. Sage „Was steht heute in meinem Kalender?“. *Erwartet:* Die vorgelesene Antwort besteht aus ganzen Sätzen („um zehn Uhr Zahnarzt und um vierzehn Uhr Besprechung“), nicht aus „Termine Doppelpunkt …“ oder Aufzählungszeichen; die Antwort auf dem Bildschirm ist dieselbe Fassung. Notiere, was gesprochen wurde: ____________________.
- [ ] **7.2 Zahlen und Zeiten.** „Wann ist mein nächster Termin?“ *Erwartet:* Uhrzeit und Datum klingen sprechbar („um zehn Uhr“, „am Dienstag“), nicht „10:00“ Ziffer für Ziffer.
- [ ] **7.3 Getippt bleibt unverändert.** Dieselbe Frage tippen. *Erwartet:* Die geschriebene Antwort darf Listen und Zeiten wie „10:00“ enthalten (der Hinweis gilt nur für Spracheingaben).
- [ ] **7.4 Auswahl und Erklärung.** Einstellungen → Sprache → **Sprechfassung** ansehen. *Erwartet:* vier Stufen mit je einem Erklärungssatz; bei „Immer eigene Sprechfassung“ der Hinweis „Was vorgelesen wird, kann von dem abweichen, was auf dem Bildschirm steht.“ Der alte Schalter „Antwort in zwei Fassungen“ existiert nicht mehr. War vorher „Antwort in zwei Fassungen“ an, steht die Stufe jetzt auf **Geschützt** (Migration), war er aus, auf **Aus**.
- [ ] **7.5 Stufe „Immer“ / „Geschützt“ ohne fremde Inhalte.** Stufe **Geschützt**, Frage wie 7.1 per Stimme. *Erwartet:* gesprochen wird ein kurzer, natürlicher Text, auf dem Bildschirm steht die ausführlichere Antwort. Nie ein Block „<spoken>“ oder dessen Inhalt doppelt auf dem Bildschirm. Notiere Unterschiede zu 7.1: ____________________. Dasselbe mit **Immer eigene Sprechfassung** und **Mit KI-Prüfung** (ohne fremde Inhalte verhalten sich alle drei gleich, ohne Zusatzkosten).
- [ ] **7.6 Nach fremden Inhalten.** Stelle eine Frage, die Webinhalte oder Inhalte eines MCP-Servers einbezieht (z. B. „Such im Web, wie das Wetter morgen wird“, falls eine Web-Suche eingerichtet ist, sonst `Rufe get_time auf dem Server auf` mit MCP). Danach eine Spracheingabe im selben Gespräch. *Erwartet:* Stufe **Geschützt**: vorgelesen wird die angezeigte Antwort. **Immer**: der Sprechtext. **Mit KI-Prüfung**: Sprachausgabe beginnt etwas später (ein Prüfaufruf); passen Sprech- und geschriebene Fassung, wird der Sprechtext gelesen, sonst die sichtbare Antwort mit Hinweis „Vorgelesen wurde die angezeigte Fassung“. Notiere pro Stufe, was vorgelesen wurde: ____________________.
- [ ] **7.7 Fallback.** Mit einem schwachen/kleinen Modell als Standard (z. B. Haiku): Stufe **Geschützt**, Frage per Stimme. *Erwartet:* Auch wenn das Modell den Sprechtext vergisst, wird die geschriebene Antwort vorgelesen (kein Schweigen, kein Fehler).
- [ ] **7.8 Kosten und Latenz.** Einstellungen → **Kosten**: vergleiche die Kosten der Anfragen aus 7.1 (Aus), 7.5 (Geschützt) und 7.6 (Mit KI-Prüfung): Tokens der Antwort, bei der Prüfung die Zusatzkosten. Latenz bis zum Beginn der Sprachausgabe in der Tabelle 15.2 eintragen (Aus gegen Mit KI-Prüfung). *Erwartet:* „Geschützt“ braucht etwas mehr Ausgabe-Tokens als „Aus“; „Mit KI-Prüfung“ nach fremden Inhalten zusätzlich einen kleinen Prüfaufruf und beginnt später. Notiere Werte: ____ / ____ / ____.
- [ ] **7.9 Zurück auf Standard.** Sprechfassung wieder auf **Aus** (Standard), sofern du es nicht behalten willst.

## 8. Taschenlampe, auch bei gesperrtem Telefon (WP48, WP53)

Die Taschenlampe ist eine eingebaute Integration („flashlight“, Tools an/aus/umschalten, Risiko „write“ mit Rückgängig, ohne Nachfrage, ohne Kamera-Berechtigung). Einstellungen → **Integrationen** zeigt sie.

- [ ] **8.1 Per Text.** Telefon entsperrt, im Hauptbildschirm `Taschenlampe an` tippen. *Erwartet:* Tool-Karte `flashlight__on`, LED leuchtet, keine Nachfrage. Dann `Taschenlampe aus` (LED aus) und `Taschenlampe umschalten` (LED an).
- [ ] **8.2 Per Stimme.** „Taschenlampe an“, „Taschenlampe aus“ (Hauptbildschirm oder Overlay). *Erwartet:* wie 8.1.
- [ ] **8.3 Rückgängig.** Nach „Taschenlampe an“ auf der Karte **Rückgängig** tippen. *Erwartet:* LED geht aus (vorheriger Zustand).
- [ ] **8.4 Systemkachel.** Taschenlampe über die Schnellkachel des Systems einschalten, dann „Taschenlampe aus“ sagen. *Erwartet:* LED geht aus (Wendelin erkennt den Zustand).
- [ ] **8.5 Gesperrt: Taschenlampe geht.** Telefon sperren (Display aus, gesperrt). Power-Taste lang drücken (oder Wake Word, sobald Block 10 geprüft ist) und „Taschenlampe an“ sagen. *Erwartet:* LED an **ohne Entsperren**, kein Inhalt auf dem Sperrbildschirm, kein Modellaufruf (Protokoll unter Datenschutz und Logs hat nach dem Entsperren einen Tool-Eintrag mit Markierung „bei Sperre“, ohne Inhalte). „Taschenlampe aus“ schaltet aus.
- [ ] **8.6 Gesperrt: alles andere nur „Bitte entsperre das Telefon“.** Gesperrt: „Was steht morgen im Kalender?“ *Erwartet:* nur der feste Satz „Bitte entsperre das Telefon“, **keine** Inhalte auf dem Sperrbildschirm, kein Verlauf, keine Tool-Karte; nach dem Entsperren wird die Äußerung nicht nachträglich beantwortet (verworfen). In Einstellungen → Kosten steht für diese Äußerung keine Anfrage.
- [ ] **8.7 Wake Word gesperrt.** Gesperrt, Bildschirm aus: „Hey Wendelin, Taschenlampe an“, dann „Hey Wendelin, Taschenlampe aus“ (nach Block 10). *Erwartet:* LED an bzw. aus. Gesperrt: „Hey Wendelin, was steht morgen im Kalender?“ ergibt nur „Bitte entsperre das Telefon“.

## 9. Wake Word einlernen, kalibrieren, ausprobieren (WP58, WP60)

Einstellungen → **Sprache** → Abschnitt „Aktivierungswort“ → „Wendelin lernt deine Stimme“. Gespeichert werden nur Zahlenwerte (Embeddings), nie Audio.

- [ ] **9.1 Merkmalsmodelle laden.** Abschnitt „Merkmalsmodelle“: laden (WLAN). *Erwartet:* Fortschritt, danach „Stimme einlernen“ ist freigeschaltet (vorher Hinweis „Dafür müssen zuerst die Merkmalsmodelle geladen sein.“).
- [ ] **9.2 Stimme einlernen.** „Stimme einlernen“, Name optional. Sage nach der Aufforderung „Hey Wendelin“ (Hinweise der Schritte: nah, aus ein bis zwei Metern, leise wie abends, wie im Alltag). *Erwartet:* Fortschritt „x von y“ (etwa 15 bis 20 Aufnahmen), Rückmeldungen „Gehört.“, „Zu leise. Bitte etwas lauter.“, „Zu früh angefangen …“, „Nichts gehört …“; zu leise oder abgeschnittene Aufnahmen werden verworfen. Am Ende „Alle Aufnahmen sind da.“ und **Speichern**. Dauer ungefähr 3 Minuten: ____ min. Danach steht die Stimme unter „Gelernte Stimmen“ mit „n Aufnahmen · Schwelle 0.xx“ (vorläufig etwa 0,85).
- [ ] **9.3 Abbruch.** Einlernen starten, nach einigen Aufnahmen **Abbrechen**. *Erwartet:* nichts wird gespeichert bzw. nur mit „Mit n Aufnahmen speichern“, wenn du das wählst; kein Absturz.
- [ ] **9.4 Weitere Person und Verwalten.** „Weitere Person einlernen“ (Name optional), dann im Menü einer Stimme „Neu einlernen“ und „Löschen“ prüfen. *Erwartet:* Neu einlernen ersetzt nur die Vorlagen dieser Person; Löschen entfernt nur sie. „Alle Stimmen löschen“ fragt nach („Wendelin vergisst alle eingelernten Stimmen …“).
- [ ] **9.5 Ausprobieren.** „Jetzt ausprobieren“. Sage „Hey Wendelin“ mehrmals aus 1 m und 2 m, dazu andere Wörter („Wendel“, „Vanille“, „Berlin“, „Wendeltreppe“) und ein Radio/Gespräch im Hintergrund. *Erwartet:* Treffer erscheinen live als „Kandidat · Ähnlichkeit 0.xx“ mit „Nachprüfung: bestätigt“ bzw. „nicht bestätigt“ (Whisper), ohne dass das Overlay aufgeht. Notiere 10 Versuche „Hey Wendelin“ (Kandidat/bestätigt) und die Fehltreffer: Tabelle 15.3 (Ausprobieren).
- [ ] **9.6 Nachprüfung ausschalten.** Im Abschnitt „Prüfen“ „Nachprüfung (Stufe 2)“ aus, 9.5 kurz wiederholen. *Erwartet:* mehr Kandidaten, jeder Treffer ohne Bestätigungsvermerk (Hinweis „dann gibt es mehr Fehlauslösungen“). Danach wieder **an** (Standard).
- [ ] **9.7 Kalibrieren (30 min).** „Kalibrieren (30 min, empfohlen)“, Sprecher wählen („Wen kalibrieren?“). Handy hinlegen, normal weiterreden, Fernseher/Radio an. Auf die gelegentlichen Pieptöne antworten: „Hey Wendelin“ sagen. *Erwartet:* Restzeit („Noch n min“), „Aufforderungen: x von y beantwortet“; Mikrofonanzeige sichtbar; am Ende „Kalibriert.“ mit „Schwelle 0.xx · geschätzt … Fehlalarme/h“ oder „Nicht verwertbar.“ (dann mehr Aufforderungen beantworten und wiederholen). **Jetzt beenden** ist erst nach genug Aufforderungen möglich; **Abbrechen** lässt alles unverändert („Abgebrochen. Es wurde nichts geändert.“). Trage Schwelle und geschätzte Fehlalarme in Tabelle 15.3 ein.
- [ ] **9.8 Kein Rohaudio.** Nach 9.2 bis 9.7 liegt auf dem Telefon keine Aufnahme der Einlern-/Kalibrierphase im Dateisystem der App (nur der Vorlagenspeicher). Prüfen mit `adb -s SERIAL shell run-as app.wendelin ls -R files | grep -iE "wav|pcm|flac|ogg"` (nur bei Debug-Build möglich; bei Release-Build entfällt der Punkt, dann „nicht prüfbar“ vermerken).
- [ ] **9.9 „Alles löschen“.** Einstellungen → **Datenschutz und Logs** → „Alles löschen“ (Text nennt „… die eingelernten Stimmen …“): erst am Ende des Gesamttests, danach ist „Gelernte Stimmen“ leer. Neu einlernen für weitere Tests.

## 10. Wake-Word-Dienst (WP50)

Der Dienst läuft als Vordergrunddienst (Typ Mikrofon, dauerhafte Benachrichtigung „Wendelin hört auf „Hey Wendelin““ mit den Knöpfen „Pause 1 h“ und „Aus“). Er wird über die Assistentenrolle gestartet (auch nach Neustart) und braucht mindestens eine eingelernte Stimme. Der Bildschirm kann aus und das Telefon gesperrt sein. Die Bedienung sitzt oben auf der Seite „Aktivierungswort“ (Einstellungen → Sprache → Aktivierungswort → „Wendelin lernt deine Stimme“), Abschnitt „Zuhören im Hintergrund“ mit Zeile „Status“ und Schalter „Aktivierungswort einschalten“.

- [ ] **10.1 Ohne Einlernen kein Dienst.** (Nur wenn du vorher alle Stimmen gelöscht hast.) Dienst einschalten. *Erwartet:* Er lässt sich nicht einschalten, Hinweis „Erst Stimme einlernen“ mit Knopf „Zum Einlernen“.
- [ ] **10.2 Ohne Rolle gesperrt.** Assistentenrolle in den Android-Einstellungen kurz auf „Keiner“ stellen. *Erwartet:* Der Schalter ist gesperrt; es erscheint „Wendelin ist nicht dein Assistent“ mit dem Knopf „Assistenten wählen“. Rolle wieder auf Wendelin setzen.
- [ ] **10.3 Einschalten und Erklärung.** Dienst einschalten. *Erwartet:* Dialog „Aktivierungswort einschalten?“ mit den Punkten „Dauerhafte Benachrichtigung“, „Mikrofon-Punkt“, „Zuhören bleibt auf dem Gerät“ und „Akku“ (Knöpfe „Abbrechen“ / „Einschalten“; danach evtl. „Akku-Optimierung ausnehmen?“). Abschnitt „Wann zuhören?“: **Nur beim Laden** (Standard) oder **Immer**. Abschnitt „Ton und Prüfung“: Schalter „Bestätigungston“ und „Nachprüfung (Stufe 2)“. Eine eigene Empfindlichkeit gibt es hier nicht (die Schwelle kommt aus Einlernen und Kalibrieren). Für die folgenden Tests auf **Immer** stellen. In der Benachrichtigungsleiste steht „Wendelin hört auf „Hey Wendelin““ mit „Pause 1 h“ und „Aus“. Log: `wake-start result=ok source=… mode=…`.
- [ ] **10.4 Treffer bei Bildschirm aus.** Bildschirm aus (Power-Taste kurz), 30 Minuten liegen lassen. Dann „Hey Wendelin, wie spät ist es?“ aus 1 bis 2 m. *Erwartet:* Das Overlay öffnet sich (gesperrt: nur Taschenlampe, sonst „Bitte entsperre das Telefon“; entsperrt/nach Entsperren die Antwort). Der Satzanfang nach dem Wake Word wird erkannt, der Pre-Roll geht mit. 10 Versuche, Treffer notieren (Tabelle 15.3; Ziel ≥ 90 %). Nach dem Treffer gibt der Dienst das Mikrofon frei, das Overlay nimmt ohne Fehler auf.
- [ ] **10.4a „Hey Wendelin, mach …“ in einem Atemzug (WP68).** Bildschirm an, entsperrt, Dienst läuft. Ohne Pause sagen: „Hey Wendelin, wie spät ist es?“, dann „Hey Wendelin, schalte die Taschenlampe an“. *Erwartet:* Das Overlay zeigt die Anfrage **ohne** das Wort „Hey Wendelin“ („wie spät ist es?“), der Satzanfang fehlt nicht, es kommt **kein Bestätigungston** (du sprichst schon weiter). Dann mit Pause: „Hey Wendelin“ … (1 s Pause) … „wie spät ist es?“: gleiche Anfrage, Ton kommt. Nur „Hey Wendelin“ sagen und schweigen: Overlay wartet auf die Anfrage. Log: `wake-handoff ms=… captured=… continues=true|false` und `wake-gap ms=…` (Zeit zwischen Ende der Dienst-Aufnahme und dem ersten Bild des Overlay-Mikrofons; Ziel unter 150 ms). **WP73 (zusätzlich, je 10 Versuche schnell und langsam gesprochen):** `wake-handoff … continues=true` und kein Ton, wenn du ohne Pause weiterredest; mit Pause `continues=false` und Ton. `wake-gap ms=… afterTake=…` (`afterTake` = Teil der Lücke ab Übergabe an das Overlay bis zu dessen erstem Bild; der Rest ist das Schließen des Dienst-Mikrofons) und `wake-handoff-take … close=…ms` (Schließen des Dienst-Mikrofons) benennen, wo die Lücke liegt; nur diese Zahlen notieren. `wake-verify-text cat=exact|variant|other|empty ms=…` zeigt für jede Nachprüfung nur die Kategorie, nie den Text (`other` bei vielen Ablehnungen = Whisper hört etwas anderes, `empty` = Fenster ohne Sprache). „Licht an“ darf kein `conv-exit reason=stopWord` auslösen; tut es das, steht davor `stop-word source=transcript|barge-in`. Fehlschläge (Satzanfang fehlt, „Hey Wendelin“ im Text) in Tabelle 15.3 notieren.
- [ ] **10.5 Neustart ohne App-Öffnen.** Telefon neu starten, Wendelin **nicht** öffnen. Nach 2 Minuten „Hey Wendelin, wie spät ist es?“. *Erwartet:* löst aus (Rolle gesetzt). Log: `wake-start result=ok source=vis` ohne „microphone access“-Warnung. Ohne Rolle startet der Dienst nicht und es erscheint die Benachrichtigung „Wake Word ist aus“ (bei verlorener Rolle ohne Knopf; sonst mit Knopf „Wieder einschalten“).
- [ ] **10.6 Nur beim Laden.** Bedingung **Nur beim Laden** wählen. *Erwartet:* Am Ladegerät läuft der Dienst (Benachrichtigung da), Stecker ziehen: Dienst stoppt; Stecker rein: Dienst startet (über Lade-Ereignisse, kein Neustart nötig). Danach wieder **Immer** für die weiteren Tests.
- [ ] **10.7 Hintergrund-Speicher und Alltag.** Dienst läuft im Ruhezustand. `adb -s SERIAL shell dumpsys meminfo app.wendelin | grep -E "TOTAL PSS|TOTAL RSS|Native Heap"`. *Erwartet:* **TOTAL PSS < etwa 200 MB** ohne geladenes Whisper (Whisper wird erst beim ersten Kandidaten geladen und nach ca. 60 s ohne Kandidat freigegeben); Spitzenwert mit Whisper in Tabelle 15.1 eintragen. Dann 8 Stunden Alltag mit laufendem Dienst: Fehlalarme (`wake-hit` im Log; `wake-cand` und `wake-verify` getrennt; Kandidaten/h und bestätigt/h aus `wake-alive cand=… ok=… candPerH=… okPerH=… min=…`; die Benachrichtigung hat keinen Zähler) und Akku in % (Einstellungen → Akku → App) in Tabelle 15.3 eintragen. Ziel: höchstens 1 Fehlauslösung in 8 h.
- [ ] **10.8 Dienst überlebt HyperOS.** Mit Standard-Akkueinstellungen gegen die empfohlenen Einstellungen (nach 0.9a): Läuft der Dienst nach 2 Stunden Display aus noch? Prüfen an `wake-alive` (alle 5 min) im Log und an einem Treffer. Einmal vor und einmal nach 0.9a; Ergebnis: ____________________. Fällt der Dienst aus, zeigt die Zeile „Status“ auf der Seite „Aktivierungswort“ den Grund (z. B. „Vom System beendet“, „Vom System beendet (Zeitlimit von Android)“) und, wenn der Dienst selbst endete, erscheint die Benachrichtigung „Wake Word ist aus“ (Log `wake-stop reason=…`).
- [ ] **10.9 Telefonat und Sprachmemo.** Während eines Telefonats und bei laufender Sprachmemo-App. *Erwartet:* Der Dienst pausiert (Mikrofon freigegeben, kein Fehler) und läuft danach weiter.
- [ ] **10.10 Pause und Aus.** In der Benachrichtigung **Pause 1 h** tippen: kein Treffer mehr, Benachrichtigung „Wendelin pausiert“ („Bis HH:mm Uhr“), Status „Pausiert bis …“, Log `wake-pause reason=user`; **Fortsetzen**: Treffer wieder möglich (`wake-resume`). **Aus**: Dienst beendet, Benachrichtigung weg (`wake-stop reason=…`).
- [ ] **10.11 Bluetooth-Kopfhörer.** Mit verbundenem Bluetooth-Kopfhörer „Hey Wendelin“ am Handy sagen. *Erwartet:* Dienst und Overlay arbeiten weiter am Handy-Mikrofon, die Antwort kommt auf dem Kopfhörer.
- [ ] **10.12 Eigene Ausgabe löst nicht aus.** Sprachausgabe laut lassen (kein „Hey Wendelin“ im Text). *Erwartet:* kein Treffer durch die eigene Stimme (keine neue `wake-hit`-Zeile).

## 11. Gesprächsmodus und Barge-in (WP45, WP51)

Einstellungen → **Sprache** → Abschnitt „Gespräch“: **Weiter zuhören nach der Antwort** (Standard aus) und **Unterbrechen während der Antwort** (Aus / Schlüsselwörter / Beliebige Sprache (experimentell)).

- [ ] **11.1 Einmalige Frage.** Zurücksetzen nicht nötig bei frischer Installation: Gesprächsmodus ist aus, noch keine Frage beantwortet. Stelle eine Spracheingabe, auf die eine Folgefrage sinnvoll wäre („Wie spät ist es?“). *Erwartet:* Nach der **ersten** gesprochenen Antwort erscheint **einmalig** die Karte „Soll ich nach meinen Antworten standardmäßig weiter zuhören?“ mit **Ja** und **Nein** und dem Zusatz „Das lässt sich jederzeit unter Einstellungen → Sprache ändern.“ Antwortest du, kommt die Frage nie wieder (auch nicht nach Neustart der App). Wähle **Ja**. Hast du die Frage schon im Onboarding-Schritt „Gespräch“ beantwortet, erscheint sie nicht (dann „n. a.“, aber den Schritt im Onboarding vermerken).
- [ ] **11.2 Einstellung folgt der Antwort.** Einstellungen → Sprache → „Gespräch“. *Erwartet:* Der Schalter „Weiter zuhören nach der Antwort“ steht auf der gegebenen Antwort (Ja → an). Mit Nein steht er auf aus.
- [ ] **11.3 Folgefrage ohne Tipp.** Schalter an. Frage 1 per Stimme („Wie spät ist es?“). Nach dem Ende der Sprachausgabe läuft ein Folgefenster (Zuhör-Leiste „Hört noch 5 s zu · „Stopp“ beendet“, mit Restzeit). Innerhalb von 5 s ohne Tippen Frage 2 stellen („Und wie wird das Wetter?“). *Erwartet:* neue Anfrage im selben Gespräch (der Bezug „und …“ wird verstanden). Wiederhole für drei Folgefragen hintereinander.
- [ ] **11.4 Endebedingungen.** (a) Stille: Nach der Antwort 6 s nichts sagen: Fenster endet, Mikrofon aus. (b) „Danke“ sagen (nur das Wort, auch „Das war’s“): Gespräch endet. (c) „Stopp“ im Folgefenster: endet. (d) Tipp auf den Knopf: endet. (e) Höchstzahl: nach fünf Folgerunden endet das Fenster. Im Log (`conv-exit reason=…`) steht je Ende genau ein Grund: ______________. Eine Rückfrage-Karte (Ja/Nein) hat Vorrang: dann antworte mit Ja/Nein, das Folgefenster übernimmt nicht.
- [ ] **11.5 Nur bei Sprachanfragen und nur im Vordergrund.** Getippte Anfrage: kein Folgefenster. App mit Home-Taste verlassen, während das Fenster läuft: Mikrofon geht aus (kein Zuhören im Hintergrund, außer dem Wake-Word-Dienst).
- [ ] **11.3a Kein „Bad state“ nach der Antwort (WP64).** Gesprächsmodus an, Unterbrechen: **Schlüsselwörter**, eine Stimme eingelernt. Frage stellen, die Antwort zu Ende hören. *Erwartet:* Das Folgefenster öffnet ohne Fehlermeldung im Chat (kein „Bad state: Die Aufnahme läuft bereits.“). Log (`adb -s SERIAL logcat -d | grep "Wendelin/voice"`) in dieser Reihenfolge: `barge-listen on=true` (Ausgabe beginnt), `mic-stop`, `barge-listen on=false`, `audio-source profile=recognition`, `mic-start profile=recognition` (Folgefenster). Steht `mic-busy` im Log, hält noch jemand das Mikrofon: Auszug liefern.
- [ ] **11.6 Barge-in „Stopp“ (WP64b).** Einstellung Unterbrechen: **Schlüsselwörter**. Zuerst Aktivierungswort-Seite: Hinweis „Ohne gelerntes „Stopp“ …“ sichtbar, dann **„Stopp“ einlernen** (10 Aufnahmen, danach „„Stopp“ ist gelernt“). Lange Antwort laut vorlesen lassen („Erzähl mir etwas über Hamburg“), mitten drin **„Stopp“ allein** sagen. *Erwartet:* Die Ausgabe endet sofort (Log `barge-hit kind=keyword-stop`, davor `barge-stop-word learned=true`), die Anfrage und das Overlay sind beendet (`conv-exit reason=stopWord`, Einstellung „Stopp schließt das Overlay“ an). Ohne gelerntes „Stopp“ (Vorlagen gelöscht, `barge-stop-word learned=false`) geht nur „Hey Wendelin, stopp“ (`barge-hit kind=keyword-wake`, danach „stopp“ erkannt). 10 Versuche; Selbstauslösungen **ohne** Sprechen zählen (Ziel 0), auch wenn die Antwort selbst „Stopp“ enthält (eigene Ausgabe darf nicht auslösen). Notiere in Tabelle 15.3.
- [ ] **11.7 Barge-in „Hey Wendelin“.** Während der Ausgabe „Hey Wendelin, wie spät ist es?“. *Erwartet:* Ausgabe endet, die neue Frage wird verstanden (Log `barge-hit kind=keyword-wake`, `barge-in kind=keyword-wake`). Das Folgefenster nach dem Barge-in beginnt ohne Fehlermeldung (`mic-start profile=recognition`).

- **Barge-in-Diagnose (WP72) – ein Lauf für 11.6/11.7.** Version mit WP72 installieren, Gespräch an, Unterbrechen „Schlüsselwörter“. Lange Antwort vorlesen lassen, dabei „Stopp“ bzw. „Hey Wendelin“ sagen (mehrfach, auch nah am Mikrofon). Danach `adb logcat | grep Wendelin/voice` und diese Zeilen lesen:
  - `mic-config profile=speechOutput variant=…` und `mic-state state=…`: Variante der Aufnahme; `mic-state state=pause` während der Ausgabe belegt, dass Android die Aufnahme angehalten hat (Ursache **belegt aus Code**: das `record`-Plugin pausierte bei jedem Audiofokus-Verlust, die Ausgabe nimmt den Fokus; seit WP72 `audioInterruption: none` nur für die Ausgabe-Aufnahme, dann darf kein `pause` mehr erscheinen; Erkennung und übrige Profile nutzen `pauseResume`: `mic-state state=pause`, danach wieder `record`). `mic-state state=started` steht je Start; `barge-hit` trägt `sim`/`stop`/`thr`/`sthr` (Maxima bis zum Treffer).
  - `barge-config margin=… thr=… sthr=…`: wirksame Schwellen (Vorlagenschwelle + Aufschlag) für „Hey Wendelin“ und „Stopp“.
  - `barge-diag t=… frames=… rms=… peak=… lag=… proc=… sim=… stop=… thr=… sthr=…`, jede Sekunde: `frames=0` heißt, das Mikrofon liefert nichts (pausiert); `frames>0` und `rms=0` heißt stumm (Fokus/Silencing); `rms` klein (< ca. 100) bei gesprochenem Wort heißt, AEC/Rauschunterdrückung dämpft die Stimme stark; `lag` > 500 oder `proc` > 1000 heißt, die Erkennung kommt nicht hinterher (Treffer kämen verspätet); `sim`/`stop` ist die beste Ähnlichkeit der Sekunde zu den „Hey Wendelin“- bzw. „Stopp“-Vorlagen: liegt sie beim Sprechen knapp unter `thr`/`sthr`, ist die Schwelle zu streng (Variante +0,00 probieren), liegt sie weit darunter (< 0,5), passt das Signal nicht zu den Vorlagen (Quelle wechseln).
  - `barge-end frames=… sim=… stop=…`: Maxima der ganzen Ausgabe. `barge-hit`/`barge-in` wie bisher.
  - WP80 „Stopp“-Trennung: `stop` wird nur noch über das Fensterende (die letzten 9 von 16 Embeddings, Wort plus Nachklang) bewertet, ein Treffer braucht Sprachpegel im Strom (`lvl` ≥ max(150, 4 × `quiet`)) und `stop` ≥ `sfloor` + 0,02 (`sfloor` = gleitende „Stopp“-Ähnlichkeit des Hintergrunds, `sgap` = größter Abstand `stop` − `sfloor` der Sekunde, `quiet` = Grundpegel, `lvl` = Spitzenpegel der letzten 0,8 s, jeweils RMS). Erwartet: in Stille bleibt `lvl` klein (< 150), also kein Treffer, auch wenn `stop` hoch ist; beim gesprochenen „Stopp“ steigen `lvl` und `sgap` (> 0,02) und `stop` erreicht `sthr`. Liegt `stop` beim Sprechen trotzdem unter `sthr`, ist es ein Schwellen-/Vorlagenthema (neu einlernen, Aufschlag 0,00).
  - Varianten unter **„Erweitert“** (Button neben „Unterbrechen während der Antwort“, WP80; früher langes Drücken), mit Erklärung je Option: Quelle: „Kommunikation + AEC“ (Standard), „Erkennung + AEC“, „Erkennung, ohne AEC“ (zeigt, ob die Echo-Unterdrückung die Stimme frisst; dann kann die Ausgabe selbst auslösen, Selbstauslösungen zählen). Aufschlag: +0,05 (Standard), 0,00, −0,05. Wirkt ab der nächsten Antwort. Reihenfolge: zuerst Standard (belegt, ob `pause` weg ist); wirkt „Stopp“ noch nicht, anhand `sim`/`stop` gegen `thr`/`sthr` entscheiden: Schwelle senken oder Quelle wechseln. Nach dem Test auf Standard zurückstellen.
- [ ] **11.7a Anruf/Musik während Erkennung und Ausgabe (WP72).** (a) Während der Erkennung (Mikrofon offen, Zuhör-Leiste) Musik/Navi-Ansage/Anruf eines zweiten Geräts starten: Aufnahme pausiert (`mic-focus lost=true`, dann `mic-state state=pause`; die App pausiert selbst, WP90) und läuft nach dem Ende weiter (`mic-focus lost=false`, `mic-state state=record`), kein Einfrieren. (b) Während der Antwort (Barge-in aktiv) dasselbe: die Barge-in-Aufnahme bleibt unberührt (kein `pause`, `barge-diag frames>0`), „Hey Wendelin“ unterbricht weiter. Ansagen mit Ducking (CAN_DUCK, z. B. Navi) pausieren die Aufnahme nicht; nur Anruf oder transienter Verlust pausiert. Notiere: ____________________.
- [ ] **11.8 Ohne Barge-in.** Einstellung Unterbrechen: **Aus**. *Erwartet:* „Stopp“ bzw. „Hey Wendelin“ während der Ausgabe stoppt nicht per Stimme (Tippen auf den Knopf stoppt weiter). Danach zurück auf **Schlüsselwörter**.
- [ ] **11.9 „Beliebige Sprache (experimentell)“.** Ist die Zeile verfügbar (Hinweis „Nicht verfügbar: …“ sonst): bei leisem Hintergrund und Standardlautstärke mit eigener Ausgabe testen: kein Selbstauslösen durch die eigene Stimme (kein AEC-Bezug garantiert), sonst Option aus lassen. Notiere: ____________________.
- [ ] **11.10 Echo bei lauter Ausgabe.** Ausgabe laut (Lautsprecher) und leise: löst die eigene Stimme „Stopp“ aus (Fehlstopp)? Notiere (Handy-AEC ist gerätespezifisch): ____________________.
- [ ] **11.11 Bluetooth-Kopfhörer.** Mit Kopfhörer Gesprächsmodus und Barge-in wiederholen (11.3, 11.6). *Erwartet:* beides funktioniert, Audio bleibt auf dem Kopfhörer.
- [ ] **11.12 Qualität der Erkennung.** Die eigentliche Anfrage nach Barge-in oder im Folgefenster wird genauso gut erkannt wie eine normale (kein Qualitätsverlust gegenüber 6.1; die Quelle wechselt nur während der Sprachausgabe).

## 12. Phala und TEE-Prüfstatus (WP46, WP47, WP49, WP52)

Ein Phala-Profil (RedPill, Vorlage „Phala (RedPill)“) trägt nach Ende jeder Antwort ein Schild: **grün** (geprüft), **gelb** (wird geprüft, nur Zwischenstand), **rot** (Prüfung fehlgeschlagen). Rot sperrt den Anbieter bis „Neu prüfen“. Phala-Key aus 0.2. Es gibt keine Option, bei fehlgeschlagener Prüfung auf einen anderen Anbieter auszuweichen.

- [ ] **12.1 Einrichten.** Einstellungen → **Provider** → **+ Provider** → „Phala (RedPill)“, Key eintragen. Es sind nur Modelle mit TEE wählbar (`is_tee`), „✓ TEE“ erscheint beim Modell. Das kleinste TEE-Modell nehmen. **Modell prüfen**. *Erwartet:* „Modell geprüft“ mit Ergebnis je Stufe der ersten Attestierung. Prüfzeit der ersten Attestierung (es gibt keine Zeile `attest-done`: Zeitstempel der ersten und letzten Zeile `Wendelin/attest: …` aus `logcat -v time` bzw. Dauer im Attestierungsprotokoll) in Tabelle 15.2.
- [ ] **12.2 Drei Fragen, jede grün.** Phala-Profil als Ziel (z. B. über eine Regel mit Präfix „Phala“ oder als Standard). Drei Fragen, eine davon mit Tool (z. B. Kalender oder `Rufe get_time auf dem Server auf`). *Erwartet:* Jede Antwort hat nach dem Ende ein grünes Schild („geprüft“, Screenreader „TEE-Prüfung: geprüft“). Das Tool läuft sofort, wenn es nur liest oder schreibt; ein „external“-Tool (z. B. `delete_thing`) startet erst nach der geprüften Quittung.
- [ ] **12.3 Prüfprotokoll lesen.** Tipp auf das Schild bzw. Einstellungen → **Datenschutz und Logs** → **TEE-Prüfprotokoll**. *Erwartet:* je Anfrage eine Zeile (Zeit, Provider, Modell, Ergebnis je Stufe: Quote/TCB, Nonce-Bindung, Keyset, Endorsement, Gültigkeit, Event-Log/Compose-Hash, Provenance, TLS; bei der Antwort Quittung, Signatur, Hashes), Quittungs-ID, Keyset-Digest, Commit. Filter **Alle / Geprüft / Wird geprüft / Fehlgeschlagen**. Nur IDs und Hashes, keine Prompt- oder Antwortinhalte.
- [ ] **12.4 Flugmodus gelb → grün.** Direkt nach einer Antwort Flugmodus an, bevor das Schild grün wird (oder während der Quittungsabruf läuft). *Erwartet:* Schild **gelb** („wird geprüft“), bis zu drei Wiederholungen; Netz zurück (Flugmodus aus): wird **grün**. Bleibt das Netz weg, wird es nach 3 Versuchen **rot**. Gelb ist nur ein Zwischenstand, nie der Endstatus.
- [ ] **12.5 Rot bei Fehler und Sperre.** Eine rote Prüfung provozieren: Gibt es keine Fixture-Möglichkeit auf dem Gerät, genügt die Beobachtung eines echten Fehlschlags (z. B. Uhrzeit des Telefons um mehr als einen Tag falsch stellen: `not_after`/Zertifikatsgültigkeit schlägt fehl; danach Uhr wieder automatisch). *Erwartet:* Schild **rot** („Prüfung fehlgeschlagen“), Warnkarte mit Grund und **Neu prüfen**; der Anbieter ist gesperrt (nächste Anfrage geht nicht raus, Log: `Wendelin/attest: Anfrage nicht gesendet (<Stufe>)`), **kein** Wechsel zu einem anderen Anbieter. Nach korrekter Uhr: **Neu prüfen** → grün, Anfragen gehen wieder. Ist das nicht herstellbar: „Emulator belegt (WP52, Fixture rot)“ und hier „nicht prüfbar“ vermerken.
- [ ] **12.6 TCB `OutOfDate` ist rot.** Meldet die Gegenseite ein veraltetes Sicherheitsniveau (Hardware ohne neuestes Update), ist der Endstatus **rot** mit Hinweis „Sicherheits-Update beim Betreiber ausstehend … kein Hinweis auf eine Manipulation …“ (Entscheidung Maintainer: rot mit Hinweis). Tritt das im Test nicht auf, vermerke „nicht aufgetreten“ (belegt im Emulatorlauf WP46/WP52 mit Fixture). Tritt es auf: Text und Quelle (`TCB-Status`) in der Rückmeldung notieren.
- [ ] **12.7 Pinning-Wechsel.** Rollt der Anbieter ein Update aus, erscheint der Hinweis „Anbieter hat ein Update ausgerollt, neu geprüft“ (nur falls es während des Tests passiert; nicht erzwingbar).
- [ ] **12.8 Export.** Im Prüfprotokoll **Als JSON exportieren**, Datei ansehen (Teilen-Intent, z. B. an dich selbst). *Erwartet:* keine Prompt-/Antwortinhalte, keine Keys, keine Rohquittung, nur IDs, Hashes, Stufen. **Löschen** im Protokoll fragt nach und leert es.
- [ ] **12.9 GPU-Prüfung über NVIDIA (WP46/WP52).** Einstellungen → Provider → TEE-Profil (Phala, NEAR) bearbeiten, im letzten Schritt „GPU-Prüfung über NVIDIA“, **je Profil** einstellbar (WP82; der alte globale Wert wurde beim ersten Start auf alle TEE-Profile übernommen), mit drei Stufen:
  - **Aus (Standard):** Frage an das Phala-Profil. *Erwartet:* grün; im Protokoll steht „GPU: nicht geprüft“ bzw. nur lokale Nonce-Bindung; kein Netzaufruf an `nras.attestation.nvidia.com` (am Router/DNS-Log, falls möglich).
  - **Vorher (blockierend):** Stufe wählen (Erklärung: „NVIDIA prüft die GPU-Nachweise, bevor deine Anfrage den Anbieter erreicht …“). Neue Sitzung (App neu starten oder „Neu prüfen“), dann Frage. *Erwartet:* Die Anfrage geht erst nach der grünen GPU-Prüfung raus; im Protokoll „geprüft (NRAS)“. Die Zusatzlatenz notierst du in Tabelle 15.2. Mit Flugmodus **nur gegen NVIDIA** (z. B. Domain im Router sperren, falls möglich; sonst überspringen) wird nichts gesendet (fail-closed), Hinweis mit **„Ohne GPU-Prüfung senden“** (gilt nur für diese Anfrage) oder Abbrechen.
  - **Nachher (nicht blockierend):** Frage geht sofort raus, die Prüfung läuft danach. *Erwartet:* Schild wird nach der GPU-Prüfung grün; schlägt sie fehl: System-Benachrichtigung, roter Status an der Antwort und im Protokoll, weitere Anfragen an das Modell fragen vorher nach.
  - **Modell ohne GPU-Nachweis (z. B. GLM 5.2 bei Phala):** ist trotzdem wählbar; beim Prüfen des Modells erscheint „Keine GPU-Prüfung möglich (Anbieter liefert keinen Nachweis)“ statt „Modell nicht nutzbar“, und die Einschränkungs-Notiz nennt „GPU-Nachweis des Anbieters“. *Erwartet:* **Aus** nichts; **Nachher** Frage geht raus, kein roter Status, keine Benachrichtigung; **Vorher** Frage wird nicht gesendet, Dialog „Kein GPU-Nachweis“ mit **„Ohne GPU-Prüfung senden“** (nur diese Anfrage).
  - Ein anderes TEE-Profil behält seine eigene Stufe (Stufe an einem Profil ändern, das andere prüfen).
  - Danach auf **Aus** zurück (Standard), sofern du es nicht behalten willst.
- [ ] **12.10 Vorwärmen und Prüfzeit.** App neu starten (Phala-Profil aktiv, Netz da): die Sitzungs-Attestierung läuft im Hintergrund vor der ersten Frage. Dauer der Prüfung und Latenz der ersten Antwort in Tabelle 15.2.
- [ ] **12.11 Kein Inhalt im Log.** `adb -s SERIAL logcat -d | grep "Wendelin/attest"` nach 12.2 bis 12.5: nur Stufen und Ergebnisse, keine Frage- oder Antworttexte.

## 13. Power-Taste nach Pause und „Zuverlässig öffnen“ (WP56)

- [ ] **13.1 Standard-Assistent gesetzt.** Siehe 0.8.
- [ ] **13.2 Hinweise ansehen.** Siehe 0.9 (notiere die Hinweise dort).
- [ ] **13.3 Vorher-Messung.** (Hinweise unverändert, Ausnahmen noch nicht erteilt.) Wendelin per Taskmanager wegwischen. Telefon 2 Stunden oder über Nacht liegen lassen (Display aus). Dann Power-Taste lang drücken. *Erwartet (Ziel):* Wendelin öffnet sich. Notiere ja/nein und wie lange es dauert: ____________________. Bei Fehlversuch `tool/diag_assistant_idle.sh SERIAL` **vor** dem Drücken starten (Pflichtargument ist die Seriennummer; das Skript leert per `logcat -c` den Gerätelog) und die Ausgabe an den Maintainer geben.
- [ ] **13.4 Ausnahmen erteilen.** Jetzt 0.9a ausführen (Autostart, „Keine Einschränkungen“, Ausnahme, Letzte Apps). *Erwartet:* Die Hinweise aktualisieren sich beim Zurückkehren aus den Systemseiten.
- [ ] **13.5 Nachher-Messung.** Wie 13.3 (wegwischen, 2 Stunden bzw. über Nacht, Power-Taste lang). *Erwartet:* Wendelin öffnet sich zuverlässig. Notiere: ____________________.
- [ ] **13.6 Kaltstart-Platzhalter.** Lief der Prozess nicht (Start nach 13.3/13.5), erscheint kurz **„Wendelin startet …“**, danach das Assistenten-Sheet (kein leerer Bildschirm, kein Flackern). Notiere ja/nein, Dauer ungefähr ____ s.

## 14. Speicher und Latenz (K14 c)

Ziel: höchstens ca. 1,1 GB bei aktiver Sprachnutzung, unter 200 MB im Hintergrund, auch mit laufendem Wake-Word-Dienst. Werte in Tabelle 15.1.

- [ ] **14.1 Frischer Start.** Wendelin per Taskmanager wegwischen, Telefon 1 Minute liegen lassen.
- [ ] **14.2 Ruhewert.** Wendelin öffnen (Hauptbildschirm), nichts sagen, 30 s warten. `adb -s SERIAL shell dumpsys meminfo app.wendelin | grep -E "TOTAL PSS|TOTAL RSS|Native Heap"`. Notiere **TOTAL PSS**.
- [ ] **14.3 Nach Sprachnutzung.** Eine Spracheingabe im Hauptbildschirm, danach eine im Overlay (Power-Taste), direkt danach dieselbe Messung. *Erwartet:* **TOTAL PSS ≤ etwa 1100 MB**. Höchstens **ein** Modell gleichzeitig: in `adb -s SERIAL logcat -d | grep "Wendelin/voice" | grep "model-"` steht vor jedem weiteren `model-load whisper` ein `model-free` (`live=` nie größer als 1). Neuladen nach 2 min Hintergrund ist erlaubt.
- [ ] **14.4 Im Hintergrund.** Wendelin verlassen (Home), 3 Minuten warten (das Modell wird nach 2 Minuten im Hintergrund freigegeben). Messung wiederholen, einmal **ohne** und einmal **mit** laufendem Wake-Word-Dienst (Block 10). *Erwartet:* **TOTAL PSS < etwa 200 MB** (mit Dienst im Ruhezustand ohne Whisper; Whisper wird bei Kandidaten kurz geladen).
- [ ] **14.5 Latenz Erkennung.** Satz von etwa 4 s sprechen. Stoppuhr: Ende des Sprechens bis zum sichtbaren Text. *Erwartet:* höchstens etwa 2 s mit Whisper small (Mac-Emulator: Ø 0,5 s, Telefon langsamer). Genauer: `tool/whisper_timing.sh` (siehe `docs/testing/m2-device.md` Abschnitt 8).
- [ ] **14.6 Latenz bis Antwort.** Ende des Sprechens bis zum Beginn der Sprachausgabe („Wie spät ist es?“ mit Standardprofil). Richtwert: unter 5 s.
- [ ] **14.7 Erster Tipp nach Pause.** Telefon 10 Minuten liegen lassen, dann Mikrofon tippen. *Erwartet:* kurz „Moment …“, dann der Ring; der erste Satz geht nicht verloren (nach dem Ring sprechen). Wartezeit bis zum Ring notieren.
- [ ] **14.8 Wake-Word-Latenz.** Vom Ende von „Hey Wendelin“ bis zum geöffneten Overlay (mit Nachprüfung durch Whisper etwa 1 s Zusatz). Stoppuhr, 5 Versuche, Mittel in Tabelle 15.2. Richtwert: unter 2 s.

## 15. Messwerte zum Ausfüllen

### 15.1 Speicher (TOTAL PSS in MB)

| Zustand | Punkt | Soll | Gemessen |
| --- | --- | --- | --- |
| Ruhe im Hauptbildschirm | 14.2 | – | |
| Nach Sprachnutzung (Haupt + Overlay) | 14.3 | ≤ 1100 | |
| Hintergrund, Dienst aus | 14.4 | < 200 | |
| Hintergrund, Wake-Word-Dienst im Ruhezustand | 10.7 / 14.4 | < 200 | |
| Wake-Word-Dienst mit geladenem Whisper (Spitze) | 10.7 | berichten | |
| Modelle gleichzeitig geladen (`live=`) | 14.3 | ≤ 1 | |

### 15.2 Latenz und Prüfzeit (Sekunden)

| Messung | Punkt | Richtwert | Gemessen |
| --- | --- | --- | --- |
| Ende Sprechen bis Text | 14.5 | ≤ 2 | |
| Ende Sprechen bis Beginn Sprachausgabe (Standard) | 14.6 | < 5 | |
| Wartezeit bis Ring nach 10 min Pause | 14.7 | berichten | |
| Wake Word bis Overlay | 14.8 | < 2 | |
| Sprechfassung „Aus“ bis Sprachausgabe | 7.8 | berichten | |
| Sprechfassung „Mit KI-Prüfung“ bis Sprachausgabe | 7.8 | berichten | |
| Erste Phala-Attestierung (Zeitstempel `Wendelin/attest`) | 12.1 | berichten | |
| Zusatzlatenz GPU-Prüfung „Vorher“ | 12.9 | berichten | |

### 15.3 Wake Word, Barge-in, Akku

| Messung | Punkt | Ziel | Ergebnis |
| --- | --- | --- | --- |
| Ausprobieren, 10× „Hey Wendelin“ aus 1 m: Kandidat / bestätigt | 9.5 | ≥ 9 von 10 | / |
| Ausprobieren, Fehltreffer bei anderen Wörtern / Radio | 9.5 | 0 | |
| Kalibrierung: Schwelle, geschätzte Fehlalarme/h | 9.7 | ≤ 1 pro h vor Nachprüfung | |
| Bildschirm aus nach 30 min, 10× „Hey Wendelin, wie spät ist es?“ | 10.4 | ≥ 9 von 10 | |
| Telefon nach Neustart, ohne App zu öffnen | 10.5 | löst aus | |
| Fehlauslösungen in 8 h Alltag (bestätigt/h aus `wake-alive`) | 10.7 | ≤ 1 in 8 h | |
| Kandidaten/h (vor Nachprüfung) | 10.7 | berichten | |
| Akku über 8 h mit laufendem Dienst (Start % → Ende %) | 10.7 | berichten | → |
| „Stopp“ während der Ausgabe, 10× | 11.6 | 10 von 10 | |
| Selbstauslösungen ohne Sprechen (Barge-in) | 11.6 | 0 | |
| Dienst nach 2 h Display aus: vor / nach Akku-Ausnahmen | 10.8 | läuft / läuft | / |

## 16. Aus M3 entfallen

Nichts aus `m3-device.md` ist ersatzlos gestrichen. Geändert, ersetzt oder zusammengelegt wurde:

| M3-Punkt | Jetzt | Grund |
| --- | --- | --- |
| 7.4 „Antwort in zwei Fassungen“ einschalten (Schalter), 7.5 Fallback, 7.7 wieder ausschalten | 7.4 bis 7.9 | Der Schalter heißt nicht mehr so: WP55 ersetzt ihn durch die Einstellung **Sprechfassung** mit vier Stufen (Aus, Immer, Geschützt, Mit KI-Prüfung). Der Fallback (Modell vergisst den Sprechtext) bleibt als 7.7. |
| 1.8 Offline-Regel / Fallback-Annahme | 1.8 bis 1.11 | WP59/K28/K33: Es gibt keine Eskalationsketten und keinen automatischen Anbieterwechsel mehr. Das gewählte Ziel ist bindend; Fehler → Meldung, höchstens 1 Retry beim selben Ziel, „nochmal mit X“ bleibt. Der Punkt prüft jetzt die Fehlermeldung statt eines Wechsels. |
| 9.1, 9.2, 9.4, 9.7 (Standard-Assistent, Hinweise, Ausnahmen, Rückkehr aus Systemseiten) | 0.8, 0.9, 0.9a, 13.4 | Einrichtung steht einmal am Anfang (Assistentenrolle und Akku-Ausnahmen sind auch Voraussetzung für das Wake Word). Die Messung vorher/nachher bleibt in Block 13. |
| `docs/testing/wp56-device.md` (Schritte 1 bis 5) | 0.9, 0.9a, 13.2 bis 13.6 | Zusammengelegt, dieselben Schritte; Schritt 5 (Rückkehr aus den Systemseiten) steht in 0.9a. |
| 0.1 bis 0.7 (Voraussetzungen) | 0.1 bis 0.6 | Zusammengelegt: Testdaten für Bring! stehen in 0.5; Telefon, Mikrofon und Rolle sind neu 0.7 und 0.8. |
| 10.1 bis 10.6 (Gesamtabnahme M3) | Abschnitt „Definition of Done M3 + M4“ | In die gemeinsame Abnahme überführt. |
| 8.1 bis 8.7 (Speicher, Latenz) | 14.1 bis 14.7 | Nur umnummeriert; ergänzt um den Fall „mit laufendem Wake-Word-Dienst“ (14.4). |

## 17. Definition of Done M3 + M4

Quelle M4: `docs/work-packages/M4.md` („Messbare Definition of Done“) und das Konzept. Quelle M3: `docs/work-packages/M3.md`.

**M3**
- [ ] **D3.1** „Claude, …“ geht an das Claude-Profil: 1.4, 1.6 (und 1.7 per Stimme).
- [ ] **D3.2** Ein MCP-Server über Tailscale liefert Tools, ein lesendes läuft, ein zerstörendes fragt nach: 2.3, 2.5, 2.6.
- [ ] **D3.3** Ein HTTP-Tool und Bring! laufen gegen echte Dienste: 3.3, 4.3, 4.4.
- [ ] **D3.4** Sprach-UX und vorlesefreundliche Antworten verhalten sich wie beschrieben: Blöcke 6 und 7.
- [ ] **D3.5** Speicher und Latenz im Rahmen: 14.3, 14.4 (Tabellen 15.1 und 15.2).
- [ ] **D3.6** Power-Taste nach Pause öffnet Wendelin: 13.5.
- [ ] **D3.7** Kein automatischer Anbieterwechsel (WP59): 1.8 bis 1.11.

**M4**
- [ ] **D4.1** Wake-Word-Dienst läuft mit Bildschirm aus (`KEYCODE_SLEEP`), „Hey Wendelin, mach die Taschenlampe an“ bzw. „Hey Wendelin, wie spät ist es“ öffnet das Overlay bzw. führt das Taschenlampen-Tool aus; der Dienst übersteht einen Neustart, wenn Wendelin Standard-Assistent ist. Emulator belegt (WP50, WP54, WP53); Gerät: 8.5, 8.7, 10.4, 10.5.
- [ ] **D4.2** Echtes Gerät (Xiaomi/HyperOS): Wake Word löst mit Bildschirm aus nach 30 min Standby aus, Treffer ≥ 90 % bei 1 bis 2 m ruhig, höchstens 1 Fehlauslösung in 8 h: 10.4, 10.7, Tabelle 15.3; Dienst unter HyperOS: 10.8.
- [ ] **D4.3** Jede Antwort eines Phala-Profils trägt nach Ende des Streams einen Endstatus grün oder rot (gelb nur Zwischenstand): 12.2, 12.4, 12.5; manipulierter Fixture-Fall rot und Live-Test grün: Emulator belegt (WP46, WP52, WP54).
- [ ] **D4.4** Gate grün, APK baut, `tool/check_apk.sh` grün (keine GMS-Klassen): Emulator/CI belegt (WP54), kein Handytest.
- [ ] **D4.5** K11 f / K16: vor dem Entsperren keine Inhalte und keine Sprachantwort an ein Modell, einzige Ausnahme Taschenlampen-Befehle: 8.5, 8.6, 8.7.
- [ ] **D4.6** K14 c: Speicher im Hintergrund unter 200 MB, auch mit laufendem Wake-Word-Dienst: 10.7, 14.4.
- [ ] **D4.7** Keine Audio-Aufnahmen, Transkripte oder Quittungsinhalte im Log: 9.8, 12.8, 12.11 und Sichtprüfung aller `Wendelin/voice`-/`Wendelin/attest`-Zeilen.
- [ ] **D4.8** Gesprächsmodus mit einmaliger Frage nach der ersten Antwort, Einstellung unter Sprache, Barge-in „Stopp“: 11.1 bis 11.8. Emulator belegt (WP45, WP51: Pipeline, Folgefenster, Barge-in mit eingespeister WAV).
- [ ] **D4.9** Persönliches Einlernen, Kalibrieren, Ausprobieren, Nachprüfung (K29): Block 9. Emulator belegt (WP44, WP60: Einlernen mit eingespeister synthetischer Stimme).
- [ ] **D4.10** GPU-Prüfung Aus / Vorher / Nachher (Entscheidung Maintainer 4): 12.9. Emulator belegt (WP46 mit Fake-NRAS).
- [ ] **D4.11** TCB `OutOfDate` rot mit Hinweis (Entscheidung 3): 12.6. Emulator belegt (WP46 Fixture).
- [ ] **D4.12** Taschenlampe als Integration inklusive gesperrtes Gerät (K16): Block 8. Emulator belegt (WP48, WP53 mit Fake-Torch; die echte LED nur am Gerät).
- [ ] **D4.13** Wake Word nur mit Assistentenrolle (Entscheidung 5) und Mikrofon-Indikator „nur beim Laden“ als Standard, wählbar „immer“ (Entscheidung 7): 10.2, 10.3, 10.6.
- [ ] **D4.14** (WP65) Passwortmanager: Beim Antippen von Bring!-Passwort, Anbieter-API-Key, Websuche-Key, MCP-Token/-Header-Wert und HTTP-Tool-Secret erscheint die Autofill-Leiste des Passwortmanagers über der Tastatur (mit Gerät und Manager nennen, z. B. Bitwarden); nach dem Speichern bietet er an, den Eintrag zu sichern. Offen, nur am Gerät prüfbar.
- [ ] **D4.15** (WP65) Prüfprotokoll nur über „Prüfprotokoll ansehen“ (Datenschutz und Logs; Anbieter-Einrichtung nach dem Test), keine Liste inline. Hauptmenü ohne Obsidian/Listen/Web-Suche/Gedächtnis (nur unter Integrationen).
- [ ] **D4.16** (WP65) Aktivierungswort ohne geladene Modelle: Hinweis „Dafür muss zuerst das Sprachmodell geladen werden“ mit Button „Sprachmodell laden“, Einlernen/Kalibrieren/Ausprobieren gesperrt, nach dem Laden frei.

## Aufräumen

- MCP-Test-Server beenden (Strg+C), `tailscale serve reset`, falls Weg B benutzt wurde.
- In Wendelin: MCP-Server, HTTP-Tools und Bring!-Login löschen, wenn das Testkonto nicht bleiben soll; Testtermine im Kalender und Testnotiz im Vault löschen; Phala-Profil behalten oder löschen.
- Wake-Word-Dienst ausschalten, wenn er nicht bleiben soll; bei Bedarf „Alle Stimmen löschen“.
- Telefon-Uhr wieder auf automatisch (falls für 12.5 verstellt), GPU-Prüfung auf **Aus**, Sprechfassung auf gewünschter Stufe.
- Die Test-Keys bei Anthropic und Phala widerrufen, falls sie nur für diesen Test angelegt wurden.

## Ergebnis zurückmelden

Pro Punkt: Haken oder ein Satz, was stattdessen passierte. Zusätzlich: Gerät und Android-Version, die ausgefüllten Tabellen 15.1 bis 15.3, die Texte aus 7.1 bis 7.8, die Ausgabe von `tool/diag_assistant_idle.sh` bei Fehlversuchen in 13.3 oder 13.5, Logauszüge aus `Wendelin/voice` (nur `wake-*`, `conv-exit`, `barge-in`, `model-*`) und `Wendelin/attest` bei Auffälligkeiten, und Screenshots von auffälligen Bildschirmen (ohne Keys und ohne Inhalte). Der Maintainer trägt Abweichungen als Befunde ein. 
