import 'dart:async';
import 'dart:collection';

import '../io/text_to_speech.dart';

/// Speaks sentences one after another on a [TextToSpeech] engine.
///
/// Every sentence belongs to a segment (one model call of the agent), so
/// that an `AgentTextReset` can drop exactly the not yet spoken sentences of
/// the discarded segment ([dropSegment]). The sentence currently playing is
/// finished.
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

  final _pending = Queue<({String text, int segment})>();
  String? _current;
  bool _stopped = false;
  Completer<void>? _idle;

  /// Whether nothing is playing or waiting.
  bool get isIdle => _current == null && _pending.isEmpty;

  /// The sentence currently playing.
  String? get current => _current;

  /// Sentences waiting to be spoken.
  List<String> get pending => [for (final e in _pending) e.text];

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
      _pending.add((text: s, segment: segment));
    }
    if (_current == null && _pending.isNotEmpty) unawaited(_pump());
  }

  /// Removes the waiting sentences of [segment] and returns them.
  List<String> dropSegment(int segment) {
    final dropped = [
      for (final e in _pending)
        if (e.segment == segment) e.text,
    ];
    _pending.removeWhere((e) => e.segment == segment);
    return dropped;
  }

  /// Drops everything waiting and stops the sentence being spoken; the
  /// queue stays usable (unlike [stop]).
  Future<void> interrupt() async {
    if (_stopped) return;
    _pending.clear();
    if (_current != null) await tts.stop();
  }

  /// Clears the queue and stops the engine. The queue accepts nothing
  /// afterwards.
  Future<void> stop() async {
    _stopped = true;
    _pending.clear();
    _completeIdle();
    if (_current != null) await tts.stop();
  }

  Future<void> _pump() async {
    while (_pending.isNotEmpty && !_stopped) {
      final next = _pending.removeFirst();
      _current = next.text;
      onStart?.call(next.text);
      try {
        await tts.speak(
          next.text,
          voice: voice,
          language: language,
          rate: rate,
        );
      } on Object catch (e) {
        onError?.call(e);
      }
      _current = null;
    }
    if (_stopped) return;
    _completeIdle();
    onIdle?.call();
  }

  void _completeIdle() {
    final idle = _idle;
    _idle = null;
    if (idle != null && !idle.isCompleted) idle.complete();
  }
}
