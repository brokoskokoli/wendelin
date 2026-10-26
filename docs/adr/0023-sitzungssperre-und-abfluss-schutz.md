# ADR 0023 – Sitzungssperre und Abfluss-Schutz (WP157)

Status: angenommen · 2026-10-26

## Kontext
Zwei Lücken aus dem Projekt-Review vom 2026-10-26:

1. **Sperre nach roter Quittung** (K44/K46/K70): `RiskPolicy.lockExternal` wurde nie gerufen. Die Sperre lebte nur in `AttestedProvider._lock` im Speicher einer Engine; Neustart unter 5 Minuten, Provider-Wechsel und Neuaufbau der Engine hoben sie auf (`adoptSessionOf` übernimmt sie nicht), `pinChanged` setzte nur `_session = null`. Belegt durch `app/test/agent/session_lock_test.dart` („ohne Speicher“). Die Overlay-Einladung allein ist kein Loch, sie beginnt immer eine frische Sitzung.
2. **Abfluss über Lesewerkzeuge:** Nach fremden Inhalten (Web, Mails, Einladungen, MCP) liefen `read`-Werkzeuge mit Netzziel ohne Rückfrage; eingeschleuste Anweisungen konnten private Daten als Parameter hinausschicken.

## Entscheidung
**Sperre je Unterhaltung (Sitzungs-ID), persistiert.**
- Eine Stelle sperrt: `AttestationGate.settle` ruft bei roter Quittung (auch geänderter Anbieter-Schlüssel, `pinChanged` = rot) über `SessionLockable.lockExternal(sessionId, profileId:)` den `ToolExecutor`, der `RiskPolicy.lockExternal` ruft. Gelb/unbestätigt sperrt nicht (nur nicht prüfbar, kein Nachweis eines Fehlers).
- Die Sperre steht im `SessionLockStore` (`SettingsSessionLockStore`, Einstellung `security.sessionLocks`: Sitzung → Profil-Id, höchstens 50 Einträge, ältester fällt zuerst heraus). Sie überlebt Engine-Neuaufbau und App-Neustart.
- Ende: die Unterhaltung endet (`endSession`) oder der Nutzer prüft den Anbieter neu und die Prüfung wird grün (`AttestationHub.onRecheckedGreen` → `unlockProfile(profileId)` hebt alle Sperren dieses Profils).
- **Fail-closed:** ist der Speicher nicht lesbar oder beschädigt (Nicht-String), gilt jede Sitzung als gesperrt (`isExternalLocked`), nie als ungesperrt. Schreibfehler halten die Sperre im Speicher und verlieren sie nur für den nächsten Start.
- Toter Code: die Sperre in `AttestedProvider` bleibt nur als Sofortschutz der Anfrage; maßgeblich ist die Policy.

**Rückfrage nach fremden Inhalten (Abfluss-Schutz).**
- `untrustedSeen` zählt über den Verlauf, nicht nur im Lauf: die Injektion bleibt im Kontext des Modells. Das Fenster ist `AgentConfig.historyTurns` (10 Turns); ältere Ergebnisse fallen auch aus dem Modellkontext, eine neue Unterhaltung (leerer Verlauf) setzt zurück.
- Jedes Tool ohne `NoNetworkTarget` (fail-closed: unbekannt = Netzziel) wird danach zur Rückfrage gehoben, die Karte zeigt Ziel und Argumente. Das gilt **zusätzlich zur Stufe** (ADR 0022): die Rückfrage ist ein Minimum, die Stufe ergänzt nur. **Stufe A hebt sie nicht auf** (das Strengere gewinnt); bei gesperrtem Gerät führt sie wie Stufe D zu „Entsperren“. Ein Override `deny` und die Sitzungssperre bleiben vorrangig.
- **Gesperrte Sitzung und Fremdes:** ist die Sitzung gesperrt (rot/`pinChanged`) **und** wurden fremde Inhalte gesehen, ist ein Netz-Tool **hart gesperrt**, nicht nur zu bestätigen, auch bei einer späteren grünen Quittung (Entscheidung Maintainer; das Strengere gewinnt). Ohne Fremdes bleibt ein `read`-Tool in gesperrter Sitzung wie bisher erlaubt. Zusätzlich wartet ein Netz-Tool nach Fremdem (`effectiveRisk` = `external`) bei TEE auf die grüne Quittung der anfordernden Antwort.
- **Was fremd ist** (`ContentTrustAware`/`ResultTrustAware`, Tabellen `app/test/trust/*.json`): Notizen, Listen, Aufgaben, Einkauf, eigene und strukturierte Daten (Ort, Medien, Wetter, Alarme …) sind sicher; Websuche ist immer fremd; HTTP-GET-Tools und MCP-Server tragen den Haken „Kann unsichere Inhalte enthalten“ (Standard an, Nutzer darf je Tool/Server abschalten). `tools__search` ist fremd nur bei Treffern von MCP/HTTP mit Haken, bei unbekannter Herkunft fail-closed fremd. Restrisiko: frei formulierte Texte Dritter in Kalender, Kontakten, HA-Namen und Spotify-Titeln gelten als sicher (Grenzfall `spotify__search`).

## Alternativen
- Sperre je Provider (wie vorher): nicht tragfähig, ein Wechsel des Anbieters in derselben Unterhaltung umgeht sie.
- Rückfrage nur im Lauf: der Verlauf trägt die Injektion in den nächsten Lauf, deshalb Verlauf.
- Stufe A als Ausnahme von der Rückfrage: würde den Schutz mit einem Klick aufheben.

## Folgen
- Abweichungen vom Konzept (Orchestrator trägt ein): K122 Sperre je Sitzung statt je Provider; Fremd-Einstufung neu (lockert WP41); Netzziel-Rückfrage.
- Beide Engines (App, Overlay) speichern je ihren Snapshot, der letzte Schreiber gewinnt. Sperr-Einträge beendeter Sitzungen bleiben bis zum Limit stehen, wenn die App beim Ende nicht lief.
- Nicht Teil: Sitzungsdauer/SessionManager (separat).
