import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'routing_context.dart';
import 'routing_text.dart';

const _list = ListEquality<Object?>();
const _set = SetEquality<Object?>();

/// A routing condition (concept: „Routing und Eskalation“). Text conditions
/// look at the normalized transcript ([RoutingText]).
///
/// Every type has a JSON name ([type]) and an entry in the
/// `ConditionRegistry`, so new types only need a subclass here and a
/// registry entry.
@immutable
sealed class Condition {
  const Condition();

  /// JSON name of the type, e.g. `keyword`.
  String get type;

  /// Direct sub-conditions (for `and`/`or`/`not`).
  List<Condition> get children => const [];

  /// Why the condition cannot be evaluated (e.g. broken regex), or `null`.
  /// A rule with such a condition is invalid and skipped.
  String? get problem => null;

  /// The match if the condition holds for [ctx], else `null`.
  ConditionMatch? evaluate(RoutingContext ctx);

  /// This condition and all conditions below it, depth first.
  Iterable<Condition> get all sync* {
    yield this;
    for (final c in children) {
      yield* c.all;
    }
  }

  /// Text triggers that hold positively (not below a `not`): words of
  /// `prefix` and `keyword` conditions. Used as aliases for „nochmal mit …“.
  Iterable<String> get triggerWords sync* {
    switch (this) {
      case PrefixCondition(:final words) || KeywordCondition(:final words):
        yield* words;
      case AndCondition(:final conditions) || OrCondition(:final conditions):
        for (final c in conditions) {
          yield* c.triggerWords;
        }
      case _:
        break;
    }
  }

  /// Whether a `privacy` condition is reachable without a `not`.
  bool get marksPrivate => switch (this) {
    PrivacyCondition() => true,
    AndCondition(:final conditions) ||
    OrCondition(:final conditions) => conditions.any((c) => c.marksPrivate),
    _ => false,
  };
}

/// All [conditions] hold (`and`).
final class AndCondition extends Condition {
  /// Creates the condition; [conditions] are copied.
  AndCondition(List<Condition> conditions)
    : conditions = List.unmodifiable(conditions);

  /// The parts.
  final List<Condition> conditions;

  @override
  String get type => 'and';

  @override
  List<Condition> get children => conditions;

  @override
  ConditionMatch? evaluate(RoutingContext ctx) {
    var match = ConditionMatch.plain;
    for (final c in conditions) {
      final m = c.evaluate(ctx);
      if (m == null) return null;
      match = match.and(m);
    }
    return match;
  }

  @override
  bool operator ==(Object other) =>
      other is AndCondition && _list.equals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(type, _list.hash(conditions));
}

/// At least one of [conditions] holds (`or`); the first matching one
/// supplies the triggers.
final class OrCondition extends Condition {
  /// Creates the condition; [conditions] are copied.
  OrCondition(List<Condition> conditions)
    : conditions = List.unmodifiable(conditions);

  /// The alternatives.
  final List<Condition> conditions;

  @override
  String get type => 'or';

  @override
  List<Condition> get children => conditions;

