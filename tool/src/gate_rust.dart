// Rust-Schritte des Gates für `native/attest` (WP47): fmt, clippy, test, deny und
// „flutter_rust_bridge-Code aktuell“. Ohne Rust-Toolchain werden die Schritte lokal übersprungen
// (Hinweis in der Tabelle), in CI (`CI=true`) sind fehlende Werkzeuge ein Fehler.
import 'dart:io';

import 'gate_cache.dart';
import 'gate_run.dart';

/// Prüfziel für `dart run tool/gate.dart native/attest`.
const rustTarget = 'native/attest';

/// Crate-Ordner.
const rustDir = 'native/attest';

/// Von `flutter_rust_bridge_codegen` erzeugte Dateien (müssen eingecheckt und aktuell sein).
const frbGeneratedDirs = ['app/lib/platform/attest/generated'];
const frbGeneratedFiles = ['$rustDir/src/frb_generated.rs'];

/// Orte, an denen `cargo` & Co. außerhalb des Shell-PATH liegen (rustup ist unter Homebrew keg-only).
List<String> rustSearchDirs(String home) => [
  '$home/.cargo/bin',
  '/opt/homebrew/opt/rustup/bin',
  '/usr/local/opt/rustup/bin',
];

/// Findet ein Programm im PATH oder in [rustSearchDirs]; liefert den Ordner oder null.
String? findToolDir(
  String tool, {
  required Iterable<String> path,
  required String home,
  required bool Function(String file) exists,
}) {
  for (final d in [...path, ...rustSearchDirs(home)]) {
    if (exists('$d/$tool')) return d;
  }
  return null;
}

/// Hinweis für das lokale Überspringen, oder `null`, wenn der Schritt laufen soll.
/// In CI führt ein fehlendes Werkzeug zu einem Fehler ([ci]).
enum RustTool {
  /// `cargo` (Toolchain).
  cargo('cargo', 'Rust fehlt (rustup, Android-Targets: docs/ENGINEERING.md)'),

  /// `cargo-deny`.
  deny('cargo-deny', 'cargo-deny fehlt (cargo install cargo-deny --locked)'),

  /// `flutter_rust_bridge_codegen`.
  codegen(
    'flutter_rust_bridge_codegen',
    'flutter_rust_bridge_codegen fehlt (cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked)',
  ),

  /// `sccache` (optional, WP97): beschleunigt Rust-Builds, fehlt er, läuft alles wie bisher.
  sccache('sccache', 'sccache fehlt (optional)');

  const RustTool(this.binary, this.hint);

  /// Programmname.
  final String binary;

  /// Text bei fehlendem Werkzeug.
  final String hint;
}

/// Inhalte der erzeugten Dateien (Pfad → Bytes) für den Vorher/Nachher-Vergleich.
Map<String, List<int>> snapshotGenerated({
  List<String> dirs = frbGeneratedDirs,
  List<String> files = frbGeneratedFiles,
}) {
  final out = <String, List<int>>{};
  for (final d in dirs) {
    final dir = Directory(d);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      out[f.path] = f.readAsBytesSync();
    }
  }
  for (final p in files) {
    final f = File(p);
    if (f.existsSync()) out[p] = f.readAsBytesSync();
  }
  return out;
}

/// Pfade, die sich zwischen [before] und [after] unterscheiden (geändert, neu oder weggefallen).
List<String> changedFiles(
  Map<String, List<int>> before,
  Map<String, List<int>> after,
) {
  bool same(List<int> a, List<int> b) =>
      a.length == b.length &&
      !Iterable<int>.generate(a.length).any((i) => a[i] != b[i]);
  return [
    for (final k in {...before.keys, ...after.keys})
      if (before[k] == null || after[k] == null || !same(before[k]!, after[k]!))
        k,
  ]..sort();
}

