# ADR 0022 – Sicherheitsstufe je Tool und je Home-Assistant-Gerät (WP154)

Status: angenommen · 2026-10-26

## Kontext
Bisher gab es zwei grobe Mittel: das Risiko des Tools (`read`/`write` laufen frei, `external` fragt immer, Nutzer konnte nur verschärfen, K8 b) und bei Home Assistant die Schalter „ohne Rückfrage“ (nur Rollos) und „immer bestätigen“. Gesperrt-Betrieb und Sprecherkennung (WP92) brauchen eine Abstufung „wer darf wann“. Der Maintainer hat am 2026-10-26 entschieden: Stufen A–D gelten für **jedes** Tool (und für HA je Gerät), ohne globalen Schalter und ohne feste Obergrenze je Domäne; die Verantwortung liegt beim Nutzer.

## Entscheidung
Vier Stufen (`SecurityLevel`, `packages/wendelin_core/lib/src/safety/security_level.dart`) und **eine** reine Funktion `levelAccess(Stufe, locked, speakerRecognized)`:

| Stufe | entsperrt | gesperrt, Stimme erkannt | gesperrt, andere/keine Stimme |
|---|---|---|---|
| A | erlaubt | erlaubt | erlaubt |
| B | erlaubt | erlaubt | entsperren |
| C | erlaubt | entsperren | entsperren |
| D | Bestätigung | entsperren | entsperren |

- **Fail-closed:** fehlende Stufe in der Funktion = D; eine gespeicherte Stufe, die nicht `a`..`d` ist (manipuliert, kaputt, kein String), zählt als D und **nie** als Standard (`SecurityLevel.effective`). Nur ein *fehlender* Eintrag nimmt den Standard.
- **Standard = Empfehlung = heutiges Verhalten.** Tools: `read`/`write` = C, `external` = D (`RiskPolicy.defaultLevelFor`). Der Nutzer überschreibt je Tool frei (auch `external` auf A–C: das hebt K8 b auf, ausdrücklich). Vorbehalte bleiben unabhängig von der Stufe: ein vom Nutzer deaktiviertes Tool (`setOverride(deny)`) und die Sitzungssperre `lockExternal` (nicht verifizierte TEE-Antwort) verweigern weiter.
- **Home Assistant je Gerät** (`ha_policy.dart`): `haDefaultLevel` liefert die Standardstufe aus Domäne, Live-Klasse und K57-Szenenart, `haEffectiveLevel` die geltende Stufe, `haDecide` die Entscheidung. Die Tools `ha__call` (nimmt `allowed`) und `ha__call_secure` (nimmt `confirm`) wählen nach dem Ergebnis, nicht nach der Domäne; eine Stufe A–C auf dem Schloss läuft also über `ha__call` ohne Rückfrage (ohne Undo, `planHaUndo` kennt kein Schloss/Alarm). `ha__call_secure` nimmt zusätzlich jedes Gerät mit `allowed` (nur strenger: es fragt trotzdem), damit eine bestätigte Karte nie in einen Fehler läuft. Die HA-Aufruf-Tools bekommen **keine** Tool-Stufe (sie würde die Gerätestufe umgehen); ein altes „immer bestätigen“ (D) auf ihnen bleibt wirksam und wird bei der Migration **nicht** verworfen (das würde das Tool still lockern). Es ist in den Einstellungen sichtbar durch „Altes ‚Immer bestätigen‘ entfernen“ entfernbar; erst dann entscheidet allein die Gerätestufe. Gesperrt gilt dasselbe: eine gespeicherte Tool-Stufe auf `ha__call` zählt zusätzlich zur Gerätestufe (die strengere gewinnt), gesperrt ist nie lockerer als entsperrt. Der freie Persona-Zusatz geht gesperrt wie der Nutzername nicht an den Anbieter.
- **Gesperrt ist ab L2 angeschlossen** (Abschnitt „L2 Gesperrt“ unten). Sprecher = L3 (Abschnitt „L3 Stimme“ unten): `speakerRecognized` kommt je Anfrage aus der Sprechererkennung (bis L2 fest `false`). `HaIntegration.allowedWhileLocked` bleibt als Hook, `IntegrationSpec.allowedWhileLocked` bleibt `false`.

