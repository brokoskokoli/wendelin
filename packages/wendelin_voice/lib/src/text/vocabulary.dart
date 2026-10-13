import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../io/speech_to_text.dart';

// Vokabular-Korrektur nach der Erkennung (WP33, B6): Whisper (sherpa-onnx
// 1.13.8) kennt weder Initialprompt noch Hotwords. Eigennamen wie
// Notiztitel werden deshalb nach der Erkennung lokal korrigiert. Das
// Vokabular liegt nur im Speicher und wird nie geloggt.

/// Words that are never replaced and never start or end a corrected span
/// (function words and frequent command words in de/fr/en).
final Set<String> vocabularyStopwords = Set.unmodifiable({
  for (final words in [_stopDe, _stopFr, _stopEn]) ...words.split(' '),
});

const _stopDe =
    'der die das den dem des ein eine einen einem einer eines und oder '
    'aber in im an am auf aus bei mit nach von vom vor zu zum zur fur '
    'uber unter ich du er sie es wir ihr mir mich dir dich mein meine '
    'meiner meinem meinen dein deine sein seine was wie wo wann wer ist '
    'sind war hat habe haben steht stehen nicht kein keine ja nein '
    'bitte danke noch schon auch dass heute morgen gestern notiz '
    'notizen liste listen termin kalender lies lese schreib schreibe '
    'trag erganze hinzu neue neues neuen letzte letzten';

const _stopFr =
    'le la les un une des du de et ou dans sur pour par avec mon ma mes '
    'ton ta tes je tu il elle nous vous est oui non note notes liste '
    'moi qui que quoi';

const _stopEn =
    'the a an and or of to in on at for with my your me is are was what '
    'which yes no please note notes list lists read add today tomorrow';

/// One name of the [Vocabulary].
final class VocabularyTerm {
  VocabularyTerm._(this.text, this.flat, this.words, {required this.name});

  /// The name as it should appear in the transcript („Wendelin-Test“).
  final String text;

  /// [foldFlat] of [text].
  final String flat;

  /// Number of words of [text] (hyphen and underscore separate words).
  final int words;

  /// A proper name (the assistant name), corrected even as a single word.
  final bool name;

  final Map<String, String> _keys = {};

  /// Phonetic key for [language] (computed once).
  String key(String? language) =>
      _keys[language ?? 'de'] ??= phoneticKey(text, language: language);
}

/// Local names the recognizer may get wrong: the assistant name, note
/// titles from the index, list names. Lives in memory only; [toString]
/// never shows the names.
final class Vocabulary {
  /// Creates the vocabulary from [titles] (note titles, list names) and
  /// proper [names] (the assistant name).
  ///
  /// Titles of a single word („Garten“, „Rezepte“) are dropped: they are
  /// often ordinary words, and correcting them would change everyday
  /// sentences („die Karten“ → „die Garten“). The title search and its
  /// „Meinst du …?“ question catch them instead. Also dropped: entries
  /// shorter than [VocabularyCorrector.minLength] letters or digits,
  /// stopwords and duplicates (same [foldFlat]; the first spelling wins,
  /// [names] first).
  factory Vocabulary(
    Iterable<String> titles, {
    Iterable<String> names = const [],
  }) {
    final seen = <String>{};
    final terms = <VocabularyTerm>[];
    void add(String raw, {required bool name}) {
      final text = raw.trim();
      final flat = foldFlat(text);
      final words = _wordsOf(text).length;
      if (flat.length < VocabularyCorrector.minLength ||
          vocabularyStopwords.contains(flat) ||
          (!name && words < 2) ||
          !seen.add(flat)) {
        return;
      }
      terms.add(VocabularyTerm._(text, flat, words, name: name));
    }

    for (final n in names) {
      add(n, name: true);
    }
    for (final t in titles) {
      add(t, name: false);
    }
    return Vocabulary._(List.unmodifiable(terms));
  }

  const Vocabulary._(this.terms);

  /// No names.
  static const empty = Vocabulary._([]);

  /// The usable names.
  final List<VocabularyTerm> terms;

  /// Whether there is nothing to correct with.
  bool get isEmpty => terms.isEmpty;

  @override
  String toString() => 'Vocabulary(${terms.length} Namen)';
}

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Words of a transcript: letters and digits, joined by apostrophes or
/// hyphens („Wendelin-Test“, „aujourd'hui“ are one token).
final _token = RegExp(r"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*", unicode: true);

List<String> _wordsOf(String s) =>
    _word.allMatches(s).map((m) => m[0]!).toList();

final class _Token {
  _Token(this.start, this.end, String text)
    : flat = foldFlat(text),
      words = _wordsOf(text).length;

  final int start;
  final int end;
  final String flat;
  final int words;

  bool get stop => vocabularyStopwords.contains(flat);
}

final class _Candidate {
  _Candidate(
    this.first,
    this.last,
    this.term,
    this.distance,
    this.replace, {
    this.keep = '',
  });

