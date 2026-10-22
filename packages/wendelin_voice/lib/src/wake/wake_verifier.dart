import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../io/speech_to_text.dart';
import '../models/wake_classifier_catalog.dart';
import 'level_normalize.dart';

/// Stage 2: confirms a candidate (port, so tests run without Whisper).
abstract interface class WakeVerifier {
  /// Which recognizer decides (`whisper`, `parakeet`; diagnostics only, goes
  /// into the log line `wake-hit-stage`).
  String get kind;

  /// Whether [pcm] (16 kHz mono, pre-roll plus candidate window, at most
  /// about three seconds) really contains the wake word.
  Future<bool> confirm(Int16List pcm);
}

/// Spellings of „Wendelin“ that count as the wake word after folding
/// (`foldForMatch`): the name, common mis-hearings and splits.
const wakeWordSpellings = [
  'wendelin',
  'wendeline',
  'wendelien',
  'wendlin',
  'vendelin',
  'wendeling',
  'wendelyn',
  'wendellin',
  'wendelmann',
  'wendemann',
  'wendelen',
  'wendelan',
];

/// Kölner Phonetik of „Wendelin“ (`36256`): words that sound like it but
/// are spelled differently („Wendelmann“, „Fendelien“) count as well.
final _wakeKey = colognePhonetic('wendelin');

/// Whether [word] (folded, one word) sounds like „Wendelin“: same
/// Kölner-Phonetik key, plausible length and the same initial sound
/// (w/v/f).
bool soundsLikeWakeWord(String word) =>
    word.length >= 6 &&
    word.length <= 11 &&
    'wvf'.contains(word[0]) &&
    colognePhonetic(word) == _wakeKey;

/// Edit distance tolerance of the wake word check and of stripping the wake
/// word from the transcript (WP73): the same for both, so what is
/// recognized is also removed. Two edits count only for a single word
/// (see [wakeWordMatchLength]).
const wakeVerifyMaxDistance = 2;

/// How many words from [words] (folded, from index [i]) form the wake word:
/// 0 (none), 1 (one word) or 2 (a split word, „Wende Lin“; never in front
/// of a function word: „Wendel in den Keller“, WP68). One edit counts for
/// both, two edits only for a single word of at least seven characters that
/// starts like „Wendelin“ (w/v/f): „Wandolin“ (WP73). Shared by
/// [matchesWakeWord] and [stripWakeWord].
int wakeWordMatchLength(
  List<String> words,
  int i, {
  int maxDistance = wakeVerifyMaxDistance,
}) {
  if (_nearWakeWord(words[i], maxDistance, single: true)) return 1;
  if (i + 1 < words.length &&
      !_notSplitTail.contains(words[i + 1]) &&
      _nearWakeWord(words[i] + words[i + 1], maxDistance, single: false)) {
    return 2;
  }
  return 0;
}

/// Whether [transcript] contains „Wendelin“ fuzzily: after folding (case,
/// diacritics, punctuation) a word or a pair of neighbouring words
/// („Wende Lin“) must be within [maxDistance] edits of a spelling or sound
/// like it ([soundsLikeWakeWord]).
bool matchesWakeWord(
  String transcript, {
  int maxDistance = wakeVerifyMaxDistance,
}) {
  final list = foldForMatch(transcript)
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  for (var i = 0; i < list.length; i++) {
    if (wakeWordMatchLength(list, i, maxDistance: maxDistance) > 0) {
      return true;
    }
  }
  return false;
}

bool _nearWakeWord(String s, int maxDistance, {required bool single}) {
  if (soundsLikeWakeWord(s)) return true;
  final twoEdits =
      single && maxDistance >= 2 && s.length >= 7 && 'wvf'.contains(s[0]);
  for (final spelling in wakeWordSpellings) {
    final d = _distance(s, spelling);
    if (d <= 1 && d <= maxDistance) return true;
    if (twoEdits && d <= 2 && spelling == 'wendelin') return true;
  }
  return false;
}

/// How a transcript relates to the wake word, for the log of the
/// verification (WP73): `empty`, `exact` („Wendelin“), `variant` (another
/// spelling or sound) or `other` (some other text). Never the text itself.
String wakeTranscriptCategory(
  String transcript, {
  int maxDistance = wakeVerifyMaxDistance,
}) {
  if (transcript.trim().isEmpty) return 'empty';
  if (!matchesWakeWord(transcript, maxDistance: maxDistance)) return 'other';
  return foldForMatch(transcript).split(' ').contains('wendelin')
      ? 'exact'
      : 'variant';
}

