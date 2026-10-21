// Selbsttests von tool/emulator_boot.sh und der Einbindung in
// tool/e2e_android.sh (WP124). Fake-adb und Fake-emulator, kein echter Emulator.
import 'dart:io';

import 'self_check.dart';

Future<void> emulatorBootChecks(SelfCheck t) async {
  t.group('Emulator-Autostart');
  final dir = Directory.systemTemp.createTempSync('emuboot_selftest_');
  try {
    _Boot(t, dir.path)
      ..start()
      ..alreadyRunning()
      ..keep()
      ..port()
      ..realDevice()
      ..doubleStart()
      ..staleMutex()
      ..timeout()
      ..diesEarly()
      ..wiring();
  } finally {
    _killFake(dir.path);
    dir.deleteSync(recursive: true);
  }
}

void _killFake(String dir) {
  final pid = File('$dir/emu.pid');
  if (pid.existsSync()) {
    Process.runSync('kill', [pid.readAsStringSync().trim()]);
  }
}

final class _Boot {
  _Boot(this.t, this.dir) : lib = File('tool/emulator_boot.sh').absolute.path {
    File('$dir/adb').writeAsStringSync(_fakeAdb);
    File('$dir/emulator').writeAsStringSync(_fakeEmulator);
    for (final f in ['adb', 'emulator']) {
      Process.runSync('chmod', ['+x', '$dir/$f']);
    }
  }

  final SelfCheck t;
  final String dir;
  final String lib;

  void reset({String devices = ''}) {
    _killFake(dir);
    for (final f in [
      'booted',
      'emu.pid',
      'emu.args',
      'adb.log',
      'devices.txt',
    ]) {
      final file = File('$dir/$f');
      if (file.existsSync()) file.deleteSync();
    }
    final locks = Directory('$dir/locks');
    if (locks.existsSync()) locks.deleteSync(recursive: true);
    File('$dir/devices.txt').writeAsStringSync(devices);
    if (devices.contains('emulator-')) File('$dir/booted').createSync();
  }

