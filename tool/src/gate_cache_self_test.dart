// Selbsttests für Gate-Cache, Semaphor und .so-Cache (WP97).
import 'dart:convert';
import 'dart:io';

import 'gate_cache.dart';
import 'gate_lock.dart';
import 'gate_run.dart';
import 'gate_rust.dart';
import 'self_check.dart';

/// Alle Prüfungen von WP97.
Future<void> gateCacheChecks(SelfCheck t) async {
  _sha(t);
  _keys(t);
  await _gateWithCache(t);
  await _rust(t);
  _slotsSync(t);
  await _slots(t);
  await _attestScript(t);
}

void _sha(SelfCheck t) {
  t.group('Gate-Cache: sha256');
  t.eq(
    sha256Hex(utf8.encode('abc')),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    'Testvektor abc',
  );
  t.eq(
    sha256Hex(const []),
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    'leere Eingabe',
  );
  t.eq(
    sha256Hex(List.filled(1000, 97)),
    '41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3',
    'mehrere Blöcke',
  );
}

/// Cache mit Dateien im Speicher; `null` als Inhalt = Datei fehlt.
GateCache _cache(
  Directory dir,
  Map<String, String?> files, {
  Map<String, String?>? tools,
  bool failList = false,
  bool failRead = false,
}) => GateCache(
  dir: dir,
  listFiles: () {
    if (failList) throw const ProcessException('git', [], 'kaputt', 128);
    return files.keys.toList();
  },
  toolVersion: (tool) => (tools ?? const {'dart': '3.13'})[tool],
  readFile: (p) {
    if (failRead) throw const FileSystemException('kaputt');
    final c = files[p];
    return c == null ? null : utf8.encode(c);
  },
);

