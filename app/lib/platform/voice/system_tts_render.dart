import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';

import 'pcm.dart';

/// The engine did not deliver a usable file (error, timeout, stop, format).
/// The caller speaks directly instead (or stays silent after a stop).
final class SystemSpeechRenderFailed implements Exception {
  /// Creates the exception; [reason] never contains the text.
  const SystemSpeechRenderFailed(this.reason);

  /// Why (no spoken content in it).
  final String reason;

  @override
  String toString() => 'SystemSpeechRenderFailed($reason)';
}

/// Renders a text with the Android `TextToSpeech` engine (via `flutter_tts`
/// `synthesizeToFile`) into memory (WP188), so the answer can be played on a
/// chosen output device.
///
/// The temporary file is spoken user content: it lies only in the app cache
/// ([directory]) and is deleted on every way out (done, error, timeout,
/// [cancel]); files a crash left behind are swept before the first render.
/// Voice, language and rate are those set on the engine before.
final class SystemSpeechRenderer {
  /// Creates the renderer.
  SystemSpeechRenderer(
    this._tts, {
    required this.directory,
    this.timeout = const Duration(seconds: 20),
  });

  final FlutterTts _tts;

  /// The app cache directory.
  final Future<Directory> Function() directory;

  /// Safety limit for one synthesis.
  final Duration timeout;

  /// Start of the file names (what the sweep deletes).
  static const prefix = 'wendelin_tts_';

  Completer<void>? _pending;
  var _swept = false;
  var _seq = 0;
  var _cancelEpoch = 0;

  /// Synthesizes [text]; throws [SystemSpeechRenderFailed] without content.
  Future<Wav> render(String text) async {
    final epoch = _cancelEpoch;
    final dir = await directory();
    await _sweep(dir);
    // A cancel during the file IO above found nothing pending: honour it here
    // (no await between this check and `_pending` below).
    if (epoch != _cancelEpoch) {
      throw const SystemSpeechRenderFailed('cancelled');
    }
    final file = File(
      '${dir.path}/$prefix${DateTime.now().microsecondsSinceEpoch}_${_seq++}.wav',
    );
    final done = _pending = Completer<void>();
    void finish([String? failure]) {
      if (done.isCompleted) return;
      failure == null
          ? done.complete()
          : done.completeError(SystemSpeechRenderFailed(failure));
    }

    _tts
      ..setCompletionHandler(finish)
      ..setErrorHandler((_) => finish('engine'))
      ..setCancelHandler(() => finish('cancelled'));
    // Listener first: an error may arrive before the await below.
    final waiting = done.future.timeout(
      timeout,
      onTimeout: () => throw const SystemSpeechRenderFailed('timeout'),
    );
    unawaited(waiting.then<void>((_) {}, onError: (Object _) {}));
    try {
      await _tts.synthesizeToFile(text, file.path, true);
      await waiting;
      return wavFromEngineFile(await file.readAsBytes());
    } on SystemSpeechRenderFailed catch (e) {
      if (e.reason == 'timeout') await _stopEngine();
      rethrow;
    } on FormatException {
      throw const SystemSpeechRenderFailed('format');
    } on Object catch (e) {
      throw SystemSpeechRenderFailed('${e.runtimeType}');
    } finally {
      if (identical(_pending, done)) _pending = null;
      await _delete(file);
    }
  }

  /// Aborts a running [render] (it throws, deletes its file).
  void cancel() {
    _cancelEpoch++;
    final p = _pending;
    if (p != null && !p.isCompleted) {
      p.completeError(const SystemSpeechRenderFailed('cancelled'));
    }
  }

  Future<void> _stopEngine() async {
    try {
      await _tts.stop();
    } on Object {
      // Engine gone.
    }
  }

  Future<void> _sweep(Directory dir) async {
    if (_swept) return;
    _swept = true;
    try {
      await for (final e in dir.list()) {
        if (e is File && e.uri.pathSegments.last.startsWith(prefix)) {
          await _delete(e);
        }
      }
    } on Object {
      // No cache directory yet: nothing to sweep.
    }
  }

  static Future<void> _delete(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on Object {
      // Best effort; the next sweep tries again.
    }
  }
}

/// Reads the WAV file of the engine as mono 16 bit. Sample rate, channel
/// count and sample format are the engine's own: PCM 8/16/32 bit and float
/// 32 bit, any number of channels (averaged to mono). Throws
/// [FormatException] for anything else or for no samples.
Wav wavFromEngineFile(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes, at, at + 4);
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('Keine WAV-Datei');
  }
  int? format, channels, rate, bits;
  var off = 12;
  while (off + 8 <= bytes.length) {
    final id = tag(off);
    final len = data.getUint32(off + 4, Endian.little);
    final body = off + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      rate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
      if (format == 0xFFFE && len >= 26 && body + 26 <= bytes.length) {
        format = data.getUint16(body + 24, Endian.little); // extensible
      }
    } else if (id == 'data') {
      if (format == null || channels == null || rate == null || bits == null) {
        throw const FormatException('fmt fehlt vor data');
      }
      final end = len > bytes.length - body ? bytes.length : body + len;
      return _toMono(data, body, end, format, channels, rate, bits);
    }
    off = body + len + (len & 1);
  }
  throw const FormatException('data-Abschnitt fehlt');
}

Wav _toMono(
  ByteData d,
  int start,
  int end,
  int format,
  int channels,
  int rate,
  int bits,
) {
  final isFloat = format == 3 && bits == 32;
  if (channels < 1 ||
      rate < 1 ||
      !(isFloat || (format == 1 && const [8, 16, 32].contains(bits)))) {
    throw FormatException(
      'Nicht unterstützt (Format $format, $channels Kanäle, $bits bit)',
    );
  }
  final width = bits ~/ 8;
  final frames = (end - start) ~/ (width * channels);
  if (frames < 1) throw const FormatException('keine Samples');
  double sample(int at) {
    if (isFloat) return d.getFloat32(at, Endian.little);
    return switch (bits) {
      8 => (d.getUint8(at) - 128) / 128,
      16 => d.getInt16(at, Endian.little) / 32768,
      _ => d.getInt32(at, Endian.little) / 2147483648,
    };
  }

  final out = Int16List(frames);
  for (var i = 0; i < frames; i++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += sample(start + (i * channels + c) * width);
    }
    final v = sum / channels;
    out[i] = v.isNaN ? 0 : (v * 32767).clamp(-32768.0, 32767.0).round();
  }
  return Wav(out, sampleRate: rate);
}
