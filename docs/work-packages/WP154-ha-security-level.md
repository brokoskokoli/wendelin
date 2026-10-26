# WP154 – Home Assistant: Sicherheitsstufe je Gerät

**Zuordnung:** Wunsch des Maintainers vom 2026-10-26. Ersetzt den Schalter „ohne Rückfrage“ (WP135 E) durch eine Stufe je Gerät. Konzeptänderung (K-Eintrag durch den Orchestrator), ADR nötig.

## Ist-Stand
- Je Gerät gibt es „ohne Rückfrage“ (`noConfirm`, nur Rollos mit passender Klasse, `ha_policy.dart:97-109`) und „immer bestätigen“ (`alwaysConfirm`), Schalter in `app/lib/ui/settings/ha_device_sections.dart:82-130`. Die Schalter sind so groß wie alle anderen und immer offen.
- Gesperrt darf ein erkannter Sprecher Licht, Szenen und Medien steuern (`haLockSafeDomains`, `ha_policy.dart:111-114`, `locked_agent_run.dart`, `HaIntegration.allowedWhileLocked`). Sprechererkennung: `app/lib/ui/settings/speaker/`.

## Stufen
| Stufe | Bedeutung |
|---|---|
| A | immer, auch gesperrt und ohne erkannte Stimme |
| B | bei erkannter Stimme (auch gesperrt) oder entsperrt |
| C | nur entsperrt |
| D | entsperrt und Bestätigung auf dem Display |

## Inhalt
- **Standard je Gerät = heutiges Verhalten** (Abbildung im Paket herleiten und als Tabelle belegen; Vorschlag: Licht/Szene/Medien B, Rollo mit „ohne Rückfrage“ und passender Klasse C, alle übrigen D). Nach dem Update ändert sich nichts, solange der Nutzer nichts umstellt (Migration von `noConfirm`/`alwaysConfirm`, Test).
- **Standard je Punkt, Nutzer überschreibt** (Maintainer 2026-10-26): Wendelin setzt je Gerät eine Standardstufe (z. B. Schloss, Alarm, Tor/Tür = D), der Nutzer kann sie je Gerät überschreiben. Die UI zeigt, ob die Stufe Standard oder geändert ist, und bietet „Standard wiederherstellen“.
- **Je Gerät frei einstellbar** (Entscheidung Maintainer 2026-10-26: keine Obergrenze je Domäne, auch Schloss, Alarm oder Tor dürfen auf A; die Verantwortung liegt beim Nutzer). Fail-closed bleibt: fehlende, unbekannte oder ungültige gespeicherte Stufe = D. Bei A/B für Schloss, Alarm, Tor/Tür einmal ein deutlicher Hinweis beim Umstellen.
- **UI:** Je Gerät ein kompakter, eingerückter Reiter (z. B. „Details“) mit kleinem Pfeil, standardmäßig eingeklappt (Maintainer 2026-10-26: immer eingeklappt, ausklappbar). Eingeklappt zeigt er die Stufe als kurzen Text, ausgeklappt die Auswahl A–D mit je einer Zeile Erklärung (kleiner als die normalen Schalter). Die bisherigen Schalter „ohne Rückfrage“/„immer bestätigen“ entfallen bzw. wandern dort hinein. Texte in allen Sprachen.
- **Policy an einer Stelle** (`ha_policy.dart`): eine Funktion „darf ausgeführt werden / braucht Bestätigung / braucht Entsperren“ aus Stufe, Domäne, Klasse, Sperrzustand und Sprechererkennung. `locked_agent_run` und die Bestätigung nutzen nur sie.

## Abnahmekriterien
- [ ] Tabelle Stufe × Sperrzustand × Stimme → Ergebnis als Tabellentest, je Zeile ein Fall; Mutationen an der Policy werden rot.
- [ ] Ungültige oder fehlende Stufe = D in der Policy (Test mit manipulierter Einstellung); Hinweis beim Umstellen gefährlicher Domänen (Widget-Test).
- [ ] Migration: ohne Nutzeränderung gleiches Verhalten wie vorher (Test mit alten Einstellungen).
- [ ] UI: eingeklappt, eingerückt, kleiner; Widget-Test und Golden (macOS).
- [ ] ADR „Sicherheitsstufe je HA-Gerät“; Abweichungen fürs Änderungsprotokoll im Bericht.
- [ ] Gerätetest-Anleitung `docs/testing/m5/wp154.md` (Licht auf A bei gesperrtem Gerät mit fremder Stimme, Rollo C, Schloss bleibt D).
- [ ] `--changed` grün, CI grün, Review FREIGABE (Schwerpunkt Sicherheit, fail-closed).

## Parallel-Hinweise
- Berührt `ha_policy.dart` und HA-Einstellungen; nicht gleichzeitig mit WP150 (HA-Werkzeugschleife, `ha_call_tools.dart`, `ha_context.dart`) – nacheinander, WP150 zuerst.