### Herleitung: welche Stufe entspricht heute jedem HA-Gerät
Entsperrt ohne Rückfrage lief nur, was `ha__call` bekam (`haOpenServices`); `ha__call_secure` fragt. Gesperrt lief HA vor L2 gar nicht (`LockGateAgentRun` kannte nur die Taschenlampe). „B“ gilt erst mit erkannter Stimme (L3) (Hook `haLockSafeDomains`: Licht, Szene, Medien).

| Gerät | entsperrt heute | gesperrt heute | Standardstufe |
|---|---|---|---|
| Licht | ohne Rückfrage, Undo | läuft nicht (mit L2 nur auf A) | B |
| Medien | ohne Rückfrage, Undo | läuft nicht (Hook: erlaubt) | B |
| Szene, Mitglieder bekannt und unkritisch | ohne Rückfrage, Undo | läuft nicht (Hook: erlaubt) | B |
| Szene, Mitglieder unbekannt (z. B. Hue) | ohne Rückfrage | läuft nicht (Hook: nein) | C |
| Szene mit Schloss, Alarm, Rollo, Gruppe oder Mitglied auf D (K57) | Bestätigung | nein | D (je Aufruf aus dem Live-Zustand) |
| Schalter, Heizung | ohne Rückfrage, Undo | nein | C |
| Rollo mit „ohne Rückfrage“ und Live-Klasse blind/shade/shutter/awning/curtain | ohne Rückfrage, Undo | nein | C |
| Rollo sonst, Garage, Tor, Tür, Klasse fehlt | Bestätigung | nein | D |
| Schloss, Alarmanlage | Bestätigung | nein | D |
| beliebiges Gerät mit „immer bestätigen“ | Bestätigung | nein | D |
| nicht steuerbare Domäne | nur lesen | nur lesen | D (fail-closed) |

Migration: kein Umschreiben. Die alten Felder (`confirm` = `alwaysConfirm`, `quiet` = `noConfirm`) bleiben im Speicher und fließen in den Standard ein (`haDefaultLevel`); ein fehlender `level`-Eintrag heißt „Standard“. Erst wenn der Nutzer eine Stufe wählt, wird `level` geschrieben und die alten Flags werden gelöscht (`HaEntity.withLevel`); „Standard wiederherstellen“ löscht auch `level` und damit den Rest. Beim Rollo gilt weiter der **Live-Zustand** (`device_class`), nicht die gespeicherte Klasse; eine **gewählte** Stufe gilt dagegen unabhängig von der Klasse (Entscheidung des Maintainers: keine Obergrenze). Tools: `ToolPrefs.alwaysConfirm` zählt als D für ein Tool ohne Eintrag in `levels`.

