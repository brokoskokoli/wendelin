import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:wendelin_core/wendelin_core.dart' show redactSensitiveContent;
import 'package:wendelin_storage/wendelin_storage.dart' show redactSecrets;
import 'package:wendelin_voice/wendelin_voice.dart';

import '../platform/voice/pcm.dart';
import 'dev_audio.dart';
import 'dev_log.dart';

/// Wake word archive of the developer mode (WP155): every candidate of the
/// idle wake word and of the barge-in (accepted, rejected, dropped) and the
/// near misses, each as a WAV (accepted: about 2 s before the hit; the
/// others 4 s) with a line in `index.jsonl`, for the later listening and labelling. Lives in
/// `dev-audio/wake-archive/` (reached by `adb pull`, nothing is uploaded),
/// is **not** cleaned after a day, only by the size cap [devArchiveMaxBytes]
/// (oldest first), by the button in the developer settings or when the
/// developer mode is switched off and the user says so. Without the
/// developer mode nothing is collected or written.

/// Name of the folder below `dev-audio`.
const devArchiveFolder = 'wake-archive';

/// Name of the index (one JSON object per line, UTF-8).
const devArchiveIndexName = 'index.jsonl';

/// The archive may take this much (the oldest cases go first). A case is
/// about 128 KB for the hit clip (4 s, 16 kHz, PCM16) plus up to 100 KB for
/// the clip of the check, so 1 GB holds roughly 4500 cases: at the guessed
/// rate of a few dozen a day (candidates plus near misses, see
/// `devNearMissFrom`) many months, at the worst case of 720 near misses per
/// hour some 8 hours of continuous speech nearby.
const devArchiveMaxBytes = 1024 * 1024 * 1024;

/// Most cases waiting to be written; further ones are dropped (and logged).
const devArchiveMaxPending = 16;

/// Version stored with every case (the pubspec version; a test keeps the two
/// equal, a build can set `--dart-define=WENDELIN_VERSION`).
const devArchiveAppVersion = String.fromEnvironment(
  'WENDELIN_VERSION',
  defaultValue: '0.1.1+2',
);

final _info = <String, Map<String, Object?>>{};

/// Facts the engine knows (thresholds, mode, microphone source) that every
/// case of [source] (`idle`, `barge`) carries.
void devArchiveSetInfo(String source, Map<String, Object?> info) =>
    _info[source] = {..._info[source] ?? const {}, ...info};

/// Forgets the facts (tests).
void devArchiveResetInfo() => _info.clear();

Map<String, Object?> _context(String source) => {
  'app': devArchiveAppVersion,
  ...?_info[source],
};

Map<String, Object?>? _stt;

/// Remembers the transcript of the check that just ran (the recognizer calls
/// it; developer mode only). The archive reads it with [takeSttNote].
void noteDevStt({required String text, double? lp, String? model}) {
  if (!devLogEnabled) return;
  _stt = {'text': text, 'lp': lp, 'model': model};
}

/// The last transcript note, forgotten.
Map<String, Object?> takeSttNote() {
  final n = _stt ?? const <String, Object?>{};
  _stt = null;
  return n;
}

/// The archive hook of `devAudioClips`.
final DevArchive devArchive = DevArchive(
  write: saveDevArchiveEntry,
  context: _context,
  takeStt: takeSttNote,
);

/// Folder of the archive; `null` if the device has none.
Future<Directory?> devArchiveDirectory() async {
  final base = await devAudioDirectory();
  return base == null ? null : Directory('${base.path}/$devArchiveFolder');
}

int _pending = 0;
int? _bytes;
Future<void> _queue = Future.value();

/// Completes when everything handed to [saveDevArchiveEntry] is written.
/// Nothing waiting: a fresh future, so the caller's zone runs the answer (a
/// completed future delivers in the zone it was made in).
Future<void> get devArchiveIdle => _pending == 0 ? Future.value() : _queue;