/// Words that follow a name in a sentence, not the second half of a split
/// wake word: „Wendel in den Keller“ is not „Wendelin“ (WP68).
const _notSplitTail = {
  'in',
  'im',
  'ins',
  'an',
  'am',
  'auf',
  'aus',
  'bei',
  'mit',
  'von',
  'vor',
  'zu',
  'zum',
  'zur',
  'den',
  'dem',
  'der',
  'die',
  'das',
  'ein',
  'und',
};

const _greetings = {'hey', 'hallo', 'hi', 'he', 'ok', 'okay', 'ey'};

/// [transcript] without the leading wake word (WP68): „Wendelin, schalte die
/// Taschenlampe an“ becomes „schalte die Taschenlampe an“. Spellings as in
/// [matchesWakeWord] (also split: „Wende Lin“, but not in front of a function word:
/// „Wendel in den Keller“ stays), a greeting before it
/// („Hey Wendelin“) goes too. The word counts only at the start (the first
/// three words); otherwise the text stays as it is. May return an empty
/// string (only the wake word was said).
String stripWakeWord(
  String transcript, {
  int maxDistance = wakeVerifyMaxDistance,
}) {
  final tokens = transcript.trim().split(RegExp(r'\s+'));
  final folded = [for (final t in tokens) foldForMatch(t).replaceAll(' ', '')];
  final limit = tokens.length < 3 ? tokens.length : 3;
  for (var i = 0; i < limit; i++) {
    if (folded[i].isEmpty) continue;
    final consumed = wakeWordMatchLength(folded, i, maxDistance: maxDistance);
    if (consumed > 0) {
      final before = folded.sublist(0, i);
      if (before.any((w) => w.isNotEmpty && !_greetings.contains(w))) break;
      return tokens
          .sublist(i + consumed)
          .join(' ')
          .replaceFirst(RegExp(r'^[\s,.:;!?\-–—]+'), '');
    }
  }
  return transcript.trim();
}

int _distance(String a, String b) {
  if ((a.length - b.length).abs() > 3) return 99;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + c,
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Takes [preferred] if [available] says so (e.g. the better model is
/// installed), else [fallback]; an [available] that throws counts as
/// „not available“ (WP129: Parakeet, else Whisper). [kind] is the one of the
/// recognizer that took the last clip.
final class PreferredWakeVerifier implements WakeVerifier {
  /// Creates the verifier.
  PreferredWakeVerifier({
    required this.preferred,
    required this.fallback,
    required this.available,
  }) : _kind = fallback.kind;

  /// Used when [available].
  final WakeVerifier preferred;

  /// Used otherwise.
  final WakeVerifier fallback;

  /// Whether [preferred] can run now.
  final Future<bool> Function() available;

  String _kind;

  @override
  String get kind => _kind;

  @override
  Future<bool> confirm(Int16List pcm) async {
    var use = fallback;
    try {
      if (await available()) use = preferred;
    } on Object {
      use = fallback;
    }
    _kind = use.kind;
    return use.confirm(pcm);
  }
}

/// [WakeVerifier] on top of a [SpeechToText] (Whisper or Parakeet, already
/// loaded or base). The clip is scaled to `WakeClassifierRules.verifyPeak`
/// first if [normalize] is set (per recognizer, see the catalog rules).
final class TranscriptWakeVerifier implements WakeVerifier {
  /// Creates the verifier; only the last [maxSamples] are transcribed.
  TranscriptWakeVerifier(
    this.stt, {
    this.maxSamples = 48000,
    this.language = 'de',
    this.maxDistance = wakeVerifyMaxDistance,
    this.onCategory,
    this.kind = 'whisper',
    this.normalize = WakeClassifierRules.verifyNormalizeWhisper,
  });

  @override
  final String kind;

  /// Whether the clip is scaled to the target peak before the transcription.
  final bool normalize;

  /// The recognizer.
  final SpeechToText stt;

  /// Longest transcribed audio (default 3 s).
  final int maxSamples;

  /// Recognition language.
  final String language;

  /// Edit distance tolerance ([wakeVerifyMaxDistance], WP73: Whisper often
  /// writes a near miss).
  final int maxDistance;

  /// Called with [wakeTranscriptCategory] and the audio length in ms of every
  /// verdict (diagnostics, no text).
  final void Function(String category, int ms)? onCategory;

  @override
  Future<bool> confirm(Int16List pcm) async {
    final tail = pcm.length > maxSamples
        ? Int16List.sublistView(pcm, pcm.length - maxSamples)
        : pcm;
    final audio = normalize
        ? normalizePeak(
            tail,
            target: WakeClassifierRules.verifyPeak,
            minPeak: WakeClassifierRules.verifyMinPeak,
          )
        : tail;
    final t = await stt.transcribe(audio, language: language);
    onCategory?.call(
      wakeTranscriptCategory(t.text, maxDistance: maxDistance),
      audio.length ~/ 16,
    );
    return matchesWakeWord(t.text, maxDistance: maxDistance);
  }
}
