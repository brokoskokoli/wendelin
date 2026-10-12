# Review-Protokoll

Jedes Arbeitspaket wird von einem Agenten geprüft, der den Code nicht geschrieben hat. Der Reviewer ändert keinen Produktivcode; er darf temporär Code ändern, um Tests zu prüfen (Schritt 4), und stellt den Ausgangszustand danach wieder her (`git stash`/`git checkout -- .`, am Ende `git status` sauber).

## Prüfschritte

1. **Gate reproduzieren**: `dart run tool/gate.dart` (bzw. die im WP genannten Befehle) selbst ausführen. Nicht der Aussage des Coders vertrauen. Abdeckung ablesen.
2. **Abnahmekriterien**: Jedes Kriterium im WP-Dokument einzeln abhaken, mit Fundstelle (Datei:Zeile oder Testname). Fehlt eines → Befund.
3. **Spezifikationstreue**: Relevante Abschnitte des Gesamtkonzepts gegen die Umsetzung lesen (Namen, Grenzwerte, Verhalten, z. B. 8 Tool-Runden, 60 s, Tool-Namensformat, Risikostufen).
4. **Test-Gegenbeweis (Mutationsprobe)**: Mindestens 5 gezielte Mutationen in Kernlogik einbauen (Bedingung umdrehen, Grenzwert ±1, Zweig entfernen, Fehler verschlucken, Reihenfolge ändern). Jede Mutation muss mindestens einen Test rot machen. Überlebende Mutationen sind Befunde („Test fehlt für …"). Danach zurücksetzen.
5. **Architekturgrenzen**: `dart run tool/check_deps.dart`; zusätzlich manuell: keine Provider-JSON-Typen außerhalb der Adapter, keine Flutter-Imports in `packages/`, Ports statt Plattformzugriff, Fakes unter `lib/testing/`.
6. **Sicherheit**: Secrets nie geloggt/persistiert, `external` immer bestätigt, Eingaben aus Tools/Netz als Daten behandelt, keine Keys im Baum (`tool/check_secrets.dart`), Commit-Identität (`git log --format='%an <%ae>%n%(trailers)' main..HEAD`) nur erlaubte Werte.
7. **Code-Qualität**: Lesbarkeit, Doppelungen, unnötige Komplexität, öffentliche API knapp und dokumentiert, README pro Integration.
8. **Nur app/UI**: Golden-Bilder öffnen (Read-Tool auf PNG) und mit `docs/design/screens/*@1x.png` vergleichen: Farben aus `WColors`, Abstände, Texte, Status-Formen (Kreis/Dreieck/Quadrat), Touch-Ziele ≥ 44, Semantics-Labels.

## Ergebnisformat

```
VERDICT: APPROVE | CHANGES_REQUESTED
GATE: <grün/rot, Abdeckung je Paket>
MUTATIONS: <n getestet, n getötet, Liste überlebender>
FINDINGS:
- [blocker|major|minor] <Datei:Zeile> – <Befund> – <konkreter Vorschlag>
```

`APPROVE` nur ohne blocker/major. minor-Befunde dürfen offen bleiben, werden aber gelistet.