/// Writes [entry] in the background (one at a time, never blocks the
/// caller). An error is swallowed and logged (`archive-error`); the voice
/// path never notices. Does nothing without the developer mode.
void saveDevArchiveEntry(DevArchiveEntry entry) {
  if (!devLogEnabled) return;
  if (_pending >= devArchiveMaxPending) {
    devLog('archive-dropped', {'outcome': entry.outcome});
    return;
  }
  _pending++;
  _queue = _queue
      .then((_) => _write(entry))
      .catchError((Object e) {
        devLog('archive-error', {'error': e.runtimeType.toString()});
      })
      .whenComplete(() => _pending--);
}

/// The cases written by this isolate since the last full scan; every
/// [_scanEvery]th write scans the folder and prunes (the wake service writes
/// from a second isolate, so a running sum alone would drift).
int _sinceScan = 0;
const _scanEvery = 25;

Future<void> _write(DevArchiveEntry e) async {
  // Fail-closed: the mode may have gone off while the entry was waiting.
  if (!devLogEnabled) return;
  final dir = await devArchiveDirectory();
  if (dir == null) return;
  await dir.create(recursive: true);
  final written = <File>[];
  try {
    final base = await _claim(dir, e, written);
    var size = 0;
    String? name;
    String? verifyName;
    final cand = e.cand;
    if (cand != null) {
      name = '$base.wav';
      size += await devArchivePut(
        File('${dir.path}/$name'),
        Wav(cand.pcm).encode(),
      );
    }
    final verify = e.verify;
    if (verify != null) {
      verifyName = '$base-verify.wav';
      final f = File('${dir.path}/$verifyName');
      if (!written.any((w) => w.path == f.path)) written.add(f);
      size += await devArchivePut(f, Wav(verify.pcm).encode());
    }
    // The line comes last and only with the mode still on: an audio file
    // without a line is swept as an orphan, a line never lacks its audio.
    if (!devLogEnabled) throw const _SwitchedOff();
    final line = jsonEncode(_record(e, name, verifyName));
    await File('${dir.path}/$devArchiveIndexName')
        .writeAsString('$line\n', mode: FileMode.append, flush: true);
    size += line.length + 1;
    devLog('archive', {
      'file': name == null ? null : DevLogLiteral(name),
      'source': e.source,
      'outcome': e.outcome,
    });
    _bytes = (_bytes ?? 0) + size;
  } on Object catch (err) {
    // No half case: the audio without a line is of no use.
    for (final f in written) {
      try {
        await f.delete();
      } on Object {
        // Swept later as an orphan.
      }
    }
    if (err is _SwitchedOff) return;
    rethrow;
  }
  if (_bytes == null ||
      ++_sinceScan >= _scanEvery ||
      _bytes! > devArchiveMaxBytes) {
    _sinceScan = 0;
    // No orphan sweep here: it needs the whole index (tens of MB after
    // weeks), too much for the wake service's isolate while it listens. The
    // sweep runs at the start (`cleanDevAudio`).
    await pruneDevArchive(dir, sweepOrphans: false);
  }
}

/// Raised when the developer mode went off between two steps of a write.
final class _SwitchedOff implements Exception {
  const _SwitchedOff();
}

/// Writes [bytes]; refuses (nothing written) once the mode is off. A
/// variable only so a test can act between two steps of a write.
@visibleForTesting
Future<int> Function(File f, List<int> bytes) devArchivePut = _put;

Future<int> _put(File f, List<int> bytes) async {
  if (!devLogEnabled) throw const _SwitchedOff();
  await f.writeAsBytes(bytes, flush: true);
  return bytes.length;
}

/// Claims a free name by creating its first file exclusively, so two
/// isolates never take the same one (the check and the creation are one
/// step in the file system).
Future<String> _claim(
  Directory dir,
  DevArchiveEntry e,
  List<File> written,
) async {
  final base0 = '${devAudioStamp(e.at)}_${e.source}-${e.outcome}';
  // Without audio there is nothing to claim: the line stands alone.
  if (e.cand == null && e.verify == null) return base0;
  for (var n = 1; ; n++) {
    final base = n == 1 ? base0 : '$base0-$n';
    final f = File('${dir.path}/$base${e.cand != null ? '' : '-verify'}.wav');
    try {
      await f.create(exclusive: true);
    } on PathExistsException {
      continue;
    }
    written.add(f);
    return base;
  }
}

