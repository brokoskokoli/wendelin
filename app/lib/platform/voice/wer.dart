import 'dart:math' as math;

// Word error rate for the STT measurement (tool/stt_wer.dart, tests).

/// Errors of one transcript against its reference.
typedef WordErrors = ({int errors, int words});

const _numbers = {
  'de': [
    'null', 'eins', 'zwei', 'drei', 'vier', 'fünf', 'sechs', 'sieben', //
    'acht', 'neun', 'zehn', 'elf', 'zwölf', 'dreizehn', 'vierzehn',
    'fünfzehn', 'sechzehn', 'siebzehn', 'achtzehn', 'neunzehn', 'zwanzig',
  ],
  'fr': [
    'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', //
    'huit', 'neuf', 'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze',
    'seize', 'dix-sept', 'dix-huit', 'dix-neuf', 'vingt',
  ],
  'en': [
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', //
    'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen',
    'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty',
  ],
};

final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Words of [text] for the WER: lower case, punctuation, hyphens and
/// apostrophes as word breaks, numbers 0–20 as words of [language]
/// (Whisper writes „10 Uhr“ for „zehn Uhr“). Times like „6:30“ become two
/// numbers, French „7h30“ becomes „sept heures 30“; everything else is
/// compared as is.
List<String> werWords(String text, String language) {
  final numbers = _numbers[language] ?? const <String>[];
  List<String> word(String w) {
    final n = int.tryParse(w);
    return n != null && n >= 0 && n < numbers.length
        ? numbers[n].split('-')
        : [w];
  }

  var t = text.toLowerCase();
  if (language == 'fr') {
    // „7h30“, „9h“ → „7 heures 30“, „9 heures“.
    t = t.replaceAllMapped(
      RegExp(r'(\d+)h(\d*)'),
      (m) => ' ${m[1]} heures ${m[2] == '00' ? '' : m[2]} ',
    );
  }
  return [
    for (final w in t.split(_separators))
      if (w.isNotEmpty) ...word(w),
  ];
}

/// Word-level edit distance (substitutions, insertions, deletions) between
/// [reference] and [hypothesis], and the number of reference words.
WordErrors wordErrors(String reference, String hypothesis, String language) {
  final r = werWords(reference, language);
  final h = werWords(hypothesis, language);
  var prev = List<int>.generate(h.length + 1, (j) => j);
  for (var i = 1; i <= r.length; i++) {
    final cur = List<int>.filled(h.length + 1, 0)..[0] = i;
    for (var j = 1; j <= h.length; j++) {
      final sub = prev[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1);
      cur[j] = math.min(sub, math.min(prev[j] + 1, cur[j - 1] + 1));
    }
    prev = cur;
  }
  return (errors: prev[h.length], words: r.length);
}

/// Sums [WordErrors] of several sentences.
final class WerCounter {
  /// Edit operations.
  int errors = 0;

  /// Reference words.
  int words = 0;

  /// Sentences counted.
  int sentences = 0;

  /// Sentences without errors.
  int exact = 0;

  /// Adds one sentence.
  void add(WordErrors e, {String? sentence}) {
    errors += e.errors;
    words += e.words;
    sentences++;
    if (e.errors == 0) exact++;
  }

  /// Adds the counts of [other].
  void merge(WerCounter other) {
    errors += other.errors;
    words += other.words;
    sentences += other.sentences;
    exact += other.exact;
  }

  /// WER 0–1 (may exceed 1 with many insertions).
  double get rate => words == 0 ? 0 : errors / words;

  /// WER as „12,3 %“.
  String get percent =>
      '${(rate * 100).toStringAsFixed(1).replaceAll('.', ',')} %';
}
