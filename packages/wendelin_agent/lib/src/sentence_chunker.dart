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
///
/// WP120: with [firstSplitWords] > 0 a long **first** sentence (of the
/// answer or after [flush]/[reset]) is cut at the first comma or colon that
/// follows at least that many words, so the voice can start before the
/// sentence is complete. The pieces are marked in [lastPartial].
final class SentenceChunker {
  /// Creates a chunker; [abbreviations] (lower case, without the dot)
  /// replaces [defaultAbbreviations].
  SentenceChunker({Set<String>? abbreviations, this.firstSplitWords = 0})
    : abbreviations = abbreviations ?? defaultAbbreviations;

  /// Minimum number of words before the first comma/colon of the first
  /// sentence at which it is cut early; 0 = never.
  final int firstSplitWords;

  /// For the list returned by the last [add]/[flush]: whether the sentence
  /// at that index is only the first part of a sentence that continues (cut
  /// at a comma or colon, [firstSplitWords]).
  List<bool> lastPartial = const [];

  bool _first = true;

  /// Words that are followed by a dot without ending the sentence.
  static const defaultAbbreviations = {
    // de
    'dr', 'nr', 'bzw', 'ca', 'evtl', 'ggf', 'inkl', 'zzgl', 'prof', 'str',
    'tel', 'vgl', 'sog', 'abs', 'hr', 'fr', 'min', 'max', 'mio', 'mrd',
    // fr
    'mme', 'mlle', 'env', 'cf',
    // en
    'mr', 'mrs', 'ms', 'st', 'vs', 'approx', 'jr', 'sr',
  };

  /// Abbreviations only before a number („No. 5“, „ex. 3“); elsewhere they
  /// are ordinary words („Say no. Then …“).
  static const numberAbbreviations = {'no', 'ex'};

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
  List<String> flush() {
    final out = _extract(isFinal: true);
    _first = true;
    return out;
  }

  /// Clears the buffer without returning anything (e.g. after an
  /// escalation replaced the answer).
  void reset() {
    _buffer = '';
    _first = true;
  }

  List<String> _extract({required bool isFinal}) {
    final s = _buffer;
    final out = <String>[];
    final partial = <bool>[];
    var start = 0;

    void emit(int end, {bool part = false}) {
      final sentence = s.substring(start, end).trim();
      if (sentence.isNotEmpty) {
        out.add(sentence);
        partial.add(part);
        _first = false;
      }
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
    if (!isFinal && _first && firstSplitWords > 0) {
      final cut = _earlySplit(s, start);
      if (cut != null) emit(cut, part: true);
    }
    lastPartial = partial;
    _buffer = s.substring(start).trimLeft();
    return out;
  }

  /// End (exclusive) of the first part of the unfinished sentence starting at
  /// [from]: after the first comma or colon that is followed by a space and
  /// preceded by at least [firstSplitWords] words (so „10,5“ and „10:30“ are
  /// never cut); `null` if there is none yet.
  int? _earlySplit(String s, int from) {
    for (var i = from; i < s.length - 1; i++) {
      final c = s[i];
      if ((c != ',' && c != ':') || !_isSpace(s[i + 1])) continue;
      final words = s
          .substring(from, i)
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      if (words >= firstSplitWords) return i + 1;
    }
    return null;
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
    // Single letters are treated as initials or abbreviations („z. B.“,
    // „M. Dupont“, „J. R. R. Tolkien“). „Plan B. Dann …“ therefore stays one
    // chunk: a missed break only delays TTS a little, a wrong break in the
    // middle of a name is audible.
    if (word.length == 1) return true;
    if (numberAbbreviations.contains(word.toLowerCase())) {
      return RegExp(r'\d').hasMatch(s[next]);
    }
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
