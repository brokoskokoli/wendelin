import 'dart:async';
import 'dart:typed_data';

import '../io/audio_input.dart';
import '../io/speech_to_text.dart';
import '../io/voice_activity_detector.dart';
import '../io/voice_exception.dart';
import '../pipeline/endpointer.dart';

/// Why a recognition request failed. The Android service maps the kinds to
/// `SpeechRecognizer.ERROR_*` codes.
enum RecognitionErrorKind {
  /// Speech was heard but nothing was recognized (`ERROR_NO_MATCH`).
  noMatch,

  /// No speech within the no-speech timeout (`ERROR_SPEECH_TIMEOUT`).
  speechTimeout,

  /// The microphone failed (`ERROR_AUDIO`).
  audio,

  /// The microphone permission is missing
  /// (`ERROR_INSUFFICIENT_PERMISSIONS`).
  permission,

  /// Whisper or Silero are not downloaded (`ERROR_CLIENT`).
  modelMissing,

  /// The requested language is not de/fr/en
  /// (`ERROR_LANGUAGE_NOT_SUPPORTED`).
  language,

  /// Anything else (`ERROR_CLIENT`).
  client,
}

/// Event of a [RecognitionSession]. Every session that is not cancelled
/// ends with exactly one [RecognitionResult] or [RecognitionFailed].
sealed class RecognitionEvent {
  const RecognitionEvent();
}

/// The first speech frame was heard (`onBeginningOfSpeech`).
final class RecognitionSpeechBegan extends RecognitionEvent {
  /// Creates the event.
  const RecognitionSpeechBegan();
}

/// Listening ended with an utterance; transcription follows
/// (`onEndOfSpeech`).
final class RecognitionSpeechEnded extends RecognitionEvent {
  /// Creates the event.
  const RecognitionSpeechEnded();
}

/// The recognized text (`onResults`).
final class RecognitionResult extends RecognitionEvent {
  /// Creates the event.
  const RecognitionResult(this.transcript);

  /// Whisper's transcript (text not empty).
  final Transcript transcript;
}

/// The request failed (`onError`).
final class RecognitionFailed extends RecognitionEvent {
  /// Creates the event.
  const RecognitionFailed(this.kind, this.message);

  /// What went wrong.
  final RecognitionErrorKind kind;

  /// German, secret-free description (for logs and hints).
  final String message;

  @override
  String toString() => 'RecognitionFailed(${kind.name}, $message)';
}

/// Supported recognition languages (Whisper in Wendelin, concept K1).
const recognitionLanguages = {'de', 'fr', 'en'};

/// Language of a recognition request: the primary subtag of [requested]
/// (`EXTRA_LANGUAGE`, e.g. `de-DE`) if given, otherwise [fallback] (the
/// app setting; `null` = let Whisper detect).
///
/// Throws `VoiceException(unsupportedLanguage)` if [requested] is not one
/// of [supported].
String? recognitionLanguage(
  String? requested, {
  String? fallback,
  Set<String> supported = recognitionLanguages,
}) {
  final tag = requested?.trim() ?? '';
  if (tag.isEmpty) return fallback;
  final primary = tag.split(RegExp('[-_]')).first.toLowerCase();
  if (!supported.contains(primary)) {
    throw VoiceException(
      VoiceErrorKind.unsupportedLanguage,
      'Die Sprache „$tag“ erkennt Wendelin nicht '
      '(nur ${supported.join(', ')}).',
    );
  }
  return primary;
}

/// One speech recognition request for another app (Android
/// `RecognitionService`, WP20): listens on [audio] with the same endpointing
/// as the `VoicePipeline` ([Endpointer] over [vad]), transcribes the
/// utterance with [stt] and reports [RecognitionEvent]s to [onEvent].
///
/// Nothing is stored: the audio lives only in memory until the transcript
/// is done.
final class RecognitionSession {
  /// Creates a session. [stt] may still be loading (it is awaited only
  /// after the utterance, so loading overlaps with listening); its errors
  /// are reported as [RecognitionFailed].
  RecognitionSession({
    required this.audio,
    required this.vad,
    required Future<SpeechToText> stt,
    required this.onEvent,
    this.endpoint = const EndpointConfig(),
    this.language,
    this.listenGrace = const Duration(seconds: 2),
  }) : _stt = stt..ignore();

  /// Microphone (on Android: frames from the service).
  final AudioInput audio;

  /// Silero VAD.
  final VoiceActivityDetector vad;

  final Future<SpeechToText> _stt;

  /// Receives the events.
  final void Function(RecognitionEvent event) onEvent;

  /// Endpointing limits (from Einstellungen → Sprache).
  final EndpointConfig endpoint;

  /// Whisper language; `null` = detect.
  final String? language;

  /// Wall-clock grace on top of the audio-time limits, in case the
  /// microphone stops delivering frames.
  final Duration listenGrace;

