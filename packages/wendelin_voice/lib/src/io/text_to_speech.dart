import 'package:meta/meta.dart';

/// Playback state of a [TextToSpeech] engine.
enum TtsState {
  /// Nothing is playing.
  idle,

  /// An utterance is playing.
  speaking,
}

/// A voice offered by a [TextToSpeech] engine.
@immutable
final class TtsVoice {
  /// Creates a voice.
  const TtsVoice({required this.id, required this.language, this.name});

  /// Engine-specific id, passed to [TextToSpeech.speak].
  final String id;

  /// Language as BCP 47 tag.
  final String language;

  /// Display name.
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.id == id && other.language == language;

  @override
  int get hashCode => Object.hash(id, language);

  @override
  String toString() => 'TtsVoice($id, $language)';
}

/// Speech output (concept: stage 5): system voice or sherpa-onnx voice.
///
/// Contract (`textToSpeechContract`):
/// - [speak] completes when the utterance has finished **or** was stopped
///   by [stop]; [state] is [TtsState.speaking] in between and
///   [TtsState.idle] afterwards. Utterances do not overlap: a [speak]
///   while speaking waits for or replaces the current one (implementation
///   choice), the returned future still completes.
/// - Blank text completes immediately without changing [state].
/// - [rate] (1.0 = normal) must be > 0, otherwise `ArgumentError`.
/// - [stop] is idempotent and never throws.
/// - [states] is a broadcast stream of state changes.
abstract interface class TextToSpeech {
  /// Whether the engine can speak (system TTS installed, sherpa voice
  /// downloaded).
  Future<bool> get isAvailable;

  /// Voices of the engine.
  Future<List<TtsVoice>> voices();

  /// Current state.
  TtsState get state;

  /// State changes.
  Stream<TtsState> get states;

  /// Speaks [text] with [voice] (a [TtsVoice.id]) at [rate]. Without
  /// [voice] the engine picks its default voice for [language] (BCP 47,
  /// `null` = engine default).
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  });

  /// Stops the current utterance.
  Future<void> stop();
}

/// An utterance whose synthesis was started ahead of playback
/// ([PrefetchingTextToSpeech.prepare]).
abstract interface class TtsPrepared {
  /// The text of the utterance.
  String get text;

  /// Throws the prepared audio away (idempotent, never throws). Playing a
  /// discarded utterance completes at once without a sound.
  void discard();
}

/// A [TextToSpeech] that can synthesise an utterance while another one is
/// still playing (WP120): the pause between two sentences then shrinks from
/// "synthesis time" to nothing, as long as the voice is faster than real
/// time.
///
/// Contract:
/// - [prepare] starts the synthesis at once and never plays; it does not
///   change [state]. Errors surface in [speakPrepared].
/// - [speakPrepared] behaves like [speak] but uses the prepared audio; it
///   completes when the utterance has finished or was stopped.
/// - [stop] also invalidates everything prepared before it (a later
///   [speakPrepared] of such an utterance completes without a sound).
abstract interface class PrefetchingTextToSpeech implements TextToSpeech {
  /// Starts synthesising [text] without playing it.
  TtsPrepared prepare(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  });

  /// Plays [prepared] (waits for its synthesis if it is still running).
  Future<void> speakPrepared(TtsPrepared prepared);
}
