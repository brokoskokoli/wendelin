// Selbsttests für Gate-Cache, Semaphor und .so-Cache (WP97).
import 'dart:convert';
import 'dart:io';

import 'gate_cache.dart';
import 'gate_lock_self_test.dart';
import 'gate_run.dart';
import 'gate_rust.dart';
import 'self_check.dart';

/// Alle Prüfungen von WP97.
Future<void> gateCacheChecks(SelfCheck t) async {
  _sha(t);
  _keys(t);
  await _gateWithCache(t);
  await _rust(t);
  await gateLockChecks(t);
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

    t.isTrue(
      key({...base, 'packages/a/lib/x.dart': null}) != k,
      'gelöschte, noch getrackte Datei: Marker gehört zum Schlüssel',
    );
    final all = _cache(tmp, base);
    t.isTrue(
      all.keyFor('analyze', analyzeSpec(['packages/a'])) !=
          all.keyFor('analyze', analyzeSpec(['packages/a', 'packages/b'])),
      'analyze: Teillauf und voller Lauf haben verschiedene Schlüssel',
    );
    t.eq(
      all.keyFor('analyze', analyzeSpec(['packages/b', 'packages/a'])),
      all.keyFor('analyze', analyzeSpec(['packages/a', 'packages/b'])),
      'analyze: Reihenfolge der Ordner egal',
    );
    const ft = {'dart': '3', 'flutter': '4'};
    final withDesign = {...base, 'docs/design/tokens.json': 't'};
    t.isTrue(
      _cache(tmp, withDesign, tools: ft).keyFor('test app', appSpec(['app'])) !=
          _cache(tmp, {
            ...withDesign,
            'docs/design/tokens.json': 't2',
          }, tools: ft).keyFor('test app', appSpec(['app'])),
      'App-Schlüssel hängt von docs/design/tokens.json ab',
    );
    t.isTrue(
      kotlinSpec('/sdk').roots.contains('app/android') &&
          kotlinSpec('/sdk').roots.contains('native/attest') &&
          _cache(tmp, base, tools: ft).keyFor('k', kotlinSpec('/a')) !=
              _cache(tmp, base, tools: ft).keyFor('k', kotlinSpec('/b')),
      'kotlin-unit: Wurzeln und SDK im Schlüssel',
    );

    t.isTrue(
      _cache(tmp, base, tools: ft).keyFor('k', kotlinSpec('/a', jdk: '17')) !=
          _cache(tmp, base, tools: ft).keyFor('k', kotlinSpec('/a', jdk: '21')),
      'kotlin-unit: JDK-Version im Schlüssel',
    );
    t.eq(
      jdkVersion({
        'JAVA_HOME': '/jh',
      }, probe: (e) => e == '/jh/bin/java' ? 'openjdk 21\n' : null),
      'openjdk 21',
      'jdkVersion: JAVA_HOME zuerst',
    );
    t.eq(
      jdkVersion({}, probe: (e) => e == 'java' ? 'v17' : null),
      'v17',
      'jdkVersion: java im PATH',
    );
    t.eq(jdkVersion({}, probe: (_) => null), '', 'jdkVersion: fail-open');

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
      'b': {'c'},
      'c': <String>{},
    };
    t.eq(cacheRoots('a', deps), [
      'packages/a',
      'packages/b',
      'packages/c',
    ], 'Wurzeln: transitive Abhängigkeiten a→b→c');
    t.eq(cacheRoots('app', deps), [
      'app',
      'packages/a',
      'packages/b',
      'packages/c',
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
    // Schritt verändert seine eigenen Eingaben: Schlüssel von vorher passt nicht.
    final before = runs;
    files['packages/a/lib/a.dart'] = 'v1';
    final mutating = Gate(
      verbose: false,
      out: StringBuffer(),
      cache: _cache(tmp, files),
      runner: (e, a, {cwd, required verbose}) async {
        runs++;
        files['packages/a/lib/a.dart'] = 'v2';
        return const ProcResult(0);
      },
    );
    await mutating.step('gen', 'x', const [], cacheSpec: spec);
    files['packages/a/lib/a.dart'] = 'v1';
    await mutating.step('gen', 'x', const [], cacheSpec: spec);
    t.eq(runs - before, 2, 'Schritt ändert Dateien: nichts gespeichert');
    final off = Gate(
      verbose: false,
      out: StringBuffer(),
      runner: (e, a, {cwd, required verbose}) async {
        runs++;
        return const ProcResult(0);
      },
    );
    await off.step('test a', 'dart', const [], cacheSpec: spec);
    t.eq(runs - before, 3, 'ohne Cache läuft der Schritt');
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

Never fail(String m) => throw StateError(m);

/// `.so`-Cache von `tool/build_attest_android.sh` mit Attrappen für cargo.
/// Das Skript läuft aus einer Kopie in einem temporären Repo-Gerüst.
Future<void> _attestScript(SelfCheck t) async {
  t.group('Attest-.so-Cache (build_attest_android.sh)');
  if (Platform.isWindows) return;
  final tmp = Directory.systemTemp.createTempSync('attest_cache_');
  try {
    final repo = Directory('${tmp.path}/repo')..createSync();
    Directory('${repo.path}/tool').createSync();
    Directory('${repo.path}/native/attest/src').createSync(recursive: true);
    Directory('${repo.path}/native/attest/target').createSync();
    File('${repo.path}/native/attest/src/lib.rs').writeAsStringSync('x');
    final script = File('${repo.path}/tool/build_attest_android.sh')
      ..writeAsStringSync(
        File('tool/build_attest_android.sh').readAsStringSync(),
      );
    final bin = Directory('${tmp.path}/bin')..createSync();
    final pre = Directory('${tmp.path}/pre')..createSync();
    final log = File('${tmp.path}/builds.log')..writeAsStringSync('');
    final envLog = File('${tmp.path}/env.log')..writeAsStringSync('');
    final ndk = Directory('${tmp.path}/ndk')..createSync();
    File('${ndk.path}/source.properties').writeAsStringSync('Pkg.Revision=1\n');
    File('${bin.path}/cargo').writeAsStringSync(_fakeCargo('bin', log, envLog));
    File('${bin.path}/cargo-ndk').writeAsStringSync('#!/bin/sh\n');
    File('${bin.path}/sccache').writeAsStringSync('#!/bin/sh\n');
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
        [script.path, out.path, abis],
        includeParentEnvironment: false,
        environment: {
          'PATH': '${bin.path}:/usr/bin:/bin',
          'HOME': tmp.path,
          'WENDELIN_RUST_BIN_DIRS': '',
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

    File('${repo.path}/native/attest/target/artefakt')
        .writeAsStringSync('build-ausgabe');
    await run('x86_64');
    t.eq(builds().length, 6, 'target/ gehört nicht zum Schlüssel');
    File('${repo.path}/native/attest/src/lib.rs').writeAsStringSync('y');
    await run('x86_64');
    t.eq(builds().length, 7, 'Quelländerung: neuer Schlüssel');
    script.writeAsStringSync('${script.readAsStringSync()}\n# geändert\n');
    await run('x86_64');
    t.eq(builds().length, 8, 'geändertes Skript: neuer Schlüssel');
    File('${repo.path}/native/attest/src/neu.rs').writeAsStringSync('z');
    await run('x86_64');
    t.eq(builds().length, 9, 'neue Quelldatei: neuer Schlüssel');

    // sccache: lokal genutzt, in CI nicht.
    envLog.writeAsStringSync('');
    await run('x86_64', env: {'WENDELIN_ATTEST_CACHE': '0'});
    t.isTrue(
      envLog.readAsStringSync().contains('wrapper=sccache'),
      'lokal: sccache als Wrapper',
    );
    envLog.writeAsStringSync('');
    await run('x86_64', env: {'CI': 'true'});
    t.isTrue(
      envLog.readAsStringSync().contains('wrapper=none'),
      'CI: kein sccache',
    );

    await _rustDirOrder(t, tmp, pre, log, envLog, run);
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

/// Reihenfolge der vorangestellten Rust-Ordner in `build_attest_android.sh`.
Future<void> _rustDirOrder(
  SelfCheck t,
  Directory tmp,
  Directory pre,
  File log,
  File envLog,
  Future<void> Function(String, {Map<String, String> env}) run,
) async {
  // PATH-Reihenfolge: Rust-Ordner stehen vor dem übrigen PATH.
  File('${pre.path}/cargo').writeAsStringSync(_fakeCargo('pre', log, envLog));
  Process.runSync('chmod', ['+x', '${pre.path}/cargo']);
  envLog.writeAsStringSync('');
  await run(
    'x86_64',
    env: {'WENDELIN_ATTEST_CACHE': '0', 'WENDELIN_RUST_BIN_DIRS': pre.path},
  );
  t.isTrue(
    envLog.readAsStringSync().contains('pre') &&
        !envLog.readAsStringSync().contains('bin'),
    'cargo aus den Rust-Ordnern gewinnt gegen den übrigen PATH',
  );
  // Reihenfolge der Liste: der erste Ordner gewinnt.
  final pre2 = Directory('${tmp.path}/pre2')..createSync();
  File('${pre2.path}/cargo').writeAsStringSync(_fakeCargo('pre2', log, envLog));
  Process.runSync('chmod', ['+x', '${pre2.path}/cargo']);
  envLog.writeAsStringSync('');
  await run(
    'x86_64',
    env: {
      'WENDELIN_ATTEST_CACHE': '0',
      'WENDELIN_RUST_BIN_DIRS': '${pre.path}:${pre2.path}',
    },
  );
  t.isTrue(
    envLog.readAsStringSync().contains('pre') &&
        !envLog.readAsStringSync().contains('pre2'),
    'erster Rust-Ordner der Liste gewinnt',
  );
}

String _fakeCargo(String tag, File log, File envLog) =>
    '''#!/usr/bin/env bash
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
echo "wrapper=\${RUSTC_WRAPPER:-none}" >>"${envLog.path}"
echo "$tag" >>"${envLog.path}"
for a in "\${abis[@]}"; do
  mkdir -p "\$o/\$a"
  echo "so-\$a" >"\$o/\$a/libwendelin_attest.so"
  echo dep >"\$o/\$a/libdcap.so"
done
''';

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
          ? _cache(
              tmp,
              files,
              tools: {'dart': '1', 'rust': 'r', 'frb': 'f', 'deny': 'd'},
            )
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
    await rustSteps(gate(), ci: true, toolDir: withSccache, snapshot: same);
    t.isTrue(
      !has('fetch') && !has('--offline'),
      'CI: weder fetch noch --offline',
    );
    t.isTrue(
      !calls.any((c) => c.any((a) => a.startsWith('RUSTC_WRAPPER'))),
      'CI: kein sccache',
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
      today: '2026-01-01',
    );
    final first = calls.length;
    calls = [];
    final g = gate(cache: true);
    await rustSteps(
      g,
      ci: false,
      toolDir: withSccache,
      snapshot: same,
      today: '2026-01-01',
    );
    t.isTrue(first > 5, 'erster Lauf ruft cargo auf');
    t.eq(
      g.results
          .where((r) => r.outcome == Outcome.cached)
          .map((r) => r.name)
          .toList(),
      ['rust fmt', 'rust clippy', 'rust test', 'rust deny', 'rust frb'],
      'zweiter Lauf: Schritte cached',
    );
    t.isTrue(
      !has('fetch') && !has('clippy') && !has('test'),
      'cached: kein fetch, kein cargo',
    );
    t.isTrue(!has('deny'), 'cargo-deny am selben Tag gecacht');
    calls = [];
    await rustSteps(
      gate(cache: true),
      ci: false,
      toolDir: withSccache,
      snapshot: same,
      today: '2099-01-01',
    );
    t.isTrue(has('deny') && !has('clippy'), 'neuer Tag: nur deny läuft neu');
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
