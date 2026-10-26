# Review-Protokoll

Jedes Arbeitspaket wird von einem Agenten geprüft, der den Code nicht geschrieben hat. Der Reviewer ändert keinen Produktivcode. Rolle, Prüf-Worktree (`../james-wt/rev-<wp>`, Mutationen nur dort, am Ende sauber und entfernt), Grenzen und Re-Review stehen in `docs/agents/reviewer.md`, die übrigen Regeln in `AGENTS.md`. Temporäre Skripte liegen in einem eigenen Unterordner.

## Prüfschritte

1. **CI prüfen statt Gate lokal laufen lassen**: Der CI-Lauf des `wp/*`-Branches auf genau dem Commit (`gh run list -b <branch>`) muss grün sein; rot oder fehlend ist ein Befund. Lokal nur gezielte Testdateien (`tool/t.sh`, `--concurrency=2`). Abdeckung aus dem CI-Bericht oder gezielt ablesen. Nicht der Aussage des Coders vertrauen.
2. **Abnahmekriterien**: Jedes Kriterium im WP-Dokument einzeln abhaken, mit Fundstelle (Datei:Zeile oder Testname). Fehlt eines → Befund.
3. **Spezifikationstreue**: Relevante Abschnitte des Gesamtkonzepts gegen die Umsetzung lesen (Namen, Grenzwerte, Verhalten, z. B. 8 Tool-Runden, 60 s, Tool-Namensformat, Risikostufen).
4. **Test-Gegenbeweis (Mutationsprobe)**: 3 bis 10 gezielte Mutationen in Kernlogik einbauen (Bedingung umdrehen, Grenzwert ±1, Zweig entfernen, Fehler verschlucken, Reihenfolge ändern). Jede Mutation muss mindestens einen Test rot machen. Überlebende Mutationen sind Befunde („Test fehlt für …"). Danach zurücksetzen.
5. **Architekturgrenzen**: `dart run tool/check_deps.dart`; zusätzlich manuell: keine Provider-JSON-Typen außerhalb der Adapter, keine Flutter-Imports in `packages/`, Ports statt Plattformzugriff, Fakes unter `lib/testing/`.
6. **Sicherheit**: Secrets nie geloggt/persistiert, `external` immer bestätigt, Eingaben aus Tools/Netz als Daten behandelt, keine Keys im Baum (`tool/check_secrets.dart`), Commit-Identität (`git log --format='%an <%ae>%n%(trailers)' main..HEAD`) nur erlaubte Werte (`docs/agents/common.md`).
7. **Code-Qualität**: Lesbarkeit, Doppelungen, unnötige Komplexität, öffentliche API knapp und dokumentiert, README pro Integration.
8. **Nur app/UI**: Golden-Bilder öffnen (Read-Tool auf PNG) und mit `docs/design/screens/*@1x.png` vergleichen: Farben aus `WColors`, Abstände, Texte, Status-Formen (Kreis/Dreieck/Quadrat), Touch-Ziele ≥ 44, Semantics-Labels.

## Ergebnisformat

```
URTEIL: FREIGABE | NACHBESSERN
CI: <grün/rot, Lauf-URL, Abdeckung je Paket>
MUTATIONEN: <n getestet, n erkannt, Liste überlebender>
CHECKLISTE: <Haken des Coders geprüft: ja/Abweichungen>
BEFUNDE:
- [Blocker|Muss|Soll] <kategorie> <Datei:Zeile> – <Befund> – <konkreter Vorschlag>
```

`FREIGABE` nur ohne Blocker/Muss. Soll-Befunde dürfen offen bleiben, werden aber gelistet. Die Kategorie ist ein Schlüssel der Checkliste in `docs/agents/coder.md` (`bestaetigung`, `fail-closed`, `dispose`, `negativtest`, `texte`, `doku`, `berechtigung`) oder `sonstiges`.

## Urteilsdatei (maschinenlesbar)

Der Reviewer legt sein Urteil als Datei ab: `../james-wt/reviews/<wp>-review.md` (z. B. wp110-review.md; aus einem Worktree heraus liegt der Ordner reviews neben dem Worktree). Das ist der dauerhafte Ablageort: `tool/cleanup_wt.sh` löscht dort nichts und verschiebt Urteile, die noch im Ordner handoff liegen, nach reviews, beim Re-Review `<wp>-review2.md`, dann `-review3.md`. Die Datei beginnt mit genau diesem Kopf (eine Angabe je Zeile, `Schlüssel: Wert`, danach beliebiger Text, am besten das Ergebnis oben):

```
URTEIL: FREIGABE | NACHBESSERN
RUNDE: 1
MUTATIONEN: 6/1
BEFUNDE: bestaetigung=0 fail-closed=1 dispose=0 negativtest=2 texte=0 doku=0 berechtigung=0 sonstiges=0
```

- `RUNDE`: 1 beim ersten Review, 2 beim Re-Review usw. (passt zur Dateinummer).
- `MUTATIONEN: <getestet>/<überlebt>`; überlebende Mutationen sind zugleich Befunde (meist `negativtest`).
- `BEFUNDE`: Anzahl der Blocker/Muss/Soll-Befunde je Kategorie; fehlt eine Kategorie, gilt 0.
- `dart run tool/review_stats.dart [ordner]` (Standard: der Ordner `reviews` neben dem Hauptcheckout, auch aus einem Worktree gefunden) liest alle `*-review*.md` und nennt die Quote „beim ersten Review sauber“ (Runde 1 mit FREIGABE), die Befunde je Kategorie und die Mutationsbilanz. Selbsttest: `tool/src/review_stats.dart` in `dart run tool/self_test.dart`.
