import 'dart:async';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
import '../channel_audio_focus_port.dart';

/// Holds the `duck` audio focus while an answer is spoken (WP90): a running
/// media player gets quieter instead of staying at full volume, and
/// continues at normal volume afterwards.
///
/// The answer arrives sentence by sentence; the focus is therefore kept
/// while the pipeline still works on the answer ([SpeechFocus.busy]) and
/// given back only [hold] after that, so it stays for the whole answer and
/// does not flutter between sentences or tool rounds.
///
/// WP118 (K88): with [communication] on, the same span also holds the call
/// path ([route]); it is given back with the focus, also on [drop] (stop).
final class SpeechFocus {
  /// Creates the holder on [port]; [route] and [communication] are the
  /// optional call path of the answer (off when [communication] is null).
  SpeechFocus(
    this._port, {
    this.hold = const Duration(milliseconds: 1500),
    this._route,
    this._communication,
  });

  final AudioFocusPort _port;
  final SpeechRoutePort? _route;
  final Future<bool> Function()? _communication;
  // The call path works for the answer (the player may use its usage).
  bool _routed = false;
  // A switch was asked for, so a leave must follow (also if it failed).
  bool _entered = false;

  /// Whether the answer runs in the call path right now (only after the
  /// switch succeeded).
  bool get routed => _routed;

  /// How long the focus stays after the answer ended (and nobody is busy).
  final Duration hold;

  int _active = 0;
  // Counts the stops: a sentence of a stopped answer must not end the
  // sentences of the next one.
  int _generation = 0;
  bool _held = false;
  bool _busy = false;
  Timer? _release;

  /// Whether the answer is still in progress although no sentence is spoken
  /// right now (the pipeline thinks: a tool round, a slow model). The focus
  /// is kept meanwhile; [hold] only starts when this turns false.
  bool get busy => _busy;

  set busy(bool value) {
    if (_busy == value) return;
    _busy = value;
    if (value) {
      _release?.cancel();
      _release = null;
    }
    if (!value && _held && _active == 0) _schedule();
  }

  /// Identifies the current answer: read it before [begin] and pass it to
  /// [end].
  int get generation => _generation;

  /// A sentence starts: requests the focus. Asking again is cheap and makes
  /// sure it is held after Android took it away for good.
  Future<void> begin() async {
    _active++;
    _release?.cancel();
    _release = null;
    final first = !_held;
    _held = true;
    if (first) await _enterRoute(_generation);
    await _port.acquire(AudioFocusKind.duck);
  }

  Future<void> _enterRoute(int generation) async {
    final route = _route;
    if (route == null || _entered) return;
    try {
      if (!await (_communication?.call() ?? Future.value(false))) return;
    } on Object {
      return; // Setting unreadable: stay in the normal path.
    }
    // Stopped (or given back) while the setting was read: do not switch.
    if (generation != _generation || !_held) return;
    _entered = true;
    final device = await route.enter();
    // Stopped meanwhile: drop already asked for the leave (after our enter).
    if (generation != _generation || !_entered) return;
    _routed = device != null;
    voiceLog('speech-route', {
      'mode': device == null ? 'normal' : 'communication',
      'device': device ?? 'failed',
    });
  }

  void _leaveRoute() {
    if (!_entered) return;
    _entered = false;
    _routed = false;
    voiceLog('speech-route', {'mode': 'normal', 'device': 'restored'});
    unawaited(_route?.leave());
  }

  /// The sentence ended or failed: gives the focus back after [hold] unless
  /// another sentence follows or the pipeline is [busy]. [generation] is the
  /// value read before [begin]; after a [drop] the call is ignored.
  void end(int generation) {
    if (generation != _generation) return;
    if (_active > 0) _active--;
    if (_active > 0) return;
    if (!_busy) _schedule();
  }

  void _schedule() {
    _release?.cancel();
    _release = Timer(hold, () {
      _release = null;
      _held = false;
      unawaited(_port.release(AudioFocusKind.duck));
      _leaveRoute();
    });
  }

  /// Gives the focus back at once (stop).
  void drop() {
    _generation++;
    _active = 0;
    _release?.cancel();
    _release = null;
    _leaveRoute();
    if (!_held) return;
    _held = false;
    unawaited(_port.release(AudioFocusKind.duck));
  }
}

/// A [TextToSpeech] that holds [SpeechFocus] while it speaks.
final class DuckingTextToSpeech implements PrefetchingTextToSpeech {
  /// Wraps [inner].
  DuckingTextToSpeech(this.inner, this.focus);

  /// The wrapped engine.
  final TextToSpeech inner;

  /// The focus holder.
  final SpeechFocus focus;

  @override
  TtsState get state => inner.state;

  @override
  Stream<TtsState> get states => inner.states;

  @override
  Future<bool> get isAvailable => inner.isAvailable;

  @override
  Future<List<TtsVoice>> voices() => inner.voices();

  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) async {
    if (text.trim().isEmpty) return;
    final generation = focus.generation;
    await focus.begin();
    try {
      await inner.speak(text, voice: voice, language: language, rate: rate);
    } finally {
      focus.end(generation);
    }
  }

  @override
  TtsPrepared prepare(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) {
    final engine = inner;
    if (engine is PrefetchingTextToSpeech) {
      return engine.prepare(text, voice: voice, language: language, rate: rate);
    }
    // No lead for an engine that cannot prepare: spoken on its turn.
    return _Deferred(text, voice, language, rate);
  }

  @override
  Future<void> speakPrepared(TtsPrepared prepared) async {
    final text = prepared.text;
    if (text.trim().isEmpty) return;
    final generation = focus.generation;
    await focus.begin();
    try {
      final engine = inner;
      if (prepared is _Deferred) {
        await engine.speak(
          text,
          voice: prepared.voice,
          language: prepared.language,
          rate: prepared.rate,
        );
      } else {
        await (engine as PrefetchingTextToSpeech).speakPrepared(prepared);
      }
    } finally {
      focus.end(generation);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await inner.stop();
    } finally {
      focus.drop();
    }
  }
}

final class _Deferred implements TtsPrepared {
  _Deferred(this.text, this.voice, this.language, this.rate);

  @override
  final String text;
  final String? voice;
  final String? language;
  final double rate;

  @override
  void discard() {}
}
