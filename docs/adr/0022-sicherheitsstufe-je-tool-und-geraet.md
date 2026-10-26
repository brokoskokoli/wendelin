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
- **Home Assistant je Gerät** (`ha_policy.dart`): `haDefaultLevel` liefert die Standardstufe aus Domäne, Live-Klasse und K57-Szenenart, `haEffectiveLevel` die geltende Stufe, `haDecide` die Entscheidung. Die Tools `ha__call` (nimmt `allowed`) und `ha__call_secure` (nimmt `confirm`) wählen nach dem Ergebnis, nicht nach der Domäne; eine Stufe A–C auf dem Schloss läuft also über `ha__call` ohne Rückfrage (ohne Undo, `planHaUndo` kennt kein Schloss/Alarm). Die HA-Aufruf-Tools bekommen **keine** Tool-Stufe (sie würde die Gerätestufe umgehen); nur das alte „immer bestätigen“ bleibt dort wirksam (D).
- **Dieses Paket (L1) lässt gesperrt unverändert:** Die Tabelle deckt Sperre × Stimme ab und ist getestet, aber niemand ruft sie mit `locked: true` auf. Gesperrt-Pfad = L2, Sprecher = L3. `HaIntegration.allowedWhileLocked` fragt die Tabelle mit „gesperrt, Stimme erkannt“ (Hook, weiter ohne Aufrufer; `IntegrationSpec.allowedWhileLocked` bleibt `false`).

### Herleitung: welche Stufe entspricht heute jedem HA-Gerät
Entsperrt ohne Rückfrage lief nur, was `ha__call` bekam (`haOpenServices`); `ha__call_secure` fragt. Gesperrt lief HA gar nicht (`HaIntegration.allowedWhileLocked` ohne Aufrufer, `LockGateAgentRun` kennt nur die Taschenlampe). „B“ ist der Plan für L2/L3 (Hook `haLockSafeDomains`: Licht, Szene, Medien).

| Gerät | entsperrt heute | gesperrt heute | Standardstufe |
|---|---|---|---|
| Licht | ohne Rückfrage, Undo | läuft nicht (Hook: erlaubt) | B |
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

## Folgen
- UI: je Gerät und je Tool ein eingeklappter, eingerückter, kleinerer Reiter „Details“ (`SecurityLevelPicker`) mit Stufe als Kurztext, Auswahl A–D mit je einer Erklärungszeile, Standard/geändert und „Standard wiederherstellen“. Beim Umstellen von Schloss, Alarm, Tor/Tür (HA) auf A/B und von `external`-Tools auf A–C kommt einmal ein deutlicher Hinweis.
- Eine Szene mit kritischem Mitglied, die der Nutzer selbst auf A–C stellt, läuft ohne Bestätigung (Nutzerentscheidung).
- Die Sperrbildschirm-Logik (L2) und die Sprecherzuordnung (L3) rufen `levelAccess`/`haDecide` mit `locked`/`speakerRecognized`; sie dürfen keine zweite Tabelle bauen.
- K8 b („Risiko nur verschärfbar“) entfällt als Regel; Konzepteintrag über den Orchestrator.