Map<String, Object?> _record(DevArchiveEntry e, String? file, String? verify) {
  final out = <String, Object?>{
    ...e.meta,
    't': e.at.toUtc().toIso8601String(),
    'file': file,
    'verify_file': verify,
    'source': e.source,
    'outcome': e.outcome,
    if (e.cand != null)
      'ms': samplesToDuration(e.cand!.pcm.length).inMilliseconds,
    for (final MapEntry(:key, :value) in (e.cand?.marksMs ?? const {}).entries)
      '${key}_ms': value,
    if (e.verify != null)
      'verify_ms': samplesToDuration(e.verify!.pcm.length).inMilliseconds,
    for (final MapEntry(:key, :value)
        in (e.verify?.marksMs ?? const {}).entries)
      'verify_${key}_ms': value,
    // For the later review page.
    'label': '',
  }..removeWhere((k, v) => v == null);
  // Keys and values like the developer log; the text of a check also like
  // its content masking (a spoken "PIN 1234", a card number).
  final safe = redactSecrets(out)! as Map<String, Object?>;
  for (final k in _numberKeys) {
    // Not a number (e.g. a verifier's "none"): null, so the type stays one.
    if (safe.containsKey(k)) safe[k] = _asNumber(safe[k]);
  }
  if (safe['text'] case final String text) {
    safe['text'] = redactSensitiveContent(text, mask: '***');
  }
  return safe;
}

/// Fields that are numbers in the index (the engines note some of them as
/// text with fixed decimals).
const _numberKeys = ['score', 'sim', 'thr', 'conf', 'lp', 'cand'];

/// [v] as a JSON number rounded to 4 decimals (`0.5299999999999999` becomes
/// `0.53`); text that is a number becomes one, anything else is `null`.
num? _asNumber(Object? v) {
  final n = v is String ? num.tryParse(v) : v;
  if (n is! num || !n.isFinite) return null;
  if (n is int) return n;
  return num.parse(n.toStringAsFixed(4));
}

/// Case name of a file (`…_idle-accepted` for `…_idle-accepted-verify.wav`).
String _caseOf(String path) {
  final n = path.split('/').last;
  final stem = n.substring(0, n.length - '.wav'.length);
  return stem.endsWith('-verify')
      ? stem.substring(0, stem.length - '-verify'.length)
      : stem;
}

final _nearMissCase = RegExp(r'_[a-z]+-near-miss(-\d+)?$');

/// A file younger than this is never touched by [pruneDevArchive]: the other
/// isolate may still be between its audio and its line.
const devArchiveMinAge = Duration(minutes: 1);

