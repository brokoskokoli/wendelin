import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'pcm.dart';

/// The part of the `record` plugin that [RecordAudioInput] uses
/// (replaceable in tests).
abstract interface class PcmRecorder {
  /// Whether the microphone permission is granted; with [request] Android
  /// asks the user.
  Future<bool> hasPermission({bool request = true});

  /// Starts a 16 kHz mono PCM stream (little-endian bytes).
  Future<Stream<Uint8List>> startStream();

  /// Stops the stream.
  Future<void> stop();
}

/// [PcmRecorder] on `package:record` (Android `AudioRecord`, no GMS).
final class RecordPcmRecorder implements PcmRecorder {
  /// Creates the recorder; [recorder] is created lazily.
  RecordPcmRecorder([AudioRecorder? recorder]) : _given = recorder;

  final AudioRecorder? _given;
  late final AudioRecorder _recorder = _given ?? AudioRecorder();

  @override
  Future<bool> hasPermission({bool request = true}) =>
      _recorder.hasPermission(request: request);

  @override
  Future<Stream<Uint8List>> startStream() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: AudioInput.sampleRate,
      numChannels: 1,
      // Speech recognition source: no automatic gain on most devices.
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceRecognition,
      ),
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }
}

/// Microphone as [AudioInput]: 16 kHz mono 16-bit PCM from [PcmRecorder].
///
/// [start] checks the permission without asking (the app asks first with
/// an explanation, see `ensureMicrophoneAccess`), so a missing permission
/// becomes `VoiceException(permissionDenied)`; any other failure is
/// `VoiceException(unavailable)` on the frame stream.
final class RecordAudioInput implements AudioInput {
  /// Creates the input.
  RecordAudioInput([PcmRecorder? recorder])
    : _recorder = recorder ?? RecordPcmRecorder();

  final PcmRecorder _recorder;
  StreamController<Int16List>? _out;
  // Cancelled via a local copy in _finish() and stop().
  // ignore: cancel_subscriptions
  StreamSubscription<Uint8List>? _sub;
  Future<void> _stopping = Future.value();

  @override
  bool get isRunning => _out != null;

  @override
  Stream<Int16List> start() {
    if (_out != null) throw StateError('Die Aufnahme läuft bereits.');
    final out = StreamController<Int16List>();
    _out = out;
    unawaited(_begin(out));
    return out.stream;
  }

  Future<void> _begin(StreamController<Int16List> out) async {
    await _stopping;
    try {
      if (!await _recorder.hasPermission(request: false)) {
        throw const VoiceException(
          VoiceErrorKind.permissionDenied,
          'Wendelin darf das Mikrofon nicht benutzen.',
        );
      }
      final bytes = await _recorder.startStream();
      if (!identical(_out, out)) {
        // stop() came first.
        await _recorder.stop();
        return;
      }
      final decoder = PcmBytesDecoder();
      _sub = bytes.listen(
        (chunk) {
          final frame = decoder.convert(chunk);
          if (frame.isNotEmpty && !out.isClosed) out.add(frame);
        },
        onError: (Object e) => _fail(out, e),
        onDone: () => unawaited(_finish(out)),
      );
    } on Object catch (e) {
      _fail(out, e);
    }
  }

  void _fail(StreamController<Int16List> out, Object e) {
    if (!out.isClosed) {
      out.addError(
        e is VoiceException
            ? e
            : VoiceException(
                VoiceErrorKind.unavailable,
                e is PlatformException
                    ? 'Das Mikrofon ist nicht verfügbar.'
                    : 'Die Aufnahme ist fehlgeschlagen.',
                cause: e,
              ),
      );
    }
    // The platform may still be recording (an error does not always end
    // the stream): stop it, and let a new start wait for that.
    _stopping = _finish(out, stopRecorder: true);
  }

  Future<void> _finish(
    StreamController<Int16List> out, {
    bool stopRecorder = false,
  }) async {
    if (identical(_out, out)) _out = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    if (stopRecorder) {
      try {
        await _recorder.stop();
      } on Object {
        // Nothing to stop any more.
      }
    }
    if (!out.isClosed) await out.close();
  }

  @override
  Future<void> stop() {
    final out = _out;
    if (out == null) return _stopping;
    _out = null;
    return _stopping = () async {
      final sub = _sub;
      _sub = null;
      await sub?.cancel();
      try {
        await _recorder.stop();
      } on Object {
        // Already stopped by the platform; the stream ends anyway.
      }
      if (!out.isClosed) await out.close();
    }();
  }
}
