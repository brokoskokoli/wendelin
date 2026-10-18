import 'routing_text.dart';

/// Decides whether a request needs a tool category (`needsTool`), without
/// a model call (ADR 0009 §2).
///
/// Categories are `<integration>` (any use) or `<integration>.read` /
/// `<integration>.edit`, e.g. `obsidian.edit`.
abstract interface class ToolCategoryMatcher {
  /// Whether [text] (the request, not normalized) needs [category].
  /// Unknown categories never match.
  bool matches(RoutingText text, String category);
}

/// Standard [ToolCategoryMatcher] with keyword lists (de/fr/en).
///
/// A request matches `<integration>` if it contains one of the
/// integration's topic words, and `<integration>.read|edit` if it also
/// contains a read or edit verb. Words are stems: „notiz“ matches
/// „Notizen“, „umschreib“ matches „umschreiben“.
final class KeywordToolCategoryMatcher implements ToolCategoryMatcher {
  /// Creates the matcher; [topics] and [verbs] replace the built-in lists
  /// (see [defaultTopics], [defaultVerbs]).
  KeywordToolCategoryMatcher({
    Map<String, List<String>>? topics,
    Map<String, List<String>>? verbs,
  }) : _topics = _prepare(topics ?? defaultTopics),
       _verbs = _prepare(verbs ?? defaultVerbs);

  final Map<String, List<List<String>>> _topics;
  final Map<String, List<List<String>>> _verbs;

  /// Topic stems per integration.
  static const defaultTopics = <String, List<String>>{
    'obsidian': [
      'obsidian', 'notiz', 'vault', 'tagebuch', 'journal', //
      'note', 'notes', 'carnet',
    ],
    'calendar': [
      'kalender', 'termin', 'besprechung', 'meeting', //
      'calendar', 'appointment', 'agenda', 'calendrier', 'rendez vous',
      'reunion',
    ],
    'memory': [
      'merk dir', 'merke dir', 'erinner dich', 'gedachtnis', //
      'remember', 'memory', 'souviens toi', 'retiens', 'memoire',
    ],
    'web': [
      'internet', 'web', 'google', 'such im netz', 'recherchier', //
      'search the web', 'look up', 'cherche sur', 'recherche',
    ],
    'alarm': [
      'wecker', 'weck mich', 'timer', //
      'alarm', 'wake me', 'reveil', 'minuteur',
    ],
    'lists': [
      'einkaufsliste', 'liste', 'todo', 'aufgabe', //
      'shopping list', 'list', 'to do', 'task', 'courses',
    ],
    'tasks': [
      'aufgabe', 'faellig', 'uberfaellig', 'todo', 'erinner', //
      'task', 'due', 'overdue', 'tache', 'echeance',
    ],
  };

  /// Verb stems per access kind.
  static const defaultVerbs = <String, List<String>>{
    'read': [
      'lies', 'lese', 'zeig', 'was steht', 'such', 'finde', 'offne', //
      'read', 'show', 'what does', 'find', 'open',
      'lis', 'montre', 'affiche', 'trouve', 'ouvre',
    ],
    'edit': [
      'umschreib', 'schreib', 'bearbeit', 'erganz', 'ander', //
      'trag',
      'eintrag',
      'fug',
      'loesch',
      'losch',
      'korrigier',
      'formulier',
      'leg',
      'rewrite', 'edit', 'add', 'append', 'update', 'change', 'delete',
      'write', 'fix',
      'reecri', 'modifi', 'ajout', 'supprim', 'corrig', 'ecri',
    ],
  };

  static Map<String, List<List<String>>> _prepare(
    Map<String, List<String>> lists,
  ) => {
    for (final MapEntry(:key, :value) in lists.entries)
      key: [
        for (final w in value)
          if (RoutingText.normalize(w) case final n when n.isNotEmpty)
            n.split(' '),
      ],
  };

  @override
  bool matches(RoutingText text, String category) {
    final dot = category.indexOf('.');
    final integration = dot < 0 ? category : category.substring(0, dot);
    final topics = _topics[integration];
    if (topics == null) return false;
    final words = text.normalized.isEmpty
        ? const <String>[]
        : text.normalized.split(' ');
    if (!topics.any((t) => _containsStems(words, t))) return false;
    if (dot < 0) return true;
    final verbs = _verbs[category.substring(dot + 1)];
    if (verbs == null) return false;
    return verbs.any((v) => _containsStems(words, v));
  }

  /// Whether [words] contains consecutive words starting with [stems].
  static bool _containsStems(List<String> words, List<String> stems) {
    for (var i = 0; i + stems.length <= words.length; i++) {
      var ok = true;
      for (var j = 0; j < stems.length && ok; j++) {
        ok = words[i + j].startsWith(stems[j]);
      }
      if (ok) return true;
    }
    return false;
  }
}