/// Shrinks the archive. Rules:
///
/// 1. near misses may take at most [nearMissMaxBytes] (default half of
///    [maxBytes]); the oldest ones go first, even if the total fits;
/// 2. while the total exceeds [maxBytes], near misses go first (oldest
///    first), only then the oldest accepted/rejected/dropped ones, which are
///    kept as long as possible;
/// 3. audio that no line of the index names (a crash between the two steps)
///    is deleted as an orphan, if [sweepOrphans] (reads the whole index,
///    streamed; the periodic prune of the wake service leaves it out).
///
/// The index is **never rewritten** (the wake service appends to it from
/// another isolate; a rewrite would lose its line, see the architecture
/// notes): lines of deleted audio stay and readers skip them. Files younger
/// than [minAge] are left alone, so a case that is just being written is
/// neither cut nor taken for an orphan. Returns the number of deleted cases;
/// errors count as nothing deleted.
Future<int> pruneDevArchive(
  Directory dir, {
  int maxBytes = devArchiveMaxBytes,
  int? nearMissMaxBytes,
  Duration minAge = devArchiveMinAge,
  bool sweepOrphans = true,
}) async {
  final nearMax = nearMissMaxBytes ?? maxBytes ~/ 2;
  var deleted = 0;
  try {
    if (!await dir.exists()) return 0;
    final settledBefore = DateTime.now().subtract(minAge);
    final named = sweepOrphans ? await _namedByIndex(dir) : null;
    final cases = <String, List<({File file, int size})>>{};
    final young = <String>{};
    var total = 0;
    await for (final f in dir.list(followLinks: false)) {
      if (f is! File) continue;
      final stat = await f.stat();
      total += stat.size;
      if (!f.path.endsWith('.wav')) continue;
      final settled = !stat.modified.isAfter(settledBefore);
      final caseName = _caseOf(f.path);
      if (!settled) young.add(caseName);
      if (settled && named != null && !named.contains(f.path.split('/').last)) {
        await f.delete(); // orphan
        total -= stat.size;
        continue;
      }
      (cases[caseName] ??= []).add((file: f, size: stat.size));
    }
    // Names begin with the time stamp: sorted is oldest first.
    final names = (cases.keys.where((n) => !young.contains(n)).toList()
      ..sort());
    final near = names.where(_nearMissCase.hasMatch).toList();
    final other = names.where((n) => !_nearMissCase.hasMatch(n)).toList();
    int sizeOf(String n) => cases[n]!.fold(0, (a, f) => a + f.size);
    var nearTotal =
        near.fold<int>(0, (a, n) => a + sizeOf(n)) +
        young
            .where(_nearMissCase.hasMatch)
            .fold<int>(0, (a, n) => a + sizeOf(n));
    Future<void> drop(String n) async {
      for (final f in cases[n]!) {
        await f.file.delete();
      }
      total -= sizeOf(n);
      deleted++;
    }

    while (nearTotal > nearMax && near.isNotEmpty) {
      final n = near.removeAt(0);
      nearTotal -= sizeOf(n);
      await drop(n);
    }
    while (total > maxBytes && (near.isNotEmpty || other.isNotEmpty)) {
      await drop(near.isNotEmpty ? near.removeAt(0) : other.removeAt(0));
    }
    _bytes = total;
  } on Object {
    // Left as it is.
  }
  return deleted;
}

/// File names the index mentions; `null` if there is no (readable) index,
/// then nothing counts as an orphan. Reads the file as a stream, line by
/// line (never the whole file as one string), and gives the event loop a
/// turn every [_yieldEvery] lines: 100000 lines (29 MB, a few weeks of near
/// misses) took 250 ms at a stretch on a desktop, several times that on a
/// phone.
Future<Set<String>?> _namedByIndex(Directory dir) async {
  final index = File('${dir.path}/$devArchiveIndexName');
  if (!await index.exists()) return null;
  final out = <String>{};
  var n = 0;
  try {
    final lines = index
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        for (final k in ['file', 'verify_file']) {
          final v = m[k];
          if (v is String) out.add(v);
        }
      } on Object {
        // A torn or foreign line names nothing.
      }
      if (++n % _yieldEvery == 0) await Future<void>.delayed(Duration.zero);
    }
  } on Object {
    return null; // unreadable: nothing counts as an orphan
  }
  return out;
}

const _yieldEvery = 500;

/// Number of cases with audio and bytes of the archive (settings screen).
/// From the folder listing alone, the index is not read (it only grows,
/// and lines of pruned audio stay in it); a case without any audio (only a
/// line) is not counted.
Future<({int cases, int bytes})> devArchiveStats() async {
  try {
    final dir = await devArchiveDirectory();
    if (dir == null || !await dir.exists()) return (cases: 0, bytes: 0);
    final cases = <String>{};
    var bytes = 0;
    await for (final f in dir.list(followLinks: false)) {
      if (f is! File) continue;
      bytes += (await f.stat()).size;
      if (f.path.endsWith('.wav')) cases.add(_caseOf(f.path));
    }
    return (cases: cases.length, bytes: bytes);
  } on Object {
    return (cases: 0, bytes: 0);
  }
}

/// Deletes the whole archive (the user asked).
Future<void> clearDevArchive() async {
  await devArchiveIdle;
  try {
    final dir = await devArchiveDirectory();
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  } on Object {
    // Nothing more to do.
  }
  _bytes = null;
}
