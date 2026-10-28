# Arbeitspakete

Index und Regeln für Arbeitspakete. Der Umsetzungsstand aller Meilensteine und Pakete steht in **`STATUS.md`** (maßgeblich); Paketdateien heißen `WPnn-<slug>.md`, das Prüfprotokoll steht in `REVIEW.md`.

Jedes Paket: eigener Branch `wp/<nr>-<slug>` in eigenem Worktree, Umsetzung durch einen Coding-Agenten, Prüfung durch einen unabhängigen Review-Agenten nach `REVIEW.md`, Merge nach bestandenem Review.

## Größe eines Arbeitspakets

Richtwert: **höchstens ca. 1 500 Zeilen geänderter Produktivcode je Review-Einheit** (hinzugefügt plus entfernt unter `lib/` bzw. `app/lib/` und Kotlin `main`, ohne Tests und generierten Code). Größere Pakete werden in Teil-Merges (a/b/c) geschnitten, jeder Teil mit eigenem Review nach `REVIEW.md` und eigenen Mutationsproben. Messung: `git diff --shortstat main...HEAD -- '*/lib/*'` und `dart run tool/check_sizes.dart --report`. Größenregeln für Dateien und Funktionen: `docs/ENGINEERING.md`, Abschnitt „Größen“.

## Merge-Hotspots

Diese Dateien ändert fast jedes Feature-Paket. Regel: **nur anhängen, nicht umsortieren oder umformatieren; bei einem Konflikt den Integrator fragen**, statt selbst semantisch zu mergen. Mit WP38 entschärft (je Integration eigene Barrel-, Spec- und Routendatei; `main.dart`, `app.dart`, `providers.dart` und `test_env.dart` sind schlank bzw. Re-Export-Barrels).

- `packages/wendelin_integrations/lib/wendelin_integrations.dart` (nur noch eine Exportzeile je Integration), `fakes.dart`, `testing.dart`
- `app/lib/di/integrations/registry.dart` (eine Zeile je Integration)
- `app/lib/ui/routes.dart` (`AppRoutes`-Namen), `app/lib/ui/screens/labels.dart`
- `app/test/di/wiring_test.dart`
- `app/android/app/src/main/AndroidManifest.xml`, `app/pubspec.yaml`
