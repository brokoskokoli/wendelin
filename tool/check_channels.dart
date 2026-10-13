// Kanal-Check (docs/ENGINEERING.md, „Plattformkanäle“): vergleicht
// app/channels.json mit den Dart- und Kotlin-Quellen der MethodChannels.
//
//   dart run tool/check_channels.dart
import 'dart:io';

import 'src/channel_check.dart';

const manifestPath = 'app/channels.json';
const _dartRoot = 'app/lib';
const _kotlinRoot = 'app/android/app/src/main/kotlin';

void main() {
  final sw = Stopwatch()..start();
  final manifest = File(manifestPath);
  if (!manifest.existsSync()) {
    stderr.writeln('$manifestPath:1: Manifest fehlt');
    exitCode = 1;
    return;
  }
  final r = checkChannels(
    manifestText: manifest.readAsStringSync(),
    manifestPath: manifestPath,
    read: (p) {
      final f = File(p);
      return f.existsSync() ? f.readAsStringSync() : null;
    },
    dartFiles: _files(_dartRoot, '.dart'),
    kotlinFiles: _files(_kotlinRoot, '.kt'),
  );
  r.errors.forEach(stderr.writeln);
  final summary =
      '${r.channels} Kanäle, ${r.methods} Methoden, '
      '${r.errors.length} Fehler (${sw.elapsedMilliseconds} ms)';
  if (r.errors.isEmpty) {
    stdout.writeln('check_channels: ok, $summary');
  } else {
    stderr.writeln('check_channels: ROT, $summary');
    exitCode = 1;
  }
}

List<String> _files(String root, String ext) => [
  for (final e in Directory(root).listSync(recursive: true))
    if (e is File && e.path.endsWith(ext)) e.path,
]..sort();
