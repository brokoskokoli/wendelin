import 'package:meta/meta.dart';

import '../text/spoken_answer.dart';
import 'endpointer.dart';

/// How barge-in (interrupting the spoken answer) reacts.
enum BargeInMode {
  /// No barge-in (default): only tapping stops the speech.
  off,

  /// Only the keyword „Wendelin“ (concept K23 c).
  keywords,

  /// Free speech as well (experimental; needs echo cancellation).
  speech,
}

/// Settings of the [VoicePipeline].
@immutable
final class VoicePipelineConfig {
  /// Creates a configuration.
  const VoicePipelineConfig({
    this.endpoint = const EndpointConfig(),
    this.language,
    this.shortening = const SpeechShortening(),
    this.stopWords = defaultStopWords,
    this.fillerWords = defaultFillerWords,
    this.stopPhrases = defaultStopPhrases,
    this.conversationMode = false,
    this.followUpWindow = const Duration(seconds: 5),
    this.maxFollowUps = 5,
    this.closingPhrases = defaultClosingPhrases,
    this.bargeIn = BargeInMode.off,
    this.voice,
    this.rate = 1.0,
    this.listenGrace = const Duration(seconds: 3),
    this.speakNothingUnderstood = true,
    this.speakErrors = true,
  });

  /// Stop words (lower case) in de/fr/en.
  static const defaultStopWords = {
    // de
    'stopp', 'stop', 'halt', 'abbrechen', 'abbruch', 'aufhören', 'ruhe',
    // fr
    'arrête', 'arrêtez', 'annule', 'annuler', 'stoppe',
    // en
    'cancel', 'quiet', 'enough',
  };

  /// Multi-word stop commands (lower case, words separated by spaces).
  static const defaultStopPhrases = {
    // de
    'hör auf', 'hört auf', 'hören sie auf', 'sei still', 'sei ruhig',
    // fr
    'arrête ça', 'arrête ca', 'tais toi', 'taisez vous', 'ça suffit',
    'ca suffit',
    // en
    'stop it', 'stop that', 'be quiet', 'that is enough',
  };

  /// Closing phrases of the conversation mode (lower case, no punctuation).
  static const defaultClosingPhrases = {
    // de
    'danke', 'danke schön', 'danke sehr', 'vielen dank', 'das wars',
    'das war es',
    // fr
    'merci', 'merci beaucoup',
    // en
    'thanks', 'thank you', 'thanks a lot',
  };

  /// Words that may accompany a stop word („Stopp bitte“, „Nein, stopp“).
  static const defaultFillerWords = {
    // de
    'bitte', 'nein', 'jetzt', 'sofort', 'mal', 'doch', 'ok', 'okay', 'danke',
    // the name: „Wendelin, stopp“ after a wake barge-in is a stop command
    'wendelin',
    // fr
    'non', 'maintenant', 's', 'il', 'te', 'vous', 'plaît', 'plait', 'toi',
    'merci', 'ça', 'ca', 'tout', 'de', 'suite',
    // en
    'please', 'no', 'now', 'it', 'that', 'thanks',
  };

  /// Endpointing limits (pre-roll, end silence, maximum, minimum speech).
  final EndpointConfig endpoint;

  /// Fixed STT language (`de`, `fr`, `en`); `null` = detect automatically.
  final String? language;

  /// Limits of the spoken answer.
  final SpeechShortening shortening;

  /// A transcript that consists only of these words and [fillerWords]
  /// (with at least one stop word, repetitions allowed) aborts the request.
  /// While the answer is spoken only tapping ([VoicePipeline.cancel]) or
  /// barge-in ([bargeIn]) stops it.
  final Set<String> stopWords;

  /// Words allowed next to a stop word.
  final Set<String> fillerWords;

  /// Phrases that count like a stop word („Hör auf!“, „arrête ça“,
  /// „stop it“).
  final Set<String> stopPhrases;

  /// Conversation mode (from M4, off by default): after an answer, keep
  /// listening for [followUpWindow] for a follow-up question.
  final bool conversationMode;

  /// Follow-up window of the conversation mode (concept: 5 s).
  final Duration followUpWindow;

  /// Maximum number of follow-up rounds in one conversation (concept
  /// proposal: 5). Afterwards the conversation ends (`maxFollowUps`).
  final int maxFollowUps;

  /// An utterance in the follow-up window that consists only of one of
  /// these phrases ends the conversation quietly („Danke“, „Das war’s“).
  final Set<String> closingPhrases;

  /// Barge-in during speech output (needs a `BargeInDetector`).
  final BargeInMode bargeIn;

  /// TTS voice id; `null` = engine default for the answer language.
  final String? voice;

  /// TTS speech rate.
  final double rate;

  /// Wall-clock safety margin on top of [EndpointConfig.maxDuration] in
  /// case the microphone stops delivering frames.
  final Duration listenGrace;

  /// Whether „Ich habe nichts verstanden“ is spoken.
  final bool speakNothingUnderstood;

  /// Whether the message of a failed agent run is spoken.
  final bool speakErrors;
}
