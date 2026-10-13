import 'package:meta/meta.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

import 'voice_texts.dart';

/// Limits for the spoken version of an answer (concept: „Antworten werden
/// für Sprache gekürzt; lange Inhalte nur auf dem Bildschirm“).
@immutable
final class SpeechShortening {
  /// Creates limits.
  const SpeechShortening({
    this.maxSentences = 3,
    this.maxChars = 400,
    this.maxListItems = 3,
    this.announceRest = true,
  });

  /// Maximum number of spoken sentences (a summarized list counts as one).
  final int maxSentences;

  /// Maximum number of spoken characters (without the rest hint).
  final int maxChars;

  /// List items read out before „und N weitere“.
  final int maxListItems;

  /// Whether to add „Den Rest siehst du auf dem Bildschirm.“ when something
  /// was cut or left out (code, tables, sentences over the limit).
  final bool announceRest;
}

enum _LineMode { undecided, prose, buffered }

/// Turns a streamed (Markdown) answer into short sentences for TTS.
///
/// - Sentences are cut with the agent's [SentenceChunker], so speaking can
///   start before the answer is complete.
/// - Markdown is removed: emphasis, headings, quotes, inline code markers,
///   links (link text stays), bare URLs, images. Code blocks and tables are
///   left out.
/// - Lists are summarized: „Milch, Brot, Eier und 4 weitere.“ (spoken once
///   the list has ended).
/// - At most [SpeechShortening.maxSentences] sentences /
///   [SpeechShortening.maxChars] characters are spoken; the first sentence
///   is cut at a word boundary if it alone is too long.
///
/// Feed [add] with `AgentTextDelta`s, call [endSegment] at tool calls,
/// [reset] on `AgentTextReset` and [finish] at the end of the answer.
final class SpokenAnswer {
  /// Creates an assembler for one answer in [language].
  SpokenAnswer({
    this.config = const SpeechShortening(),
    String? language,
    SentenceChunker? chunker,
  }) : texts = VoiceTexts.of(language),
       _chunker = chunker ?? SentenceChunker();

  /// Shortens a complete [text] at once (same rules as streaming).
  static List<String> shorten(
    String text, {
    String? language,
    SpeechShortening config = const SpeechShortening(),
  }) {
    final answer = SpokenAnswer(config: config, language: language);
    return [...answer.add(text), ...answer.finish()];
  }

  /// Limits.
  final SpeechShortening config;

  /// Phrases in the answer language.
  final VoiceTexts texts;

  final SentenceChunker _chunker;

  String _line = '';
  _LineMode _mode = _LineMode.undecided;
  int _fed = 0; // chars of _line already given to the chunker
  bool _inCode = false;
  final _list = <String>[];

  int _sentences = 0;
  int _chars = 0;
  bool _truncated = false;
  bool _omitted = false;
  bool _truncatedInSegment = false;
  bool _omittedInSegment = false;
  bool _finished = false;

  /// Whether sentences were dropped because of the limits.
  bool get truncated => _truncated;

  /// Whether code blocks or tables were left out.
  bool get omitted => _omitted;

  /// Adds a text delta; returns the sentences ready to be spoken.
  List<String> add(String delta) {
    final out = <String>[];
    if (_finished) return out;
    final parts = delta.split('\n');
    for (var i = 0; i < parts.length; i++) {
      _line += parts[i];
      if (i < parts.length - 1) {
        _completeLine(out);
      } else {
        _partialLine(out);
      }
    }
    return out;
  }

  /// Ends the text of the current model call (before a tool call): returns
  /// the buffered rest as sentences. The answer continues afterwards.
  List<String> endSegment() {
    final out = <String>[];
    if (_finished) return out;
    _flushAll(out);
    _truncatedInSegment = false;
    _omittedInSegment = false;
    return out;
  }

  /// Discards the text of the current segment (`AgentTextReset`).
  ///
  /// [unspoken] are sentences returned earlier that were not spoken and are
  /// dropped by the caller; they no longer count towards the limits.
  void reset({Iterable<String> unspoken = const []}) {
    _line = '';
    _mode = _LineMode.undecided;
    _fed = 0;
    _inCode = false;
    _list.clear();
    _chunker.reset();
    for (final s in unspoken) {
      _sentences--;
      _chars -= s.length;
    }
    if (_sentences < 0) _sentences = 0;
    if (_chars < 0) _chars = 0;
    if (_truncatedInSegment) _truncated = false;
    if (_omittedInSegment) _omitted = false;
    _truncatedInSegment = false;
    _omittedInSegment = false;
    _finished = false;
  }

