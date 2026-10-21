import 'dart:async';
import 'dart:collection';

import '../io/text_to_speech.dart';

/// Speaks sentences one after another on a [TextToSpeech] engine.
///
/// Every sentence belongs to a segment (one model call of the agent), so
/// that an `AgentTextReset` can drop exactly the not yet spoken sentences of
/// the discarded segment ([dropSegment]). The sentence currently playing is
/// finished.
///
/// WP120: on an engine that is a [PrefetchingTextToSpeech] the sentence
/// after the playing one is synthesised while the playing one is audible
/// (lead of one sentence), so there is no pause for the synthesis between
/// two sentences. [dropSegment], [interrupt] and [stop] discard what was
/// prepared.
final class SpeechQueue {
  /// Creates a queue on [tts].
  SpeechQueue(
    this.tts, {
    this.voice,
    this.language,
    this.rate = 1.0,
    this.onStart,
    this.onIdle,
    this.onError,
  });

  /// Engine.
  final TextToSpeech tts;

  /// Voice id passed to [TextToSpeech.speak].
  final String? voice;

  /// Language passed to [TextToSpeech.speak].
  final String? language;

  /// Speech rate.
  final double rate;

  /// Called when a sentence starts playing.
  final void Function(String sentence)? onStart;

  /// Called when the queue has run empty (not after [stop]).
  final void Function()? onIdle;

  /// Called when the engine fails on a sentence; the queue continues.
  final void Function(Object error)? onError;

  final _pending = Queue<_Item>();
  String? _current;
  bool _stopped = false;
  Completer<void>? _idle;

  /// Whether nothing is playing or waiting.
  bool get isIdle => _current == null && _pending.isEmpty;

  /// The sentence currently playing.
  String? get current => _current;

  /// Sentences waiting to be spoken.
  List<String> get pending => [for (final e in _pending) e.text];

  /// Whether the head of the waiting sentences is already synthesised or
  /// being synthesised (WP120).
  bool get hasPrepared =>
      _pending.isNotEmpty && _pending.first.prepared != null;

  /// Completes when the queue is idle (immediately if it already is) or
  /// stopped.
  Future<void> get whenIdle {
    if (isIdle || _stopped) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  /// Appends [sentences] of [segment]; starts speaking if idle.
  void addAll(Iterable<String> sentences, {int segment = 0}) {
    if (_stopped) return;
    for (final s in sentences) {
      _pending.add(_Item(s, segment));
    }
    if (_current == null && _pending.isNotEmpty) {
      unawaited(_pump());
    } else {
      _prefetch();
    }
  }

  /// Removes the waiting sentences of [segment] and returns them.
  List<String> dropSegment(int segment) {
    final dropped = [
      for (final e in _pending)
        if (e.segment == segment) e.text,
    ];
    _pending.removeWhere((e) {
      if (e.segment != segment) return false;
      e.prepared?.discard();
      return true;
    });
    _prefetch(); // a new head may need its synthesis now
    return dropped;
  }

  /// Drops everything waiting and stops the sentence being spoken; the
  /// queue stays usable (unlike [stop]).
  Future<void> interrupt() async {
    if (_stopped) return;
    _clearPending();
    if (_current != null) await tts.stop();
  }

  /// Clears the queue and stops the engine. The queue accepts nothing
  /// afterwards.
  Future<void> stop() async {
    _stopped = true;
    _clearPending();
    _completeIdle();
    if (_current != null) await tts.stop();
  }

  Future<void> _pump() async {
    while (_pending.isNotEmpty && !_stopped) {
      final next = _pending.removeFirst();
      _current = next.text;
      onStart?.call(next.text);
      try {
        final engine = tts;
        if (engine is PrefetchingTextToSpeech) {
          final prepared = next.prepared ?? _prepare(engine, next.text);
          // The next sentence is synthesised while this one plays.
          _prefetch();
          await engine.speakPrepared(prepared);
        } else {
          await tts.speak(
            next.text,
            voice: voice,
            language: language,
            rate: rate,
          );
        }
      } on Object catch (e) {
        onError?.call(e);
      }
      _current = null;
    }
    if (_stopped) return;
    _completeIdle();
    onIdle?.call();
  }

  TtsPrepared _prepare(PrefetchingTextToSpeech engine, String text) =>
      engine.prepare(text, voice: voice, language: language, rate: rate);

  void _prefetch() {
    final engine = tts;
    if (engine is! PrefetchingTextToSpeech ||
        _stopped ||
        _current == null ||
        _pending.isEmpty) {
      return;
    }
    final head = _pending.first;
    if (head.prepared != null) return;
    try {
      head.prepared = _prepare(engine, head.text);
    } on Object {
      // Not prepared: it is prepared (and fails visibly) when its turn comes.
    }
  }

  void _clearPending() {
    for (final e in _pending) {
      e.prepared?.discard();
    }
    _pending.clear();
  }

  void _completeIdle() {
    final idle = _idle;
    _idle = null;
    if (idle != null && !idle.isCompleted) idle.complete();
  }
}

final class _Item {
  _Item(this.text, this.segment);

  final String text;
  final int segment;
  TtsPrepared? prepared;
}
