import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../io/audio_input.dart';

/// Limits for [Endpointer] (concept: Aufnahme und VAD).
@immutable
final class EndpointConfig {
  /// Creates a configuration; all durations must be positive.
  const EndpointConfig({
    this.preRoll = const Duration(milliseconds: 300),
    this.endSilence = const Duration(milliseconds: 800),
    this.maxDuration = const Duration(seconds: 30),
    this.minSpeech = const Duration(milliseconds: 200),
    this.noSpeechTimeout = const Duration(seconds: 8),
  });

  /// Audio kept from before the first speech frame, so the first word is
  /// not cut off.
  final Duration preRoll;

  /// Silence after speech that ends the utterance.
  final Duration endSilence;

  /// Maximum recording time from the start of listening.
  final Duration maxDuration;

  /// Speech shorter than this (from the first to the last speech frame) is
  /// treated as noise: it is dropped and listening continues. 200 ms keeps
  /// short answers like „Ja“ or „Nein“; calibrate with real Silero VAD
  /// output on devices (WP17) and adjust if clicks or breaths get through.
  final Duration minSpeech;

  /// Listening ends with [EndpointKind.nothing] if no valid speech has
  /// started within this time (also the follow-up window of the
  /// conversation mode).
  final Duration noSpeechTimeout;

  /// Copy with a different [noSpeechTimeout].
  EndpointConfig withNoSpeechTimeout(Duration timeout) => EndpointConfig(
    preRoll: preRoll,
    endSilence: endSilence,
    maxDuration: maxDuration,
    minSpeech: minSpeech,
    noSpeechTimeout: timeout,
  );
}

/// How listening ended.
enum EndpointKind {
  /// An utterance was captured.
  utterance,

  /// No (long enough) speech: „nichts verstanden“.
  nothing,
}

/// Why listening ended.
enum EndpointReason {
  /// [EndpointConfig.endSilence] of silence after speech.
  silence,

  /// [EndpointConfig.maxDuration] reached.
  maxDuration,

  /// No speech within [EndpointConfig.noSpeechTimeout].
  noSpeech,

  /// The caller ended listening ([Endpointer.finish]).
  manual,
}

/// Result of [Endpointer].
@immutable
final class Endpoint {
  /// Creates a result.
  const Endpoint({
    required this.kind,
    required this.reason,
    required this.pcm,
    this.speechStart,
    this.speechEnd,
    required this.elapsed,
  });

  /// Utterance or nothing.
  final EndpointKind kind;

  /// Why listening ended.
  final EndpointReason reason;

  /// Captured audio (pre-roll + speech + trailing silence); empty for
  /// [EndpointKind.nothing].
  final Int16List pcm;

  /// Offset of the first speech frame from the start of listening.
  final Duration? speechStart;

  /// Offset of the end of the last speech frame.
  final Duration? speechEnd;

  /// Audio time consumed when the decision was made.
  final Duration elapsed;

  @override
  String toString() =>
      'Endpoint(${kind.name}, ${reason.name}, '
      '${speechStart?.inMilliseconds}–${speechEnd?.inMilliseconds} ms, '
      '${pcm.length} samples)';
}

/// Decides from per-frame speech/silence flags when an utterance starts and
/// ends. Pure logic over audio time (sample counts), no wall clock.
///
/// Feed frames with [add] until it returns an [Endpoint]; afterwards the
/// endpointer is finished and must be recreated.
final class Endpointer {
  /// Creates an endpointer for one recording.
  Endpointer([this.config = const EndpointConfig()]);

  /// Limits.
  final EndpointConfig config;

  final _preRoll = <Int16List>[];
  int _preRollSamples = 0;
  final _speech = <Int16List>[];

  int _elapsed = 0; // samples since listening started
  int? _speechStart; // samples
  int _speechEnd = 0; // samples
  int _silenceRun = 0; // samples
  Endpoint? _result;

