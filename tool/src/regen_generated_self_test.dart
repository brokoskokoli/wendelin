// Selbsttest von tool/regen_generated.sh: Mit Stub-`dart` im PATH wird geprüft,
// welche Erzeuger je Argumentliste laufen.
import 'dart:io';

import 'self_check.dart';

void regenGeneratedChecks(SelfCheck t) {
  t.group('regen_generated');
  final script = File('tool/regen_generated.sh').absolute.path;
  final tmp = Directory.systemTemp.createTempSync('regen_');
  try {
    final bin = Directory('${tmp.path}/bin')..createSync();
    final log = File('${tmp.path}/calls.log');
    File('${bin.path}/dart')
      ..writeAsStringSync('#!/bin/sh\necho "\$@" >> "${log.path}"\n')
      ..createSync();
    Process.runSync('chmod', ['+x', '${bin.path}/dart']);

    List<String> run(List<String> args) {
      if (log.existsSync()) log.deleteSync();
      final r = Process.runSync(
        'sh',
        [script, ...args],
        workingDirectory: tmp.path,
        environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
      );
      t.eq(r.exitCode, 0, 'Exit 0 für $args');
      return log.existsSync() ? log.readAsLinesSync() : <String>[];
    }

    t.eq(run([]), [
      'run tool/l10n_merge.dart',
      'run tool/gen_docs.dart',
    ], 'ohne Argumente laufen beide Erzeuger');
    t.eq(run(['app/lib/l10n/app_en.arb']), [
      'run tool/l10n_merge.dart',
    ], 'ARB: nur l10n');
    t.eq(run(['docs/testing/m5/README.md']), [
      'run tool/gen_docs.dart',
    ], 'm5-Index: nur gen_docs');
    final r = Process.runSync(
      'sh',
      [script, 'lib/x.dart'],
      workingDirectory: tmp.path,
      environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
    );
    t.isTrue(r.exitCode != 0, 'unbekannte Datei bricht ab');
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
