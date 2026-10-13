# WP36 – R2: Gemeinsame Bausteine – Netzziel-Prüfung, Text-Faltung, Namenskollision (`wendelin_integrations`, `wendelin_core`, `wendelin_mcp`, `wendelin_agent`, `wendelin_storage`)

Abhängig von: **WP35** (Größen-Check, `--changed`, Messwerte). Teil b zusätzlich nach dem Merge von **WP27**, Teil c nach dem Merge von **WP33**. Übersicht und Grundregeln: `R-refactoring.md` (verhaltensneutral). Bezug: Gutachten **M2** (SSRF-Prüfung dreifach), **M3** (Text-Faltung dreifach), **M4** (`MemoryEntry` in zwei Paketen), **N1** (doppelter SSE-Parser-Test). Andockpunkte: `packages/wendelin_integrations/lib/src/web/fetch_guard.dart` (`HostResolver`, Adressklassen um :100–113), `…/http_tools/http_target.dart` (:15–67), `packages/wendelin_mcp/lib/src/net_policy.dart` (:67–88), `packages/wendelin_integrations/lib/src/common/matching.dart` (`normalizeText`, `foldText`, `bestMatches`), `packages/wendelin_agent/lib/src/routing/routing_text.dart` (:147–164), `packages/wendelin_mcp/lib/src/tools/naming.dart` (:28–31), `packages/wendelin_storage/lib/src/model/memory_entry.dart`, `packages/wendelin_integrations/lib/src/memory/memory.dart`, `app/lib/platform/repository_memory_port.dart` (Präfix-Importe), `packages/wendelin_providers/test/sse/sse_parser_test.dart`. ADR 0011 (HTTP-Tools und Netzziele).

## Schnitt in Teil-Merges

| Teil | Inhalt | Start |
| --- | --- | --- |
| a | Netzziel-Kern in `wendelin_integrations`, `fetch_guard` und `http_target` darauf; `MemoryEntry`-Umbenennung; SSE-Testduplikat | nach WP35 |
| b | `wendelin_mcp/src/net_policy.dart` auf den Kern | nach WP27-Merge (WP27 nutzt `net_policy` in der App) |
| c | Text-Faltung in `wendelin_core`, Umstellung von Listen/Obsidian-Matching, Routing und Kommentar in MCP-Naming | nach WP33-Merge (WP33 baut die phonetische Titelsuche auf `foldText`) |

## Inhalt

**Netzziel-Prüfung (M2), Teil a und b**
- Neue Datei `packages/wendelin_integrations/lib/src/common/net_scope.dart`. Sie liegt in `wendelin_integrations`, weil sie `InternetAddress` (`dart:io`) braucht und `wendelin_core` frei von `dart:io` ist; `wendelin_mcp` darf `wendelin_integrations` nutzen. Inhalt:
  - `AddressScope classify(InternetAddress a)` mit einer Klasse je Bereich (z. B. `loopback`, `private` (RFC 1918, `fc00::/7`), `carrierNat` (`100.64.0.0/10`, Tailscale), `linkLocal` (`169.254/16`, `fe80::/10`), `unspecified`, `multicast`, `public` …). Die Klassen ergeben sich aus der Vereinigung dessen, was die drei Stellen heute unterscheiden.
  - `isLoopbackHost(String host)`, `HostResolver` (zieht aus `fetch_guard.dart` um, dort weiter exportiert).
- `fetch_guard`, `http_target` und `net_policy` behalten **nur ihre Policy** (welche Klassen erlaubt sind, welche Fehlermeldung kommt) und fragen die Klasse beim Kern ab.
- **Verhaltensneutral heißt hier:** Für jede Adresse ergibt jede der drei Policies dasselbe Ergebnis wie vorher. Findet der Coder eine Adresse, bei der sich die drei heute widersprechen (z. B. IPv4-mapped IPv6 `::ffff:10.0.0.1`, `0.0.0.0`, `::`), bleibt das bisherige Ergebnis je Policy erhalten. Der Widerspruch kommt mit Vorschlag in den Abschlussbericht. Eine Verschärfung ist ein eigenes Sicherheits-Fix-Paket mit Regressionstest, kein Teil dieses Refactorings.
- **Contract- bzw. Tabellentest** `wendelin_integrations/lib/testing/net_scope_contract.dart` oder Tabellentest im Paket: je Bereich Grenzfälle (erste/letzte Adresse, ±1 außerhalb), IPv4 und IPv6, mapped-Adressen. Dazu je Policy ein **Vergleichstest**, der die bisherige und die neue Entscheidung für dieselbe Adressliste vergleicht. Er wird vor dem Umbau gegen den alten Code geschrieben und läuft danach unverändert.

