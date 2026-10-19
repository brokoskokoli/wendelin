// Temporäre Git-Repos für die Selbsttests der Skripte (WP109).
import 'dart:io';

/// Erlaubte Identität und Trailer (wie in docs/agents/common.md).
const sbName = 'brokoskokoli';
const sbMail = '16724498+brokoskokoli@users.noreply.github.com';
const sbTrailer =
    'Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>';
const sbZero = '0000000000000000000000000000000000000000';

/// Temporäres Git-Repo mit der erlaubten Identität.
final class Sandbox {
  Sandbox(this.dir);

  final Directory dir;

  Map<String, String> get env => {
    'GIT_CONFIG_GLOBAL': '/dev/null',
    'GIT_CONFIG_SYSTEM': '/dev/null',
    'GIT_AUTHOR_NAME': sbName,
    'GIT_AUTHOR_EMAIL': sbMail,
    'GIT_COMMITTER_NAME': sbName,
    'GIT_COMMITTER_EMAIL': sbMail,
  };

  String git(
    List<String> a, {
    Map<String, String> extra = const {},
    String? cwd,
  }) {
    final r = Process.runSync(
      'git',
      a,
      workingDirectory: cwd ?? dir.path,
      environment: {...env, ...extra},
    );
    if (r.exitCode != 0) throw StateError('git $a: ${r.stderr}');
    return (r.stdout as String).trim();
  }

  /// Schreibt [file] und committet (Standardnachricht mit Trailer).
  void commit(
    String file,
    String text, {
    String? msg,
    Map<String, String> extra = const {},
    String? cwd,
  }) {
    final f = File('${cwd ?? dir.path}/$file')..createSync(recursive: true);
    f.writeAsStringSync(text);
    git(['add', file], cwd: cwd);
    git(
      ['commit', '-q', '-m', msg ?? 'c\n\n$sbTrailer'],
      extra: extra,
      cwd: cwd,
    );
  }

  String head() => git(['rev-parse', 'HEAD']);

  bool hasRef(String ref) =>
      Process.runSync(
        'git',
        ['rev-parse', '--verify', '-q', ref],
        workingDirectory: dir.path,
        environment: env,
      ).exitCode ==
      0;
}