  final int first;
  final int last;
  final VocabularyTerm term;
  final int distance;

  /// `false` for a span that already is the name (it only blocks others).
  final bool replace;

  /// Start of the first token that stays (a glued word like „Notiz“).
  final String keep;

  _Candidate blocking() =>
      _Candidate(first, last, term, distance, false, keep: keep);

  int get span => last - first + 1;

  bool overlaps(_Candidate o) => first <= o.last && o.first <= last;
}

/// Result of [VocabularyCorrector.correctDetailed]: the corrected text and
/// the names put into it.
typedef VocabularyCorrection = ({String text, List<VocabularyTerm> terms});

/// Replaces word runs in a transcript that sound like a [Vocabulary] name
/// („Wandel Intest“ → „Wendelin-Test“). Conservative: a run is replaced
/// only if
/// - its letters ([foldFlat]) have the same phonetic key as the name
///   ([phoneticKey] in the transcript language) and differ by at most
///   [maxDistance] edits, or equal the name but are split differently
///   („Wendel in“ → „Wendelin“);
/// - it has at least [minLength] letters, is not made of stopwords only
///   and (unless it equals the name) neither starts nor ends with one;
/// - it does not differ from the name only in an inflection ending
///   ([onlyEndingDiffers]: „ein Rezept“ stays, „Wendelins“ stays);
/// - for a title, it starts with the same letter („Karten Ideen“ stays);
/// - it does not split a single word into a name of several words
///   („Wochenplan“ stays), unless the name is glued to the assistant name
///   or a [gluedWords] entry;
/// - no other name fits the same or an overlapping run equally well.
///
/// A [gluedWords] entry in front of a name is split off again
/// („Notizwende-Lintest“ → „Notiz Wendelin-Test“).
final class VocabularyCorrector {
  /// Creates the corrector.
  const VocabularyCorrector();

  /// Shortest name or run (letters and digits) that is corrected.
  static const minLength = 6;

  /// Longest run (in words) compared with a name.
  static const maxWords = 6;

  /// Words Whisper glues to a following name („Notizwendelintest“); the
  /// corrector separates them again.
  static const gluedWords = ['notiz', 'note', 'liste', 'list'];

  /// Word endings (inflection) whose difference alone is never corrected.
  static const endings = {'', 'e', 'n', 's', 'en', 'er', 'es', 'em'};

  /// Whether [a] and [b] differ only in their endings: after the common
  /// beginning both rests are inflection [endings] („rezept“/„rezepte“,
  /// „iden“/„ideen“). Such a difference is grammar, not a misheard name.
  static bool onlyEndingDiffers(String a, String b) {
    var i = 0;
    while (i < a.length && i < b.length && a[i] == b[i]) {
      i++;
    }
    return endings.contains(a.substring(i)) && endings.contains(b.substring(i));
  }

  /// Allowed edit distance for a name with [length] letters: 1 up to 9
  /// letters, 2 above.
  static int maxDistance(int length) => length <= 9 ? 1 : 2;

  /// [text] with the names of [vocabulary] corrected; [language] chooses
  /// the phonetic key (`null` = German).
  String correct(String text, Vocabulary vocabulary, {String? language}) =>
      correctDetailed(text, vocabulary, language: language).text;

  /// Like [correct], plus the names that were put into the text.
  VocabularyCorrection correctDetailed(
    String text,
    Vocabulary vocabulary, {
    String? language,
  }) {
    if (vocabulary.isEmpty || text.isEmpty) {
      return (text: text, terms: const []);
    }
    final tokens = [
      for (final m in _token.allMatches(text)) _Token(m.start, m.end, m[0]!),
    ];
    final candidates = <_Candidate>[];
    for (var i = 0; i < tokens.length; i++) {
      final head = tokens[i];
      _scan(
        tokens,
        i,
        head.flat,
        head.stop,
        '',
        vocabulary,
        language,
        candidates,
      );
      // Whisper sometimes glues the name to the word before it
      // („Notizwendelintest“): try the token without that word too.
      for (final glued in gluedWords) {
        final surface = text.substring(head.start, head.end);
        if (head.flat.length > glued.length + 3 &&
            head.flat.startsWith(glued) &&
            surface.toLowerCase().startsWith(glued)) {
          final rest = head.flat.substring(glued.length);
          _scan(
            tokens,
            i,
            rest,
            vocabularyStopwords.contains(rest),
            '${surface.substring(0, glued.length)} ',
            vocabulary,
            language,
            candidates,
          );
        }
      }
    }
    final chosen = _choose(candidates);
    if (chosen.isEmpty) return (text: text, terms: const []);
    final b = StringBuffer();
    var at = 0;
    for (final c in chosen..sort((a, b) => a.first.compareTo(b.first))) {
      b
        ..write(text.substring(at, tokens[c.first].start))
        ..write(c.keep)
        ..write(c.term.text);
      at = tokens[c.last].end;
    }
    b.write(text.substring(at));
    return (
      text: b.toString(),
      terms: List.unmodifiable([for (final c in chosen) c.term]),
    );
  }

