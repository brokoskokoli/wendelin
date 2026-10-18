// Gezielter Testlauf mit kompakter Ausgabe (Aufruf über tool/t.sh).
//
//   tool/t.sh app/test/voice/foo_test.dart packages/wendelin_core/test/x_test.dart
//   tool/t.sh packages/wendelin_agent --name "routing"
//
// Pfade (Datei oder Ordner) gelten vom Aufrufordner aus oder vom Repo-Root.
// Je Paket ein Lauf: `flutter test` bei Flutter-Paketen, sonst `dart test`.
import 'dart:io';

import 'src/gate_run.dart';

const _maxLines = 80;

Future<void> main(List<String> args) async {
  final root = args[0];
  final callDir = args[1];
  final rest = args.sublist(2);
  final paths = <String>[];
  final flags = <String>[];
  for (var i = 0; i < rest.length; i++) {
    final a = rest[i];
    if (a == '--concurrency' && i + 1 < rest.length) {
      flags.add('--concurrency=${rest[++i]}');
    } else if (a.startsWith('-')) {
      flags.add(a);
      // Wert zu --name/-n/--plain-name/-N/--tags/-t übernehmen.
      if (const {
            '--name',
            '-n',
            '--plain-name',
            '-N',
            '--tags',
            '-t',
          }.contains(a) &&
          i + 1 < rest.length) {
        flags.add(rest[++i]);
      }
    } else {
      paths.add(a);
    }
  }
  if (paths.isEmpty) {
    stderr.writeln('Aufruf: tool/t.sh <testdatei-oder-ordner…> [--name x]');
    exit(64);
  }
  // Paketordner -> Testpfade (relativ zum Paket).
  final byPkg = <String, List<String>>{};
  for (final p in paths) {
    final abs = _resolve(p, callDir, root);
    if (abs == null) {
      stderr.writeln('Pfad nicht gefunden: $p');
      exit(66);
    }
    final pkg = _packageRoot(abs, root);
    if (pkg == null) {
      stderr.writeln('Kein Paket (pubspec.yaml) über: $p');
      exit(66);
    }
    final rel = abs == pkg ? '' : abs.substring(pkg.length + 1);
    byPkg.putIfAbsent(pkg, () => []).addAll(rel.isEmpty ? [] : [rel]);
  }
  final out = <String>[];
  var code = 0;
  var n = 0;
  for (final MapEntry(key: pkg, value: tests) in byPkg.entries) {
    final flutter = File('$pkg/pubspec.yaml')
        .readAsStringSync()
        .contains(RegExp(r'^\s+sdk:\s*flutter\s*$', multiLine: true));
    final json = '${Directory.systemTemp.path}/t_${pkg.hashCode}_$pid.json';
    final r = await Process.run(flutter ? 'flutter' : 'dart', [
      'test',
      '--reporter=failures-only',
      '--file-reporter=json:$json',
      ...flags,
      ...tests,
    ], workingDirectory: pkg);
    final c = countTests(json);
    final label = pkg.substring(root.length + 1);
    n += c == null ? 0 : c.passed + c.failed;
    if (r.exitCode != 0) {
      code = r.exitCode;
      out.add('ROT $label (${testDetail(c)})');
      final failed = renderFailures(json, maxLines: _maxLines - 2);
      if (failed.isNotEmpty) {
        out.addAll(failed.split('\n'));
      } else {
        final raw = '${r.stdout}\n${r.stderr}'
            .split('\n')
            .where((l) => l.trim().isNotEmpty && !isNoiseLine(l))
            .toList();
        out.addAll(tail(raw, _maxLines - 4).map((l) => '  | $l'));
      }
    } else {
      out.add('ok  $label (${testDetail(c)})');
    }
    final f = File(json);
    if (f.existsSync()) f.deleteSync();
  }
  if (out.length > _maxLines) {
    out
      ..removeRange(_maxLines - 1, out.length)
      ..add('… Ausgabe auf $_maxLines Zeilen gekürzt');
  }
  stdout.writeln(out.join('\n'));
  if (code == 0) stdout.writeln('GRÜN ($n Tests)');
  exit(code);
}

String? _resolve(String p, String callDir, String root) {
  for (final base in [callDir, root]) {
    final path = p.startsWith('/') ? p : '$base/$p';
    final type = FileSystemEntity.typeSync(path);
    if (type != FileSystemEntityType.notFound) {
      return File(path).absolute.uri
          .toFilePath()
          .replaceFirst(RegExp(r'/$'), '');
    }
  }
  return null;
}

String? _packageRoot(String abs, String root) {
  var d = FileSystemEntity.isDirectorySync(abs)
      ? abs
      : abs.substring(0, abs.lastIndexOf('/'));
  while (d.length >= root.length && d.startsWith(root)) {
    if (File('$d/pubspec.yaml').existsSync() && d != root) return d;
    final i = d.lastIndexOf('/');
    if (i < 0) break;
    d = d.substring(0, i);
  }
  return null;
}
