// Öffentliches Repo (WP127): keine lokalen Pfade mit Benutzername und keine
// Begriffe aus der Liste außerhalb des Repos. `--staged` prüft nur die
// hinzugefügten Zeilen des Index (Hook `tool/hooks/privacy-guard.sh`).
import 'dart:io';

import 'src/privacy_check.dart';

void main(List<String> args) {
  exitCode = runPrivacyCheck(staged: args.contains('--staged'));
}
