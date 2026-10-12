// Sucht im Git-Arbeitsbaum nach Schlüssel-Mustern und verbotenen Identitäten.
import 'dart:io';

final patterns = <String, RegExp>{
  'Anthropic-Key': RegExp(r'sk-ant-[A-Za-z0-9_\-]{20,}'),
  'OpenAI-Key': RegExp(r'sk-(proj-)?[A-Za-z0-9]{32,}'),
  'GitHub-Token': RegExp(r'gh[pousr]_[A-Za-z0-9]{30,}'),
  'Private Key': RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
  'Bearer-Token': RegExp(r'Bearer [A-Za-z0-9\-_.]{30,}'),
  'Arbeitgeber-Identität': RegExp(
    r'web-?fabric|[entfernt]-?it',
    caseSensitive: false,
  ),
};

void main() {
  final files = Process.runSync('git', [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
  ]);
  final errors = <String>[];
  for (final path in (files.stdout as String).split('\n')) {
    if (path.isEmpty ||
        path == 'tool/check_secrets.dart' ||
        path.startsWith('tool/hooks/')) {
      continue;
    }
    final file = File(path);
    if (!file.existsSync()) continue;
    String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      continue; // Binärdatei
    }
    patterns.forEach((name, re) {
      if (re.hasMatch(text)) errors.add('$path: $name gefunden');
    });
  }
  if (errors.isEmpty) {
    stdout.writeln('check_secrets: ok');
  } else {
    errors.forEach(stderr.writeln);
    exitCode = 1;
  }
}
