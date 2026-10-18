// Aktualisiert die eingebettete Sigstore-Trust-Root (WP76b):
//
//   dart run tool/update_sigstore_root.dart          prüfen, nichts schreiben
//   dart run tool/update_sigstore_root.dart --write  Asset überschreiben
//
// Quelle 1: TUF-Repo `tuf-repo-cdn.sigstore.dev` (timestamp -> snapshot -> targets ->
// Ziel `trusted_root.json`, Hashes und Längen entlang der Kette geprüft; die TUF-
// Signaturen prüft das Skript nicht). Quelle 2: `sigstore/root-signing` auf GitHub
// (signierte Commits). Nur wenn beide Quellen byte-gleich sind, gilt die Datei als
// verlässlich. Danach den Hash in `native/attest/tests/sigstore.rs`
// (`embedded_trust_root_is_the_documented_one`) und in
// `docs/notes/sigstore-trust-root.md` nachziehen. Siehe dort für den Ablauf.
import 'dart:convert';
import 'dart:io';

const _cdn = 'https://tuf-repo-cdn.sigstore.dev/';
const _gh =
    'https://raw.githubusercontent.com/sigstore/root-signing/main/targets/trusted_root.json';
const _asset = 'native/attest/assets/sigstore_trusted_root.json';

Future<List<int>> _get(HttpClient c, String url) async {
  final r = await (await c.getUrl(Uri.parse(url))).close();
  if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}: $url');
  return r.fold<List<int>>([], (a, b) => a..addAll(b));
}

Map<String, dynamic> _json(List<int> b) =>
    jsonDecode(utf8.decode(b)) as Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final c = HttpClient();
  final ts = _json(await _get(c, '${_cdn}timestamp.json'));
  final sv = _at(ts, ['signed', 'meta', 'snapshot.json', 'version']) as int;
  final sn = _json(await _get(c, '$_cdn$sv.snapshot.json'));
  final tv = _at(sn, ['signed', 'meta', 'targets.json', 'version']) as int;
  final tg = _json(await _get(c, '$_cdn$tv.targets.json'));
  const base = ['signed', 'targets', 'trusted_root.json'];
  final hash = _at(tg, [...base, 'hashes', 'sha256']) as String;
  final length = _at(tg, [...base, 'length']) as int;
  final cdn = await _get(c, '${_cdn}targets/$hash.trusted_root.json');
  if (await _sha(cdn) != hash || cdn.length != length) {
    stderr.writeln('CDN-Datei passt nicht zu den TUF-Metadaten');
    exit(1);
  }
  final gh = await _get(c, _gh);
  c.close();
  if (!_same(cdn, gh)) {
    stderr.writeln(
      'CDN und sigstore/root-signing weichen ab: nichts übernommen',
    );
    exit(1);
  }
  final cur = File(_asset).readAsBytesSync();
  final same = _same(cur, cdn);
  stdout.writeln('sha256 neu: $hash');
  stdout.writeln(same ? 'eingebettet: identisch' : 'eingebettet: ABWEICHEND');
  if (args.contains('--write') && !same) {
    File(_asset).writeAsBytesSync(cdn);
    stdout.writeln('geschrieben: $_asset (Hash in Test und Doku nachziehen)');
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// SHA-256 (Hex) über `shasum`, damit das Skript ohne Pakete läuft.
Future<String> _sha(List<int> data) async {
  final p = await Process.start('shasum', ['-a', '256']);
  p.stdin.add(data);
  await p.stdin.close();
  final out = await utf8.decodeStream(p.stdout);
  return out.split(' ').first;
}

Object? _at(Map<String, dynamic> m, List<String> path) {
  Object? cur = m;
  for (final k in path) {
    cur = (cur! as Map<String, dynamic>)[k];
  }
  return cur;
}
