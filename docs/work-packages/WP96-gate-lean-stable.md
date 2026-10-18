# WP96 – Gate schlank und stabil (`tool/gate.dart`, `tool/src/`, `app/test/flutter_test_config.dart`, Flake-Tests)

**Zuordnung:** M5 (Beschleunigung). Grundlage: `docs/notes/dev-speedup-analysis.md` §2, §7, §9.

## Inhalt
1. Rot-Ausgabe aus dem JSON-Reporter: je roter Test Name, Datei und Fehler, höchstens ~60 Zeilen je Schritt; Log-Rauschen (`Wendelin/voice:`) in Tests puffern und nur bei Rot des jeweiligen Tests ausgeben.
2. Flakes beheben: `conditions_test.dart:308` (Stopwatch-Assert), `main_attestation_test`/`wake_lifecycle_test` (feste `runAsync`-Wartezeiten), `wake_barge_in_test` (echte Timer), Overlay-/Push-to-talk-Tests; `pumpUntil`-Helfer bzw. `fakeAsync`; Zeitzonen-Probe einmal kompilieren statt `dart run` je Probe.
3. Gate-Check (grep): keine Wanduhr-Asserts und kein `runAsync(Future.delayed)` als Wartezeit in Tests.
4. `tool/t.sh <pfad…>`: gezielter Testlauf mit kompakter Ausgabe für Agenten.

## Abnahmekriterien
- [ ] Rot-Ausgabe ≤ 4 KB mit Testname und Fehler (Selbsttest).
- [ ] 5 volle Läufe bei Last ≥ 30 ohne Flake (bzw. in CI 5 Läufe grün).
- [ ] Grep-Check aktiv; Gate grün.
