# Paket zieht nach WP98 nach

Anleitung für Pakete, die vor WP98 begonnen wurden und `origin/main` (mit WP98) mergen. Beispiel: WP90 (Integration `media`). Nach `git merge origin/main` mit Konflikten:

Sicht des Pakets: `ours` ist der eigene Paket-Branch (alter Stil), `theirs` ist `origin/main` mit WP98.

1. **l10n.** Die eigene Gesamt-ARB (`--ours`, enthält die eigenen Schlüssel) behalten, die Erzeugnisse von main (`gen/`) nehmen und die Schlüssel mit `--adopt` in ein Fragment überführen; danach neu erzeugen:
   ```sh
   git checkout --ours app/lib/l10n/app_*.arb && git checkout --theirs app/lib/l10n/gen
   dart run tool/l10n_merge.dart --adopt <bereich>   # z. B. media; legt app/lib/l10n/src/<bereich>/ an
   dart run tool/l10n_merge.dart && dart run tool/l10n_merge.dart --check
   git add app/lib/l10n
   ```
   `--adopt` ohne Bereich ordnet nach Präfix (`prefixAreas`); „0 Schlüssel“ danach heißt: nichts Fremdes übrig. Danach erzeugt `tool/regen_generated.sh` (ohne Argumente) alles Erzeugte neu.
2. **Testlisten.** `registry_probe_test`, `wiring_test`, `integrations_screen_test`: WP98-Version behalten (`git checkout --theirs <datei>`), da die Listen jetzt aus der Registry kommen. Eigene Wiring-Tests der Integration aus der alten Version in eine **eigene Datei** `app/test/di/<id>_wiring_test.dart` verlegen (Vorlage `app/test/di/media_wiring_test.dart`; Imports prüfen, `flutter analyze`).
3. **Vertrauenstabelle.** Die Erwartung aus `packages/wendelin_integrations/test/trust_registry_test.dart` (Konflikt: WP98-Version behalten per `git checkout --theirs`, den eigenen `_trusted`-Block verwerfen) steht jetzt je Integration in `app/test/trust/<id>.json` (Tool -> `true` = vertrauenswürdig); die eigenen `_trusted`-Einträge dorthin übertragen. `schemas_test` brauchte für WP90 keine Änderung.
4. **Architektur.** `git checkout --theirs docs/ARCHITECTURE.md` (Index von main). Die eigenen neuen Zeilen in die Bereichsdatei (`docs/architecture/<bereich>.md`) bzw. `docs/architecture/integrations/<id>.md` (Kanal-/Port-Zuordnung, Besonderheiten).
5. **Gerätetests.** Den eigenen Abschnitt aus `docs/testing/m5-device.md` (Konflikt „modify/delete“, die eigene Version liegt im Arbeitsbaum) nach `docs/testing/m5/wp<nr>.md` (Titel `# WP<nr> <Name>`), dann `git rm docs/testing/m5-device.md` und `dart run tool/gen_docs.dart`.
6. **Prüfen.** `dart run tool/gen_docs.dart --check`, `dart run tool/check_registry.dart`, `dart run tool/l10n_merge.dart --check`, `dart run tool/gate.dart --changed`; Merge-Commit mit der Standardnachricht.
7. **Neue Integration trifft die registrybasierten Tests.** `app/test/di/tool_schemas_test.dart` und `trust_registry_test` prüfen jetzt alle Integrationen. Rote Tests sind dann echte Befunde der neuen Tools (bei WP90 war die Zeit-Heuristik zu lose: „start“ im Schema-Text statt als Parameter), nicht Merge-Reste; Test oder Tool anpassen, nicht die Liste.
