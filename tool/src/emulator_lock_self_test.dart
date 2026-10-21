// Selbsttests von tool/emulator_lock.sh und der Einbindung in
// tool/e2e_android.sh (WP110).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sandbox.dart';
import 'self_check.dart';

Future<void> emulatorLockChecks(SelfCheck t) async {
  t.group('Emulator-Sperre');
  final dir = Directory.systemTemp.createTempSync('emulock_selftest_');
  try {
    final l = _Lock(t, dir.path);
    await l.busyAndRelease();
    l.orphan();
    await l.orphanRace();
    l.noInfo();
    await l.foreignRelease();
    l.wpName();
    l.wiring();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

final class _Lock {
  _Lock(this.t, this.dir)
    : lib = File('tool/emulator_lock.sh').absolute.path,
      env = {'WENDELIN_LOCK_DIR': '$dir/locks'};

  final SelfCheck t;
  final String dir;
  final String lib;
  final Map<String, String> env;

  bool exists(String serial) =>
      Directory('$dir/locks/$serial.lock').existsSync();

  ProcessResult sh(String body, {Map<String, String> extra = const {}}) =>
      Process.runSync(
        'bash',
        ['-c', '. "$lib"; $body'],
        environment: {...env, ...extra},
      );

  /// Hält die Sperre in einem eigenen Prozess, bis er beendet wird.
  Future<Process> hold(String serial, String wp) async {
    final p = await Process.start(
      'bash',
      [
        '-c',
        '. "$lib"; emu_lock_acquire $serial || exit 1; echo held; sleep 60 & wait',
      ],
      environment: {...env, 'WENDELIN_WP': wp},
    );
    unawaited(p.stderr.drain<void>());
    final first = await p.stdout
        .transform(utf8.decoder)
        .first
        .timeout(const Duration(seconds: 20), onTimeout: () => 'timeout');
    if (!first.contains('held')) throw StateError('Halter: $first');
    return p;
  }

  Future<void> busyAndRelease() async {
    final holder = await hold('emulator-5554', 'WP77');
    final second = sh('emu_lock_acquire emulator-5554; echo "exit=\$?"');
    t.isTrue(
      (second.stderr as String).contains(
        'belegt durch WP77, PID ${holder.pid}',
      ),
      'zweiter Lauf: Meldung „belegt durch WP77, PID …“: ${second.stderr}',
    );
    t.isTrue(
      (second.stdout as String).contains('exit=1'),
      'zweiter Lauf: Exit ungleich 0, kein Warten',
    );
    final free = sh('emu_lock_acquire emulator-5556; echo ok').stdout;
    t.isTrue((free as String).contains('ok'), 'anderer Emulator ist frei');

    holder.kill(ProcessSignal.sigterm);
    await holder.exitCode.timeout(const Duration(seconds: 20));
    t.isTrue(!exists('emulator-5554'), 'nach Abbruch (SIGTERM) ist sie frei');
    final again = sh('emu_lock_acquire emulator-5554; echo ok').stdout;
    t.isTrue((again as String).contains('ok'), 'danach wieder belegbar');
    t.isTrue(!exists('emulator-5554'), 'normales Ende (EXIT) gibt frei');
    sh('set -e; emu_lock_acquire emulator-5554; false');
    t.isTrue(!exists('emulator-5554'), 'Abbruch durch Fehler gibt frei');
  }

  /// Verwaiste Sperre (PID tot) wird übernommen.
  void orphan() {
    final o = Directory('$dir/locks/emulator-5554.lock')
      ..createSync(recursive: true);
    File('${o.path}/info').writeAsStringSync('2000000 WP5\n');
    final take = sh(
      'emu_lock_acquire emulator-5554; echo "exit=\$?"; cat "\$_emu_lock_dir/info"',
      extra: {'WENDELIN_WP': 'WP9'},
    );
    t.isTrue(
      (take.stdout as String).contains('exit=0') &&
          (take.stderr as String).contains('verwaiste'),
      'verwaiste Sperre wird übernommen: ${take.stderr}',
    );
    t.isTrue(
      (take.stdout as String).contains('WP9'),
      'neuer Besitzer trägt sein WP ein',
    );
  }

  /// Mehrere gleichzeitige Übernahmen einer verwaisten Sperre: genau einer gewinnt.
  Future<void> orphanRace() async {
    final o = Directory('$dir/locks/emulator-5560.lock')
      ..createSync(recursive: true);
    File('${o.path}/info').writeAsStringSync('2000000 WP5\n');
    final procs = <Process>[
      for (var i = 0; i < 8; i++)
        await Process.start(
          'bash',
          [
            '-c',
            '. "$lib"; emu_lock_acquire emulator-5560 2>/dev/null && { echo won; sleep 4; }',
          ],
          environment: {
            ...env,
            'WENDELIN_WP': 'WP$i',
            // Fenster zwischen Prüfung und Räumen aufweiten: ohne Mutex gewinnen mehrere.
            'WENDELIN_LOCK_TEST_DELAY': '1',
          },
        ),
    ];
    var won = 0;
    await Future.wait([
      for (final p in procs)
        () async {
          unawaited(p.stderr.drain<void>());
          final out = await p.stdout.transform(utf8.decoder).join();
          if (out.contains('won')) won++;
        }(),
    ]).timeout(const Duration(seconds: 60));
    t.eq(won, 1, 'acht gleichzeitige Übernahmen: genau einer gewinnt');
  }

  /// Sperre ohne info-Datei: frisch belegt, nach einer Minute verwaist.
  void noInfo() {
    final o = Directory('$dir/locks/emulator-5562.lock')
      ..createSync(recursive: true);
    final fresh = sh('emu_lock_acquire emulator-5562; echo "exit=\$?"');
    t.isTrue(
      (fresh.stdout as String).contains('exit=1'),
      'Sperre ohne info, frisch: belegt',
    );
    Process.runSync('touch', ['-t', '202001010000', o.path]);
    final take = sh('emu_lock_acquire emulator-5562; echo "exit=\$?"');
    t.isTrue(
      (take.stdout as String).contains('exit=0'),
      'Sperre ohne info, alt: übernommen: ${take.stderr}',
    );
  }

  /// Die Freigabe räumt nur die eigene Sperre.
  Future<void> foreignRelease() async {
    final other = await hold('emulator-5558', 'WP3');
    final rel = sh(
      '_emu_lock_dir="$dir/locks/emulator-5558.lock"; emu_lock_release',
    );
    t.isTrue(rel.exitCode == 0, 'Release ohne Besitz: kein Fehler');
    t.isTrue(exists('emulator-5558'), 'fremde Sperre bleibt bestehen');
    other.kill(ProcessSignal.sigterm);
    await other.exitCode.timeout(const Duration(seconds: 20));
  }

  void wpName() {
    final repo = Sandbox(Directory('$dir/r')..createSync());
    repo.git(['init', '-q', '-b', 'wp/110-agent-guardrails-ci']);
    repo.commit('a', 'a');
    final name = Process.runSync('bash', [
      '-c',
      '. "$lib"; ROOT="${repo.dir.path}"; emu_lock_wp',
    ]);
    t.eq((name.stdout as String).trim(), 'WP110', 'WP-Name aus dem Branch');
  }

  /// e2e_android.sh bindet die Sperre ein und gibt in cleanup frei.
  void wiring() {
    final e2e = File('tool/e2e_android.sh').readAsStringSync();
    t.isTrue(
      e2e.contains('emu_lock_acquire "\$DEVICE"') &&
          RegExp(r'\n  emu_lock_release\n\}\ntrap cleanup EXIT').hasMatch(e2e),
      'e2e_android.sh: acquire nach Geräteauswahl, release am Ende von cleanup',
    );
  }
}