  bool _started = false;
  bool _cancelled = false;
  bool _ended = false;
  Endpointer? _endpointer;
  void Function(Endpoint?)? _endListening;

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled;

  /// Runs the request; completes after the final event (or the cancel).
  Future<void> run() async {
    if (_started) throw StateError('RecognitionSession läuft bereits');
    _started = true;
    final endpoint = await _listen();
    if (_cancelled || endpoint == null) return;
    if (endpoint.kind == EndpointKind.nothing) {
      return endpoint.reason == EndpointReason.noSpeech
          ? _fail(RecognitionErrorKind.speechTimeout, 'Keine Sprache gehört.')
          : _fail(RecognitionErrorKind.noMatch, 'Nichts verstanden.');
    }
    _emit(const RecognitionSpeechEnded());
    final Transcript transcript;
    try {
      transcript = await (await _stt).transcribe(
        endpoint.pcm,
        language: language,
      );
    } on Object catch (e) {
      if (_cancelled) return;
      return _fail(_kindOf(e, RecognitionErrorKind.client), _messageOf(e));
    }
    if (_cancelled) return;
    if (transcript.text.trim().isEmpty) {
      return _fail(RecognitionErrorKind.noMatch, 'Nichts verstanden.');
    }
    _end(RecognitionResult(transcript));
  }

  /// Ends listening now (`stopListening`): the speech so far is
  /// transcribed, without speech the request ends with
  /// [RecognitionErrorKind.noMatch].
  void stop() {
    final e = _endpointer;
    final end = _endListening;
    if (e != null && end != null) end(e.finish());
  }

  /// Cancels the request (`cancel`): stops the microphone, no further
  /// events.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    final end = _endListening;
    if (end != null) end(null);
    if (audio.isRunning) await audio.stop();
  }

  Future<Endpoint?> _listen() async {
    final endpointer = _endpointer = Endpointer(endpoint);
    final done = Completer<Endpoint?>();
    void end(Endpoint? e) {
      if (!done.isCompleted) done.complete(e);
    }

    void fail(Object error) {
      if (done.isCompleted) return;
      if (!_cancelled) {
        _fail(_kindOf(error, RecognitionErrorKind.audio), _messageOf(error));
      }
      end(null);
    }

    _endListening = end;
    StreamSubscription<Int16List>? sub;
    final guards = <Timer>[];
    var began = false;
    try {
      vad.reset();
      sub = audio.start().listen(
        (frame) {
          if (done.isCompleted || frame.isEmpty) return;
          try {
            final e = endpointer.add(frame, speech: vad.isSpeech(frame));
            if (!began && endpointer.inSpeech) {
              began = true;
              _emit(const RecognitionSpeechBegan());
            }
            if (e != null) end(e);
          } on Object catch (error) {
            fail(error);
          }
        },
        onError: fail,
        onDone: () => end(endpointer.finish()),
      );
      guards
        ..add(
          Timer(endpoint.noSpeechTimeout + listenGrace, () {
            if (!endpointer.inSpeech) {
              end(endpointer.finish(EndpointReason.noSpeech));
            }
          }),
        )
        ..add(
          Timer(
            endpoint.maxDuration + listenGrace,
            () => end(endpointer.finish(EndpointReason.maxDuration)),
          ),
        );
    } on Object catch (error) {
      fail(error);
    }
    final result = await done.future;
    _endListening = null;
    _endpointer = null;
    for (final g in guards) {
      g.cancel();
    }
    try {
      if (sub != null && audio.isRunning) await audio.stop();
    } on Object catch (error) {
      // The decision is made; a failing stop must not hide the result.
      if (result == null) fail(error);
    }
    unawaited(sub?.cancel());
    return result;
  }

  static RecognitionErrorKind _kindOf(
    Object error,
    RecognitionErrorKind other,
  ) => switch (error) {
    VoiceException(kind: VoiceErrorKind.permissionDenied) =>
      RecognitionErrorKind.permission,
    VoiceException(kind: VoiceErrorKind.modelMissing) =>
      RecognitionErrorKind.modelMissing,
    VoiceException(kind: VoiceErrorKind.unsupportedLanguage) =>
      RecognitionErrorKind.language,
    _ => other,
  };

  static String _messageOf(Object error) => switch (error) {
    VoiceException(:final message) => message,
    _ => 'Die Spracherkennung ist fehlgeschlagen.',
  };

  void _fail(RecognitionErrorKind kind, String message) =>
      _end(RecognitionFailed(kind, message));

  void _end(RecognitionEvent event) {
    if (_ended || _cancelled) return;
    _ended = true;
    onEvent(event);
  }

  void _emit(RecognitionEvent event) {
    if (!_ended && !_cancelled) onEvent(event);
  }
}