void _keys(SelfCheck t) {
  t.group('Gate-Cache: Schlüssel');
  final tmp = Directory.systemTemp.createTempSync('gate_cache_');
  try {
    final base = {
      'packages/a/lib/a.dart': 'a',
      'packages/b/lib/b.dart': 'b',
      'pubspec.lock': 'lock',
      'pubspec.yaml': 'ws',
      'analysis_options.yaml': 'ao',
      'tool/gate.dart': 'gate',
    };
    const spec = CacheSpec(['packages/a']);
    String? key(
      Map<String, String?> files, {
      CacheSpec s = spec,
      String step = 'test a',
      Map<String, String?>? tools,
    }) => _cache(tmp, files, tools: tools).keyFor(step, s);

    final k = key(base);
    t.isTrue(k != null && k.length == 64, 'Schlüssel ist ein sha256');
    t.eq(key({...base}), k, 'gleicher Inhalt, gleicher Schlüssel');
    t.eq(
      key({...base, 'packages/a/lib/a.dart': 'a2'}),
      key({...base, 'packages/a/lib/a.dart': 'a2'}),
      'deterministisch',
    );
    t.isTrue(
      key({...base, 'packages/a/lib/a.dart': 'a2'}) != k,
      'geänderte Datei: neuer Schlüssel',
    );
    t.isTrue(
      key({...base, 'packages/a/lib/neu.dart': ''}) != k,
      'neue (untracked) Datei: neuer Schlüssel',
    );
    t.isTrue(
      key({...base, 'packages/a/lib/a.dart': null}) != k,
      'gelöschte Datei: neuer Schlüssel',
    );
    t.eq(
      key({...base, 'packages/b/lib/b.dart': 'b2'}),
      k,
      'Datei außerhalb der Wurzeln ändert den Schlüssel nicht',
    );
    t.isTrue(
      key({
            ...base,
            'packages/b/lib/b.dart': 'b2',
          }, s: const CacheSpec(['packages/a', 'packages/b'])) !=
          key(base, s: const CacheSpec(['packages/a', 'packages/b'])),
      'Abhängigkeit in den Wurzeln: Änderung wirkt',
    );
    t.isTrue(
      key({...base, 'pubspec.lock': 'lock2'}) != k,
      'pubspec.lock ändert den Schlüssel',
    );
    t.isTrue(
      key({...base, 'tool/gate.dart': 'gate2'}) != k,
      'Gate-Code ändert den Schlüssel',
    );
    t.isTrue(
      key({
            ...base,
            'native/attest/Cargo.lock': 'x',
          }, s: const CacheSpec(['native/attest'])) !=
          key(base, s: const CacheSpec(['native/attest'])),
      'Cargo.lock unter native/attest ändert den Rust-Schlüssel',
    );
    t.isTrue(
      key(base, tools: {'dart': '3.14'}) != k,
      'Toolchain-Version ändert den Schlüssel',
    );
    t.eq(
      key(base, s: const CacheSpec(['packages/a'], tools: ['flutter'])),
      null,
      'unbekannte Toolchain: kein Schlüssel',
    );
    t.isTrue(
      key(base, step: 'analyze') != k,
      'Schrittname gehört zum Schlüssel',
    );
    t.eq(
      _cache(tmp, base, failList: true).keyFor('x', spec),
      null,
      'git-Fehler: kein Schlüssel (fail-open)',
    );
    t.eq(
      _cache(tmp, base, failRead: true).keyFor('x', spec),
      null,
      'Lesefehler: kein Schlüssel (fail-open)',
    );

    _storeAndEnv(t, tmp, base);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

void _storeAndEnv(SelfCheck t, Directory tmp, Map<String, String?> base) {
  {
    final deps = {
      'app': {'a', 'b'},
      'a': {'b'},
      'b': <String>{},
    };
    t.eq(cacheRoots('a', deps), [
      'packages/a',
      'packages/b',
    ], 'Wurzeln: Abhängige');
    t.eq(cacheRoots('app', deps), [
      'app',
      'packages/a',
      'packages/b',
    ], 'Wurzeln: App');

    final c = _cache(tmp, base);
    t.eq(c.lookup('abc'), null, 'kein Treffer vor dem Speichern');
    c.store('abc', '12 Tests');
    t.eq(c.lookup('abc'), '12 Tests', 'Treffer nach dem Speichern');
    t.isTrue(
      tmp.listSync().every((e) => !e.path.endsWith('.tmp')),
      'keine tmp-Reste (atomares Schreiben)',
    );
    final tmpFile = File('${tmp.path}/abc')
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 60)));
    c.prune();
    t.isTrue(!tmpFile.existsSync(), 'alte Einträge werden entfernt');

    t.isTrue(
      GateCache.fromEnvironment({'HOME': tmp.path}, const []) != null,
      'Cache standardmäßig an',
    );
    t.eq(
      GateCache.fromEnvironment({'HOME': tmp.path, 'CI': 'true'}, const []),
      null,
      'CI=true schaltet ab',
    );
    t.eq(
      GateCache.fromEnvironment({
        'HOME': tmp.path,
        'WENDELIN_GATE_CACHE': '0',
      }, const []),
      null,
      'WENDELIN_GATE_CACHE=0 schaltet ab',
    );
    t.eq(
      GateCache.fromEnvironment({'HOME': tmp.path}, const ['--no-cache']),
      null,
      '--no-cache schaltet ab',
    );

    // Echtes git: untracked Dateien erscheinen in der Liste.
    final probe = File('tool/.selftest_untracked_$pid')..writeAsStringSync('x');
    try {
      final files = gitFiles();
      t.isTrue(files.contains('tool/gate.dart'), 'git-Liste: getrackte Datei');
      t.isTrue(
        files.contains(probe.path),
        'git-Liste: untracked Datei erscheint',
      );
    } finally {
      probe.deleteSync();
    }
  }
}

