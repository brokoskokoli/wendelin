// Inhaltsadressierter Cache für Gate-Schritte (WP97).
//
// Ein grüner Schritt wird unter einem Schlüssel abgelegt: sha256 über die
// Inhalte aller zugehörigen Dateien (inklusive nicht committeter und neuer),
// die Gate-Werkzeuge unter `tool/`, die Lockfiles und die Versionen der
// Toolchains. Ändert sich nichts davon, gilt der Schritt als „cached“.
// Fail-open: bei jedem Zweifel (git-Fehler, Lesefehler, unbekannte
// Toolchain) gibt es keinen Schlüssel und der Schritt läuft.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Was zu einem Schritt gehört: Ordner/Dateien ([roots], `.` = ganzes Repo)
/// und die Toolchains ([tools]: `dart`, `flutter`, `rust`, `frb`).
final class CacheSpec {
  /// Erstellt eine Beschreibung.
  const CacheSpec(
    this.roots, {
    this.tools = const ['dart'],
    this.extra = const [],
  });

  /// Ordner und Dateien relativ zum Repo-Root.
  final List<String> roots;

  /// Benötigte Toolchains.
  final List<String> tools;

  /// Zusätzliche Schlüsselbestandteile (z. B. Schalter eines Schritts).
  final List<String> extra;
}

/// Dateien, die jeden Schlüssel beeinflussen: Lockfile, Workspace, Analyse
/// und der Gate-Code selbst.
const globalCacheRoots = [
  'pubspec.yaml',
  'pubspec.lock',
  'analysis_options.yaml',
  'tool',
];

/// Ordner eines Prüfziels (Paketname, `evals`, `app`).
String targetDir(String target) =>
    target == 'app' || target == 'evals' ? target : 'packages/$target';

/// Ordner von [target] und allen (transitiven) Workspace-Abhängigkeiten.
List<String> cacheRoots(String target, Map<String, Set<String>> deps) {
  final seen = <String>{};
  void walk(String t) {
    if (seen.add(t)) deps[t]?.forEach(walk);
  }

  walk(target);
  return [for (final t in seen) targetDir(t)]..sort();
}

/// Beschreibung des Analyse-Schritts: Die Argumente ([dirs]) gehören zum
/// Schlüssel, damit ein `--changed`-Teillauf keinen vollen Lauf vergiftet.
CacheSpec analyzeSpec(List<String> dirs) => CacheSpec(
  const ['packages', 'evals', 'tool'],
  extra: ['dirs:${(dirs.toList()..sort()).join(',')}'],
);

/// Beschreibung der App-Schritte: Wurzeln der App und ihrer Abhängigkeiten
/// plus `docs/design` (`app/test/ui/tokens_test.dart` liest `tokens.json`).
CacheSpec appSpec(List<String> roots) =>
    CacheSpec([...roots, 'docs/design'], tools: const ['dart', 'flutter']);

/// Beschreibung von `kotlin-unit`: Android-Projekt, Testdaten, das Rust-Modul
/// (Gradle-Task `buildRustAttest`), das App-Manifest und das SDK.
CacheSpec kotlinSpec(String sdk) => CacheSpec(
  const [
    'app/android',
    'app/test/fixtures/stt',
    'app/pubspec.yaml',
    'native/attest',
  ],
  tools: const ['dart', 'flutter'],
  extra: ['sdk:$sdk'],
);

/// Liste aller Repo-Dateien (getrackt, neu, nicht ignoriert); wirft bei Fehler.
typedef FileLister = List<String> Function();

/// Version einer Toolchain oder `null`, wenn unbekannt.
typedef ToolVersion = String? Function(String tool);

/// Ablage grüner Schritte.
final class GateCache {
  /// Erstellt den Cache. [readFile] liefert `null` für eine fehlende Datei
  /// und wirft bei anderen Lesefehlern.
  GateCache({
    required this.dir,
    required this.listFiles,
    required this.toolVersion,
    List<int>? Function(String path)? readFile,
  }) : _readFile = readFile ?? _readFromDisk;

  /// Cache aus der Umgebung; `null` (kein Cache), wenn per `--no-cache`,
  /// `WENDELIN_GATE_CACHE=0` oder in CI (`CI=true`) abgeschaltet.
  static GateCache? fromEnvironment(
    Map<String, String> env,
    List<String> args,
  ) {
    if (args.contains('--no-cache') ||
        env['WENDELIN_GATE_CACHE'] == '0' ||
        env['CI'] == 'true') {
      return null;
    }
    final home = env['HOME'] ?? '';
    if (home.isEmpty) return null;
    return GateCache(
      dir: Directory('$home/.cache/wendelin-gate/cache'),
      listFiles: gitFiles,
      toolVersion: defaultToolVersion(home),
    )..prune();
  }

  /// Ablageordner (eine Datei je Schlüssel, Inhalt = Details der Zeile).
  final Directory dir;

  /// Dateiliste des Repos (einmal je Lauf abgefragt).
  final FileLister listFiles;

  /// Toolchain-Versionen.
  final ToolVersion toolVersion;

  final List<int>? Function(String) _readFile;
  List<String>? _files;
  final _hashes = <String, String>{};
  final _versions = <String, String?>{};

