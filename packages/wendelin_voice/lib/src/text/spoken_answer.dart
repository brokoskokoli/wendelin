import 'package:meta/meta.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

import 'speech_normalizer.dart';
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
    this.firstSplitWords = 6,
  });

  /// Maximum number of spoken sentences (a summarized list counts as one).
  final int maxSentences;

  /// Maximum number of spoken characters (without the rest hint).
  final int maxChars;

  /// List items read out before „und N weitere“.
  final int maxListItems;

  /// The first sentence of an answer (and of each segment after a tool
  /// call) is cut at the first comma or colon after at least this many
  /// words, so the voice starts sooner (WP120); 0 = never.
  ///
  /// Six words are about 2 s of speech: long enough that the cut falls at a
  /// natural pause and the next piece is synthesised before this one ends,
  /// short enough that a typical German opening clause („Ich habe die
  /// Lampe im Wohnzimmer eingeschaltet, …“) is spoken first.
  final int firstSplitWords;

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
       _chunker =
           chunker ?? SentenceChunker(firstSplitWords: config.firstSplitWords);

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
  bool _heading = false; // the current prose line is a heading

  /// Sentences returned in the current segment; `counted` = counts towards
  /// [SpeechShortening.maxSentences].
  final _segment = <({String text, bool counted})>[];

  /// Sentences of a discarded segment that were already spoken; if the
  /// agent sends them again after the reset (pauseTurn retry), they are
  /// skipped instead of being spoken twice.
  final _replay = <String>[];

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
    // Short bridging text before a tool call („Ich schaue nach.“) does not
    // use up the sentence limit of the actual answer.
    for (final e in _segment) {
      if (e.counted) _sentences--;
    }
    _segment.clear();
    _replay.clear();
    _truncatedInSegment = false;
    _omittedInSegment = false;
    return out;
  }

  /// Discards the text of the current segment (`AgentTextReset`).
  ///
  /// [unspoken] are sentences returned earlier that were not spoken and are
  /// dropped by the caller; they no longer count towards the limits. The
  /// other sentences of the segment were spoken (or are playing): if the
  /// agent repeats them right after the reset (it re-sends the kept text of
  /// a paused answer), they are skipped and not counted again.
  void reset({Iterable<String> unspoken = const []}) {
    _line = '';
    _mode = _LineMode.undecided;
    _fed = 0;
    _inCode = false;
    _heading = false;
    _list.clear();
    _chunker.reset();
    final dropped = List.of(unspoken);
    final spoken = <String>[];
    for (final e in _segment) {
      if (dropped.remove(e.text)) {
        if (e.counted) _sentences--;
        _chars -= e.text.length;
      } else {
        spoken.add(e.text);
      }
    }
    _segment.clear();
    _replay
      ..clear()
      ..addAll(spoken);
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
    final rest = _chunker.flush();
    for (var i = 0; i < rest.length; i++) {
      _accept(rest[i], out, part: _chunker.lastPartial[i]);
    }
    _inCode = false;
  }

  void _partialLine(List<String> out) {
    if (_inCode) return;
    if (_mode == _LineMode.undecided) {
      _mode = _classifyPartial(_line);
      if (_mode != _LineMode.prose) return;
      _endList(out);
      _fed = _proseStart(_line);
      _heading = _isHeading(_line);
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
      _heading = false;
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
    _heading = _isHeading(line);
    _feed('${line.substring(_proseStart(line))}\n', out);
    _heading = false;
  }

  void _feed(String text, List<String> out) {
    if (text.isEmpty) return;
    final sentences = _chunker.add(stripUrls(text, placeholder: urlMark));
    for (var i = 0; i < sentences.length; i++) {
      _accept(sentences[i], out, part: _chunker.lastPartial[i]);
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

  // [part]: the first piece of a sentence cut early (it does not count as a
  // sentence of its own, the rest of the sentence does).
  void _accept(String raw, List<String> out, {bool part = false}) {
    var s = cleanForSpeech(raw);
    if (s.isNotEmpty) s = normalizeForSpeech(s, texts.language);
    if (s.isEmpty) {
      // A sentence that was only a link: on the screen only.
      if (raw.contains(urlMark)) _markOmitted();
      return;
    }
    if (_replay.isNotEmpty) {
      if (_replay.first == s) {
        _replay.removeAt(0);
        _segment.add((text: s, counted: false));
        return;
      }
      _replay.clear();
    }
    if (_truncated) return;
    final counted = !_heading && !part;
    final fits =
        (!counted || _sentences < config.maxSentences) &&
        _chars + s.length <= config.maxChars;
    if (!fits) {
      _truncated = true;
      _truncatedInSegment = true;
      if (_chars > 0) return;
      s = _cutAtWord(s, config.maxChars);
    }
    if (counted) _sentences++;
    _chars += s.length;
    _segment.add((text: s, counted: counted));
    out.add(s);
  }

  static bool _isHeading(String line) => line.trimLeft().startsWith('#');

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
final _emoji = RegExp(
  r'[\p{Extended_Pictographic}\u{1F1E6}-\u{1F1FF}\u{1F3FB}-\u{1F3FF}\u200D\uFE0F\u20E3]',
  unicode: true,
);
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
      .replaceAll(urlMark, '')
      .replaceAll(_emoji, '')
      .replaceAll(_emptyBrackets, '')
      .replaceAll(_strong, '')
      .replaceAll(_emphasis, '')
      .replaceAll(_spaces, ' ')
      .replaceAllMapped(_spaceBeforePunct, (m) => m[1]!)
      .trim();
  return _hasWord.hasMatch(s) ? s : '';
}

/// Marks where [SpokenAnswer] removed a URL before sentence chunking
/// (private-use character, removed by [cleanForSpeech]).
const urlMark = '\uE000';

/// Removes bare URLs from [text] (replaced by [placeholder]), keeping
/// sentence punctuation that directly follows them.
String stripUrls(String text, {String placeholder = ''}) =>
    text.replaceAllMapped(_url, (m) {
      final trail = _urlTrail.firstMatch(m[0]!)?.group(0);
      return '$placeholder${trail ?? ''}';
    });
