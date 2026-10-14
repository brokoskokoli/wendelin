import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// [AudioInput] of the wake word engine: the service (Kotlin) owns the
/// microphone, because a foreground service must record
/// (`AudioRecord`, `VOICE_RECOGNITION`). [start] asks it to record
/// (`startMic`) and [push] hands the 16 kHz PCM16 chunks it sends to the
/// stream; [stop] frees the microphone (`stopMic`). Restartable: the
/// listener pauses for the assistant overlay and resumes afterwards.
final class ServiceAudioInput implements AudioInput {
  /// Creates the input on the engine channel.
  ServiceAudioInput(this.channel);

  /// Channel to the service.
  final MethodChannel channel;

  // Closed in [stop].
  // ignore: close_sinks
  StreamController<Int16List>? _out;

  @override
  bool get isRunning => _out != null;

  @override
  Stream<Int16List> start() {
    if (_out != null) throw StateError('Das Mikrofon läuft bereits.');
    // ignore: close_sinks
    final out = _out = StreamController<Int16List>();
    unawaited(_call('startMic'));
    return out.stream;
  }

  /// Adds little-endian PCM16 [bytes] from the service.
  void push(Uint8List bytes) {
    final out = _out;
    if (out == null || bytes.length < 2) return;
    final frame = Int16List(bytes.length ~/ 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < frame.length; i++) {
      frame[i] = data.getInt16(i * 2, Endian.little);
    }
    out.add(frame);
  }

  /// The service could not record (or lost the microphone for good).
  void fail(Object error) {
    final out = _out;
    if (out == null) return;
    out.addError(VoiceException(VoiceErrorKind.unavailable, '$error'));
  }

  @override
  Future<void> stop() async {
    final out = _out;
    if (out == null) return;
    _out = null;
    await _call('stopMic');
    await out.close();
  }

  Future<void> _call(String method) async {
    try {
      await channel.invokeMethod<void>(method);
    } on PlatformException {
      // The service is gone; its end is reported separately.
    } on MissingPluginException {
      // Same.
    }
  }
}