## L2 Gesperrt (WP154 Lieferung 2)
Gesperrt (und Stimme unbekannt, L3 steht aus) läuft nur, was die Tabelle `levelAccess` für „gesperrt, andere/keine Stimme“ erlaubt, also **Stufe A**. Alles andere antwortet „Entsperren nötig“ (fester Satz, kein Modelltext) und bietet das Entsperren an.
- **Eine Tabelle:** `RiskPolicy.decide(..., access: AccessContext)` und `ToolExecutor` fragen `levelAccess`; HA entscheidet je Gerät über `haDecide(..., access)`. `ha__call_secure` läuft gesperrt nie (Bestätigung auf dem Sperrbildschirm gibt es nicht). Fehlt der Kontext, gilt entsperrt wie bisher; ein gesperrter Kontext ohne Berechtigung = verweigern (fail-closed).
- **Standard bleibt das heutige Verhalten:** Taschenlampe `on`/`off` haben Standard **A** (`DefaultLevelTool`; sie ändern nur die Lampe dieses Telefons, lesen und senden nichts, wirken sofort sichtbar und heben sich auf), `toggle` bleibt C. Alle anderen Tools und HA-Geräte haben Standard B bis D und laufen gesperrt nicht, solange der Nutzer nichts ändert. HA-Licht auf A ist die Wahl des Nutzers (Beispiel im Gerätetest).
- **Entscheidung a, keine Doppelausführung:** `LockGateAgentRun` sammelt über den ganzen Modelllauf, ob etwas erledigt und ob etwas verweigert wurde. Erst erledigt, dann verweigert (oder umgekehrt) bietet das Entsperren für den **Rest** an (`onPartlyDone`, Audit `lockedRefused`); die Anfrage wird **nicht** gemerkt, sonst liefe das schon Erledigte nach dem Entsperren ein zweites Mal. Der Nutzer sagt den Rest neu. Wurde nichts erledigt, bleibt das Merken (K85, 30 s) wie bisher. Folge: Bricht der Nutzer den Stream mitten ab, entfällt dieses Angebot (fail-closed, aber ohne Hinweis).
- **Entscheidung b, kein Nutzername gesperrt:** Der Prompt eines gesperrten Laufs enthält den Namen nicht (`config.withUserName(null)`); er ginge an den Anbieter, ohne dass jemand entsperrt hat.
- **Entscheidung c, Modell nur über die lokalen Befehle hinaus:** `lockedScopeProvider` liefert nur dann einen Modelllauf, wenn die erlaubten Tools mehr sind als `lockedCommandTools` (`flashlight__on`/`off`). Sonst bliebe es beim lokalen Befehl ohne Modell: Läge schon die Taschenlampe auf A als Grund für einen Modelllauf, ginge jede gesperrte Frage („Wie wird das Wetter?“) an den Anbieter, obwohl das Modell nichts als die Lampe dürfte. Das Standardverhalten (K16/K30) bleibt so erhalten. Der Preis: ein Nutzer, der nur die Lampe hat, bekommt für Sätze, die der Befehlserkenner nicht trifft, „Bitte entsperre das Telefon“.
- **Kontextquellen im gesperrten Lauf (`LockedScope`, `LockedCatalog`):** Das Modell sieht nur die erlaubten Tool-Specs (Zielanbieter mit der niedrigsten Datenschutzstufe, K10), nur deren Promptabschnitte (bei HA nur Geräte auf A, keine `list_entities`), keinen Verlauf (nicht gelesen, nichts gespeichert), keine Erinnerungen außer `memory__search`, falls erlaubt, und keinen Nutzernamen. `lookup` findet weiter alles, damit ein erfundener Toolname sauber abgelehnt wird (`Executor` prüft ohnehin). Audit kennzeichnet `whileLocked`.
- **Zeitgrenze:** Ein hängender Torch-Aufruf bricht nach 20 s ab (Test `FakeTorchPort.hangs`).
- **Konzeptabweichungen (Meldung, der Orchestrator trägt ein):** K85 (Freigabeliste je Tool/Gerät nach Stufe statt fester Liste; Taschenlampe A, toggle C), K92 (Modell gesperrt nur mit erlaubten Tools über die lokalen Befehle hinaus; Merk-Anfrage nur, wenn nichts lief), K8 b (Stufe statt „nur verschärfbar“, schon L1).
- **Bekannte Grenzen:** Der gesperrte Modelllauf registriert Undo-Karten, der alte lokale Befehlspfad nicht. `lockedScopeProvider` nimmt `providers.lowestPrivacy`; der Anbieter, der dann antwortet, ist derselbe.