  /// Schlüssel für [step] oder `null` bei jedem Zweifel.
  String? keyFor(String step, CacheSpec spec) {
    try {
      final files = _files ??= listFiles();
      final roots = {...spec.roots, ...globalCacheRoots};
      final selected = <String>{};
      for (final f in files) {
        if (roots.contains('.') ||
            roots.any((r) => f == r || f.startsWith('$r/'))) {
          selected.add(f);
        }
      }
      // Auch gelöschte, noch getrackte Dateien stehen in der Liste: ihr
      // Marker „fehlt“ gehört zum Schlüssel.
      final b = StringBuffer('step:$step\n');
      for (final r in spec.roots.toList()..sort()) {
        b.writeln('root:$r');
      }
      for (final e in spec.extra) {
        b.writeln('extra:$e');
      }
      for (final t in spec.tools.toList()..sort()) {
        final v = _versions.putIfAbsent(t, () => toolVersion(t));
        if (v == null || v.isEmpty) return null;
        b.writeln('tool:$t=$v');
      }
      for (final f in selected.toList()..sort()) {
        final h = _hashes[f] ??= _hashFile(f);
        b.writeln('file:$f=$h');
      }
      return sha256Hex(utf8.encode(b.toString()));
    } on Object {
      return null;
    }
  }

  String _hashFile(String path) {
    final bytes = _readFile(path);
    return bytes == null ? 'fehlt' : sha256Hex(bytes);
  }

  /// Verwirft Dateiliste und Hashes, damit der nächste [keyFor] den
  /// aktuellen Stand liest (nach einem ausgeführten Schritt).
  void invalidate() {
    _files = null;
    _hashes.clear();
  }

  /// Gibt es für [step] einen Treffer?
  bool isHit(String step, CacheSpec spec) {
    final key = keyFor(step, spec);
    return key != null && lookup(key) != null;
  }

  /// Gespeicherte Details des grünen Schritts oder `null` (kein Treffer).
  String? lookup(String key) {
    try {
      final f = File('${dir.path}/$key');
      return f.existsSync() ? f.readAsStringSync() : null;
    } on Object {
      return null;
    }
  }

  /// Legt einen grünen Schritt atomar ab; Fehler werden ignoriert.
  void store(String key, String detail) {
    try {
      dir.createSync(recursive: true);
      final tmp = File('${dir.path}/.$key.$pid.tmp');
      tmp.writeAsStringSync(detail);
      tmp.renameSync('${dir.path}/$key');
    } on Object {
      // Cache ist nur Beschleunigung.
    }
  }

  /// Entfernt Einträge, die älter als [maxAge] sind.
  void prune({Duration maxAge = const Duration(days: 30)}) {
    try {
      if (!dir.existsSync()) return;
      final limit = DateTime.now().subtract(maxAge);
      for (final f in dir.listSync().whereType<File>()) {
        if (f.lastModifiedSync().isBefore(limit)) f.deleteSync();
      }
    } on Object {
      // ignorieren
    }
  }
}

List<int>? _readFromDisk(String path) {
  final f = File(path);
  return f.existsSync() ? f.readAsBytesSync() : null;
}

/// Alle Dateien im Arbeitsbaum: getrackte und neue, ohne ignorierte.
List<String> gitFiles() {
  final r = Process.runSync('git', [
    'ls-files',
    '-z',
    '--cached',
    '--others',
    '--exclude-standard',
  ], stdoutEncoding: utf8);
  if (r.exitCode != 0) {
    throw ProcessException('git', ['ls-files'], '', r.exitCode);
  }
  return (r.stdout as String)
      .split('\u0000')
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Versionen der Toolchains aus der Umgebung; `null` bei Fehlern.
ToolVersion defaultToolVersion(String home) => (tool) {
  switch (tool) {
    case 'dart':
      return Platform.version;
    case 'flutter':
      return _flutterVersion();
    case 'rust':
      return _run(['rustc', '-V'], home) == null
          ? null
          : '${_run(['rustc', '-V'], home)} ${_run(['cargo', '-V'], home)}';
    case 'deny':
      return _run(['cargo-deny', '--version'], home);
    case 'frb':
      return _run(['flutter_rust_bridge_codegen', '--version'], home);
    default:
      return null;
  }
};

String? _flutterVersion() {
  var d = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final f = File('${d.path}/cache/flutter.version.json');
    if (f.existsSync()) return f.readAsStringSync();
    final g = File('${d.path}/bin/cache/flutter.version.json');
    if (g.existsSync()) return g.readAsStringSync();
    d = d.parent;
  }
  return null;
}

String? _run(List<String> cmd, String home) {
  try {
    final path = [
      '$home/.cargo/bin',
      '/opt/homebrew/opt/rustup/bin',
      '/usr/local/opt/rustup/bin',
      Platform.environment['PATH'] ?? '',
    ].join(':');
    final r = Process.runSync(
      cmd.first,
      cmd.sublist(1),
      workingDirectory: Directory('native/attest').existsSync()
          ? 'native/attest'
          : null,
      environment: {'PATH': path},
    );
    return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
  } on Object {
    return null;
  }
}

/// sha256 als Hex-String.
String sha256Hex(List<int> data) {
  const k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  final h = Uint32List.fromList([
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ]);
  final len = data.length;
  final padded = (len + 9 + 63) ~/ 64 * 64;
  final buf = Uint8List(padded)..setRange(0, len, data);
  buf[len] = 0x80;
  final bd = ByteData.view(buf.buffer);
  bd.setUint32(padded - 8, (len * 8) ~/ 0x100000000);
  bd.setUint32(padded - 4, (len * 8) & 0xffffffff);
  final w = Uint32List(64);
  int rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;
  for (var off = 0; off < padded; off += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = bd.getUint32(off + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ (~e & 0xffffffff & g);
      final t1 = (hh + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h[0] += a;
    h[1] += b;
    h[2] += c;
    h[3] += d;
    h[4] += e;
    h[5] += f;
    h[6] += g;
    h[7] += hh;
  }
  return [for (final v in h) v.toRadixString(16).padLeft(8, '0')].join();
}