  /// Ends the answer: returns the remaining sentences plus, if something
  /// was cut or left out, the rest hint. Later calls return nothing.
  List<String> finish() {
    final out = <String>[];
    if (_finished) return out;
    _flushAll(out);
    _finished = true;
    if (config.announceRest && (_truncated || _omitted)) out.add(texts.rest);
    return out;
  }

  void _flushAll(List<String> out) {
    if (_line.isNotEmpty) _completeLine(out);
    _endList(out);
    _chunker.flush().forEach((s) => _accept(s, out));
    _inCode = false;
  }

  void _partialLine(List<String> out) {
    if (_inCode) return;
    if (_mode == _LineMode.undecided) {
      _mode = _classifyPartial(_line);
      if (_mode != _LineMode.prose) return;
      _endList(out);
      _fed = _proseStart(_line);
    }
    if (_mode != _LineMode.prose) return;
    // Hold back the unfinished last word: it may be the start of a URL,
    // which must be removed before the chunker sees its dots.
    final upTo = _line.lastIndexOf(_space) + 1;
    if (upTo > _fed) {
      _feed(_line.substring(_fed, upTo), out);
      _fed = upTo;
    }
  }

  void _completeLine(List<String> out) {
    final line = _line;
    final mode = _mode;
    final fed = _fed;
    _line = '';
    _mode = _LineMode.undecided;
    _fed = 0;
    final t = line.trimLeft();
    if (_inCode) {
      if (t.startsWith('```')) _inCode = false;
      return;
    }
    if (mode == _LineMode.prose) {
      _feed('${line.substring(fed)}\n', out);
      return;
    }
    if (t.trim().isEmpty) return; // blank lines keep a list open
    final indent = line.length - t.length;
    if (t.startsWith('```')) {
      _endList(out);
      _inCode = true;
      _markOmitted();
      return;
    }
    if (t.startsWith('|')) {
      _endList(out);
      _markOmitted();
      return;
    }
    if (_isRule(t)) return;
    final item = _listItem.firstMatch(t);
    if (item != null && indent < 2) {
      final text = _cleanItem(t.substring(item.end));
      if (text.isNotEmpty) _list.add(text);
      return;
    }
    if (_list.isNotEmpty && indent >= 2) return; // sub item / continuation
    _endList(out);
    _feed('${line.substring(_proseStart(line))}\n', out);
  }

  void _feed(String text, List<String> out) {
    if (text.isEmpty) return;
    for (final s in _chunker.add(stripUrls(text))) {
      _accept(s, out);
    }
  }

  void _endList(List<String> out) {
    if (_list.isEmpty) return;
    final items = List.of(_list);
    _list.clear();
    final shown = items.take(config.maxListItems).toList();
    final rest = items.length - shown.length;
    final String sentence;
    if (rest > 0) {
      sentence = '${shown.join(', ')} ${texts.more(rest)}.';
    } else if (shown.length == 1) {
      sentence = '${shown.single}.';
    } else {
      final head = shown.sublist(0, shown.length - 1).join(', ');
      sentence = '$head ${texts.and} ${shown.last}.';
    }
    _accept(sentence, out);
  }

  void _accept(String raw, List<String> out) {
    if (_truncated) return;
    var s = cleanForSpeech(raw);
    if (s.isEmpty) return;
    final fits =
        _sentences < config.maxSentences &&
        _chars + s.length <= config.maxChars;
    if (!fits) {
      _truncated = true;
      _truncatedInSegment = true;
      if (_sentences > 0) return;
      s = _cutAtWord(s, config.maxChars);
    }
    _sentences++;
    _chars += s.length;
    out.add(s);
  }

  void _markOmitted() {
    _omitted = true;
    _omittedInSegment = true;
  }

  static final _listItem = RegExp(r'^(?:[-*+]|\d{1,3}[.)])\s+');
  static final _checkbox = RegExp(r'^\[[ xX]\]\s*');
  static final _headingOrQuote = RegExp(r'^\s*(?:#{1,6}|>+)\s*');

