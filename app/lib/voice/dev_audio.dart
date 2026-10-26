import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../platform/voice/pcm.dart';
import 'dev_log.dart';

/// Audio recordings of the developer mode (WP148): WAV files (16 kHz, mono,
/// PCM16) in the app's external files folder, where `adb pull` reaches them
/// in the release build (`Android/data/<package>/files/dev-audio/`). A
/// deliberate exception to "no audio on the device": nothing leaves it, the
/// files go after a day, and without the developer mode nothing is written.

/// Name of the folder below the app's external files folder.
const devAudioFolder = 'dev-audio';

/// Files older than this are deleted (at the app start and after each write).
const devAudioMaxAge = Duration(days: 1);

/// All files together may take this much; the oldest go first.
const devAudioMaxBytes = 200 * 1024 * 1024;

/// Most clips waiting to be written; further ones are dropped (and logged),
/// so a candidate storm cannot pile up audio in memory.
const devAudioMaxPending = 8;

/// The folder of the clips; `null` if the device has none (then nothing is
/// written). Tests replace it.
Future<Directory?> Function() devAudioDirectory = _externalDirectory;

Future<Directory?> _externalDirectory() async {
  final base = await getExternalStorageDirectory();
  return base == null ? null : Directory('${base.path}/$devAudioFolder');
}

/// The hook that voice code gets: collects only in developer mode.
final DevClips devAudioClips = DevClips(
  enabled: () => devLogEnabled,
  write: saveDevClip,
);

int _pending = 0;
Future<void> _queue = Future.value();

/// Writes [clip] without blocking the caller (one file at a time, in the
/// background), then logs `audio file=… event=… ms=… <mark>Ms=…` to the
/// developer log. Does nothing without the developer mode.
void saveDevClip(DevClip clip) {
  if (!devLogEnabled) return;
  if (_pending >= devAudioMaxPending) {
    devLog('audio-dropped', {'event': clip.event});
    return;
  }
  _pending++;
  _queue = _queue
      .then((_) => _write(clip))
      .catchError((Object _) {})
      .whenComplete(() => _pending--);
}

/// Completes when everything handed to [saveDevClip] is written (tests).
Future<void> get devAudioIdle => _queue;

Future<void> _write(DevClip clip) async {
  final dir = await devAudioDirectory();
  if (dir == null) return;
  await dir.create(recursive: true);
  final name = await _freeName(dir, clip);
  await File('${dir.path}/$name').writeAsBytes(Wav(clip.pcm).encode());
  devLog('audio', {
    'file': DevLogLiteral(name),
    'event': clip.event,
    'ms': samplesToDuration(clip.pcm.length).inMilliseconds,
    for (final MapEntry(:key, :value) in clip.marksMs.entries)
      '${key}Ms': value,
  });
  await pruneDevAudio(dir);
}

Future<String> _freeName(Directory dir, DevClip clip) async {
  final base = '${devAudioStamp(clip.at)}_${clip.event}';
  var name = '$base.wav';
  for (var n = 2; await File('${dir.path}/$name').exists(); n++) {
    name = '$base-$n.wav';
  }
  return name;
}

/// `20261026-002349.507` (local time), the start of every file name.
String devAudioStamp(DateTime t) {
  String p(int v, int w) => v.toString().padLeft(w, '0');
  return '${p(t.year, 4)}${p(t.month, 2)}${p(t.day, 2)}-'
      '${p(t.hour, 2)}${p(t.minute, 2)}${p(t.second, 2)}.${p(t.millisecond, 3)}';
}

/// Deletes the `.wav` files of [dir] that are older than [maxAge] and then
/// the oldest ones until the rest fits [maxBytes]. Returns the number of
/// deleted files. Errors count as nothing deleted (the folder is a debugging
/// aid, never a reason to fail).
Future<int> pruneDevAudio(
  Directory dir, {
  DateTime? now,
  Duration maxAge = devAudioMaxAge,
  int maxBytes = devAudioMaxBytes,
}) async {
  var deleted = 0;
  try {
    if (!await dir.exists()) return 0;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    final files = <({File file, DateTime time, int size})>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File || !e.path.endsWith('.wav')) continue;
      final stat = await e.stat();
      files.add((file: e, time: stat.modified, size: stat.size));
    }
    files.sort((a, b) => a.time.compareTo(b.time));
    var total = files.fold<int>(0, (n, f) => n + f.size);
    for (final f in files) {
      if (f.time.isAfter(cutoff) && total <= maxBytes) break;
      await f.file.delete();
      total -= f.size;
      deleted++;
    }
  } on Object {
    // Left as it is.
  }
  return deleted;
}

/// Cleans the folder (app start, wake engine start), whether the mode is on
/// or not: recordings of an earlier session must not linger.
Future<void> cleanDevAudio() async {
  try {
    final dir = await devAudioDirectory();
    if (dir != null) await pruneDevAudio(dir);
  } on Object {
    // Nothing to clean.
  }
}
