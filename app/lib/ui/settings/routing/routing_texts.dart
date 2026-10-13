import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../../di/routing.dart';

// Texts of the routing page: conditions in mono („prefix "Claude" |
// "Fable"“), targets („Claude API · Opus“) and the test field result.

/// Weekday names (`DateTime.monday` = 1).
const weekdayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// „08:30“ for minutes after midnight.
String minutesLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// German name of a condition type (JSON name).
String conditionTypeLabel(String type) => switch (type) {
  'keyword' => 'Schlüsselwort',
  'prefix' => 'Präfix',
  'regex' => 'Regulärer Ausdruck',
  'language' => 'Sprache',
  'sttConfidence' => 'Unsichere Erkennung',
  'inputLength' => 'Lange Eingabe',
  'hasImage' => 'Mit Bild',
  'network' => 'Netz',
  'timeWindow' => 'Zeitfenster',
  'needsTool' => 'Braucht Tool',
  'privacy' => 'Privat',
  'and' => 'und',
  'or' => 'oder',
  'not' => 'nicht',
  _ => type,
};

String _words(List<String> words, {int show = 2}) {
  final quoted = [for (final w in words.take(show)) '"$w"'].join(' | ');
  return words.length > show ? '$quoted +${words.length - show}' : quoted;
}

/// [condition] as one mono line, e.g. `prefix "Claude" | "Fable"`,
/// `network = offline`, `(keyword "notiz") und nicht (hasImage)`.
String describeCondition(Condition condition) => switch (condition) {
  KeywordCondition(:final words) => 'keyword ${_words(words)}',
  PrefixCondition(:final words) => 'prefix ${_words(words)}',
  PrivacyCondition(:final words) => 'privacy ${_words(words, show: 1)}',
  RegexCondition(:final pattern) => 'regex /$pattern/',
  LanguageCondition(:final languages) => 'language ${languages.join(' | ')}',
  SttConfidenceCondition(:final below) => 'sttConfidence < $below',
  InputLengthCondition(:final above) => 'inputLength > $above',
  HasImageCondition() => 'hasImage',
  NetworkCondition(:final state) => 'network = ${state.name}',
  TimeWindowCondition(:final days, :final start, :final end) => [
    'timeWindow',
    if (days.isNotEmpty)
      (days.toList()..sort()).map((d) => weekdayLabels[d - 1]).join(','),
    start == end ? 'ganztags' : '${minutesLabel(start)}–${minutesLabel(end)}',
  ].join(' '),
  NeedsToolCondition(:final category) => 'needsTool $category',
  NotCondition(:final condition) => 'nicht ${_group(condition)}',
  AndCondition(:final conditions) => conditions.map(_group).join(' und '),
  OrCondition(:final conditions) => conditions.map(_group).join(' oder '),
};

String _group(Condition c) => switch (c) {
  AndCondition(:final conditions) || OrCondition(:final conditions)
      when conditions.length > 1 =>
    '(${describeCondition(c)})',
  _ => describeCondition(c),
};

/// Target of a rule as shown in the list (short, as in the design): the
/// profile name, or the model if it is not the profile's default
/// („Opus“). The test field and the editor show both.
String targetLabel(RoutingState state, RouteTarget target) {
  final profile = state.profile(target.profileId);
  if (profile == null) return '${target.profileId} (gelöscht)';
  return profile.defaultModel == target.modelId ? profile.name : target.modelId;
}

/// Full target with model („Claude API · claude-opus-4-1“).
String fullTargetLabel(RoutingState state, RouteTarget target) =>
    '${state.nameOf(target.profileId)} · ${target.modelId}';

/// Privacy level of [target]'s profile, `null` if the profile is gone.
PrivacyLevel? targetLevel(RoutingState state, RouteTarget target) =>
    state.profile(target.profileId)?.privacy;

/// Badge and text of the test field: („Regel 1“, „greift → Claude API ·
/// Opus“) or („Standard“, …).
(String, String) explainLabel(RoutingState state, RouteDecision decision) {
  final rules = state.rules!.rules;
  final rule = decision.rule;
  final badge = rule == null
      ? 'Standard'
      : 'Regel ${rules.indexWhere((r) => r.id == rule.id) + 1}';
  final private = decision.private ? ' · privat' : '';
  return (badge, 'greift → ${fullTargetLabel(state, decision.target)}$private');
}

/// Reason a rule lost in the test field.
String skipLabel(SkipReason reason) => switch (reason) {
  SkipReason.disabled => 'ausgeschaltet',
  SkipReason.invalid => 'ungültig',
  SkipReason.profileMissing => 'Profil gelöscht',
  SkipReason.profileDisabled => 'Profil deaktiviert',
  SkipReason.profileUnavailable => 'Profil nicht verfügbar',
  SkipReason.noMatch => 'passt nicht',
};