  static bool _isRule(String t) =>
      RegExp(r'^(?:[-*_]\s*){3,}$').hasMatch(t.trim());

  static int _proseStart(String line) =>
      _headingOrQuote.firstMatch(line)?.end ?? 0;

  static String _cleanItem(String text) =>
      cleanForSpeech(text.replaceFirst(_checkbox, ''))
          .replaceFirst(RegExp(r'[.;:,!?]+$'), '');

  /// Decides from the start of an unfinished line whether it is prose
  /// (stream it), a list item / table / code fence (buffer the whole line)
  /// or still unclear.
  _LineMode _classifyPartial(String line) {
    final t = line.trimLeft();
    if (t.isEmpty) return _LineMode.undecided;
    if (_list.isNotEmpty && line.length - t.length >= 2) {
      return _LineMode.buffered;
    }
    final c = t[0];
    if (c == '|') return _LineMode.buffered;
    if (c == '`') {
      if (t.startsWith('```')) return _LineMode.buffered;
      return RegExp(r'^`{1,2}$').hasMatch(t)
          ? _LineMode.undecided
          : _LineMode.prose;
    }
    if (c == '#' || c == '>') {
      return RegExp(r'^[#>]+\s*$').hasMatch(t)
          ? _LineMode.undecided
          : _LineMode.prose;
    }
    if ('-*+_'.contains(c)) {
      if (RegExp(r'^[-*+_\s]+$').hasMatch(t)) {
        return RegExp(r'^[-*+]\s+\S').hasMatch(t)
            ? _LineMode.buffered
            : _LineMode.undecided;
      }
      return RegExp(r'^[-*+]\s').hasMatch(t)
          ? _LineMode.buffered
          : _LineMode.prose;
    }
    final digits = RegExp(r'^\d{1,3}([.)])?').firstMatch(t);
    if (digits != null) {
      if (digits.end == t.length) return _LineMode.undecided;
      if (digits.group(1) != null && _isSpace(t[digits.end])) {
        return _LineMode.buffered;
      }
    }
    return _LineMode.prose;
  }

  static bool _isSpace(String c) => c.trim().isEmpty;

  static final _space = RegExp(r'\s');

  static String _cutAtWord(String s, int max) {
    if (s.length <= max) return s;
    var cut = s.lastIndexOf(' ', max - 1);
    if (cut <= 0) cut = max - 1;
    return '${s.substring(0, cut).trimRight()}…';
  }
}

final _image = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
final _angleUrl = RegExp(r'<(?:https?://|www\.)[^>]*>');
final _url = RegExp(r'(?:https?://|www\.)[^\s<>]+');
final _urlTrail = RegExp(r'[.,;:!?)»”"]+$');
final _emptyBrackets = RegExp(r'\[\s*\]|\(\s*\)|<\s*>');
final _strong = RegExp(r'\*\*|__|~~|`');
final _emphasis = RegExp(
  r'(?<![\p{L}\p{N}])[*_](?=\S)|(?<=\S)[*_](?![\p{L}\p{N}])',
  unicode: true,
);
final _spaces = RegExp(r'\s+');
final _spaceBeforePunct = RegExp(r'\s+([.,;:!?…])');
final _hasWord = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Removes Markdown and URLs from one sentence; returns `''` if nothing
/// speakable remains.
String cleanForSpeech(String text) {
  var s = text
      .replaceAll(_image, '')
      .replaceAllMapped(_link, (m) => m[1]!)
      .replaceAll(_angleUrl, '');
  s = stripUrls(s)
      .replaceAll(_emptyBrackets, '')
      .replaceAll(_strong, '')
      .replaceAll(_emphasis, '')
      .replaceAll(_spaces, ' ')
      .replaceAllMapped(_spaceBeforePunct, (m) => m[1]!)
      .trim();
  return _hasWord.hasMatch(s) ? s : '';
}

/// Removes bare URLs from [text], keeping sentence punctuation that
/// directly follows them.
String stripUrls(String text) => text.replaceAllMapped(_url, (m) {
  final trail = _urlTrail.firstMatch(m[0]!)?.group(0);
  return trail ?? '';
});
