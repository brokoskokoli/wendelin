# WP127 – Öffentliches Repo: keine Namen, Anwesenheit oder lokalen Pfade

**Zuordnung:** Werkzeuge/Regeln. Entscheidung Maintainer 2026-10-22: aktuellen Stand bereinigen und eine Sperre einbauen, Historie bleibt; in Entscheidungsvermerken nur „Maintainer“, kein Name (Zitate bleiben, ohne Namen).

## Inhalt
1. **Bereinigen (aktueller Stand, alle Dateien):**
   - Vorname/Nachname des Maintainers → „Maintainer“ (Vermerke wie „Entscheidung Maintainer 2026-10-22“; Zitate bleiben). In Tests als Beispielname → neutraler Name (z. B. „Mia“), Erwartungen anpassen.
   - Anwesenheitsangaben (am Rechner, weg, nachts, schläft …) entfernen; Lastgrenzen neutral formulieren („Standard 2, mit Freigabe bis 4“).
   - Absolute lokale Pfade (`/Users/…`, Scratchpad-Pfade des Agenten unter `/private/tmp/` samt UUIDs) → `~/…` bzw. „lokal, nicht im Repo“.
   - Mechanisch per Skript (im Handoff-Ordner), danach Sichtprüfung des Diffs; Namen im Begriffsregister des Konzepts beachten (Sinn erhalten).
2. **Sperre:**
   - Commit-Hook (`tool/hooks/`) und Gate-Check lesen eine Begriffsliste **außerhalb des Repos** (`~/.config/wendelin/forbidden-terms.txt`, eine Zeile je Begriff, Groß/klein egal; fehlt die Datei → Check übersprungen mit Hinweis). Treffer in hinzugefügten Zeilen → Abbruch mit Datei:Zeile. Die Liste selbst nie ins Repo; Selbsttest mit temporärer Liste.
   - Allgemeiner Check (auch in CI, ohne Liste): keine `/Users/<name>/`-, `/home/<name>/`-Pfade und Scratchpad-Pfade des Agenten in versionierten Textdateien (Allowlist nur begründet).
   - Regel in `docs/agents/common.md` („Öffentliches Repo“): kein Name des Maintainers, keine Anwesenheit, keine absoluten Pfade; „Maintainer“ verwenden. Kurz in `AGENTS.md` verweisen.
3. Die Begriffsliste legt der Orchestrator an (nicht der Coder).

## Abnahmekriterien
- [ ] `git grep` auf die Begriffe der Liste und auf die Pfadmuster ist leer (außer begründeter Allowlist).
- [ ] Hook und Gate-Check mit Selbsttest (Treffer → rot, ohne Liste → übersprungen, Liste nicht im Repo), Mutationsbeleg.
- [ ] Keine Verhaltensänderung der App; `dart run tool/gate.dart --changed` grün, CI grün.

## Parallel-Hinweise
- WP125 und WP126 laufen parallel (App-Code Sprache/Audio). Deren Paket-Dateien `WP125-*.md`/`WP126-*.md` NICHT ändern (bereinigt der Orchestrator beim Merge). Bei Testdateien, die diese Pakete berühren könnten (`packages/wendelin_agent/test/run/loop_test.dart`, `app/test/...barge...`), nur den Namen tauschen, nichts umbauen.