**Text-Faltung (M3), Teil c**
- Neue Datei `packages/wendelin_core/lib/src/text/fold.dart` mit `String foldForMatch(String s)` und **dokumentierter Semantik** (Doc-Kommentar und Tabelle im Test): Kleinschreibung, Umlaute und Diakritika, Ligaturen (`ß`, `æ`, `ø`, `œ`), Bindestrich/Unterstrich/Leerraum, Satzzeichen. Die Tabelle entsteht aus den heutigen drei Varianten (`matching.dart` `normalizeText`/`foldText`: ä→a, zusätzlich ae→a; `routing_text.dart`: eigene Tabelle mit æ→ae, ø→o).
- `matching.dart` und `routing_text.dart` nutzen `foldForMatch`. `stemWord`, `matchScore` und `bestMatches` bleiben in `wendelin_integrations`, nur die Faltung zieht um.
- `wendelin_mcp/src/tools/naming.dart` bleibt **bewusst** bei ä→ae (Tool-Namen müssen stabil bleiben, sonst ändern sich Tool-Namen in Registry, Regeln und Audit-Log). Ein Kommentar dort verweist auf `foldForMatch` und erklärt die Ausnahme.
- **Verhaltensneutral:** Alle bestehenden Matching-, Routing- und Obsidian-Tests bleiben unverändert grün. Weichen die Varianten bei einzelnen Zeichen ab (z. B. æ: `ae` im Routing gegen `a`/`ae` in Listen), wird je Aufrufer das bisherige Ergebnis beibehalten. Erlaubt ist dafür ein benannter Schalter oder eine zweite benannte Variante in `fold.dart`. Die Liste der Abweichungen steht im Abschlussbericht. Eine Vereinheitlichung mit Verhaltensänderung braucht die Zustimmung des Maintainers und ein eigenes Paket.
- **Abstimmung mit WP33 und WP31:** WP36 c startet nach dem Merge von WP33 und stellt dessen phonetische Titelsuche (`resolveNote`, Trefferarten) mit um. Baut WP33 vorher eine neue Faltung oder einen phonetischen Schlüssel, legt es die reine Faltung bereits als `foldForMatch` in `wendelin_core/lib/src/text/fold.dart` mit Tabellentest an; WP36 c zieht dann nur noch Routing und Listen nach. WP31 (B8, gefalteter Titelvergleich) nutzt, was zum Zeitpunkt seines Starts auf `main` ist. Wer zuletzt merged, gleicht ab.

**Namenskollision `MemoryEntry` (M4), Teil a**
- Das Storage-Modell wird umbenannt: `MemoryEntry` → `StoredMemory`, `MemoryCategory` → `StoredMemoryCategory` (in `wendelin_storage`). Das Domänenmodell in `wendelin_integrations` behält den Namen, weil Tools und Ports es nutzen. Datenbankschema, Spaltennamen und gespeicherte Kategorie-Werte bleiben gleich (keine Migration).
- `app/lib/platform/repository_memory_port.dart` und alle anderen Präfix-Importe (`as wi` / `as st`) werden ohne Präfix lesbar. Doppelte Felddefinitionen bleiben getrennt, sind aber über die Abbildung im Port-Adapter getestet.
- Alternativ (nur mit Begründung im Bericht): Domänenmodell nach `wendelin_core`. Das ist größer und nur sinnvoll, wenn beide Modelle feldgleich sind.

**SSE-Testduplikat (N1), Teil a**
- `packages/wendelin_providers/test/sse/sse_parser_test.dart` entfällt. Fälle, die es nur dort gibt (z. B. `fake_server`-Fälle), ziehen nach `packages/wendelin_core/test/sse/`. Die Abdeckung von `wendelin_core` bleibt gleich oder steigt. Die Testanzahl in providers sinkt um genau die Duplikate (im Bericht belegt).

## Abnahmekriterien
- [ ] Verhaltensneutral: keine Änderung an Nutzertexten, Fehlermeldungen, Tool-Namen, Datenbankschema. Alle bestehenden Tests unverändert grün (geänderte `expect`-Zeilen nur bei Typumbenennung, einzeln begründet). Keine Goldens berührt.
- [ ] Netz (a, b): genau eine Stelle klassifiziert Adressbereiche (`grep` auf `100.64`, `fc00`, `fe80`, `192.168` unter `lib/` findet nur `net_scope.dart`). Tabellentest mit Grenzfällen je Bereich. Vergleichstest je Policy (alte und neue Entscheidung identisch) für mindestens 40 Adressen inkl. IPv6 und mapped-Adressen. Widersprüche zwischen den alten Policies im Bericht.
- [ ] Faltung (c): `foldForMatch` mit Semantik-Tabelle im Test. `matching.dart` und `routing_text.dart` nutzen sie. MCP-Naming mit Ausnahme-Kommentar. Liste der Zeichen mit abweichendem Altverhalten im Bericht. Bestehende Routing-, Listen- und Obsidian-Tests unverändert grün.
- [ ] `MemoryEntry`/`MemoryCategory` gibt es nur noch in `wendelin_integrations`. Keine Präfix-Importe mehr für diese Typen in `app/`. Kein Schema-Diff (`*.steps.dart`, `drift_schemas` unverändert).
- [ ] SSE-Parser-Test nur noch in `wendelin_core`.
- [ ] Mutationsproben (je Teil ≥ 5) gegen die verschobenen Invarianten: z. B. Grenze `100.64.0.0/10` ±1, `fe80::/10` als öffentlich, Loopback-Erkennung umgedreht, Policy erlaubt `private` für Web-Abruf, Faltung lässt Umlaut stehen, Routing-Variante faltet æ anders. Jede Mutation macht einen Test rot.
- [ ] Abdeckung je berührtem Paket nicht niedriger als vorher, Gate grün (voll).
- [ ] Diff je Teil ≤ ca. 1 500 Zeilen Produktivcode. Reine Verschiebungen ausgewiesen.
- [ ] Messwerte vorher/nachher im Bericht: Zahl der Implementierungen der Adressklassifikation (3 → 1) und der Faltung (3 → 1 plus dokumentierte MCP-Ausnahme), Zeilen der drei Netzdateien, Präfix-Importe in `app/`, Testanzahl und Abdeckung je Paket.
- [ ] `docs/ARCHITECTURE.md` nennt `net_scope.dart` und `fold.dart` als einzige Stellen. ADR 0011 bekommt einen Satz zum gemeinsamen Kern.

Gerätetests: keine nötig (reine Dart-Pakete, App nur Importe). Falls doch ein Emulatorlauf erfolgt, nur `Wendelin_AOSP_35` mit explizitem Serial (`R-refactoring.md`).