  @override
  ConditionMatch? evaluate(RoutingContext ctx) {
    for (final c in conditions) {
      if (c.evaluate(ctx) case final m?) return m;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is OrCondition && _list.equals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(type, _list.hash(conditions));
}

/// [condition] does not hold (`not`). Never contributes triggers or
/// privacy.
final class NotCondition extends Condition {
  /// Creates the condition.
  const NotCondition(this.condition);

  /// The negated condition.
  final Condition condition;

  @override
  String get type => 'not';

  @override
  List<Condition> get children => [condition];

  @override
  ConditionMatch? evaluate(RoutingContext ctx) =>
      condition.evaluate(ctx) == null ? ConditionMatch.plain : null;

  @override
  bool operator ==(Object other) =>
      other is NotCondition && other.condition == condition;

  @override
  int get hashCode => Object.hash(type, condition);
}

/// One of [words] (or phrases) occurs as whole words anywhere in the text.
final class KeywordCondition extends Condition {
  /// Creates the condition; [words] are copied.
  KeywordCondition(List<String> words) : words = List.unmodifiable(words);

  /// Words or phrases, matched case- and accent-insensitively.
  final List<String> words;

  @override
  String get type => 'keyword';

  @override
  ConditionMatch? evaluate(RoutingContext ctx) => _findAny(ctx.text, words);

  @override
  bool operator ==(Object other) =>
      other is KeywordCondition && _list.equals(other.words, words);

  @override
  int get hashCode => Object.hash(type, _list.hash(words));
}

ConditionMatch? _findAny(
  RoutingText text,
  List<String> words, {
  bool private = false,
}) {
  for (final w in words) {
    if (text.findPhrase(w) case final span?) {
      return ConditionMatch(triggers: [span], private: private);
    }
  }
  return null;
}

/// The text starts with one of [words] („Claude, …“). Leading punctuation
/// and case do not matter; the word in the middle of a sentence does not
/// count.
final class PrefixCondition extends Condition {
  /// Creates the condition; [words] are copied.
  PrefixCondition(List<String> words) : words = List.unmodifiable(words);

  /// Prefix words or phrases.
  final List<String> words;

  @override
  String get type => 'prefix';

  @override
  ConditionMatch? evaluate(RoutingContext ctx) {
    for (final w in words) {
      if (ctx.text.startsWithPhrase(w) case final span?) {
        return ConditionMatch(triggers: [span]);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PrefixCondition && _list.equals(other.words, words);

  @override
  int get hashCode => Object.hash(type, _list.hash(words));
}

/// [pattern] matches the normalized text (lower case, no accents, single
/// spaces instead of punctuation).
///
/// Runtime protection: patterns longer than [maxPatternLength] are invalid,
/// and only the first [maxInputLength] characters are searched.
final class RegexCondition extends Condition {
  /// Creates the condition. An invalid [pattern] does not throw; the
  /// condition reports a [problem] and never matches.
  RegexCondition(this.pattern) : _regex = _compile(pattern);

  /// Longest allowed pattern.
  static const maxPatternLength = 200;

  /// Longest text searched.
  static const maxInputLength = 2000;

  /// The pattern (Dart `RegExp` syntax, case-insensitive, Unicode).
  final String pattern;

  final Object _regex;

  static Object _compile(String pattern) {
    if (pattern.length > maxPatternLength) {
      return 'Regulärer Ausdruck ist länger als $maxPatternLength Zeichen.';
    }
    try {
      return RegExp(pattern, caseSensitive: false, unicode: true);
    } on FormatException catch (e) {
      return 'Ungültiger regulärer Ausdruck: ${e.message}';
    }
  }

  @override
  String get type => 'regex';

  @override
  String? get problem => switch (_regex) {
    final String message => message,
    _ => null,
  };

  @override
  ConditionMatch? evaluate(RoutingContext ctx) {
    final regex = _regex;
    if (regex is! RegExp) return null;
    final text = ctx.text.normalized;
    final input = text.length > maxInputLength
        ? text.substring(0, maxInputLength)
        : text;
    final m = regex.firstMatch(input);
    if (m == null) return null;
    return ConditionMatch(
      triggers: [if (m.end > m.start) TriggerSpan(m.start, m.end)],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RegexCondition && other.pattern == pattern;

  @override
  int get hashCode => Object.hash(type, pattern);
}

/// The detected language is one of [languages] (primary subtag, so `de`
/// matches `de-AT`).
final class LanguageCondition extends Condition {
  /// Creates the condition; [languages] are copied.
  LanguageCondition(List<String> languages)
    : languages = List.unmodifiable(languages);

  /// BCP 47 primary language subtags, e.g. `de`, `fr`.
  final List<String> languages;

  @override
  String get type => 'language';

  @override
  ConditionMatch? evaluate(RoutingContext ctx) {
    final lang = ctx.input.language;
    if (lang == null) return null;
    final primary = lang.split(RegExp('[-_]')).first.toLowerCase();
    return languages.any((l) => l.toLowerCase() == primary)
        ? ConditionMatch.plain
        : null;
  }

  @override
  bool operator ==(Object other) =>
      other is LanguageCondition && _list.equals(other.languages, languages);

  @override
  int get hashCode => Object.hash(type, _list.hash(languages));
}

/// Speech recognition was unsure: confidence below [below]. Typed input
/// (no confidence) never matches.
final class SttConfidenceCondition extends Condition {
  /// Creates the condition.
  const SttConfidenceCondition(this.below);

  /// Threshold 0.0–1.0 (exclusive).
  final double below;

  @override
  String get type => 'sttConfidence';

  @override
  ConditionMatch? evaluate(RoutingContext ctx) =>
      switch (ctx.input.sttConfidence) {
        final c? when c < below => ConditionMatch.plain,
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      other is SttConfidenceCondition && other.below == below;

  @override
  int get hashCode => Object.hash(type, below);
}

/// The text is longer than [above] characters.
final class InputLengthCondition extends Condition {
  /// Creates the condition.
  const InputLengthCondition(this.above);

  /// Threshold in characters (exclusive).
  final int above;

  @override
  String get type => 'inputLength';

  @override
  ConditionMatch? evaluate(RoutingContext ctx) =>
      ctx.input.text.trim().runes.length > above ? ConditionMatch.plain : null;

  @override
  bool operator ==(Object other) =>
      other is InputLengthCondition && other.above == above;

  @override
  int get hashCode => Object.hash(type, above);
}

/// The request has at least one image.
final class HasImageCondition extends Condition {
  /// Creates the condition.
  const HasImageCondition();

  @override
  String get type => 'hasImage';

  @override
  ConditionMatch? evaluate(RoutingContext ctx) =>
      ctx.input.images.isNotEmpty ? ConditionMatch.plain : null;

  @override
  bool operator ==(Object other) => other is HasImageCondition;

  @override
  int get hashCode => type.hashCode;
}

/// Connectivity is [state]. `online` also matches a metered connection;
/// `metered` only a metered one.
final class NetworkCondition extends Condition {
  /// Creates the condition.
  const NetworkCondition(this.state);

  /// The required state.
  final NetworkState state;

  @override
  String get type => 'network';

  @override
  ConditionMatch? evaluate(RoutingContext ctx) {
    final ok = switch (state) {
      NetworkState.offline => ctx.network == NetworkState.offline,
      NetworkState.online => ctx.network != NetworkState.offline,
      NetworkState.metered => ctx.network == NetworkState.metered,
    };
    return ok ? ConditionMatch.plain : null;
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkCondition && other.state == state;

  @override
  int get hashCode => Object.hash(type, state);
}

/// The request falls into a weekly time window.
///
/// [start] and [end] are minutes after midnight; `start > end` spans
/// midnight (22:00–06:00), `start == end` means the whole day. [days] are
/// the weekdays (`DateTime.monday` … `DateTime.sunday`) on which the window
/// **starts**: Friday 22:00–06:00 includes Saturday 03:00. Empty [days] =
/// every day.
final class TimeWindowCondition extends Condition {
  /// Creates the condition; [days] are copied.
  TimeWindowCondition({
    Set<int> days = const {},
    required this.start,
    required this.end,
  }) : days = Set.unmodifiable(days);

  /// Weekdays on which the window starts.
  final Set<int> days;

  /// Start, minutes after midnight (inclusive).
  final int start;

  /// End, minutes after midnight (exclusive).
  final int end;

  @override
  String get type => 'timeWindow';

  @override
  String? get problem {
    bool bad(int m) => m < 0 || m >= 24 * 60;
    if (bad(start) || bad(end)) return 'Uhrzeit außerhalb von 00:00–23:59.';
    if (days.any((d) => d < 1 || d > 7)) return 'Ungültiger Wochentag.';
    return null;
  }

  @override
  ConditionMatch? evaluate(RoutingContext ctx) {
    final now = ctx.now;
    final minute = now.hour * 60 + now.minute;
    final today = now.weekday;
    final yesterday = today == DateTime.monday ? DateTime.sunday : today - 1;
    bool day(int d) => days.isEmpty || days.contains(d);
    final bool ok;
    if (start == end) {
      ok = day(today);
    } else if (start < end) {
      ok = day(today) && minute >= start && minute < end;
    } else {
      ok = (day(today) && minute >= start) || (day(yesterday) && minute < end);
    }
    return ok ? ConditionMatch.plain : null;
  }

  @override
  bool operator ==(Object other) =>
      other is TimeWindowCondition &&
      _set.equals(other.days, days) &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(type, _set.hash(days), start, end);
}

/// The request needs a tool [category] such as `obsidian.edit`, decided by
/// the [ToolCategoryMatcher] of the context (keywords, no model call).
final class NeedsToolCondition extends Condition {
  /// Creates the condition.
  const NeedsToolCondition(this.category);

  /// `<integration>` or `<integration>.read|edit`.
  final String category;

  @override
  String get type => 'needsTool';

  @override
  ConditionMatch? evaluate(RoutingContext ctx) =>
      ctx.matcher.matches(ctx.text, category) ? ConditionMatch.plain : null;

  @override
  bool operator ==(Object other) =>
      other is NeedsToolCondition && other.category == category;

  @override
  int get hashCode => Object.hash(type, category);
}

/// One of [words] occurs (like `keyword`) and marks the route as private:
/// its target's privacy level becomes the floor for every escalation
/// (K8 d).
final class PrivacyCondition extends Condition {
  /// Creates the condition; [words] are copied.
  PrivacyCondition([List<String> words = defaultWords])
    : words = List.unmodifiable(words);

  /// The default trigger words (de/fr/en).
  static const defaultWords = [
    'privat',
    'private',
    'privates',
    'privaten',
    'vertraulich',
    'prive',
    'privee',
    'confidentiel',
    'confidential',
  ];

  /// Trigger words or phrases.
  final List<String> words;

  @override
  String get type => 'privacy';

  @override
  ConditionMatch? evaluate(RoutingContext ctx) =>
      _findAny(ctx.text, words, private: true);

  @override
  bool operator ==(Object other) =>
      other is PrivacyCondition && _list.equals(other.words, words);

  @override
  int get hashCode => Object.hash(type, _list.hash(words));
}