  String read(String name) {
    final f = File('$dir/$name');
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  ProcessResult sh(String body, {Map<String, String> extra = const {}}) =>
      Process.runSync(
        'bash',
        ['-c', '. "$lib"; $body'],
        environment: {
          'ADB': '$dir/adb',
          'EMULATOR': '$dir/emulator',
          'FAKE_DIR': dir,
          'TMPDIR': dir,
          'WENDELIN_LOCK_DIR': '$dir/locks',
          'EMU_POLL': '0.05',
          'DEVICE': '',
          'ANDROID_SERIAL': '',
          'E2E_KEEP_EMULATOR': '',
          ...extra,
        },
      );

  static const ensureStop =
      'emu_boot_ensure || exit 7; echo "DEVICE=\$DEVICE"; emu_boot_stop';

  void start() {
    reset();
    final r = sh(ensureStop);
    final args = read('emu.args');
    t.isTrue(
      (r.stdout as String).contains('DEVICE=emulator-5554'),
      'Start: DEVICE=emulator-5554 gesetzt: ${r.stdout}${r.stderr}',
    );
    t.isTrue(
      args.contains('-avd Wendelin_AOSP_35') &&
          args.contains('-port 5554') &&
          args.contains('-no-window') &&
          args.contains('-no-audio') &&
          args.contains('-no-boot-anim') &&
          args.contains('-no-snapshot-save'),
      'Start: Emulator mit AVD, Port und Headless-Flags: $args',
    );
    t.isTrue(
      File('$dir/wendelin-emulator-emulator-5554.log').existsSync(),
      'Start: Log in TMPDIR',
    );
    t.isTrue(
      read('adb.log').contains('emu kill') &&
          !read('devices.txt').contains('emulator-'),
      'Ende: Emulator per „adb emu kill“ beendet und weg',
    );
    t.isTrue(
      !Directory('$dir/locks/emulator-5554.start').existsSync(),
      'Start-Mutex danach frei',
    );
  }

  void alreadyRunning() {
    reset(devices: 'emulator-5554\tdevice\n');
    final r = sh(ensureStop);
    t.isTrue(
      (r.stdout as String).contains('DEVICE=emulator-5554') &&
          read('emu.args').isEmpty,
      'Läuft schon: kein zweiter Start, DEVICE gesetzt: ${r.stdout}',
    );
    t.isTrue(read('adb.log').contains('emu kill'), 'Läuft schon: wird beendet');
  }

  void keep() {
    reset(devices: 'emulator-5554\tdevice\n');
    final r = sh(ensureStop, extra: {'E2E_KEEP_EMULATOR': '1'});
    t.isTrue(
      !read('adb.log').contains('emu kill') &&
          read('devices.txt').contains('emulator-5554') &&
          (r.stdout as String).contains('läuft weiter'),
      'E2E_KEEP_EMULATOR=1: Emulator läuft weiter: ${r.stdout}',
    );
  }

  void port() {
    reset();
    final r = sh(ensureStop, extra: {'DEVICE': 'emulator-5560'});
    t.isTrue(
      read('emu.args').contains('-port 5560') &&
          (r.stdout as String).contains('DEVICE=emulator-5560'),
      'DEVICE=emulator-5560: Port 5560: ${read('emu.args')}',
    );
  }

  void realDevice() {
    reset(devices: 'R58\tdevice\n');
    final r = sh(ensureStop);
    t.isTrue(
      (r.stdout as String).contains('DEVICE=emulator-5554') &&
          read('emu.args').contains('-port 5554'),
      'Nur echtes Gerät: Emulator wird gestartet und benutzt: ${r.stdout}${r.stderr}',
    );
    t.isTrue(
      read('adb.log').contains('-s emulator-5554 emu kill') &&
          !read('adb.log').contains('R58') &&
          read('devices.txt').contains('R58'),
      'Nur der Emulator wird beendet, das echte Gerät nie',
    );
    reset(devices: 'R58\tdevice\n');
    sh(ensureStop, extra: {'DEVICE': 'R58'});
    t.isTrue(
      read('emu.args').isEmpty && !read('adb.log').contains('emu kill'),
      'DEVICE=echtes Gerät: weder gestartet noch beendet',
    );
    reset(devices: 'R58\tdevice\nemulator-5554\tdevice\n');
    final both = sh(ensureStop);
    t.isTrue(
      (both.stdout as String).contains('DEVICE=emulator-5554') &&
          read('emu.args').isEmpty,
      'Emulator plus echtes Gerät: der Emulator wird gewählt',
    );
  }

  void doubleStart() {
    reset();
    final m = Directory('$dir/locks/emulator-5554.start')
      ..createSync(recursive: true);
    final holder = Process.runSync('bash', [
      '-c',
      'sleep 30 >/dev/null 2>&1 & echo \$!',
    ]);
    final hpid = (holder.stdout as String).trim();
    File('${m.path}/pid').writeAsStringSync(hpid);
    final r = sh(ensureStop);
    Process.runSync('kill', [hpid]);
    t.isTrue(
      r.exitCode == 7 &&
          (r.stderr as String).contains('gerade von einem anderen Lauf') &&
          read('emu.args').isEmpty,
      'Doppelstart: zweiter Lauf bricht sofort ab, kein zweiter Emulator: ${r.stderr}',
    );
  }

  void staleMutex() {
    reset();
    final m = Directory('$dir/locks/emulator-5554.start')
      ..createSync(recursive: true);
    File('${m.path}/pid').writeAsStringSync('2000000');
    final r = sh(ensureStop);
    t.isTrue(
      r.exitCode == 0 && read('emu.args').contains('-port 5554'),
      'Verwaister Start-Mutex wird übernommen: ${r.stderr}',
    );
  }

  void timeout() {
    reset();
    final r = sh(
      ensureStop,
      extra: {'FAKE_MODE': 'hang', 'EMU_BOOT_TIMEOUT': '1'},
    );
    t.isTrue(
      r.exitCode == 7 && (r.stderr as String).contains('nicht hochgefahren'),
      'Boot-Zeitlimit: Abbruch mit klarer Meldung: ${r.stderr}',
    );
    t.isTrue(
      read('adb.log').contains('emu kill') &&
          !Directory('$dir/locks/emulator-5554.start').existsSync(),
      'Zeitlimit: Emulator beendet, Mutex frei',
    );
  }

  void diesEarly() {
    reset();
    final r = sh(ensureStop, extra: {'FAKE_MODE': 'die'});
    t.isTrue(
      r.exitCode == 7 && (r.stderr as String).contains('vorzeitig'),
      'Emulator bricht sofort ab: Meldung statt Warten bis zum Limit: ${r.stderr}',
    );
  }

  /// e2e_android.sh: erst starten, dann Geräteauswahl; Beenden vor Sperrfreigabe.
  void wiring() {
    final e2e = File('tool/e2e_android.sh').readAsStringSync();
    final boot = e2e.indexOf('emu_boot_ensure ||');
    final pick = e2e.indexOf('. "\$ROOT/tool/android_device.sh"');
    t.isTrue(
      boot > 0 && pick > boot,
      'e2e_android.sh: emu_boot_ensure vor android_device.sh',
    );
    t.isTrue(
      RegExp(r'\n  emu_boot_stop\n  emu_lock_release\n\}').hasMatch(e2e) &&
          e2e.contains("trap 'emu_boot_stop; emu_lock_release' EXIT"),
      'e2e_android.sh: Emulator beenden vor Freigabe der Sperre (cleanup und früher trap)',
    );
  }
}

const _fakeAdb = r'''#!/usr/bin/env bash
d="$FAKE_DIR"
echo "$*" >>"$d/adb.log"
serial=""
if [ "$1" = -s ]; then serial="$2"; shift 2; fi
case "$1" in
  devices) echo "List of devices attached"; cat "$d/devices.txt" 2>/dev/null ;;
  shell) [ -f "$d/booted" ] && echo 1 ;;
  emu)
    [ -f "$d/emu.pid" ] && kill "$(cat "$d/emu.pid")" 2>/dev/null
    grep -v "^$serial" "$d/devices.txt" >"$d/devices.new" 2>/dev/null
    mv "$d/devices.new" "$d/devices.txt"
    rm -f "$d/booted" ;;
esac
exit 0
''';

const _fakeEmulator = r'''#!/usr/bin/env bash
d="$FAKE_DIR"
echo "$*" >>"$d/emu.args"
[ "${FAKE_MODE:-}" = die ] && exit 1
echo $$ >"$d/emu.pid"
if [ "${FAKE_MODE:-}" != hang ]; then
  sleep 0.2
  port=""
  while [ $# -gt 0 ]; do [ "$1" = -port ] && port="$2"; shift; done
  printf 'emulator-%s\tdevice\n' "$port" >>"$d/devices.txt"
  touch "$d/booted"
fi
exec sleep 300
''';
