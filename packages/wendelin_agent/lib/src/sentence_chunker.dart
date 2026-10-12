/// Buffers streamed text deltas and returns complete sentences, so that TTS
/// can start speaking before the whole answer has arrived.
///
/// A sentence ends at `.`, `!`, `?` or `…` (also runs like `?!` or `...`)
/// plus closing quotes/brackets, when whitespace and a character that is not
/// a lower-case letter follow, or at a line break. Not a sentence end:
/// abbreviations („z. B.“, „Dr.“, „e.g.“, „M.“), initials, numbers such as
/// „10.30 Uhr“ and ordinals before a month („am 3. Oktober“).
///
/// Because the decision needs the next character, a sentence is returned
/// only once the text after it has started; [flush] returns the rest.
final class SentenceChunker {
  /// Creates a chunker; [abbreviations] (lower case, without the dot)
  /// replaces [defaultAbbreviations].
  SentenceChunker({Set<String>? abbreviations})
    : abbreviations = abbreviations ?? defaultAbbreviations;

  /// Words that are followed by a dot without ending the sentence.
  static const defaultAbbreviations = {
    // de
    'dr', 'nr', 'bzw', 'ca', 'evtl', 'ggf', 'inkl', 'zzgl', 'prof', 'str',
    'tel', 'vgl', 'sog', 'abs', 'hr', 'fr', 'min', 'max', 'mio', 'mrd',
    // fr
    'mme', 'mlle', 'env', 'cf', 'ex',
    // en
    'mr', 'mrs', 'ms', 'st', 'vs', 'approx', 'no', 'jr', 'sr',
  };

  static const _months = {
    'januar',
    'jänner',
    'februar',
    'märz',
    'april',
    'mai',
    'juni',
    'juli',
    'august',
    'september',
    'oktober',
    'november',
    'dezember',
    'january',
    'february',
    'march',
    'may',
    'june',
    'july',
    'october',
    'december',
  };

  static const _terminators = '.!?…';
  static const _closers = ')]"\'”’»“';
  static const _frenchClose = '»';

  /// Abbreviations in use.
  final Set<String> abbreviations;

  String _buffer = '';

  /// Text received but not yet returned.
  String get pending => _buffer;

  /// Adds [delta] and returns the sentences completed by it.
  List<String> add(String delta) {
    _buffer += delta;
    return _extract(isFinal: false);
  }

  /// Returns all remaining text as sentences and clears the buffer.
  List<String> flush() => _extract(isFinal: true);

  /// Clears the buffer without returning anything (e.g. after an
  /// escalation replaced the answer).
  void reset() => _buffer = '';

  List<String> _extract({required bool isFinal}) {
    final s = _buffer;
    final out = <String>[];
    var start = 0;

    void emit(int end) {
      final sentence = s.substring(start, end).trim();
      if (sentence.isNotEmpty) out.add(sentence);
      start = end;
    }

    var i = 0;
    scan:
    while (i < s.length) {
      final c = s[i];
      if (c == '\n') {
        emit(i + 1);
        i++;
        continue;
      }
      if (!_terminators.contains(c)) {
        i++;
        continue;
      }
      var j = i + 1;
      while (j < s.length && _terminators.contains(s[j])) {
        j++;
      }
      final singleDot = c == '.' && j == i + 1;
      while (j < s.length && _closers.contains(s[j])) {
        j++;
      }
      // French typography: „Bonjour. »“ – closing guillemet after a space.
      final guillemet = s.indexOf(_frenchClose, j);
      if (guillemet > j && s.substring(j, guillemet).trim().isEmpty) {
        j = guillemet + 1;
      }
      if (j == s.length) {
        if (isFinal) emit(j);
        break scan;
      }
      if (!_isSpace(s[j])) {
        i = j;
        continue;
      }
      var k = j;
      while (k < s.length && _isSpace(s[k]) && s[k] != '\n') {
        k++;
      }
      if (k == s.length) {
        if (isFinal) emit(j);
        break scan;
      }
      final next = s[k];
      if (!isFinal &&
          singleDot &&
          _wordReachesEnd(s, k) &&
          _digitsBefore(s, i)) {
        break scan; // „am 3. Okt…“: wait for the whole word
      }
      final boundary =
          next == '\n' ||
          (!_isLower(next) && !(singleDot && _abbreviationBefore(s, i, k)));
      if (boundary) emit(j);
      i = k;
    }
    if (isFinal) emit(s.length);
    _buffer = s.substring(start).trimLeft();
    return out;
  }

  /// Whether the dot at [dot] belongs to an abbreviation, initial or
  /// ordinal; [next] is the start of the following word.
  bool _abbreviationBefore(String s, int dot, int next) {
    var w = dot;
    while (w > 0 && !_isSpace(s[w - 1])) {
      w--;
    }
    final word = s.substring(w, dot).replaceFirst(RegExp('^[(„"\'«“‚]+'), '');
    if (word.isEmpty) return false;
    final hasLetter = word.contains(RegExp(r'\p{L}', unicode: true));
    if (!hasLetter) {
      if (!RegExp(r'^\d+$').hasMatch(word)) return false;
      final following = RegExp(
        r'^\p{L}+',
        unicode: true,
      ).firstMatch(s.substring(next))?.group(0);
      return following != null && _months.contains(following.toLowerCase());
    }
    if (word.length == 1) return true; // initial, „z. B.“, „M. Dupont“
    if (word.contains('.')) return true; // „e.g.“, „z.B.“, „U.S.“
    return abbreviations.contains(word.toLowerCase());
  }

  static final _letters = RegExp(r'^\p{L}+', unicode: true);

  static bool _wordReachesEnd(String s, int from) =>
      _letters.firstMatch(s.substring(from))?.end == s.length - from;

  static bool _digitsBefore(String s, int dot) =>
      dot > 0 && RegExp(r'\d').hasMatch(s[dot - 1]);

  static bool _isSpace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ' ';

  static bool _isLower(String c) =>
      c != c.toUpperCase() && c == c.toLowerCase();
}
