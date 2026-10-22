// Selbsttests von tool/check_privacy.dart und tool/hooks/privacy-guard.sh
// (WP127). Begriffe und Namen sind erfunden; die echte Liste wird nie gelesen.
import 'dart:io';

import 'privacy_check.dart';
import 'sandbox.dart';
import 'self_check.dart';

const _term = 'zorbax';
const _users = '/Users';
const _home =
    '/ho'
    'me';

void privacyChecks(SelfCheck t) {
  _patterns(t);
  _diff(t);
  _hook(t);
}

void _patterns(SelfCheck t) {
  t.group('check_privacy Muster');
  const terms = [_term];
  t.eq(leak('x $_users/maria/ai/foo', null), 'lokaler Pfad', 'Benutzerpfad');
  t.eq(leak('$_home/maria/x', null), 'lokaler Pfad', 'Linux-Home');
  t.eq(
    leak(
      '/private/tmp/'
      'claude-1/a',
      null,
    ),
    'lokaler Scratchpad-Pfad',
    'Scratchpad',
  );
  t.eq(leak('/home/x/james-wt', null), null, 'Platzhalter x erlaubt');
  t.eq(leak('/home/root/app', null), null, 'Systemnutzer root erlaubt');
  t.eq(leak('https://a/v1/users/@me/x', null), null, 'API-Pfad erlaubt');
  t.eq(leak('~/ai/x', null), null, 'Tilde-Pfad erlaubt');
  t.eq(
    leak('Hallo ZORBAX!', terms),
    'verbotener Begriff',
    'Begriff, Groß/klein',
  );
  t.eq(leak('Hallo ZORBAX!', null), null, 'ohne Liste: kein Begriffstreffer');
  t.isTrue(
    !(leak('Zorbax', terms) ?? '').contains(_term),
    'Meldung nennt den Begriff nicht',
  );
  t.eq(scanText('a.md', 'ok\nzorbax\nok\n$_users/maria/x', terms), [
    'a.md:2 (verbotener Begriff)',
    'a.md:4 (lokaler Pfad)',
  ], 'Datei:Zeile je Treffer');
  t.eq(loadTerms('/nicht/vorhanden/liste'), null, 'fehlende Liste: null');
  final d = Directory.systemTemp.createTempSync('privacy_terms_');
  try {
    final f = File('${d.path}/t.txt')
      ..writeAsStringSync('# Kommentar\n\n  Zorbax \nFoo\n');
    t.eq(loadTerms(f.path), ['zorbax', 'foo'], 'Liste: Kommentare, Leerzeilen');
  } finally {
    d.deleteSync(recursive: true);
  }
  t.isTrue(
    termsFilePath().contains('/.config/wendelin/') ||
        Platform.environment.containsKey('WENDELIN_TERMS_FILE'),
    'Liste liegt außerhalb des Repos',
  );
  final ls = Process.runSync('git', ['ls-files']).stdout as String;
  t.isTrue(!ls.contains('forbidden-terms'), 'Liste nicht versioniert');
}

void _diff(SelfCheck t) {
  t.group('check_privacy Diff');
  const diff =
      'diff --git a/a.md b/a.md\n--- a/a.md\n+++ b/a.md\n'
      '@@ -3,0 +4,2 @@\n+neu\n+zorbax hier\n'
      '@@ -9 +11 @@\n-zorbax alt\n+sauber\n'
      'diff --git a/b b/b\n--- a/b\n+++ /dev/null\n@@ -1 +0,0 @@\n-zorbax\n';
  t.eq(scanDiff(diff, const [_term]), [
    'a.md:5 (verbotener Begriff)',
  ], 'nur hinzugefügte Zeilen mit Zeilennummer');
}

void _hook(SelfCheck t) {
  t.group('privacy-guard Hook');
  final hook = File('tool/hooks/privacy-guard.sh').absolute.path;
  final d = Directory.systemTemp.createTempSync('privacy_selftest_');
  try {
    final r = Sandbox(d);
    r.git(['init', '-q', '-b', 'main']);
    r.commit('alt.md', 'zorbax steht schon drin\n');
    final terms = File('${d.path}/../privacy_terms_${d.hashCode}.txt')
      ..writeAsStringSync('zorbax\n');
    ProcessResult run(String termsPath) => Process.runSync(
      'sh',
      [hook],
      workingDirectory: d.path,
      environment: {
        ...r.env,
        'WENDELIN_TERMS_FILE': termsPath,
        'PATH': Platform.environment['PATH'] ?? '',
        'HOME': Platform.environment['HOME'] ?? '',
      },
    );
    File('${d.path}/neu.md').writeAsStringSync('eins\nZorbax!\n');
    r.git(['add', 'neu.md']);
    final bad = run(terms.path);
    t.isTrue(bad.exitCode != 0, 'Treffer in hinzugefügter Zeile: rot');
    t.isTrue('${bad.stderr}'.contains('neu.md:2'), 'Meldung mit Datei:Zeile');
    t.isTrue(
      !'${bad.stderr}${bad.stdout}'.toLowerCase().contains(_term),
      'Meldung nennt den Begriff nicht',
    );
    final none = run('${d.path}/gibt-es-nicht.txt');
    t.eq(none.exitCode, 0, 'ohne Liste: grün');
    t.isTrue(
      '${none.stderr}'.contains('keine Begriffsliste'),
      'Hinweis ohne Liste',
    );
    r.git(['reset', '-q']);
    File('${d.path}/neu.md').writeAsStringSync('sauber\n');
    r.git(['add', 'neu.md']);
    t.eq(run(terms.path).exitCode, 0, 'Bestand wird nicht geprüft: grün');
    File('${d.path}/p.md').writeAsStringSync('siehe $_users/maria/x\n');
    r.git(['add', 'p.md']);
    t.isTrue(
      run('${d.path}/gibt-es-nicht.txt').exitCode != 0,
      'Pfad ohne Liste: rot',
    );
    terms.deleteSync();
  } finally {
    d.deleteSync(recursive: true);
  }
}
