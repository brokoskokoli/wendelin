import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../io/speech_to_text.dart';

/// Stage 2: confirms a candidate (port, so tests run without Whisper).
abstract interface class WakeVerifier {
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
  'wendeln',
  'wendeli',
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

/// Whether [transcript] contains „Wendelin“ fuzzily: after folding (case,
/// diacritics, punctuation) a word or a pair of neighbouring words
/// („Wende Lin“) must be within [maxDistance] edits of a spelling or sound
/// like it ([soundsLikeWakeWord]).
bool matchesWakeWord(String transcript, {int maxDistance = 1}) {
  final words = foldForMatch(transcript).split(' ').where((w) => w.isNotEmpty);
  final list = words.toList();
  bool near(String s) {
    if (soundsLikeWakeWord(s)) return true;
    for (final spelling in wakeWordSpellings) {
      if (_distance(s, spelling) <= maxDistance) return true;
    }
    return false;
  }

  for (var i = 0; i < list.length; i++) {
    if (near(list[i])) return true;
    if (i + 1 < list.length && near(list[i] + list[i + 1])) return true;
  }
  return false;
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

/// [WakeVerifier] on top of a [SpeechToText] (Whisper, already loaded or
/// base).
final class TranscriptWakeVerifier implements WakeVerifier {
  /// Creates the verifier; only the last [maxSamples] are transcribed.
  TranscriptWakeVerifier(
    this.stt, {
    this.maxSamples = 48000,
    this.language = 'de',
    this.maxDistance = 1,
  });

  /// The recognizer.
  final SpeechToText stt;

  /// Longest transcribed audio (default 3 s).
  final int maxSamples;

  /// Recognition language.
  final String language;

  /// Edit distance tolerance.
  final int maxDistance;

  @override
  Future<bool> confirm(Int16List pcm) async {
    final audio = pcm.length > maxSamples
        ? Int16List.sublistView(pcm, pcm.length - maxSamples)
        : pcm;
    final t = await stt.transcribe(audio, language: language);
    return matchesWakeWord(t.text, maxDistance: maxDistance);
  }
}