## L3 Stimme (WP154 Lieferung 3)
Gesperrt zählt die Stimme je Anfrage: `AccessContext.lockedFor(UserInput)` (`security_level.dart`) setzt `speakerRecognized` nur, wenn die Eingabe **gesprochen** ist (`InputSource.voice`) **und** eine Personen-Id trägt (`UserInput.speakerId` = `SpeakerMatch.known`, `voice_pipeline.dart` `_answer`). Alles andere ist „fremd“ und damit fail-closed: getippt, Erkennung aus (`VoiceComponents.speaker == null`), keine Profile, unbekannt (unter Schwelle), zu kurz, mehrdeutig, Fehler des Embedders, Zeitlimit (`speakerTimeout` 3 s) und leere Id.
- **Der Weg ist derselbe wie entsperrt:** Wake über den Sperrbildschirm, Overlay und Push-to-talk laufen durch dieselbe `VoicePipeline` (`voice_controller.dart` baut sie mit `components.speaker` und `lockGateFor`); die Erkennung läuft parallel zur STT auf dem Audio der Äußerung. `LockGateAgentRun._locked` bildet daraus **je Anfrage** den `AccessContext` und gibt ihn an `runCommand` (Taschenlampe, Policy und Executor) und an `lockedScopeProvider` (Umfang des Modelllaufs) weiter. Es gibt keine zweite Tabelle; der Umfang wird je Anfrage neu berechnet, nie gemerkt.
- **Wirkung:** Stufe-B-Tools und -Geräte (Standard von Licht, Medien, unkritischen Szenen) laufen gesperrt nur mit erkannter Stimme; mit fremder Stimme „Entsperren nötig“. Ein Nutzer, der nur Geräte auf B hat, bekommt ohne Stimme weiter keinen Modelllauf (`lockedCommandTools` ist die Untergrenze, Entscheidung c). C und D laufen gesperrt nie, das Schloss (Standard D) also mit keiner Stimme.
- **Bestätigter Standard:** Licht, Medien und unkritische Szenen bleiben B (Maintainer 2026-10-26); die Herleitungstabelle oben gilt unverändert, nur die Spalte „gesperrt“ wird mit erkannter Stimme wirksam.
- **Kein Sitzungswechsel gesperrt:** Eine gesperrte Anfrage ändert weder Sitzung noch gemerkten Umfang (`AgentController._sessionFor(locked: true)`). Die offene Unterhaltung endet weder durch eine andere erkannte Person noch durch eine fremde Stimme. Der Umfang kommt nur aus der Anfrage selbst: erkannte Person = ihr Personenbereich (Standardziel, `memory__search` im Namespace der Person, falls erlaubt), fremd = Standard; nie der Umfang der offenen Unterhaltung. Verlauf wird weiter nicht gelesen oder gespeichert.
- **Grenze der Stimme (ausdrücklich):** Sprechererkennung ist keine sichere Anmeldung. Eine Aufnahme der Stimme (Wiedergabe, Anruf, Video) oder eine ähnliche Stimme kann sie täuschen; die Schwelle begrenzt Fremde, beweist aber keine Identität. Darum erlaubt B nur, was bei einem Fehlgriff verkraftbar ist (Licht, Medien, unkritische Szenen); was Schaden anrichtet (Schloss, Alarm, Tor, Nachrichten, Geld), bleibt D oder wird vom Nutzer bewusst gewählt, und dann liegt die Verantwortung bei ihm (Hinweis beim Umstellen, L1). Stufe A stützt sich nie auf die Stimme.
- **Bekannte Grenzen:** Lädt das Erkennungsmodell beim ersten Satz länger als 3 s, gilt die Stimme für diese Anfrage als fremd (fail-closed, der Nutzer entsperrt oder wiederholt). Die erste Messung der Falschannahme-Rate je Schwelle steht im Gerätetest (`docs/testing/m5/wp154.md`).

## Folgen
- UI: je Gerät und je Tool ein eingeklappter, eingerückter, kleinerer Reiter „Details“ (`SecurityLevelPicker`) mit Stufe als Kurztext, Auswahl A–D mit je einer Erklärungszeile, Standard/geändert und „Standard wiederherstellen“. Beim Umstellen von Schloss, Alarm, Tor/Tür (HA) auf A/B und von `external`-Tools auf A–C kommt einmal ein deutlicher Hinweis. Ebenso beim Lockern eines Tools einer als sensibel markierten Integration (liest oder ändert persönliche Inhalte: Kalender, Kontakte, Gedächtnis, Notizen in Obsidian, Zwischenablage, Ort, Medien …) auf A oder B (`warnLevelsOf`); Taschenlampe und unkritische HA-Geräte bekommen keinen. Offen: Listen, Aufgaben, Bring sind nicht als sensibel markiert und warnen nicht.
- Eine Szene mit kritischem Mitglied, die der Nutzer selbst auf A–C stellt, läuft ohne Bestätigung (Nutzerentscheidung).
- Die Sperrbildschirm-Logik (L2) und die Sprecherzuordnung (L3), beide umgesetzt, rufen `levelAccess`/`haDecide` mit `locked`/`speakerRecognized`; sie dürfen keine zweite Tabelle bauen.
- K8 b („Risiko nur verschärfbar“) entfällt als Regel; Konzepteintrag über den Orchestrator.