/// Führt die Rust-Schritte aus. [toolDir] liefert den Ordner eines Werkzeugs (null = nicht vorhanden).
Future<void> rustSteps(
  Gate gate, {
  required bool ci,
  required String? Function(RustTool tool) toolDir,
  Map<String, List<int>> Function() snapshot = snapshotGenerated,
  Map<String, String> env = const {},
  String? today,
}) async {
  final day = today ?? DateTime.now().toIso8601String().substring(0, 10);
  void skipOrFail(String name, RustTool t) => gate.record(
    StepResult(
      name,
      ci ? Outcome.red : Outcome.skipped,
      Duration.zero,
      ci ? '${t.binary} fehlt in CI' : t.hint,
    ),
  );

  final cargoDir = toolDir(RustTool.cargo);
  if (cargoDir == null) {
    skipOrFail('rust', RustTool.cargo);
    return;
  }
  // rustup-Proxys und Unterbefehle (cargo-deny) brauchen die Ordner im PATH.
  final extra = {
    cargoDir,
    ?toolDir(RustTool.deny),
    ?toolDir(RustTool.codegen),
  }.join(':');
  // sccache nur, wenn vorhanden und nicht schon ein Wrapper gesetzt ist.
  final sccacheDir = ci ? null : toolDir(RustTool.sccache);
  final wrapper = [
    if (sccacheDir != null && (env['RUSTC_WRAPPER'] ?? '').isEmpty) ...[
      'RUSTC_WRAPPER=$sccacheDir/sccache',
      'CARGO_INCREMENTAL=0',
    ],
  ];
  final path = 'PATH=$extra:${Platform.environment['PATH'] ?? ''}';
  // Einmal `cargo fetch --locked`; danach laufen die Schritte mit --offline
  // (kein Zugriff auf die Paket-Cache-Sperre). Schlägt es fehl, läuft alles
  // wie bisher ohne --offline.
  bool? offline;
  Future<List<String>> offlineFlag() async {
    offline ??=
        (await gate.runner(
          'env',
          [path, 'cargo', 'fetch', '--locked'],
          cwd: rustDir,
          verbose: false,
        )).exitCode ==
        0;
    return [if (offline!) '--offline'];
  }

  Future<bool> cargo(
    String name,
    List<String> args, {
    String? cwd = rustDir,
    Future<StepCheck> Function(ProcResult)? check,
    bool useOffline = false,
    CacheSpec? spec,
  }) async {
    // fetch nur, wenn der Schritt wirklich läuft (kein Cache-Treffer).
    final run = spec == null || !(gate.cache?.isHit(name, spec) ?? false);
    // In CI wie bisher: weder fetch noch --offline.
    final off = useOffline && run && !ci
        ? await offlineFlag()
        : const <String>[];
    return gate.step(
      name,
      'env',
      [path, ...wrapper, 'cargo', args.first, ...off, ...args.skip(1)],
      cwd: cwd,
      check: check,
      cacheSpec: spec,
    );
  }

  const crate = CacheSpec([rustDir], tools: ['rust']);
  await cargo('rust fmt', ['fmt', '--check'], spec: crate);
  await cargo(
    'rust clippy',
    ['clippy', '--all-targets', '--locked', '--', '-D', 'warnings'],
    useOffline: true,
    spec: crate,
  );
  await cargo(
    'rust test',
    ['test', '--locked'],
    check: (r) async => (detail: _passed(r.lines), failure: null),
    useOffline: true,
    spec: crate,
  );
  // cargo-deny prüft die Advisory-DB: das Tagesdatum gehört zum Schlüssel,
  // ein Treffer gilt also höchstens bis Mitternacht.
  if (toolDir(RustTool.deny) == null) {
    skipOrFail('rust deny', RustTool.deny);
  } else {
    await cargo(
      'rust deny',
      ['deny', 'check'],
      spec: CacheSpec(
        const [rustDir],
        tools: const ['rust', 'deny'],
        extra: ['date:$day'],
      ),
    );
  }
  if (toolDir(RustTool.codegen) == null) {
    skipOrFail('rust frb', RustTool.codegen);
    return;
  }
  final before = snapshot();
  await gate.step(
    'rust frb',
    'env',
    [path, 'flutter_rust_bridge_codegen', 'generate'],
    cwd: 'app',
    cacheSpec: const CacheSpec(
      [rustDir, ...frbGeneratedDirs, 'app/flutter_rust_bridge.yaml'],
      tools: ['rust', 'frb'],
    ),
    check: (_) async {
      final diff = changedFiles(before, snapshot());
      return (
        detail: diff.isEmpty ? 'aktuell' : '',
        failure: diff.isEmpty
            ? null
            : 'generierter Code nicht aktuell (jetzt neu erzeugt, bitte einchecken): ${diff.join(', ')}',
      );
    },
  );
}

/// Summe der bestandenen Tests aus der `cargo test`-Ausgabe.
String _passed(List<String> lines) {
  var n = 0;
  final re = RegExp(r'test result: ok\. (\d+) passed');
  for (final l in lines) {
    n += int.parse(re.firstMatch(l)?.group(1) ?? '0');
  }
  return n == 0 ? '' : '$n Tests';
}