Future<void> _gateWithCache(SelfCheck t) async {
  t.group('Gate-Cache: Schritt');
  final tmp = Directory.systemTemp.createTempSync('gate_cache_');
  try {
    final files = <String, String?>{'packages/a/lib/a.dart': 'a'};
    var runs = 0;
    var exit = 0;
    Gate gate() => Gate(
      verbose: false,
      out: StringBuffer(),
      cache: _cache(tmp, files),
      runner: (e, a, {cwd, required verbose}) async {
        runs++;
        return ProcResult(exit);
      },
    );
    const spec = CacheSpec(['packages/a']);
    Future<Gate> run({CacheSpec? s = spec}) async {
      final g = gate();
      await g.step(
        'test a',
        'dart',
        const [],
        cacheSpec: s,
        check: (_) async => (detail: '5 Tests', failure: null),
      );
      return g;
    }

    var g = await run();
    t.eq(runs, 1, 'erster Lauf führt den Schritt aus');
    t.eq(g.results.single.outcome, Outcome.ok, 'erster Lauf ok');
    g = await run();
    t.eq(runs, 1, 'zweiter Lauf ohne Änderung ruft nichts auf');
    t.eq(g.results.single.outcome, Outcome.cached, 'zweiter Lauf cached');
    t.eq(g.results.single.detail, '5 Tests', 'Details bleiben erhalten');
    t.eq(g.finish(Duration.zero), 0, 'cached ist nicht rot');

    files['packages/a/lib/a.dart'] = 'geändert';
    exit = 1;
    g = await run();
    t.eq(runs, 2, 'geänderte Datei: Schritt läuft');
    t.eq(g.results.single.outcome, Outcome.red, 'roter Lauf');
    g = await run();
    t.eq(runs, 3, 'roter Schritt wird nicht gespeichert');
    exit = 0;
    g = await run(s: null);
    t.eq(runs, 4, 'ohne Cache-Beschreibung läuft der Schritt');
    final off = Gate(
      verbose: false,
      out: StringBuffer(),
      runner: (e, a, {cwd, required verbose}) async {
        runs++;
        return const ProcResult(0);
      },
    );
    await off.step('test a', 'dart', const [], cacheSpec: spec);
    t.eq(runs, 5, 'ohne Cache läuft der Schritt');
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

void _slotsSync(SelfCheck t) {
  t.group('Gate-Semaphor: Umgebung');
  t.eq(gateSlotsFromEnvironment({'HOME': '/h', 'CI': 'true'}), null, 'CI: aus');
  t.eq(
    gateSlotsFromEnvironment({'HOME': '/h', 'WENDELIN_GATE_SLOTS': '0'}),
    null,
    'WENDELIN_GATE_SLOTS=0: aus',
  );
  t.eq(gateSlotsFromEnvironment({'HOME': '/h'})?.max, 2, 'Standard: 2 Läufe');
}

Future<void> _slots(SelfCheck t) async {
  t.group('Gate-Semaphor');
  final tmp = Directory.systemTemp.createTempSync('gate_slots_');
  try {
    final alive = <int>{111, 222, 333};
    final msgs = <String>[];
    GateSlots slots(int own, {Future<void> Function(Duration)? sleep}) =>
        GateSlots(
          dir: Directory('${tmp.path}/s'),
          ownPid: own,
          isAlive: alive.contains,
          sleep: sleep ?? (_) async => fail('unerwartetes Warten'),
          log: msgs.add,
          staleEmpty: Duration.zero,
        );

    final a = await slots(111).acquire();
    final b = await slots(222).acquire();
    t.isTrue(
      a.file != null && b.file != null && a.file!.path != b.file!.path,
      'zwei Läufe belegen zwei Slots',
    );
    t.isTrue(msgs.isEmpty, 'keine Meldung ohne Warten');

    var waits = 0;
    final third = await slots(
      333,
      sleep: (_) async {
        waits++;
        if (waits == 2) a.release();
      },
    ).acquire();
    t.eq(waits, 2, 'dritter Lauf wartet, bis ein Slot frei wird');
    t.isTrue(
      msgs.length == 1 && msgs.single.contains('Gate wartet'),
      'Wartemeldung genau einmal',
    );
    t.isTrue(
      third.file!.readAsStringSync() == '333',
      'Slot trägt die PID des Laufs',
    );

    alive.remove(222);
    msgs.clear();
    final fourth = await slots(444).acquire();
    t.eq(
      fourth.file!.path,
      b.file!.path,
      'Slot eines toten Prozesses wird übernommen',
    );
    t.eq(fourth.file!.readAsStringSync(), '444', 'neue PID im Slot');
    t.isTrue(msgs.isEmpty, 'tote PID: kein Warten');

    third.release();
    fourth.release();
    t.isTrue(
      Directory('${tmp.path}/s').listSync().isEmpty,
      'release räumt die Slot-Dateien auf',
    );
    fourth.release();

    // Leere Slot-Datei (Absturz zwischen Anlegen und Schreiben) ist verwaist.
    Directory('${tmp.path}/s/').createSync(recursive: true);
    File('${tmp.path}/s/slot-0.lock').createSync();
    File('${tmp.path}/s/slot-1.lock').writeAsStringSync('111');
    final e = await slots(555).acquire();
    t.eq(
      e.file!.path,
      '${tmp.path}/s/slot-0.lock',
      'leere Datei wird aufgeräumt',
    );
    e.release();
    File('${tmp.path}/s/slot-1.lock').deleteSync();

    // Ordner nicht anlegbar: fail-open.
    File('${tmp.path}/datei').writeAsStringSync('x');
    final open = await GateSlots(
      dir: Directory('${tmp.path}/datei/s'),
      log: msgs.add,
    ).acquire();
    t.isTrue(open.file == null, 'unbenutzbarer Ordner: Lauf ohne Sperre');
    open.release();
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

Never fail(String m) => throw StateError(m);

/// `.so`-Cache von `tool/build_attest_android.sh` mit Attrappen für cargo.
Future<void> _attestScript(SelfCheck t) async {
  t.group('Attest-.so-Cache (build_attest_android.sh)');
  if (Platform.isWindows) return;
  final tmp = Directory.systemTemp.createTempSync('attest_cache_');
  try {
    final bin = Directory('${tmp.path}/bin')..createSync();
    final log = File('${tmp.path}/builds.log')..writeAsStringSync('');
    final ndk = Directory('${tmp.path}/ndk')..createSync();
    File('${ndk.path}/source.properties').writeAsStringSync('Pkg.Revision=1\n');
    File('${bin.path}/cargo').writeAsStringSync('''#!/usr/bin/env bash
[ "\$1" = ndk ] || exit 0
shift
[ "\${1:-}" = "--version" ] && { echo "cargo-ndk 1.0"; exit 0; }
abis=()
while [ \$# -gt 0 ]; do
  case "\$1" in
    -t) abis+=("\$2"); shift 2 ;;
    -o) o="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
echo "\${abis[*]}" >>"${log.path}"
for a in "\${abis[@]}"; do
  mkdir -p "\$o/\$a"
  echo "so-\$a" >"\$o/\$a/libwendelin_attest.so"
  echo dep >"\$o/\$a/libdcap.so"
done
''');
    File('${bin.path}/cargo-ndk').writeAsStringSync('#!/bin/sh\n');
    File('${bin.path}/rustc')
        .writeAsStringSync('#!/bin/sh\necho "rustc 1.99.0"\n');
    for (final f in bin.listSync().whereType<File>()) {
      Process.runSync('chmod', ['+x', f.path]);
    }
    Future<void> run(String abis, {Map<String, String> env = const {}}) async {
      final out = Directory(
        '${tmp.path}/out${DateTime.now().microsecondsSinceEpoch}',
      );
      final r = await Process.run(
        'bash',
        ['tool/build_attest_android.sh', out.path, abis],
        includeParentEnvironment: false,
        environment: {
          'PATH': '${bin.path}:/usr/bin:/bin',
          'HOME': tmp.path,
          'ANDROID_NDK_HOME': ndk.path,
          'WENDELIN_ATTEST_CACHE_DIR': '${tmp.path}/cache',
          ...env,
        },
      );
      if (r.exitCode != 0) fail('build_attest_android.sh: ${r.stderr}');
      _last = out;
    }

    List<String> builds() => log.readAsLinesSync();

    await run('x86_64');
    t.eq(builds(), ['x86_64'], 'erster Lauf baut');
    t.isTrue(
      File('${_last.path}/x86_64/libwendelin_attest.so').existsSync() &&
          !File('${_last.path}/x86_64/libdcap.so').existsSync(),
      'nur unsere .so im Ausgabeordner',
    );
    await run('x86_64');
    t.eq(builds(), ['x86_64'], 'zweiter Lauf: cargo wird nicht aufgerufen');
    t.eq(
      File('${_last.path}/x86_64/libwendelin_attest.so')
          .readAsStringSync()
          .trim(),
      'so-x86_64',
      'Treffer kopiert die .so',
    );
    await run('arm64-v8a,x86_64');
    t.eq(builds(), ['x86_64', 'arm64-v8a'], 'nur die fehlende ABI wird gebaut');
    await run('arm64-v8a,x86_64');
    t.eq(builds().length, 2, 'beide ABIs aus dem Cache');
    await run('x86_64', env: {'WENDELIN_ATTEST_CACHE': '0'});
    t.eq(builds().length, 3, 'WENDELIN_ATTEST_CACHE=0 baut');
    await run('x86_64', env: {'CI': 'true'});
    t.eq(builds().length, 4, 'CI=true baut');
    await run('x86_64', env: {'RUSTFLAGS': '-C x'});
    t.eq(builds().length, 5, 'andere Toolchain-Umgebung: neuer Schlüssel');
    File('${ndk.path}/source.properties').writeAsStringSync('Pkg.Revision=2\n');
    await run('x86_64');
    t.eq(builds().length, 6, 'andere NDK-Version: neuer Schlüssel');
    await run('x86_64');
    t.eq(builds().length, 6, 'danach wieder Treffer');
    t.isTrue(
      Directory('${tmp.path}/cache')
          .listSync()
          .every((e) => !e.path.contains('.tmp.')),
      'keine tmp-Reste im Cache',
    );
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

Directory _last = Directory('.');

Future<void> _rust(SelfCheck t) async {
  t.group('Gate Rust: fetch, offline, sccache, Cache');
  final tmp = Directory.systemTemp.createTempSync('gate_cache_');
  try {
    final files = <String, String?>{'native/attest/src/lib.rs': 'x'};
    var calls = <List<String>>[];
    Gate gate({int fetchExit = 0, bool cache = false}) => Gate(
      verbose: false,
      out: StringBuffer(),
      cache: cache
          ? _cache(tmp, files, tools: {'dart': '1', 'rust': 'r', 'frb': 'f'})
          : null,
      runner: (e, a, {cwd, required verbose}) async {
        calls.add([e, ...a]);
        return ProcResult(a.contains('fetch') ? fetchExit : 0);
      },
    );
    Map<String, List<int>> same() => {
      'a': [1],
    };
    String? withSccache(RustTool tool) => '/x';
    String? noSccache(RustTool tool) => tool == RustTool.sccache ? null : '/x';
    bool has(String s, [String? step]) =>
        calls.any((c) => c.contains(s) && (step == null || c.contains(step)));

    await rustSteps(gate(), ci: false, toolDir: withSccache, snapshot: same);
    t.eq(calls.where((c) => c.contains('fetch')).length, 1, 'fetch einmal');
    t.isTrue(
      has('--offline', 'clippy') && has('--offline', 'test'),
      '--offline',
    );
    t.isTrue(
      !has('--offline', 'deny') && !has('--offline', 'fmt'),
      'deny/fmt ohne --offline',
    );
    t.isTrue(
      has('RUSTC_WRAPPER=/x/sccache') && has('CARGO_INCREMENTAL=0'),
      'sccache gesetzt',
    );

    calls = [];
    await rustSteps(gate(), ci: false, toolDir: noSccache, snapshot: same);
    t.isTrue(
      !calls.any((c) => c.any((a) => a.startsWith('RUSTC_WRAPPER'))),
      'ohne sccache kein Wrapper',
    );
    calls = [];
    await rustSteps(
      gate(),
      ci: false,
      toolDir: withSccache,
      snapshot: same,
      env: {'RUSTC_WRAPPER': 'mein'},
    );
    t.isTrue(
      !calls.any((c) => c.any((a) => a.startsWith('RUSTC_WRAPPER'))),
      'vorhandener Wrapper bleibt',
    );
    calls = [];
    await rustSteps(
      gate(fetchExit: 1),
      ci: false,
      toolDir: withSccache,
      snapshot: same,
    );
    t.isTrue(!has('--offline'), 'fetch schlägt fehl: kein --offline');

    calls = [];
    await rustSteps(
      gate(cache: true),
      ci: false,
      toolDir: withSccache,
      snapshot: same,
    );
    final first = calls.length;
    calls = [];
    final g = gate(cache: true);
    await rustSteps(g, ci: false, toolDir: withSccache, snapshot: same);
    t.isTrue(first > 5, 'erster Lauf ruft cargo auf');
    t.eq(
      g.results
          .where((r) => r.outcome == Outcome.cached)
          .map((r) => r.name)
          .toList(),
      ['rust fmt', 'rust clippy', 'rust test', 'rust frb'],
      'zweiter Lauf: Schritte cached',
    );
    t.isTrue(
      !has('fetch') && !has('clippy') && !has('test'),
      'cached: kein fetch, kein cargo',
    );
    t.isTrue(has('deny'), 'cargo-deny wird nie gecacht');
    files['native/attest/src/lib.rs'] = 'y';
    calls = [];
    await rustSteps(
      gate(cache: true),
      ci: false,
      toolDir: withSccache,
      snapshot: same,
    );
    t.isTrue(
      has('clippy') && has('fetch'),
      'Quelländerung: Schritte laufen wieder',
    );
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