  /// Compares the runs starting at token [first] (whose letters are
  /// [headFlat]; [keep] is the glued word in front) with every name.
  void _scan(
    List<_Token> tokens,
    int first,
    String headFlat,
    bool headStop,
    String keep,
    Vocabulary vocabulary,
    String? language,
    List<_Candidate> out,
  ) {
    final flat = StringBuffer();
    var words = 0;
    var allStop = true;
    final glued =
        keep.isNotEmpty ||
        vocabulary.terms.any(
          (t) =>
              t.name &&
              headFlat.length > t.flat.length &&
              headFlat.startsWith(t.flat),
        );
    for (var j = first; j < tokens.length && j - first < maxWords; j++) {
      final t = tokens[j];
      flat.write(j == first ? headFlat : t.flat);
      words += t.words;
      allStop &= j == first ? headStop : t.stop;
      if (allStop) continue;
      final run = flat.toString();
      final edgeStop = headStop || (j > first && t.stop);
      for (final term in vocabulary.terms) {
        final c = _match(
          first,
          j,
          run,
          words,
          edgeStop,
          term,
          language,
          keep,
          glued: glued,
        );
        if (c != null) out.add(c);
      }
    }
  }

  _Candidate? _match(
    int first,
    int last,
    String run,
    int words,
    bool edgeStop,
    VocabularyTerm term,
    String? language,
    String keep, {
    required bool glued,
  }) {
    final limit = maxDistance(term.flat.length);
    if ((run.length - term.flat.length).abs() > limit) return null;
    // Fewer words than the name: a single word would be split („Wochenplan“
    // → „Wochen Plan“). Only glued names are split („Notizwendelintest“,
    // „Wendelintest“ = assistant name + rest).
    if (words < term.words && !glued) return null;
    if (run == term.flat) {
      // Same letters: only a different split is corrected.
      final split = keep.isNotEmpty || words != term.words;
      return _Candidate(first, last, term, 0, split, keep: keep);
    }
    if (edgeStop || run.length < minLength) return null;
    if (onlyEndingDiffers(run, term.flat)) return null;
    // Titles keep their first letter: „Karten Ideen“ is no „Garten Ideen“
    // (g/k, b/p, d/t share a phonetic code). The assistant name may differ
    // („Vendelin“).
    if (!term.name && run[0] != term.flat[0]) return null;
    if (term.key(language) != phoneticKey(run, language: language)) {
      return null;
    }
    final d = editDistance(run, term.flat);
    return d <= limit
        ? _Candidate(first, last, term, d, true, keep: keep)
        : null;
  }

  /// Non-overlapping candidates, best first (smaller distance, then longer
  /// run); a run that two names fit equally well blocks without replacing.
  List<_Candidate> _choose(List<_Candidate> all) {
    all.sort((a, b) {
      final d = a.distance.compareTo(b.distance);
      return d != 0 ? d : b.span.compareTo(a.span);
    });
    final taken = <_Candidate>[];
    for (final c in all) {
      if (taken.any(c.overlaps)) continue;
      final rival = all.any(
        (o) =>
            !identical(o, c) &&
            o.distance == c.distance &&
            o.span == c.span &&
            o.overlaps(c) &&
            !identical(o.term, c.term),
      );
      taken.add(rival ? c.blocking() : c);
    }
    return [
      for (final c in taken)
        if (c.replace) c,
    ];
  }
}

/// [SpeechToText] that corrects names after recognition (see
/// [VocabularyCorrector]). [vocabulary] is asked on every transcription,
/// so it can follow the note index; nothing is logged.
final class CorrectingSpeechToText implements SpeechToText {
  /// Wraps [inner].
  CorrectingSpeechToText(
    this.inner, {
    required this.vocabulary,
    this.corrector = const VocabularyCorrector(),
    this.onCorrected,
  });

  /// The recognizer.
  final SpeechToText inner;

  /// Current names.
  final FutureOr<Vocabulary> Function() vocabulary;

  /// Correction rules.
  final VocabularyCorrector corrector;

  /// Told after every transcription which names the correction put in
  /// (empty if none), e.g. so writes to such a note are asked back (B8).
  final void Function(List<VocabularyTerm> terms)? onCorrected;

  @override
  SpeechToTextEngineInfo get info => inner.info;

  @override
  Future<Transcript> transcribe(Int16List pcm, {String? language}) async {
    final t = await inner.transcribe(pcm, language: language);
    if (t.text.isEmpty) {
      onCorrected?.call(const []);
      return t;
    }
    final c = corrector.correctDetailed(
      t.text,
      await vocabulary(),
      language: t.language ?? language,
    );
    onCorrected?.call(c.terms);
    if (c.terms.isEmpty) return t;
    return Transcript(
      text: c.text,
      language: t.language,
      confidence: t.confidence,
    );
  }
}
