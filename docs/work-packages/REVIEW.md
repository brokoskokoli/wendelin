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
BEFUNDE:
- [Blocker|Muss|Soll] <Datei:Zeile> – <Befund> – <konkreter Vorschlag>
```

`FREIGABE` nur ohne Blocker/Muss. Soll-Befunde dürfen offen bleiben, werden aber gelistet.
