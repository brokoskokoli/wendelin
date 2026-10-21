import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../src/io/speech_to_text.dart';
import '../src/io/text_to_speech.dart';
import '../src/io/trigger.dart';
import '../src/io/voice_exception.dart';
import '../src/recognizer/hint_terms.dart';

/// Scripted [SpeechToText]: each [transcribe] returns the next transcript
/// of the script (empty text when the script is exhausted or the audio is
/// silent). Set [hold] to keep calls pending until [release].
///
/// Passes `speechToTextContract`.
final class FakeSpeechToText implements SpeechToText {
  /// Creates a fake recognizer.
  FakeSpeechToText([
    Iterable<Transcript> script = const [],
    this.info = const SpeechToTextEngineInfo(
      name: 'Fake-STT',
      languages: {'de', 'fr', 'en'},
      model: 'fake',
    ),
  ]) : _script = List.of(script);

  final List<Transcript> _script;

  @override
  final SpeechToTextEngineInfo info;

  /// Lengths (samples) and languages of all calls.
  final calls = <({int samples, String? language})>[];

  /// Thrown by the next [transcribe] call (then cleared).
  Object? nextError;

  /// Whether calls wait for [release].
  bool hold = false;

  final _held = <Completer<void>>[];

  /// Appends [t] to the script.
  void enqueue(Transcript t) => _script.add(t);

  /// Lets all held calls finish.
  void release() {
    for (final c in _held) {
      c.complete();
    }
    _held.clear();
  }

  @override
  Future<Transcript> transcribe(Int16List pcm, {String? language}) async {
    calls.add((samples: pcm.length, language: language));
    if (language != null && !info.languages.contains(language)) {
      throw VoiceException(
        VoiceErrorKind.unsupportedLanguage,
        'Sprache $language wird nicht unterstützt.',
      );
    }
    if (hold) {
      final c = Completer<void>();
      _held.add(c);
      await c.future;
    }
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    final silent = pcm.every((s) => s == 0);
    if (silent || _script.isEmpty) {
      return Transcript(text: '', language: language);
    }
    return _script.removeAt(0);
  }
}

/// Recording [TextToSpeech]: every utterance lasts [utteranceDuration]
/// (timer, so `fake_async` controls it) or, with [manual], until
/// [completeCurrent]. Playback starts synchronously when idle; further
/// utterances are queued, not overlapped. [stop] ends the current and all
/// queued utterances.
///
/// Passes `textToSpeechContract`.
final class FakeTextToSpeech implements PrefetchingTextToSpeech {
  /// Creates a fake engine.
  FakeTextToSpeech({
    this.utteranceDuration = Duration.zero,
    this.manual = false,
    this.synthesisDuration = Duration.zero,
    this.available = true,
    List<TtsVoice> voices = const [
      TtsVoice(id: 'fake-de', language: 'de'),
      TtsVoice(id: 'fake-fr', language: 'fr'),
      TtsVoice(id: 'fake-en', language: 'en'),
    ],
  }) : _voices = List.unmodifiable(voices);

  /// Length of each utterance.
  final Duration utteranceDuration;

  /// Time the synthesis of one utterance takes ([speak] waits for it before
  /// the utterance starts; [prepare] runs it in the background).
  final Duration synthesisDuration;

  /// Whether utterances only end with [completeCurrent] or [stop].
  final bool manual;

  /// Whether the engine reports itself available.
  bool available;

  final List<TtsVoice> _voices;
  final _states = StreamController<TtsState>.broadcast(sync: true);
  TtsState _state = TtsState.idle;
  final _queue = Queue<({String text, Completer<void> done})>();
  ({String text, Completer<void> done})? _playing;
  Timer? _timer;

  /// Texts that started playing, in order.
  final spoken = <String>[];

  /// Texts that were cut off by [stop].
  final interrupted = <String>[];

  /// Options of all [speak] calls.
  final calls =
      <({String text, String? voice, String? language, double rate})>[];

  /// Texts handed to [prepare], in order.
  final prepared = <String>[];

  /// Prepared texts that were discarded before they were played.
  final discarded = <String>[];

  /// Number of [stop] calls.
  int stops = 0;

  /// Thrown by the next [speak] call (then cleared).
  Object? nextError;

  /// When set, [speak] waits for it before the utterance starts (models the
  /// synthesis time before a sample plays); [state] stays idle meanwhile.
  Completer<void>? synthesis;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<List<TtsVoice>> voices() async => _voices;

  @override
  TtsState get state => _state;

  @override
  Stream<TtsState> get states => _states.stream;

