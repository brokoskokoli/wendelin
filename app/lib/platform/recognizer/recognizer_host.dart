import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Platform channel between `WendelinRecognitionService` (Kotlin) and the
/// recognizer engine (`recognizerMain`).
const recognizerChannelName = 'app.wendelin/recognizer';

/// One recognition request of another app, as the service sends it: the
/// requested language (`EXTRA_LANGUAGE`) and the settings mirrored from
/// Einstellungen → Sprache (`RecognizerConfigSync`).
@immutable
final class RecognizerRequest {
  /// Creates a request.
  const RecognizerRequest({
    required this.session,
    this.language,
    this.model = 'whisper-base',
    this.sttLanguage,
    this.vadThreshold = 0.5,
    this.minSpeechMs = 200,
  });

  /// Reads the channel arguments; invalid values fall back to the
  /// defaults (like `VoiceSettings.fromJson`).
  factory RecognizerRequest.fromArgs(Object? args) {
    final map = args is Map ? args : const <Object?, Object?>{};
    T? pick<T>(String key, bool Function(T) valid) {
      final v = map[key];
      return v is T && valid(v) ? v : null;
    }

    const d = RecognizerRequest(session: 0);
    final stt = pick<String>('sttLanguage', recognitionLanguages.contains);
    return RecognizerRequest(
      session: pick<int>('session', (_) => true) ?? 0,
      language: pick<String>('language', (v) => v.trim().isNotEmpty),
      model: pick<String>('model', (v) => v.startsWith('whisper-')) ?? d.model,
      sttLanguage: stt,
      vadThreshold:
          pick<num>('vadThreshold', (v) => v > 0 && v < 1)?.toDouble() ??
          d.vadThreshold,
      minSpeechMs:
          pick<int>('minSpeechMs', (v) => v >= 50 && v <= 1000) ??
          d.minSpeechMs,
    );
  }

  /// Id the service gave this request (events carry it back).
  final int session;

  /// `EXTRA_LANGUAGE` of the calling app (`de-DE`, …), if any.
  final String? language;

  /// Whisper model id.
  final String model;

  /// Language from the settings; `null` = let Whisper detect.
  final String? sttLanguage;

  /// Silero threshold.
  final double vadThreshold;

  /// Minimum speech duration of the endpointing (ms).
  final int minSpeechMs;

  /// Endpointing limits: the pipeline's, with [minSpeechMs].
  EndpointConfig get endpoint =>
      EndpointConfig(minSpeech: Duration(milliseconds: minSpeechMs));
}

/// Models for the recognizer engine (device: `DeviceRecognizerEngines`).
abstract interface class RecognizerEngines {
  /// Throws `VoiceException(modelMissing)` unless Whisper [modelId] and
  /// Silero are installed.
  Future<void> checkInstalled(String modelId);

  /// A fresh Silero VAD (freed with [releaseVad]).
  VoiceActivityDetector vad(double threshold);

  /// Frees [vad].
  void releaseVad(VoiceActivityDetector vad);

  /// Whisper [modelId] (shared with the app or loaded here).
  Future<SpeechToText> speechToText(String modelId);

  /// A request ended; models may be released after a while.
  void idle();

  /// Frees everything.
  Future<void> dispose();
}

/// [AudioInput] fed by the service over the channel: Kotlin records (with
/// the caller's attribution) and sends 16 kHz PCM16 frames. Frames that
/// arrive before [start] are kept, so nothing is lost while the engine
/// starts. [stop] tells the service to stop recording.
final class ChannelAudioInput implements AudioInput {
  /// Creates the input; [onStop] stops the recording in the service.
  ChannelAudioInput(this.onStop);

  /// Stops the recording in the service.
  final Future<void> Function() onStop;

  final _early = <Int16List>[];
  Object? _earlyError;
  // Closed in [stop].
  // ignore: close_sinks
  StreamController<Int16List>? _controller;
  bool _done = false;

  @override
  bool get isRunning => _controller != null;

  @override
  Stream<Int16List> start() {
    if (_controller != null || _done) {
      throw StateError('Die Aufnahme läuft bereits oder ist beendet.');
    }
    // Closed in [stop].
    // ignore: close_sinks
    final c = _controller = StreamController<Int16List>();
    _early.forEach(c.add);
    _early.clear();
    final error = _earlyError;
    if (error != null) c.addError(error);
    return c.stream;
  }

  /// Adds little-endian PCM16 [bytes] from the service.
  void push(Uint8List bytes) {
    if (_done || bytes.length < 2) return;
    final frame = Int16List(bytes.length ~/ 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < frame.length; i++) {
      frame[i] = data.getInt16(i * 2, Endian.little);
    }
    final c = _controller;
    c == null ? _early.add(frame) : c.add(frame);
  }

  /// The recording failed in the service.
  void fail(Object error) {
    if (_done) return;
    final c = _controller;
    c == null ? _earlyError = error : c.addError(error);
  }

  @override
  Future<void> stop() async {
    final c = _controller;
    if (c == null) return;
    _controller = null;
    _done = true;
    await onStop();
    await c.close();
  }
}

