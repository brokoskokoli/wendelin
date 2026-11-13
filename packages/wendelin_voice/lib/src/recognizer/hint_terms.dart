import 'package:meta/meta.dart';

/// What a hint term names. Only names, never content.
enum HintTermKind {
  /// Contact name (WP85 delivers them through the port later).
  contact,

  /// Agent name.
  agent,

  /// List name (shopping list, todo list, …).
  list,

  /// Home Assistant area (room).
  room,

  /// Home Assistant entity name.
  entity,

  /// Generic word for a device type (e.g. „Lampe“ for a light), WP191.
  synonym,
}

/// Which kinds win when [HintTermLimits.maxTerms] cuts the list: first
/// entry first, so contacts (the most numerous) are dropped first. Explicit,
/// not derived from the declaration order of [HintTermKind] (WP191).
const hintTermPriority = <HintTermKind>[
  HintTermKind.agent,
  HintTermKind.list,
  HintTermKind.room,
  HintTermKind.entity,
  HintTermKind.synonym,
  HintTermKind.contact,
];

/// One name for the recognizer.
@immutable
final class HintTerm {
  /// Creates a term.
  const HintTerm(this.text, this.kind);

  /// The name as written.
  final String text;

  /// What it names.
  final HintTermKind kind;

  @override
  String toString() => 'HintTerm(${kind.name})';
}

/// Source of names for the recognizer hint (WP103). Implementations return
/// **names only** (room, entity, list, agent, contact names), never the
/// content of notes, lists, messages or chats. [collectHintTerms] enforces
/// the limits as a backstop.
abstract interface class HintTermSource {
  /// The current names; may be empty.
  Future<List<HintTerm>> terms();
}

/// Limits for the hint terms (hotwords cost decoding time and, in
/// `modified_beam_search`, disturb other sentences when there are many).
@immutable
final class HintTermLimits {
  /// Creates limits.
  const HintTermLimits({
    this.maxTerms = 300,
    this.maxLength = 40,
    this.maxWords = 4,
  });

  /// Maximum number of terms (kinds earlier in [hintTermPriority] win).
  ///
  /// 300 (WP191): at hotword bonus 1.0 the measurement with 64 to 300 invented
  /// names showed no inserted names and a bearable decoding time
  /// (`docs/notes/hotword-bias-2026-10-25.md`, "Nachtrag WP191").
  final int maxTerms;

  /// Maximum characters of one term.
  final int maxLength;

  /// Maximum words of one term; longer text is content, not a name.
  final int maxWords;
}

final _space = RegExp(r'\s+');
// Sentence punctuation and digits-only strings mark content, not a name.
final _notAName = RegExp(r'[.!?;:,…\t/\\()\[\]{}<>@#=_*"“”„]');
final _lineBreak = RegExp(r'[\n\r]');
final _letter = RegExp(r'\p{L}', unicode: true);

/// The cleaned terms of [terms]: whitespace collapsed, names that are too
/// long (characters or words) or look like sentences/markup dropped,
/// duplicates (case-insensitive) removed, ordered by [hintTermPriority] (agent
/// first, contact last) and cut to [HintTermLimits.maxTerms].
List<String> sanitizeHintTerms(
  Iterable<HintTerm> terms, {
  HintTermLimits limits = const HintTermLimits(),
}) => [for (final t in sanitizeHintTermsKinded(terms, limits: limits)) t.text];

/// Like [sanitizeHintTerms], but keeps the kind of each surviving term.
List<HintTerm> sanitizeHintTermsKinded(
  Iterable<HintTerm> terms, {
  HintTermLimits limits = const HintTermLimits(),
}) {
  final ordered = [
    for (final kind in hintTermPriority)
      for (final term in terms)
        if (term.kind == kind) term,
  ];
  final seen = <String>{};
  final out = <HintTerm>[];
  for (final term in ordered) {
    final raw = term.text;
    final text = raw.trim().replaceAll(_space, ' ');
    if (text.isEmpty ||
        raw.contains(_lineBreak) ||
        text.length > limits.maxLength ||
        text.split(' ').length > limits.maxWords ||
        _notAName.hasMatch(text) ||
        !_letter.hasMatch(text) ||
        !seen.add(text.toLowerCase())) {
      continue;
    }
    out.add(HintTerm(text, term.kind));
    if (out.length == limits.maxTerms) break;
  }
  return List.unmodifiable(out);
}

/// How many cleaned terms of each kind there are (no names).
Map<HintTermKind, int> countHintTerms(Iterable<HintTerm> terms) => {
  for (final kind in hintTermPriority)
    kind: terms.where((t) => t.kind == kind).length,
};

/// Asks all [sources] (a failing source is skipped) and cleans the result
/// with [sanitizeHintTerms]. [onCounts] gets the number of cleaned terms per
/// kind (for a log without names).
Future<List<String>> collectHintTerms(
  Iterable<HintTermSource> sources, {
  HintTermLimits limits = const HintTermLimits(),
  void Function(Map<HintTermKind, int> counts)? onCounts,
}) async {
  final all = <HintTerm>[];
  for (final source in sources) {
    try {
      all.addAll(await source.terms());
    } on Object {
      // A source that is not ready must not take the recognizer down.
    }
  }
  final cleaned = sanitizeHintTermsKinded(all, limits: limits);
  onCounts?.call(countHintTerms(cleaned));
  return [for (final t in cleaned) t.text];
}
