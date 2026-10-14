/// Wendelin agent loop: context building, provider resolution (routing
/// rules), limits, the explicit hand-over on request („nochmal mit …“, never
/// automatic) and sentence chunking for TTS. Depends only on
/// `wendelin_core` interfaces.
///
/// Simple implementations of the ports (for tests, evals and the demo mode)
/// are in `package:wendelin_agent/fakes.dart`.
library;

export 'src/agent_config.dart';
export 'src/agent_runner.dart';
export 'src/agent_runner_texts.dart';
export 'src/context_builder.dart';
export 'src/give_up_classifier.dart';
export 'src/ports.dart';
export 'src/provider_resolver.dart';
export 'src/routing/conditions.dart';
export 'src/routing/routing_context.dart';
export 'src/routing/routing_engine.dart'
    show
        RouteDecision,
        RuleSetIssue,
        RuleSetIssueKind,
        SkipReason,
        SkippedRule,
        explain,
        validateRuleSet;
export 'src/routing/routing_text.dart';
export 'src/routing/rule_based_resolver.dart';
export 'src/routing/rule_set.dart';
export 'src/routing/rule_set_json.dart';
export 'src/routing/tool_category_matcher.dart';
export 'src/run/spoken_check.dart'
    show CheckVerdict, SpokenCheck, SpokenPrecheck;
export 'src/sentence_chunker.dart';
