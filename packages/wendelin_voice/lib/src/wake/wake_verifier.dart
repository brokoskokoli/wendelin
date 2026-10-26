import 'dart:math' as math;
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

/// WP155: a verifier that can tell the numbers of its last verdict (the
/// developer archive stores them; no text, no audio).
abstract interface class VerdictDetail {
  /// Numbers and codes of the last verdict (`score`, `thr`), empty if none.
  Map<String, Object?> get lastDetail;
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

/// Words that stand for „Hey“ in a transcript: the spellings recognizers
/// give for it (WP142, measured on real calls).
const heyWords = {'hey', 'hei', 'he', 'hej', 'hay', 'ey', 'eh', 'ei', 'hi'};

/// [heyWords] plus mis-hearings of „Hey“ (WP142: Parakeet writes „a“, „äh“,
/// „yeah“ … for a soft or quick „Hey“). For the enrollment, where a missed
/// good call costs more than an accepted odd one.
const heyWordsLenient = {
  ...heyWords,
  'a',
  'ah',
  'äh',
  'e',
  'yeah',
  'nee',
  'ne',
  'ja',
  'and',
};

/// Whether [transcript] contains „Hey Wendelin“: the wake word as in
/// [matchesWakeWord] with one of [heyWords] ([heyWordsLenient] if [lenient])
/// directly in front of it. „Wendelin“ alone, „Hey Octavia“ and „Hey“ alone
/// do not match. The single source of this rule (enrollment, WP143).
bool matchesHeyWakeWord(
  String transcript, {
  bool lenient = false,
  int maxDistance = wakeVerifyMaxDistance,
}) {
  final hey = lenient ? heyWordsLenient : heyWords;
  final list = foldForMatch(transcript)
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  for (var i = 1; i < list.length; i++) {
    if (hey.contains(list[i - 1]) &&
        wakeWordMatchLength(list, i, maxDistance: maxDistance) > 0) {
      return true;
    }
  }
  return false;
}

/// What the enrollment's recognizer heard in a recording (WP142).
enum HeardWake {
  /// „Hey Wendelin“ ([matchesHeyWakeWord], lenient).
  heyWendelin,

  /// The wake word without „Hey“ in front of it.
  wendelinOnly,

  /// Something else (noise, another word, nothing).
  other,
}

/// A verifier that also says whether „Hey“ was heard, for the enrollment.
abstract interface class WakeEnrollVerifier implements WakeVerifier {
  /// What [pcm] contains (same clip rules as [confirm]).
  Future<HeardWake> hear(Int16List pcm);
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

/// Diagnosis line `wake-strip` (WP146), numbers and flags only, never text:
/// whether [stripWakeWord] removed something ([rest] shorter than the
/// transcript), the length of the first word of [rest] and its edit distance
/// to „wendelin“ (`firstDist`) and the smallest to the endings „delin“ and
/// „lin“ (`tailDist`); 99 means too different in length, -1 no word.
/// A small distance with `removed=false` is a left-over of the wake word.
String wakeStripLog(String transcript, String rest, {required int speechMs}) {
  final all = transcript.trim();
  final words = rest.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final first = words.isEmpty
      ? ''
      : foldForMatch(words.first).replaceAll(' ', '');
  int d(String s) => first.isEmpty ? -1 : _distance(first, s);
  final tail = first.isEmpty ? -1 : math.min(d('delin'), d('lin'));
  return 'wake-strip speechMs=$speechMs removed=${rest.trim().length < all.length} '
      'firstLen=${first.length} firstDist=${d('wendelin')} tailDist=$tail '
      'restWords=${words.length}';
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

/// A verifier could not start (e.g. its model fails to load): the stage
/// hands the same clip to the fallback instead of rejecting the hit.
final class WakeVerifierUnavailable implements Exception {
  /// Creates the signal.
  const WakeVerifierUnavailable();

  @override
  String toString() => 'WakeVerifierUnavailable';
}

/// Takes [preferred] if [available] says so (e.g. the better model is
/// installed), else [fallback]; an [available] that throws counts as
/// „not available“ (WP129: Parakeet, else Whisper); a [preferred] that throws
/// [WakeVerifierUnavailable] hands the same clip to [fallback]. [kind] is the one of the
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
    if (identical(use, preferred)) {
      try {
        return await use.confirm(pcm);
      } on WakeVerifierUnavailable {
        _kind = fallback.kind;
        return fallback.confirm(pcm);
      }
    }
    return use.confirm(pcm);
  }
}

/// [WakeVerifier] on top of a [SpeechToText] (Whisper or Parakeet, already
/// loaded or base). The clip is scaled to `WakeClassifierRules.verifyPeak`
/// first if [normalize] is set (per recognizer, see the catalog rules).
final class TranscriptWakeVerifier implements WakeEnrollVerifier {
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

  Future<String> _transcribe(Int16List pcm) async {
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
    return t.text;
  }

  @override
  Future<bool> confirm(Int16List pcm) async =>
      matchesWakeWord(await _transcribe(pcm), maxDistance: maxDistance);

  @override
  Future<HeardWake> hear(Int16List pcm) async {
    final text = await _transcribe(pcm);
    if (matchesHeyWakeWord(text, lenient: true, maxDistance: maxDistance)) {
      return HeardWake.heyWendelin;
    }
    return matchesWakeWord(text, maxDistance: maxDistance)
        ? HeardWake.wendelinOnly
        : HeardWake.other;
  }
}