  /// The decision, once made.
  Endpoint? get result => _result;

  /// Whether speech is currently being captured.
  bool get inSpeech => _speechStart != null;

  /// Adds one frame; returns the [Endpoint] when listening is over,
  /// otherwise `null`. Frames after the decision are ignored.
  Endpoint? add(Int16List frame, {required bool speech}) {
    if (_result != null) return _result;
    final start = _elapsed;
    _elapsed += frame.length;
    if (_speechStart == null) {
      if (speech) {
        _speechStart = start;
        _speechEnd = _elapsed;
        _silenceRun = 0;
        _speech.add(frame);
      } else {
        _pushPreRoll(frame);
      }
    } else {
      _speech.add(frame);
      if (speech) {
        _speechEnd = _elapsed;
        _silenceRun = 0;
      } else {
        _silenceRun += frame.length;
        if (_silenceRun >= _samples(config.endSilence)) {
          final done = _finishSpeech(EndpointReason.silence);
          if (done != null) return done;
        }
      }
    }
    if (_elapsed >= _samples(config.maxDuration)) {
      return finish(EndpointReason.maxDuration);
    }
    if (_speechStart == null && _elapsed >= _samples(config.noSpeechTimeout)) {
      return _decide(EndpointKind.nothing, EndpointReason.noSpeech);
    }
    return null;
  }

  /// Ends listening now (manual stop or time limit) and returns the
  /// decision: the current speech if it is long enough, otherwise nothing.
  Endpoint finish([EndpointReason reason = EndpointReason.manual]) {
    if (_result != null) return _result!;
    if (_speechStart != null) {
      final done = _finishSpeech(reason);
      if (done != null) return done;
    }
    return _decide(EndpointKind.nothing, reason);
  }

  /// Ends the current speech segment: an utterance if it lasted at least
  /// [EndpointConfig.minSpeech], otherwise the noise is dropped and `null`
  /// is returned (listening continues).
  Endpoint? _finishSpeech(EndpointReason reason) {
    if (_speechEnd - _speechStart! >= _samples(config.minSpeech)) {
      return _decide(EndpointKind.utterance, reason);
    }
    // Noise: keep the tail as pre-roll for a following real utterance.
    final dropped = List.of(_speech);
    _speech.clear();
    _speechStart = null;
    _silenceRun = 0;
    dropped.forEach(_pushPreRoll);
    return null;
  }

  Endpoint _decide(EndpointKind kind, EndpointReason reason) {
    final utterance = kind == EndpointKind.utterance;
    final pcm = utterance ? _concat([..._preRoll, ..._speech]) : Int16List(0);
    return _result = Endpoint(
      kind: kind,
      reason: reason,
      pcm: pcm,
      speechStart: utterance ? samplesToDuration(_speechStart!) : null,
      speechEnd: utterance ? samplesToDuration(_speechEnd) : null,
      elapsed: samplesToDuration(_elapsed),
    );
  }

  void _pushPreRoll(Int16List frame) {
    _preRoll.add(frame);
    _preRollSamples += frame.length;
    final limit = _samples(config.preRoll);
    while (_preRoll.isNotEmpty &&
        _preRollSamples - _preRoll.first.length >= limit) {
      _preRollSamples -= _preRoll.removeAt(0).length;
    }
    // Trim the oldest frame so that exactly [preRoll] remains.
    if (_preRollSamples > limit && _preRoll.isNotEmpty) {
      final cut = _preRollSamples - limit;
      _preRoll[0] = Int16List.sublistView(_preRoll.first, cut);
      _preRollSamples = limit;
    }
  }

  static int _samples(Duration d) => durationToSamples(d);

  static Int16List _concat(List<Int16List> frames) {
    final out = Int16List(frames.fold(0, (n, f) => n + f.length));
    var offset = 0;
    for (final f in frames) {
      out.setAll(offset, f);
      offset += f.length;
    }
    return out;
  }
}