  /// The utterance playing right now.
  String? get current => _playing?.text;

  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) {
    if (rate <= 0) throw ArgumentError.value(rate, 'rate', 'muss > 0 sein');
    final error = nextError;
    if (error != null) {
      nextError = null;
      return Future.error(error);
    }
    calls.add((text: text, voice: voice, language: language, rate: rate));
    if (text.trim().isEmpty) return Future.value();
    if (synthesisDuration > Duration.zero) {
      final wait = Completer<void>();
      Timer(synthesisDuration, wait.complete);
      return wait.future.then((_) => _play(text));
    }
    return _play(text);
  }

  Future<void> _play(String text) {
    final done = Completer<void>();
    final wait = synthesis;
    if (wait != null && !wait.isCompleted) {
      return wait.future.then((_) {
        _queue.add((text: text, done: done));
        _startNext();
        return done.future;
      });
    }
    _queue.add((text: text, done: done));
    _startNext();
    return done.future;
  }

  @override
  TtsPrepared prepare(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) {
    if (rate <= 0) throw ArgumentError.value(rate, 'rate', 'muss > 0 sein');
    prepared.add(text);
    calls.add((text: text, voice: voice, language: language, rate: rate));
    final item = _FakePrepared(text, stops, this);
    if (synthesisDuration > Duration.zero) {
      Timer(synthesisDuration, item.complete);
    } else {
      item.complete();
    }
    return item;
  }

  @override
  Future<void> speakPrepared(TtsPrepared prepared) {
    final item = prepared as _FakePrepared;
    // Synchronous when the synthesis is done (like [speak] without one).
    if (item.isReady) return _playPrepared(item);
    return item._ready.future.then((_) => _playPrepared(item));
  }

  Future<void> _playPrepared(_FakePrepared item) async {
    // Discarded, or stopped after it was prepared: no sound.
    if (item.discardedFlag || item.stopsAtPrepare != stops) return;
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    if (item.text.trim().isEmpty) return;
    return _play(item.text);
  }

  /// Ends the current utterance (manual mode) and starts the next one.
  void completeCurrent() {
    final playing = _playing;
    if (playing == null) return;
    _timer?.cancel();
    _playing = null;
    if (_queue.isEmpty) _set(TtsState.idle);
    playing.done.complete();
    _startNext();
  }

  @override
  Future<void> stop() async {
    stops++;
    _timer?.cancel();
    final playing = _playing;
    _playing = null;
    final queued = List.of(_queue);
    _queue.clear();
    if (playing != null) {
      interrupted.add(playing.text);
      playing.done.complete();
    }
    for (final e in queued) {
      e.done.complete();
    }
    _set(TtsState.idle);
  }

  void _startNext() {
    if (_playing != null || _queue.isEmpty) return;
    final next = _queue.removeFirst();
    _playing = next;
    spoken.add(next.text);
    _set(TtsState.speaking);
    if (!manual) _timer = Timer(utteranceDuration, completeCurrent);
  }

  void _set(TtsState s) {
    if (_state == s) return;
    _state = s;
    _states.add(s);
  }
}

/// [TriggerSource] fired by hand.
final class FakeTriggerSource implements TriggerSource {
  /// Creates a source using [clock] for timestamps.
  FakeTriggerSource(this.clock);

  /// Time source.
  final Clock clock;

  final _controller = StreamController<TriggerEvent>.broadcast(sync: true);

  @override
  Stream<TriggerEvent> get triggers => _controller.stream;

  /// Fires a trigger of [kind] and returns it.
  TriggerEvent fire([TriggerKind kind = TriggerKind.pushToTalk]) {
    final e = TriggerEvent(source: kind, at: clock.now());
    _controller.add(e);
    return e;
  }
}

/// [HintTermSource] with fixed terms (or a failure).
final class FakeHintTermSource implements HintTermSource {
  /// Creates the source; [failure] is thrown by [terms] if set.
  FakeHintTermSource(this._terms, {this.failure});

  final List<HintTerm> _terms;

  /// Thrown by [terms] instead of returning the terms.
  final Object? failure;

  @override
  Future<List<HintTerm>> terms() async {
    final f = failure;
    if (f != null) throw f;
    return _terms;
  }
}

final class _FakePrepared implements TtsPrepared {
  _FakePrepared(this.text, this.stopsAtPrepare, this._owner);

  @override
  final String text;
  final int stopsAtPrepare;
  final FakeTextToSpeech _owner;
  final _ready = Completer<void>();
  bool discardedFlag = false;
  bool isReady = false;

  void complete() {
    isReady = true;
    _ready.complete();
  }

  @override
  void discard() {
    if (discardedFlag) return;
    discardedFlag = true;
    _owner.discarded.add(text);
  }
}