/// Dart side of the system speech recognizer (WP20, ADR 0008): runs one
/// [RecognitionSession] per request of `WendelinRecognitionService` and
/// reports its events back. Audio stays in memory; nothing is stored or
/// logged.
///
/// Calls from Kotlin: `start` (request, see [RecognizerRequest.fromArgs]),
/// `audio` (`{session, pcm}`), `audioError` (`{session, code}`), `stop`,
/// `cancel` (`{session}`), `shutdown`. Calls to Kotlin: `ready`,
/// `stopAudio` and `event` (`{session, type: began|ended|result|error,
/// text, confidence, language, error, message}`).
final class RecognizerHost {
  /// Creates the host.
  RecognizerHost({
    required this.engines,
    this.channel = const MethodChannel(recognizerChannelName),
  });

  /// Models.
  final RecognizerEngines engines;

  /// Channel to the service.
  final MethodChannel channel;

  _Request? _current;

  /// Starts answering the service and tells it the engine is ready.
  Future<void> attach() async {
    channel.setMethodCallHandler(handle);
    await channel.invokeMethod<void>('ready');
  }

  /// Handles one call of the service (public for tests).
  @visibleForTesting
  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments is Map
        ? call.arguments as Map
        : const <Object?, Object?>{};
    final session = args['session'];
    final current = _current;
    final matches = current != null && current.id == session;
    switch (call.method) {
      case 'start':
        await _start(RecognizerRequest.fromArgs(args));
      case 'audio':
        final pcm = args['pcm'];
        if (matches && pcm is Uint8List) current.audio.push(pcm);
      case 'audioError':
        if (matches) {
          current.audio.fail(
            args['code'] == 'permission'
                ? const VoiceException(
                    VoiceErrorKind.permissionDenied,
                    'Keine Mikrofon-Berechtigung.',
                  )
                : const VoiceException(
                    VoiceErrorKind.unavailable,
                    'Das Mikrofon ist ausgefallen.',
                  ),
          );
        }
      case 'stop':
        if (matches) current.session?.stop();
      case 'cancel':
        if (matches) await _cancelCurrent();
      case 'shutdown':
        await _cancelCurrent();
        await engines.dispose();
    }
    return null;
  }

  Future<void> _cancelCurrent() async {
    final current = _current;
    _current = null;
    await _cancel(current);
  }

  static Future<void> _cancel(_Request? request) async {
    if (request == null) return;
    request.cancelled = true;
    await request.session?.cancel();
  }

  Future<void> _start(RecognizerRequest request) async {
    final id = request.session;
    final audio = ChannelAudioInput(
      () => _invoke('stopAudio', {'session': id}),
    );
    // Set before any await, so audio, stop and cancel that follow right
    // away find this request.
    final previous = _current;
    final req = _current = _Request(id, audio);
    await _cancel(previous);
    final String? language;
    final VoiceActivityDetector vad;
    try {
      language = recognitionLanguage(
        request.language,
        fallback: request.sttLanguage,
      );
      await engines.checkInstalled(request.model);
      if (req.cancelled) return;
      vad = engines.vad(request.vadThreshold);
    } on Object catch (e) {
      if (!req.cancelled) _sendFinal(req, _failureOf(e));
      return;
    }
    final session = req.session = RecognitionSession(
      audio: audio,
      vad: vad,
      stt: engines.speechToText(request.model),
      endpoint: request.endpoint,
      language: language,
      onEvent: (e) => _send(req, e),
    );
    unawaited(
      session.run().whenComplete(() {
        engines
          ..releaseVad(vad)
          ..idle();
        if (identical(_current, req)) _current = null;
      }),
    );
  }

  static RecognitionFailed _failureOf(Object e) => switch (e) {
    VoiceException(kind: VoiceErrorKind.modelMissing, :final message) =>
      RecognitionFailed(RecognitionErrorKind.modelMissing, message),
    VoiceException(kind: VoiceErrorKind.unsupportedLanguage, :final message) =>
      RecognitionFailed(RecognitionErrorKind.language, message),
    VoiceException(:final message) => RecognitionFailed(
      RecognitionErrorKind.client,
      message,
    ),
    _ => const RecognitionFailed(
      RecognitionErrorKind.client,
      'Die Spracherkennung ließ sich nicht starten.',
    ),
  };

  void _sendFinal(_Request req, RecognitionFailed failure) {
    if (identical(_current, req)) _current = null;
    _send(req, failure);
  }

  void _send(_Request req, RecognitionEvent e) {
    if (req.cancelled) return;
    unawaited(_invoke('event', {'session': req.id, ...eventArgs(e)}));
  }

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Service gone (unbound): nothing to report to.
    } on PlatformException catch (e) {
      debugPrint('Erkenner: $method fehlgeschlagen (${e.code})');
    }
  }
}

/// Channel arguments of [e] (without the session id).
@visibleForTesting
Map<String, Object?> eventArgs(RecognitionEvent e) => switch (e) {
  RecognitionSpeechBegan() => {'type': 'began'},
  RecognitionSpeechEnded() => {'type': 'ended'},
  RecognitionResult(:final transcript) => {
    'type': 'result',
    'text': transcript.text.trim(),
    'confidence': transcript.confidence,
    'language': transcript.language,
  },
  RecognitionFailed(:final kind, :final message) => {
    'type': 'error',
    'error': kind.name,
    'message': message,
  },
};

final class _Request {
  _Request(this.id, this.audio);

  final int id;
  final ChannelAudioInput audio;
  RecognitionSession? session;
  bool cancelled = false;
}
