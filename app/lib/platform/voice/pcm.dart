import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// Helpers for 16 kHz mono signed 16-bit PCM (pure Dart, no Flutter: also
// used by the measurement tools under `app/tool/`).

/// [pcm] as floats in `[-1, 1)` (the sample format of sherpa-onnx).
Float32List pcmToFloat(Int16List pcm) {
  final out = Float32List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    out[i] = pcm[i] / 32768;
  }
  return out;
}

/// [samples] in `[-1, 1]` as 16-bit PCM (clipped).
Int16List floatToPcm(Float32List samples) {
  final out = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = (samples[i] * 32767).round().clamp(-32768, 32767);
  }
  return out;
}

/// Root mean square of [pcm] relative to full scale (0.0–1.0).
double rmsLevel(Int16List pcm) {
  if (pcm.isEmpty) return 0;
  var sum = 0.0;
  for (final s in pcm) {
    sum += s * s;
  }
  return math.sqrt(sum / pcm.length) / 32768;
}

/// Converts a stream of little-endian 16-bit PCM bytes into sample frames.
///
/// Chunks of odd length are allowed: a trailing byte is carried over into
/// the next chunk. Empty results are not emitted.
final class PcmBytesDecoder {
  int? _carry;

  /// Samples in [bytes] (plus a byte carried over from the last call).
  Int16List convert(List<int> bytes) {
    final carry = _carry;
    final total = bytes.length + (carry == null ? 0 : 1);
    final n = total ~/ 2;
    final out = Int16List(n);
    var src = 0;
    for (var i = 0; i < n; i++) {
      final int lo;
      if (i == 0 && carry != null) {
        lo = carry;
      } else {
        lo = bytes[src++];
      }
      final hi = bytes[src++];
      out[i] = ((hi << 8) | (lo & 0xff)).toSigned(16);
    }
    _carry = total.isOdd ? bytes[bytes.length - 1] : null;
    return out;
  }
}

/// A 16 kHz mono 16-bit WAV file.
final class Wav {
  /// Creates a WAV from [samples] at [sampleRate].
  const Wav(this.samples, {this.sampleRate = 16000});

  /// Samples.
  final Int16List samples;

  /// Sample rate in Hz.
  final int sampleRate;

  /// Duration of [samples].
  Duration get duration =>
      Duration(microseconds: samples.length * 1000000 ~/ sampleRate);

  /// Parses RIFF/WAVE PCM data (16 bit, mono). Unknown chunks are skipped.
  ///
  /// Throws [FormatException] for other formats.
  static Wav parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    String tag(int at) => String.fromCharCodes(bytes, at, at + 4);
    if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException('Keine WAV-Datei');
    }
    int? rate;
    var off = 12;
    while (off + 8 <= bytes.length) {
      final id = tag(off);
      final len = data.getUint32(off + 4, Endian.little);
      final body = off + 8;
      if (id == 'fmt ') {
        final format = data.getUint16(body, Endian.little);
        final channels = data.getUint16(body + 2, Endian.little);
        final bits = data.getUint16(body + 14, Endian.little);
        if (format != 1 || channels != 1 || bits != 16) {
          throw FormatException(
            'Nur PCM mono 16 bit (Format $format, $channels Kanäle, $bits bit)',
          );
        }
        rate = data.getUint32(body + 4, Endian.little);
      } else if (id == 'data') {
        if (rate == null) throw const FormatException('fmt fehlt vor data');
        final end = math.min(body + len, bytes.length);
        final n = (end - body) ~/ 2;
        final samples = Int16List(n);
        for (var i = 0; i < n; i++) {
          samples[i] = data.getInt16(body + 2 * i, Endian.little);
        }
        return Wav(samples, sampleRate: rate);
      }
      off = body + len + (len & 1);
    }
    throw const FormatException('data-Abschnitt fehlt');
  }

  /// Reads and parses the WAV file at [path].
  static Wav read(String path) => parse(File(path).readAsBytesSync());

  /// The file contents (44-byte header + data).
  Uint8List encode() {
    final dataLen = samples.length * 2;
    final out = ByteData(44 + dataLen);
    void tag(int at, String s) {
      for (var i = 0; i < 4; i++) {
        out.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    out.setUint32(4, 36 + dataLen, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    out
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    tag(36, 'data');
    out.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      out.setInt16(44 + 2 * i, samples[i], Endian.little);
    }
    return out.buffer.asUint8List();
  }
}
