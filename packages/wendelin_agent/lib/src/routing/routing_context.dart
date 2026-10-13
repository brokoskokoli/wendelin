import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'routing_text.dart';
import 'tool_category_matcher.dart';

/// Connectivity as the router sees it.
enum NetworkState {
  /// No connection.
  offline,

  /// Connected, not metered.
  online,

  /// Connected over a metered link (mobile data). Counts as online too.
  metered,
}

/// Source of the current [NetworkState] (a port: the app implements it
/// with the platform's connectivity API).
abstract interface class NetworkStatus {
  /// The state right now.
  NetworkState get current;
}

/// Everything a rule may look at, with clock and network injected
/// (ADR 0009 §1).
final class RoutingContext {
  /// Creates a context.
  RoutingContext({
    required this.input,
    required this.now,
    required this.network,
    required this.matcher,
  });

  /// The request.
  final UserInput input;

  /// Local wall-clock time of the request (for `timeWindow`).
  final DateTime now;

  /// Connectivity at the time of the request.
  final NetworkState network;

  /// Recognizes tool categories for `needsTool`.
  final ToolCategoryMatcher matcher;

  /// The normalized request text.
  late final RoutingText text = RoutingText(input.text);
}

/// The result of a matching condition: which parts of the text triggered
/// it (for `stripTrigger`) and whether a `privacy` condition took part.
@immutable
final class ConditionMatch {
  /// Creates a match.
  const ConditionMatch({this.triggers = const [], this.private = false});

  /// A match without text triggers.
  static const plain = ConditionMatch();

  /// Spans in [RoutingText.normalized] that triggered the match.
  final List<TriggerSpan> triggers;

  /// Whether the route is private (a `privacy` condition matched).
  final bool private;

  /// Both matches together (for `and`).
  ConditionMatch and(ConditionMatch other) => ConditionMatch(
    triggers: [...triggers, ...other.triggers],
    private: private || other.private,
  );
}
